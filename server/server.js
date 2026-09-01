import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { WebSocketServer } from 'ws';
import { initializeApp, cert } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

const PORT=Number(process.env.PORT||3001);
const DATA=path.join(process.cwd(),'data');
fs.mkdirSync(DATA,{recursive:true});

const FCM_SERVICE_ACCOUNT='/run/secrets/firebase-service-account.json';
let fcmMessaging=null;

try{
  if(fs.existsSync(FCM_SERVICE_ACCOUNT)){
    const serviceAccount=JSON.parse(
      fs.readFileSync(FCM_SERVICE_ACCOUNT,'utf8')
    );

    initializeApp({
      credential: cert(serviceAccount),
    });

    fcmMessaging=getMessaging();

    console.log('[FCM] Firebase Admin initialized');
  }else{
    console.log('[FCM] Service account not mounted; push disabled');
  }
}catch(error){
  console.error('[FCM] Firebase Admin initialization failed:',(error && error.message)||error);
  fcmMessaging=null;
}
const rooms=[
 {id:'genel',name:'Genel',online:0},{id:'sohbet',name:'Sohbet',online:0},{id:'teknoloji',name:'Teknoloji',online:0},{id:'oyun',name:'Oyun',online:0},{id:'müzik',name:'Müzik',online:0},{id:'film',name:'Film & Dizi',online:0},{id:'spor',name:'Spor',online:0},{id:'gece',name:'Gece Sohbeti',online:0}
];
const roomMessages=new Map();
const PRIVATE_MESSAGE_TTL_MS=24*60*60*1000;
const privateMessages=new Map();
const users=new Map(); // ws -> nick
const sockets=new Map(); // nick -> ws

// WebSocket bağlantısı açık kalsa bile uygulamanın gerçek UI durumunu
// takip eder. foreground dışındaki kullanıcılar çağrı açısından offline
// kabul edilir ve FCM üzerinden native çağrı bildirimi alır.
const appStates=new Map(); // normalized username -> foreground/background
const appStateUpdatedAt=new Map(); // normalized username -> last lifecycle/heartbeat time
const APP_FOREGROUND_HEARTBEAT_TTL_MS=45*1000;

function isForegroundActive(username){
  const key=normalizeUsername(username);
  if(!key || appStates.get(key)!=='foreground')return false;
  const updatedAt=Number(appStateUpdatedAt.get(key)||0);
  return updatedAt>0 && Date.now()-updatedAt<=APP_FOREGROUND_HEARTBEAT_TTL_MS;
}
const callTimers=new Map();

// Server-authoritative voice-call lifecycle.
// Signaling packets are only accepted while their callId belongs
// to the authenticated two-party call.
const activeCalls=new Map();

function callStateFor(callId){
  const id=String(callId||'').trim();
  if(!id)return null;
  return activeCalls.get(id)||null;
}

function isCallParty(call,username){
  if(!call)return false;

  const key=normalizeUsername(username);

  return key &&
    (key===call.callerKey || key===call.calleeKey);
}

function isCallPeer(call,from,to){
  if(!call)return false;

  const fromKey=normalizeUsername(from);
  const toKey=normalizeUsername(to);

  return (
    fromKey===call.callerKey &&
    toKey===call.calleeKey
  ) || (
    fromKey===call.calleeKey &&
    toKey===call.callerKey
  );
}

function endActiveCall(callId){
  const id=String(callId||'').trim();

  if(!id)return null;

  clearCallTimer(id);

  const call=activeCalls.get(id)||null;

  activeCalls.delete(id);

  return call;
}

const pendingFileTransfers=new Map();
const fileTransferSignalState=new Map();

/*
 * File transfer lifecycle state.
 *
 * Bir transfer COMPLETE / FAILED / REJECTED durumuna geldikten sonra
 * aynı transferId ile geç gelen veya duplicate signaling event'lerinin
 * transferi yeniden canlandırmasını engeller.
 */
const fileTransferLifecycleState=new Map();

const FILE_TRANSFER_STATE_TTL_MS=10*60*1000;
const PENDING_FILE_TRANSFER_TTL_MS=60*60*1000;

function cleanupFileTransferLifecycleState(){
  const now=Date.now();

  for(const [key,state] of fileTransferLifecycleState){
    if(!state || !state.updatedAt ||
       now-state.updatedAt>FILE_TRANSFER_STATE_TTL_MS){
      fileTransferLifecycleState.delete(key);
    }
  }
}

function fileTransferLifecycleKey(from,to,transferId){
  const a=normalizeUsername(from);
  const b=normalizeUsername(to);
  const id=String(transferId||'').trim();

  if(!a||!b||!id)return '';

  // OFFER A->B, ANSWER B->A gibi ters yönlü signaling
  // event'leri aynı transfer state'ine bağlanmalıdır.
  const peers=[a,b].sort();

  return `${peers[0]}|${peers[1]}|${id}`;
}

function getFileTransferLifecycle(from,to,transferId){
  cleanupFileTransferLifecycleState();

  const key=fileTransferLifecycleKey(from,to,transferId);
  if(!key)return null;

  return fileTransferLifecycleState.get(key)||null;
}

function updateFileTransferLifecycle(from,to,transferId,state){
  const key=fileTransferLifecycleKey(from,to,transferId);
  if(!key)return null;

  const current=fileTransferLifecycleState.get(key)||{
    from:safeNick(from),
    to:safeNick(to),
    transferId:String(transferId||'').trim(),
    state:'active',
    createdAt:Date.now(),
  };

  current.state=state;
  current.updatedAt=Date.now();

  if(
    state==='completed' ||
    state==='failed' ||
    state==='rejected'
  ){
    current.terminalAt=Date.now();
  }

  fileTransferLifecycleState.set(key,current);

  return current;
}

function isTerminalFileTransferState(state){
  return (
    state==='completed' ||
    state==='failed' ||
    state==='rejected'
  );
}

function isTerminalFileTransferSignal(type){
  return (
    type==='fileTransferComplete' ||
    type==='fileTransferFailed' ||
    type==='fileTransferReject'
  );
}

function pendingFileTransferKey(to,transferId){
  return `${normalizeUsername(to)}|${String(transferId||'').trim()}`;
}

function fileTransferSignalFingerprint(event){
  const copy={...event};
  delete copy.seq;

  return JSON.stringify(copy);
}

function prepareFileTransferSignal(to,event){
  const transferId=String(event.transferId||'').trim();
  const target=safeNick(to);

  if(!target || !transferId)return null;

  const key=pendingFileTransferKey(target,transferId);
  const now=Date.now();

  let state=fileTransferSignalState.get(key);

  if(!state){
    state={
      updatedAt:now,
      nextSeq:1,
      seen:new Map(),
    };
  }

  state.updatedAt=now;

  const fingerprint=fileTransferSignalFingerprint({
    ...event,
    from:String(event.from||''),
    to:target,
    transferId,
  });

  let seq=state.seen.get(fingerprint);

  if(!Number.isFinite(Number(seq)) || Number(seq)<1){
    seq=Number(state.nextSeq)||1;
    state.nextSeq=seq+1;

    state.seen.set(fingerprint,seq);

    if(state.seen.size>512){
      const firstKey=state.seen.keys().next().value;
      if(firstKey!==undefined){
        state.seen.delete(firstKey);
      }
    }
  }

  fileTransferSignalState.set(key,state);

  return {
    ...event,
    from:String(event.from||''),
    to:target,
    transferId,
    seq,
  };
}

function cleanupPendingFileTransfers(){
  const now=Date.now();

  for(const [key,pending] of pendingFileTransfers){
    if(!pending || now-pending.updatedAt>PENDING_FILE_TRANSFER_TTL_MS){
      pendingFileTransfers.delete(key);
    }
  }

  for(const [key,state] of fileTransferSignalState){
    if(!state || now-state.updatedAt>PENDING_FILE_TRANSFER_TTL_MS){
      fileTransferSignalState.delete(key);
    }
  }
}

function storePendingFileTransfer(to,event){
  const transferId=String(event.transferId||'').trim();
  const target=safeNick(to);

  if(!target || !transferId)return;

  cleanupPendingFileTransfers();

  const key=pendingFileTransferKey(target,transferId);

  const existing=pendingFileTransfers.get(key)||{
    createdAt:Date.now(),
    updatedAt:Date.now(),
    from:String(event.from||''),
    to:target,
    transferId,
    events:[],
    nextSeq:1,
  };

  existing.updatedAt=Date.now();

  const allowedTypes={
    fileTransferOffer:true,
    fileTransferIce:true,
    fileTransferAnswer:true,
    fileTransferAccept:true,
    fileTransferReject:true,
    fileTransferComplete:true,
    fileTransferFailed:true,
  };

  if(!allowedTypes[event.type])return;

  const prepared=prepareFileTransferSignal(target,{
    ...event,
    from:String(event.from||existing.from),
    to:target,
    transferId,
  });

  if(!prepared)return;

  const stored=prepared;

  if(stored.type==='fileTransferOffer'){
    void sendFileTransferPush(target,stored).catch(error=>{
      console.error(
        `[FCM] file transfer push failed for ${target}:`,
        error
      );
    });
  }

  existing.nextSeq=Math.max(
    Number(existing.nextSeq)||1,
    Number(stored.seq)+1,
  );

  if(!Array.isArray(existing.events)){
    existing.events=[];
  }

  const duplicate=existing.events.some(function(item){
    return (
      item &&
      item.type===stored.type &&
      Number(item.seq)===Number(stored.seq) &&
      JSON.stringify(item)===JSON.stringify(stored)
    );
  });

  if(!duplicate){
    existing.events.push(stored);

    existing.events.sort(function(a,b){
      return (
        (Number(a && a.seq)||0) -
        (Number(b && b.seq)||0)
      );
    });

    if(existing.events.length>256){
      existing.events=existing.events.slice(-256);
    }
  }

  /*
   * Eski alanları da güncel tut.
   * Böylece mevcut kodun diğer bölümleri kırılmaz.
   */
  existing.offer=null;
  existing.offers=[];
  existing.ice=[];
  existing.signals=[];

  for(const item of existing.events){
    if(!item)continue;

    if(item.type==='fileTransferOffer'){
      existing.offer=item;
      existing.offers.push(item);
    }else if(item.type==='fileTransferIce'){
      if(item.candidate){
        existing.ice.push(item.candidate);
      }
    }else{
      existing.signals.push(item);
    }
  }

  pendingFileTransfers.set(key,existing);
}

function clearPendingFileTransfer(to,transferId){
  const key=pendingFileTransferKey(to,transferId);

  if(!key)return;

  pendingFileTransfers.delete(key);
}

function storeTerminalPendingFileTransfer(to,event){
  const transferId=String(event && event.transferId || '').trim();
  const target=safeNick(to);

  if(!target||!transferId)return;

  const key=pendingFileTransferKey(target,transferId);

  // Terminal event geldiğinde artık eski OFFER/ICE/ANSWER/ACCEPT
  // event'lerinin pending kuyruğunda kalmasının anlamı yok.
  pendingFileTransfers.set(key,{
    createdAt:Date.now(),
    updatedAt:Date.now(),
    from:String(event.from||''),
    to:target,
    transferId,
    events:[event],
    nextSeq:(Number(event.seq)||0)+1,
    offer:null,
    offers:[],
    ice:[],
    signals:[event],
  });
}

function deliverPendingFileTransfers(ws,username){
  cleanupPendingFileTransfers();

  const targetKey=normalizeUsername(username);

  for(const [key,pending] of pendingFileTransfers){
    if(!pending || key.split('|')[0]!==targetKey)continue;

    let events=[];

    if(Array.isArray(pending.events)){
      events=pending.events.slice();
    }

    /*
     * Eski kayıt formatı için fallback.
     */
    if(events.length===0){
      const offers=Array.isArray(pending.offers)
        ? pending.offers
        : (pending.offer ? [pending.offer] : []);

      const ice=Array.isArray(pending.ice)
        ? pending.ice
        : [];

      const signals=Array.isArray(pending.signals)
        ? pending.signals
        : [];

      let seq=1;

      for(const offer of offers){
        events.push({
          ...offer,
          seq:Number(offer && offer.seq)||seq++,
        });
      }

      for(const candidate of ice){
        events.push({
          type:'fileTransferIce',
          from:pending.from,
          to:pending.to,
          transferId:pending.transferId,
          candidate:candidate,
          seq:seq++,
        });
      }

      for(const signal of signals){
        events.push({
          ...signal,
          seq:Number(signal && signal.seq)||seq++,
        });
      }
    }

    events.sort(function(a,b){
      return (
        (Number(a && a.seq)||0) -
        (Number(b && b.seq)||0)
      );
    });

    if(events.length===0){
      pendingFileTransfers.delete(key);
      continue;
    }

    let sentCount=0;
    let deliveryFailed=false;

    for(const event of events){
      if(!event)continue;

      const delivered=send(ws,event);

      if(!delivered){
        deliveryFailed=true;
        break;
      }

      sentCount++;
    }

    /*
     * Socket bağlantısı teslimat sırasında koptuysa
     * başarılı prefix'i sil, kalan event'leri koru.
     */
    if(deliveryFailed){
      pending.events=events.slice(sentCount);

      pending.updatedAt=Date.now();

      if(pending.events.length>0){
        pendingFileTransfers.set(key,pending);
      }else{
        pendingFileTransfers.delete(key);
      }

      continue;
    }

    /*
     * Bütün signaling event'leri socket'e yazıldı.
     */
    pendingFileTransfers.delete(key);
  }
}
function socketFor(username){
  const targetKey=normalizeUsername(username);
  if(!targetKey)return null;

  for(const [nick,ws] of sockets){
    if(normalizeUsername(nick)===targetKey){
      return ws;
    }
  }

  return null;
}
const accountsFile=path.join(DATA,'users.json');
let accounts=load('users.json',{});
function refreshAccounts(){accounts=load('users.json',{});}
function cleanFcmToken(v){
  const token=String((v != null ? v : '')).trim();
  if(!token)return '';
  return token.slice(0,4096);
}

async function sendFcmPush(username, message){
  if(!fcmMessaging)return false;

  refreshAccounts();

  const key=normalizeUsername(username);
  const account=accounts[key];
  const token=cleanFcmToken((account && account.fcmToken));

  if(!token){
    console.log(`[FCM] no token for ${username}`);
    return false;
  }

  try{
    const response=await fcmMessaging.send({
      token,
      ...message,
    });

    console.log(
      `[FCM] push sent to ${username}: ${response}`
    );

    return true;
  }catch(error){
    const code=(error && error.code)||'';
    const errorMessage=(error && error.message)||String(error);

    console.error(
      `[FCM] push failed for ${username}: ${code} ${errorMessage}`
    );

    if(
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ){
      refreshAccounts();

      const current=accounts[key];

      if(
        current &&
        current.fcmToken === token
      ){
        delete current.fcmToken;
        delete current.fcmTokenUpdatedAt;

        accounts[key]=current;
        saveAccounts();

        console.log(
          `[FCM] stale token removed for ${username}`
        );
      }
    }

    return false;
  }
}
async function sendFileTransferPush(username,event){
  const target=safeNick(username);
  if(!target)return false;

  // Kullanıcı uygulamayı aktif olarak kullanıyorsa WebSocket üzerinden
  // offer zaten teslim edilir; ikinci bildirim üretme.
  if(isForegroundActive(target))return false;

  const transferId=String(
    event && (event.transferId || event.fileId) || ''
  ).trim();

  const from=safeNick(
    event && (event.from || event.sender) || ''
  );

  const fileName=String(
    event && event.fileName || 'Dosya'
  ).trim() || 'Dosya';

  const fileSize=String(
    event && event.fileSize || '0'
  );

  if(!transferId || !from)return false;

  return sendFcmPush(target,{
    notification:{
      title:from,
      body:`${fileName} gönderiyor`,
    },
    data:{
      type:'privateFileMessage',
      from,
      sender:from,
      to:target,
      recipient:target,
      fileId:transferId,
      transferId,
      fileName,
      fileSize,
    },
    android:{
      priority:'high',
      ttl:3600000,
      notification:{
        channelId:'zerolog_files_v1',
        sound:'default',
      },
    },
  });
}

async function sendCallStatusPush(username,callId,title,body){
  if(!callNotificationsEnabled(username))return false;

  return sendFcmPush(username,{
    data:{
      type:'callStatus',
      callId:String(callId||''),
      title:String(title||'ZeroLog çağrı'),
      body:String(body||''),
    },
    android:{
      priority:'high',
      ttl:3600000,
    },
  });
}


async function sendCallStatusPushIfOffline(
  username,
  callId,
  title,
  body
){
  const target=safeNick(username);
  if(!target)return false;

  const targetKey=normalizeUsername(target);

  const targetName=[...sockets.keys()]
    .find(nick=>normalizeUsername(nick)===targetKey);

  if(targetName && sockets.get(targetName))return false;

  return sendCallStatusPush(
    target,
    callId,
    title,
    body
  );
}

function clearCallTimer(callId){
  const timer=callTimers.get(callId);
  if(timer){
    clearTimeout(timer);
    callTimers.delete(callId);
  }
}

for(const r of rooms){
  const messages=normalizeRoomMessages(load(`room-${r.id}.json`,[]),r.id);
  roomMessages.set(r.id,messages);
  save(`room-${r.id}.json`,messages);
}
function load(file,fallback){try{return JSON.parse(fs.readFileSync(path.join(DATA,file),'utf8'));}catch{return fallback;}}
function save(file,data){
  try{
    const target=path.join(DATA,file);
    const temp=`${target}.tmp`;
    fs.writeFileSync(
      temp,
      JSON.stringify(data.slice(-300)),
      {mode:0o600}
    );
    fs.renameSync(temp,target);
  }catch(error){
    console.error(`[DATA] ${file} save failed: ${error}`);
  }
}
function send(ws,data){
  if(!ws || ws.readyState!==1)return false;

  try{
    ws.send(JSON.stringify(data));
    return true;
  }catch{
    const nick=users.get(ws);

    if(nick){
      users.delete(ws);
      if(sockets.get(nick)===ws){
        sockets.delete(nick);

        // Socket kapandıysa state artık foreground/background ayrımı
        // yapmadan offline kabul edilir.
        appStates.delete(normalizeUsername(nick));
      }
      broadcastUserOffline(nick);
      updatePresence();
    }

    try{ws.close();}catch{}
    return false;
  }
}
function broadcast(data,except=null){
  for(const ws of users.keys()){
    if(ws!==except)send(ws,data);
  }
}
function sendUserDirectory(ws){
  refreshAccounts();

  const viewerNick=users.get(ws);
  const directoryProfiles={};

  const usersDirectory=Object.values(accounts)
    .map(account=>{
      const username=String(
        (account && account.username)||''
      ).trim();

      if(!username)return '';

      const isSelf=
        viewerNick &&
        normalizeUsername(username)===normalizeUsername(viewerNick);

      if(isSelf || presenceVisible(username)){
        directoryProfiles[username]=profileDataFor(account);
      }

      return username;
    })
    .filter(Boolean)
    .filter((name,index,list)=>
      list.findIndex(
        x=>x.toLowerCase()===name.toLowerCase()
      )===index
    )
    .sort((a,b)=>a.toLowerCase().localeCompare(b.toLowerCase()));

  send(ws,{
    type:'userDirectory',
    users:usersDirectory,
    profiles:directoryProfiles,
  });
}

function safeNick(v){return String((v != null ? v : '')).trim().replace(/[\r\n<>]/g,'').slice(0,24);}



function messageExpiresAt(msg){
  const explicit=Number(msg && msg.expiresAt);
  if(Number.isFinite(explicit) && explicit>0)return explicit;

  const ts=Number(msg && msg.ts);
  if(!Number.isFinite(ts) || ts<=0)return 0;
  return ts+PRIVATE_MESSAGE_TTL_MS;
}

function purgeExpiredPrivateMessages(a,b){
  return getPrivate(a,b);
}

function purgeAllExpiredPrivateMessages(){
  try{
    for(const file of fs.readdirSync(DATA)){
      if(!file.startsWith('private-') || !file.endsWith('.json'))continue;

      const list=load(file,[]);
      if(!Array.isArray(list))continue;

      const now=Date.now();
      const active=list.filter(msg=>{
        const expiresAt=messageExpiresAt(msg);
        return !expiresAt || expiresAt>now;
      });

      if(active.length!==list.length){
        if(active.length===0){
          try{
            fs.unlinkSync(path.join(DATA,file));
          }catch(error){
            console.error(`[DATA] expired private message file delete failed: ${error}`);
          }
        }else{
          save(file,active);
        }
      }
    }
  }catch(error){
    console.error(`[DATA] private message purge failed: ${error}`);
  }
}

function cleanText(v){return String((v != null ? v : '')).trim().slice(0,2000);}
function makeMessageId(){
  return `${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
}
function normalizeRoomMessages(list, roomId){
  if(!Array.isArray(list))return [];
  const now=Date.now();
  let changed=false;
  const result=list
    .map((msg,index)=>{
      if(!msg || typeof msg!=='object')return null;
      const ts=Number(msg.ts||0)>0?Number(msg.ts):now;
      const expiresAt=Number(msg.expiresAt||0)>0
        ? Number(msg.expiresAt)
        : ts+PRIVATE_MESSAGE_TTL_MS;
      if(!msg.id || !msg.expiresAt){changed=true;}
      return {
        ...msg,
        id:msg.id||`legacy-${roomId}-${ts}-${index}`,
        ts,
        expiresAt,
      };
    })
    .filter(Boolean)
    .filter(msg=>Number(msg.expiresAt||0)>now);
  return changed || result.length!==list.length ? result.slice(-300) : result;
}

function purgeExpiredRoomMessages(){
  const now=Date.now();
  for(const room of rooms){
    const id=room.id;
    const current=roomMessages.get(id)||[];
    const filtered=current.filter(msg=>{
      const expiresAt=Number(msg && msg.expiresAt||0);
      return !expiresAt || expiresAt>now;
    });
    if(filtered.length!==current.length){
      roomMessages.set(id,filtered);
      save(`room-${id}.json`,filtered);
    }
  }
}
function normalizeUsername(v){return safeNick(v).toLowerCase();}
function validUsername(v){
  const nick=safeNick(v);
  return nick.length>=3 && nick.length<=24 && /^[a-zA-Z0-9_.-]+$/.test(nick);
}
function validPassword(v){
  const password=String((v != null ? v : ''));
  return password.length>=8 && password.length<=128;
}
function hashPassword(password){
  const salt=crypto.randomBytes(16).toString('hex');
  const hash=crypto.scryptSync(password,salt,64).toString('hex');
  return `scrypt$${salt}$${hash}`;
}
function verifyPassword(password,stored){
  try{
    const parts=String(stored).split('$');
    if(parts.length!==3 || parts[0]!=='scrypt')return false;
    const [,salt,hex]=parts;
    const actual=crypto.scryptSync(String(password != null ? password : ''),salt,64);
    const expected=Buffer.from(hex,'hex');
    return expected.length===actual.length &&
      crypto.timingSafeEqual(actual,expected);
  }catch{return false;}
}
function saveAccounts(){
  try{
    const tempFile=`${accountsFile}.tmp`;
    fs.writeFileSync(
      tempFile,
      JSON.stringify(accounts,null,2),
      {mode:0o600}
    );
    fs.renameSync(tempFile,accountsFile);
  }catch(error){
    console.error(`[DATA] users.json save failed: ${error}`);
  }
}
function accountFor(username){
  refreshAccounts();
  return accounts[normalizeUsername(username)] || null;
}

function profileDataFor(account,{includePhoto=false}={}){
  if(!account)return null;

  const result={
    type:account.profileType||'avatar',
    avatarId:Number.isInteger(account.avatarId)
      ? account.avatarId
      : null,
    about:typeof account.about==='string'
      ? account.about
      : '',
    photoAvailable:
      account.profileType==='photo' &&
      typeof account.photoData==='string' &&
      account.photoData.length>0,
    profileRevision:Number(account.profileRevision)||0,
  };

  if(includePhoto && account.profileType==='photo'){
    result.photoData=
      typeof account.photoData==='string'
        ? account.photoData
        : '';
  }

  return result;
}


function presenceVisible(username){
  const account=accountFor(username);

  // Eski hesaplarda alan yoksa mevcut davranışı koru.
  return (account && account.presenceVisible) !== false;
}

function privateMessagesEnabled(username){
  const account=accountFor(username);

  // Eski hesaplarda alan yoksa mevcut davranışı koru.
  return (account && account.privateMessagesEnabled) !== false;
}

function messageNotificationsEnabled(username){
  const account=accountFor(username);

  // Eski hesaplarda alan yoksa mevcut davranışı koru.
  return (account && account.messageNotificationsEnabled) !== false;
}

function callNotificationsEnabled(username){
  const account=accountFor(username);

  // Eski hesaplarda alan yoksa mevcut davranışı koru.
  return (account && account.callNotificationsEnabled) !== false;
}

function visibleUsersFor(viewer){
  const viewerNick=users.get(viewer);

  return [...sockets.keys()]
    .filter(username=>{
      if(
        viewerNick &&
        normalizeUsername(username)===normalizeUsername(viewerNick)
      ){
        return true;
      }

      return presenceVisible(username);
    })
    .sort((a,b)=>a.localeCompare(b));
}

function visibleProfilesFor(viewer){
  const viewerNick=users.get(viewer);
  const result={};

  for(const username of sockets.keys()){
    const key=normalizeUsername(username);
    const account=accounts[key];

    if(!account)continue;

    const isSelf=
      viewerNick &&
      normalizeUsername(username)===normalizeUsername(viewerNick);

    if(!isSelf && !presenceVisible(username))continue;

    result[username]=profileDataFor(account);
  }

  return result;
}

function listUsers(){
  return [...sockets.keys()]
    .filter(username=>presenceVisible(username))
    .sort((a,b)=>a.localeCompare(b));
}
function updatePresence(){
  for(const ws of users.keys()){
    send(ws,{
      type:'userList',
      users:visibleUsersFor(ws),
      profiles:visibleProfilesFor(ws),
    });
  }

  for(const r of rooms){
    r.online=0;
  }

  for(const ws of users.keys()){
    const rs=ws._rooms||new Set();

    for(const id of rs){
      const r=rooms.find(x=>x.id===id);

      if(r)r.online++;
    }
  }

  broadcast({type:'rooms',rooms});
}

function broadcastUserOnline(nick){
  if(!presenceVisible(nick))return;

  for(const ws of users.keys()){
    const viewer=users.get(ws);

    if(
      viewer &&
      normalizeUsername(viewer)===normalizeUsername(nick)
    ){
      continue;
    }

    send(ws,{
      type:'userOnline',
      username:nick,
    });
  }
}

function broadcastUserOffline(nick){
  for(const ws of users.keys()){
    const viewer=users.get(ws);

    if(
      viewer &&
      normalizeUsername(viewer)===normalizeUsername(nick)
    ){
      continue;
    }

    send(ws,{
      type:'userOffline',
      username:nick,
    });
  }
}
function pairKey(a,b){return [a,b].sort().join('|');}
function privateFile(a,b){return `private-${Buffer.from(pairKey(a,b)).toString('base64url')}.json`;}
function getPrivate(a,b){
  const k=pairKey(a,b);
  if(!privateMessages.has(k))privateMessages.set(k,load(privateFile(a,b),[]));

  const arr=privateMessages.get(k)||[];
  const now=Date.now();
  const active=arr.filter(msg=>{
    const expiresAt=messageExpiresAt(msg);
    return !expiresAt || expiresAt>now;
  });

  if(active.length!==arr.length){
    privateMessages.set(k,active);
    save(privateFile(a,b),active);
  }

  return privateMessages.get(k)||[];
}
function addPrivate(a,b,msg){
  const arr=getPrivate(a,b);

  if((msg && msg.clientMessageId)){
    const existing=arr.find(
      item=>(item && item.clientMessageId)===msg.clientMessageId
    );

    if(existing){
      return existing;
    }
  }

  arr.push(msg);
  save(privateFile(a,b),arr);
  return msg;
}

function findPrivateMessageByClientId(a,b,clientMessageId){
  if(!clientMessageId)return null;

  const arr=getPrivate(a,b);

  return arr.find(
    item=>(item && item.clientMessageId)===clientMessageId
  ) || null;
}

function markPrivateMessageDelivered(a,b,messageId,clientMessageId){
  const arr=getPrivate(a,b);

  const index=arr.findIndex(item=>{
    if(messageId && (item && item.id)===messageId)return true;
    if(clientMessageId && (item && item.clientMessageId)===clientMessageId)return true;
    return false;
  });

  if(index<0)return null;

  arr[index]={
    ...arr[index],
    delivered:true,
    deliveredAt:Date.now(),
  };

  save(privateFile(a,b),arr);

  return arr[index];
}


function markPrivateMessageRead(
  reader,
  sender,
  messageId,
  clientMessageId
){
  const arr=getPrivate(reader,sender);

  const index=arr.findIndex(item=>{
    if(messageId && item && item.id===messageId)return true;
    if(clientMessageId &&
       item &&
       item.clientMessageId===clientMessageId)return true;
    return false;
  });

  if(index<0)return null;

  arr[index]={
    ...arr[index],
    read:true,
    readAt:Date.now(),
  };

  save(privateFile(reader,sender),arr);

  return arr[index];
}

function updatePrivateFileMessageTransferState(a,b,fileId,state){
  const id=String(fileId||'').trim();
  if(!id)return null;

  const arr=getPrivate(a,b);
  const index=arr.findIndex(item =>
    item &&
    item.type==='privateFileMessage' &&
    String(item.fileId||'')===id
  );

  if(index<0)return null;

  arr[index]={
    ...arr[index],
    transferStatus:String(state||'stored'),
    transferStatusAt:Date.now(),
  };

  save(privateFile(a,b),arr);
  return arr[index];
}

function pendingPrivateMessages(username){
  const target=normalizeUsername(username);
  const result=[];

  try{
    for(const file of fs.readdirSync(DATA)){
      if(!file.startsWith('private-') || !file.endsWith('.json'))continue;

      const list=load(file,[]);

      if(!Array.isArray(list))continue;

      for(const msg of list){
        const to=normalizeUsername((msg && msg.to != null ? msg.to : ''));

        if(to!==target)continue;
        if(messageExpiresAt(msg) && messageExpiresAt(msg)<=Date.now())continue;
        if((msg && msg.delivered)===true)continue;

        result.push(msg);
      }
    }
  }catch{}

  return result.sort(
    (a,b)=>Number((a && a.ts)||0)-Number((b && b.ts)||0)
  );
}

function deletePrivateDataForUser(username){
  const target=normalizeUsername(username);

  for(const key of [...privateMessages.keys()]){
    const parts=String(key).split('|');
    if(parts.some(part=>normalizeUsername(part)===target)){
      privateMessages.delete(key);
    }
  }

  try{
    for(const file of fs.readdirSync(DATA)){
      if(!file.startsWith('private-') || !file.endsWith('.json')) continue;

      const encoded=file.slice(8,-5);
      let pair='';
      try{
        pair=Buffer.from(encoded,'base64url').toString('utf8');
      }catch{
        continue;
      }

      const parts=pair.split('|');
      if(!parts.some(part=>normalizeUsername(part)===target)) continue;

      try{
        fs.unlinkSync(path.join(DATA,file));
      }catch{}
    }
  }catch{}
}

function deleteRoomMessagesForUser(username){
  const target=normalizeUsername(username);

  for(const room of rooms){
    const id=room.id;
    const current=roomMessages.get(id)||[];
    const filtered=current.filter(msg=>{
      const sender=normalizeUsername((msg && msg.from != null ? msg.from : (msg && msg.sender != null ? msg.sender : '')));
      return sender!==target;
    });

    roomMessages.set(id,filtered);
    save(`room-${id}.json`,filtered);
  }
}

function disconnect(ws){
  const nick=users.get(ws);

  if(!nick)return;

  const nickKey=normalizeUsername(nick);

  for(const [callId,call] of activeCalls){
    if(!isCallParty(call,nick))continue;

    const peer=
      call.callerKey===nickKey
        ? call.callee
        : call.caller;

    endActiveCall(callId);

    send(socketFor(peer),{
      type:'callEnded',
      from:nick,
      to:peer,
      callId,
    });
  }

  users.delete(ws);

  if(sockets.get(nick)===ws){
    sockets.delete(nick);
  }

  appStates.delete(nickKey);
  appStateUpdatedAt.delete(nickKey);

  broadcastUserOffline(nick);
  updatePresence();
}
const server=http.createServer((req,res)=>{res.setHeader('Access-Control-Allow-Origin','*');if(req.url==='/health'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({ok:true,service:'zerolog',users:sockets.size,rooms:rooms.length}));return;}res.writeHead(200,{'Content-Type':'text/plain; charset=utf-8'});res.end('Zerolog Signaling & Chat Server Aktif');});
const wss=new WebSocketServer({server});

const presenceInterval=setInterval(()=>{
  for(const ws of wss.clients){
    if(ws.isAlive===false){
      try{ws.terminate();}catch{}
      continue;
    }

    ws.isAlive=false;

    try{
      ws.ping();
    }catch{
      try{ws.terminate();}catch{}
    }
  }
},10000);

presenceInterval.unref();

const privateMessagePurgeInterval=setInterval(purgeAllExpiredPrivateMessages,60*1000);
privateMessagePurgeInterval.unref();
const roomMessagePurgeInterval=setInterval(purgeExpiredRoomMessages,60*1000);
roomMessagePurgeInterval.unref();
wss.on('connection',(ws)=>{
  ws._rooms=new Set();
  ws.isAlive=true;
  ws.on('pong',()=>{ws.isAlive=true;});
  ws.on('message',async (buf)=>{let d;try{d=JSON.parse(buf.toString());}catch{return;}const me=users.get(ws);
 switch(d.type){
  case 'registerAccount':{
    refreshAccounts();
    const nick=safeNick(d.username);
    const key=normalizeUsername(nick);
    const password=String(d.password != null ? d.password : '');

    if(!validUsername(nick)){
      send(ws,{type:'authError',code:'INVALID_USERNAME',message:'Kullanıcı adı 3-24 karakter olmalı ve sadece harf, rakam, ., _ veya - içermeli.'});
      return;
    }

    if(!validPassword(password)){
      send(ws,{type:'authError',code:'INVALID_PASSWORD',message:'Şifre en az 8 karakter olmalı.'});
      return;
    }

    if(accounts[key]){
      send(ws,{type:'authError',code:'USERNAME_TAKEN',message:'Bu kullanıcı adı zaten kayıtlı.'});
      return;
    }

    accounts[key]={
      username:nick,
      passwordHash:hashPassword(password),
      createdAt:Date.now(),
      presenceVisible:true,
      privateMessagesEnabled:true,
      messageNotificationsEnabled:true,
      callNotificationsEnabled:true,
      autoAcceptFileTransfers:true,
      profileType:'avatar',
      avatarId:null,
      about:'',
      photoData:'',
      profileRevision:1
    };
    saveAccounts();

    send(ws,{type:'accountRegistered',username:nick});
    break;
  }

  case 'login':{
    refreshAccounts();
    const nick=safeNick(d.username);
    const key=normalizeUsername(nick);
    const password=String(d.password != null ? d.password : '');
    const fcmToken=cleanFcmToken(d.fcmToken);
    const account=accounts[key];

    if(!account || !verifyPassword(password,account.passwordHash)){
      send(ws,{type:'authError',code:'INVALID_CREDENTIALS',message:'Kullanıcı adı veya şifre hatalı.'});
      return;
    }

    const old=sockets.get(account.username);

    if(old && old!==ws){
      send(ws,{type:'authError',code:'ACCOUNT_IN_USE',message:'Bu hesap başka bir cihazda aktif.'});
      return;
    }

    if(account.presenceVisible===undefined){
      account.presenceVisible=true;
    }

    if(account.privateMessagesEnabled===undefined){
      account.privateMessagesEnabled=true;
    }

    if(account.messageNotificationsEnabled===undefined){
      account.messageNotificationsEnabled=true;
    }

    if(account.callNotificationsEnabled===undefined){
      account.callNotificationsEnabled=true;
    }

    if(account.autoAcceptFileTransfers===undefined){
      account.autoAcceptFileTransfers=true;
    }

    if(account.profileType===undefined){
      account.profileType='avatar';
    }

    if(account.avatarId!==null &&
       account.avatarId!==undefined &&
       (!Number.isInteger(account.avatarId) ||
        account.avatarId < 1 ||
        account.avatarId > 50)){
      account.avatarId=null;
    }

    if(account.about===undefined){
      account.about='';
    }

    if(typeof account.about!=='string'){
      account.about='';
    }

    account.about=account.about.slice(0,300);

    if(account.photoData===undefined){
      account.photoData='';
    }

    if(typeof account.photoData!=='string'){
      account.photoData='';
    }

    if(!Number.isInteger(account.profileRevision) || account.profileRevision < 1){
      account.profileRevision=1;
    }

    if(account.photoData.length>700000){
      account.photoData='';
      if(account.profileType==='photo'){
        account.profileType='avatar';
        account.avatarId=null;
      }
    }

    accounts[key]=account;
    saveAccounts();

    users.set(ws,account.username);
    sockets.set(account.username,ws);

    // Login sonrası ilk durum foreground kabul edilir. Flutter hemen
    // gerçek lifecycle durumunu ayrıca bildirir.
    const loginStateKey=normalizeUsername(account.username);
    appStates.set(loginStateKey,'foreground');
    appStateUpdatedAt.set(loginStateKey,Date.now());

    if(fcmToken){
      account.fcmToken=fcmToken;
      account.fcmTokenUpdatedAt=Date.now();
      accounts[key]=account;
      saveAccounts();
    }

    send(ws,{type:'authenticated',username:account.username});

    // WebRTC file transfer için TURN bilgilerini client'a gönder.
    // Credential kaynak kodda tutulmaz; process environment'dan alınır.
    const turnUser = String(process.env.ZEROLOG_TURN_USER || '').trim();
    const turnPass = String(process.env.ZEROLOG_TURN_PASS || '');

    if(turnUser && turnPass){
      send(ws,{
        type:'turnCredentials',
        username:turnUser,
        credential:turnPass,
        urls:[
          'turn:92.5.38.220:3478?transport=udp',
          'turn:92.5.38.220:3478?transport=tcp',
        ],
      });
    }

    send(ws,{
      type:'privacySettings',
      presenceVisible:account.presenceVisible!==false,
      privateMessagesEnabled:account.privateMessagesEnabled!==false,
    });

    send(ws,{
      type:'notificationSettings',
      messageNotificationsEnabled:
        account.messageNotificationsEnabled!==false,
      callNotificationsEnabled:
        account.callNotificationsEnabled!==false,
      autoAcceptFileTransfers:
        account.autoAcceptFileTransfers!==false,
    });

    sendUserDirectory(ws);

    deliverPendingFileTransfers(ws,account.username);

    const pending=privateMessagesEnabled(account.username)
      ? pendingPrivateMessages(account.username)
      : [];

    if(pending.length){
      const pendingSent = send(ws,{
        type:'pendingPrivateMessages',
        messages:pending,
      });

      if(pendingSent){
        for(const pendingMessage of pending){
          const sender=safeNick(
            pendingMessage && pendingMessage.from != null
              ? pendingMessage.from
              : ''
          );

          const messageId=String(
            pendingMessage && pendingMessage.id != null
              ? pendingMessage.id
              : ''
          ).trim();

          const clientMessageId=String(
            pendingMessage && pendingMessage.clientMessageId != null
              ? pendingMessage.clientMessageId
              : ''
          ).trim();

          if(!sender || (!messageId && !clientMessageId)) continue;

          const delivered=markPrivateMessageDelivered(
            sender,
            account.username,
            messageId,
            clientMessageId
          );

          if(delivered){
            send(
              sockets.get(sender),
              {
                type:'messageDelivered',
                messageId:delivered.id||null,
                clientMessageId:delivered.clientMessageId||null,
                from:account.username,
                to:sender,
                deliveredTo:account.username,
                ts:delivered.deliveredAt||Date.now(),
              }
            );
          }
        }
      }
    }

    broadcastUserOnline(account.username);
    send(ws,{type:'rooms',rooms});
    send(ws,{
      type:'userList',
      users:visibleUsersFor(ws),
      profiles:visibleProfilesFor(ws),
    });
    updatePresence();
    break;
  }

  case 'deleteAccount':{
    if(!me){
      send(ws,{type:'authError',code:'LOGIN_REQUIRED',message:'Oturum gerekli.'});
      break;
    }

    const key=normalizeUsername(me);

    deletePrivateDataForUser(me);

    if(accounts[key]){
      delete accounts[key];
      saveAccounts();
    }

    send(ws,{type:'accountDeleted',mode:'account'});
    disconnect(ws);
    try{ws.close();}catch{}
    break;
  }

  case 'deleteAllData':{
    if(!me){
      send(ws,{type:'authError',code:'LOGIN_REQUIRED',message:'Oturum gerekli.'});
      break;
    }

    const key=normalizeUsername(me);

    deletePrivateDataForUser(me);
    deleteRoomMessagesForUser(me);

    if(accounts[key]){
      delete accounts[key];
      saveAccounts();
    }

    send(ws,{type:'accountDeleted',mode:'all'});
    disconnect(ws);
    try{ws.close();}catch{}
    break;
  }

  case 'register':{
    send(ws,{type:'authError',code:'LOGIN_REQUIRED',message:'Kullanıcı adı ve şifre ile giriş yapmalısınız.'});
    break;
  }
  case 'appState':
  case 'appHeartbeat':{
    if(!me)break;

    const state=String(d.state||'').trim().toLowerCase();

    if(state!=='foreground' && state!=='background')break;

    const stateKey=normalizeUsername(me);
    appStates.set(stateKey,state);
    appStateUpdatedAt.set(stateKey,Date.now());

    if(d.type==='appState'){
      console.log(
        `[APP_STATE] ${me} -> ${state}`
      );
    }

    if(state==='foreground'){
      // Uygulama arka plandayken kuyruklanan WebRTC signaling event'leri
      // yeniden görünür olduğunda hemen teslim edilmeli.
      deliverPendingFileTransfers(ws,me);
    }

    break;
  }

  case 'fcmToken':{
    if(!me)break;

    refreshAccounts();

    const key=normalizeUsername(me);
    const token=cleanFcmToken(d.token);
    const account=accounts[key];

    if(!account || !token)break;

    account.fcmToken=token;
    account.fcmTokenUpdatedAt=Date.now();
    accounts[key]=account;
    saveAccounts();
    break;
  }

  case 'getProfile':{
    if(!me){
      send(ws,{
        type:'profileRejected',
        reason:'LOGIN_REQUIRED',
      });
      break;
    }

    refreshAccounts();

    const requestedUsername=String(
      d.username != null ? d.username : ''
    ).trim();

    if(!requestedUsername){
      send(ws,{
        type:'profileRejected',
        reason:'USERNAME_REQUIRED',
        username:requestedUsername,
      });
      break;
    }

    const account=accountFor(requestedUsername);

    if(!account){
      send(ws,{
        type:'profileRejected',
        reason:'USER_NOT_FOUND',
        username:requestedUsername,
      });
      break;
    }

    const viewerNick=users.get(ws);

    const isSelf=
      viewerNick &&
      normalizeUsername(viewerNick)===
        normalizeUsername(account.username);

    const profile=profileDataFor(account,{
      includePhoto:true,
    });

    send(ws,{
      type:'profile',
      username:account.username,
      profileType:profile.type,
      ...profile,
    });

    break;
  }

  case 'setProfile':{
    if(!me){
      send(ws,{
        type:'profileRejected',
        reason:'LOGIN_REQUIRED',
      });
      break;
    }

    refreshAccounts();

    const key=normalizeUsername(me);
    const account=accounts[key];

    if(!account)break;

    const profileType=String(
      d.profileType != null ? d.profileType : 'avatar'
    ).trim();

    if(profileType!=='avatar' && profileType!=='photo'){
      send(ws,{
        type:'profileRejected',
        username:account.username,
        reason:'INVALID_PROFILE_TYPE',
      });
      break;
    }

    let avatarId=null;

    if(
      d.avatarId !== null &&
      d.avatarId !== undefined &&
      String(d.avatarId).trim() !== ''
    ){
      const parsed=Number(d.avatarId);

      if(
        !Number.isInteger(parsed) ||
        parsed < 1 ||
        parsed > 50
      ){
        send(ws,{
          type:'profileRejected',
          username:account.username,
          reason:'INVALID_AVATAR',
        });
        break;
      }

      avatarId=parsed;
    }

    let about=
      d.about !== undefined
        ? String(d.about != null ? d.about : '').trim()
        : (typeof account.about==='string' ? account.about : '');

    about=about.slice(0,300);

    let photoData=
      d.photoData !== undefined
        ? String(d.photoData != null ? d.photoData : '').trim()
        : (typeof account.photoData==='string' ? account.photoData : '');

    if(photoData.length>700000){
      send(ws,{
        type:'profileRejected',
        username:account.username,
        reason:'PHOTO_TOO_LARGE',
      });
      break;
    }

    if(profileType==='avatar'){
      photoData='';
    }

    if(profileType==='photo'){
      avatarId=null;

      if(!photoData){
        send(ws,{
          type:'profileRejected',
          username:account.username,
          reason:'PHOTO_REQUIRED',
        });
        break;
      }
    }

    account.profileType=profileType;
    account.avatarId=avatarId;
    account.about=about;
    account.photoData=photoData;
    account.profileRevision=(Number(account.profileRevision)||0)+1;

    accounts[key]=account;
    saveAccounts();

    const profile=profileDataFor(account,{
      includePhoto:true,
    });

    send(ws,{
      type:'profile',
      username:account.username,
      ...profile,
    });

    for(const peer of users.keys()){
      const peerNick=users.get(peer);

      send(peer,{
        type:'profileUpdated',
        username:account.username,
        profileType:profile.type,
        profileRevision:profile.profileRevision,
        avatarId:profile.avatarId,
        about:profile.about,
        photoAvailable:profile.photoAvailable===true,
        // Profil fotoğrafı burada broadcast edilmez.
        // Büyük base64 payload'ın tüm bağlı kullanıcılara yayılması
        // mesaj/presence WebSocket trafiğinde ciddi lag oluşturabilir.
        // İhtiyaç halinde istemci getProfile ile fotoğrafı doğrudan ister.
      });
    }

    break;
  }

  case 'getPrivacySettings':{
    if(!me)break;

    refreshAccounts();

    const key=normalizeUsername(me);
    const account=accounts[key];

    if(!account)break;

    send(ws,{
      type:'privacySettings',
      presenceVisible:account.presenceVisible!==false,
      privateMessagesEnabled:account.privateMessagesEnabled!==false,
    });

    break;
  }

  case 'setPrivacySettings':{
    if(!me){
      send(ws,{
        type:'privacySettingsRejected',
        reason:'LOGIN_REQUIRED',
      });
      break;
    }

    refreshAccounts();

    const key=normalizeUsername(me);
    const account=accounts[key];

    if(!account)break;

    const previousPresence=account.presenceVisible!==false;

    if(typeof d.presenceVisible==='boolean'){
      account.presenceVisible=d.presenceVisible;
    }

    if(typeof d.privateMessagesEnabled==='boolean'){
      account.privateMessagesEnabled=d.privateMessagesEnabled;
    }

    accounts[key]=account;
    saveAccounts();

    send(ws,{
      type:'privacySettings',
      presenceVisible:account.presenceVisible!==false,
      privateMessagesEnabled:account.privateMessagesEnabled!==false,
    });

    const currentPresence=account.presenceVisible!==false;

    if(previousPresence!==currentPresence){
      if(currentPresence){
        broadcastUserOnline(account.username);
      }else{
        broadcastUserOffline(account.username);
      }

      updatePresence();
    }

    break;
  }

  case 'getNotificationSettings':{
    if(!me)break;

    refreshAccounts();

    const key=normalizeUsername(me);
    const account=accounts[key];

    if(!account)break;

    send(ws,{
      type:'notificationSettings',
      messageNotificationsEnabled:
        account.messageNotificationsEnabled!==false,
      callNotificationsEnabled:
        account.callNotificationsEnabled!==false,
      autoAcceptFileTransfers:
        account.autoAcceptFileTransfers!==false,
    });

    break;
  }

  case 'setNotificationSettings':{
    if(!me){
      send(ws,{
        type:'notificationSettingsRejected',
        reason:'LOGIN_REQUIRED',
      });
      break;
    }

    refreshAccounts();

    const key=normalizeUsername(me);
    const account=accounts[key];

    if(!account)break;

    if(typeof d.messageNotificationsEnabled==='boolean'){
      account.messageNotificationsEnabled=
        d.messageNotificationsEnabled;
    }

    if(typeof d.callNotificationsEnabled==='boolean'){
      account.callNotificationsEnabled=
        d.callNotificationsEnabled;
    }

    if(typeof d.autoAcceptFileTransfers==='boolean'){
      account.autoAcceptFileTransfers=d.autoAcceptFileTransfers;
    }

    accounts[key]=account;
    saveAccounts();

    send(ws,{
      type:'notificationSettings',
      messageNotificationsEnabled:
        account.messageNotificationsEnabled!==false,
      callNotificationsEnabled:
        account.callNotificationsEnabled!==false,
      autoAcceptFileTransfers:
        account.autoAcceptFileTransfers!==false,
    });

    break;
  }

  case 'listRooms':send(ws,{type:'rooms',rooms});break;
  case 'getPresence':{
    if(!me)break;

    send(ws,{
      type:'userList',
      users:visibleUsersFor(ws),
      profiles:visibleProfilesFor(ws),
    });

    sendUserDirectory(ws);
    send(ws,{type:'rooms',rooms});
    break;
  }
  case 'getUserDirectory':{
    if(!me)break;

    sendUserDirectory(ws);
    break;
  }
  case 'joinRoom':{if(!me)break;purgeExpiredRoomMessages();const id=String(d.room);if(!rooms.some(r=>r.id===id))break;ws._rooms.add(id);send(ws,{type:'roomHistory',room:id,messages:roomMessages.get(id)||[]});updatePresence();break;}
  case 'leaveRoom':{ws._rooms.delete(String(d.room));updatePresence();break;}
  case 'roomMessage':{if(!me)break;purgeExpiredRoomMessages();const id=String(d.room);if(!ws._rooms.has(id))break;const text=cleanText(d.text);if(!text)break;const ts=Date.now();const msg={id:makeMessageId(),type:'roomMessage',room:id,from:me,text,ts,expiresAt:ts+PRIVATE_MESSAGE_TTL_MS};const arr=roomMessages.get(id)||[];arr.push(msg);roomMessages.set(id,arr);save(`room-${id}.json`,arr);for(const [peer] of users){if((peer._rooms && peer._rooms.has(id)))send(peer,msg);}break;}
  case 'privateHistory':{if(!me)break;const peer=safeNick(d.peer);const messages=purgeExpiredPrivateMessages(me,peer);send(ws,{type:'privateHistory',peer,messages});break;}
  case 'privateFileMessage':{
    if(!me)break;

    const to=safeNick(d.to);
    const fileId=String(d.fileId||'').trim();
    const fileName=String(d.fileName||'').trim().slice(0,512);
    const fileSize=Number(d.fileSize||0);
    const clientMessageId=String(d.clientMessageId||'').trim();

    if(!to||!fileId||!fileName||!Number.isFinite(fileSize)||fileSize<=0)break;

    if(!privateMessagesEnabled(to)){
      send(ws,{
        type:'privateMessageRejected',
        to,
        reason:'PRIVATE_MESSAGES_DISABLED',
        message:'Bu kullanıcı özel mesajları kabul etmiyor.',
      });

      break;
    }

    const existing=findPrivateMessageByClientId(
      me,
      to,
      clientMessageId
    );

    if(existing){
      send(ws,{
        type:'messageAck',
        messageId:existing.id||null,
        clientMessageId:existing.clientMessageId||clientMessageId,
        status:'stored',
      });

      break;
    }

    const msg={
      id:makeMessageId(),
      clientMessageId:clientMessageId||null,
      type:'privateFileMessage',
      from:me,
      to,
      fileId,
      fileName,
      fileSize,
      ts:Date.now(),
      expiresAt:Date.now()+PRIVATE_MESSAGE_TTL_MS,
      delivered:false,
      transferStatus:'stored',
    };

    const stored=addPrivate(me,to,msg);

    send(ws,{
      type:'messageAck',
      messageId:stored.id||null,
      clientMessageId:stored.clientMessageId||null,
      status:'stored',
    });

    const recipient=socketFor(to);
    const recipientForeground=!!recipient && isForegroundActive(to);

    if(recipientForeground){
      send(recipient,stored);
    }else if(messageNotificationsEnabled(to)){
      const pushSent=await sendFcmPush(to,{
        data:{
          type:'privateFileMessage',
          messageId:String(stored.id||''),
          clientMessageId:String(stored.clientMessageId||''),
          sender:String(stored.from||''),
          recipient:String(stored.to||''),
          fileId:String(stored.fileId||''),
          fileName:String(stored.fileName||''),
          fileSize:String(stored.fileSize||0),
        },
        android:{
          priority:'high',
          ttl:3600000,
        },
      });
      if(pushSent){
        const delivered=markPrivateMessageDelivered(me,to,stored.id,stored.clientMessageId);
        if(delivered){
          send(socketFor(me),{
            type:'messageDelivered',
            messageId:delivered.id||null,
            clientMessageId:delivered.clientMessageId||null,
            from:to,
            to:me,
            deliveredTo:to,
            ts:delivered.deliveredAt||Date.now(),
          });
        }
      }
    }

    break;
  }

  case 'privateMessage':{
    if(!me)break;

    const to=safeNick(d.to);
    const text=cleanText(d.text);
    const clientMessageId=String(d.clientMessageId||'').trim();

    if(!to||!text)break;

    if(!privateMessagesEnabled(to)){
      send(ws,{
        type:'privateMessageRejected',
        to,
        reason:'PRIVATE_MESSAGES_DISABLED',
        message:'Bu kullanıcı özel mesajları kabul etmiyor.',
      });

      break;
    }

    const existing=findPrivateMessageByClientId(
      me,
      to,
      clientMessageId
    );

    if(existing){
      send(ws,{
        type:'messageAck',
        messageId:existing.id||null,
        clientMessageId:existing.clientMessageId||clientMessageId,
        status:'stored',
      });

      break;
    }

    const msg={
      id:makeMessageId(),
      clientMessageId:clientMessageId||null,
      type:'privateMessage',
      from:me,
      to,
      text,
      ts:Date.now(),
      expiresAt:Date.now()+PRIVATE_MESSAGE_TTL_MS,
      delivered:false,
    };

    const stored=addPrivate(me,to,msg);

    send(ws,{
      type:'messageAck',
      messageId:stored.id||null,
      clientMessageId:stored.clientMessageId||null,
      status:'stored',
    });

    const recipient=socketFor(to);
    const recipientForeground=!!recipient && isForegroundActive(to);

    if(recipientForeground){
      send(recipient,stored);
    }else if(messageNotificationsEnabled(to)){
      const pushSent=await sendFcmPush(to,{
        // DATA-ONLY:
        // Android arka planda kendi launcher notification'ını
        // oluşturmamalı. Native FCM service kendi PendingIntent'ini
        // oluşturacak ve doğrudan ilgili özel sohbete taşıyacak.
        data:{
          type:'privateMessage',
          messageId:String(stored.id||''),
          clientMessageId:String(stored.clientMessageId||''),
          sender:String(stored.from||''),
          recipient:String(stored.to||''),
          text:String(stored.text||''),
        },
        android:{
          priority:'high',
          ttl:86400000,
        },
      });
      if(pushSent){
        const delivered=markPrivateMessageDelivered(me,to,stored.id,stored.clientMessageId);
        if(delivered){
          send(socketFor(me),{
            type:'messageDelivered',
            messageId:delivered.id||null,
            clientMessageId:delivered.clientMessageId||null,
            from:to,
            to:me,
            deliveredTo:to,
            ts:delivered.deliveredAt||Date.now(),
          });
        }
      }
    }

    break;
  }
  case 'messageDelivered':{
    if(!me)break;

    const from=safeNick(d.from);
    const messageId=String(d.messageId||'').trim();
    const clientMessageId=String(d.clientMessageId||'').trim();

    if(!from || (!messageId && !clientMessageId))break;

    const delivered=markPrivateMessageDelivered(
      from,
      me,
      messageId,
      clientMessageId
    );

    if(!delivered)break;

    send(
      socketFor(from),
      {
        type:'messageDelivered',
        messageId:delivered.id||null,
        clientMessageId:delivered.clientMessageId||null,
        from:me,
        to:from,
        deliveredTo:me,
        ts:delivered.ts||null,
      }
    );

    break;
  }

  case 'messageRead':{
    if(!me)break;

    const from=safeNick(d.from);
    const messageId=String(d.messageId||'').trim();
    const clientMessageId=String(d.clientMessageId||'').trim();

    if(!from || (!messageId && !clientMessageId))break;

    const read=markPrivateMessageRead(
      me,
      from,
      messageId,
      clientMessageId
    );

    if(!read)break;

    const senderSocket=socketFor(from);

    send(
      senderSocket,
      {
        type:'messageRead',
        messageId:read.id||null,
        clientMessageId:read.clientMessageId||null,
        from:me,
        to:from,
        readBy:me,
        ts:read.readAt||Date.now(),
      }
    );

    break;
  }

  case 'callInvite':{
    if(!me)break;

    const to=safeNick(d.to);
    const callId=String(d.callId||'').trim();

    if(!to||!callId)break;

    const callerKey=normalizeUsername(me);
    const calleeKey=normalizeUsername(to);

    if(!calleeKey || callerKey===calleeKey)break;

    if(callStateFor(callId)){
      break;
    }

    const existingPartyCall=[...activeCalls.values()].find(call =>
      call.callerKey===callerKey ||
      call.calleeKey===callerKey ||
      call.callerKey===calleeKey ||
      call.calleeKey===calleeKey
    );

    if(existingPartyCall){
      break;
    }

    clearCallTimer(callId);

    activeCalls.set(callId,{
      callId,
      caller:me,
      callee:to,
      callerKey,
      calleeKey,
      state:'ringing',
      createdAt:Date.now(),
    });

    const recipient=socketFor(to);

    // Socket açık olsa bile uygulama foreground değilse kullanıcı
    // çağrıyı UI üzerinden göremeyebilir. Bu durumda WebSocket yerine
    // native FCM/full-screen çağrı akışını kullan.
    const recipientForeground =
      !!recipient &&
      isForegroundActive(to);

    if(recipientForeground){
      send(recipient,{
        type:'callInvite',
        from:me,
        to,
        callId,
      });
    }

    if(!recipientForeground && callNotificationsEnabled(to)){
      await sendFcmPush(to,{
        data:{
          type:'callInvite',
          caller:me,
          callee:to,
          callId,
        },
        android:{
          priority:'high',
          ttl:600000,
        },
      });
    }

    callTimers.set(callId,setTimeout(async()=>{
      const currentCall=callStateFor(callId);

      if(!currentCall || currentCall.state!=='ringing')return;

      endActiveCall(callId);

      const currentRecipient=socketFor(currentCall.callee);
      const currentCaller=socketFor(currentCall.caller);

      send(currentRecipient,{
        type:'callTimeout',
        from:currentCall.caller,
        to:currentCall.callee,
        callId,
      });

      send(currentCaller,{
        type:'callTimeout',
        from:currentCall.callee,
        to:currentCall.caller,
        callId,
      });

      await sendCallStatusPushIfOffline(
        currentCall.caller,
        callId,
        'Cevapsız çağrı',
        `${currentCall.callee} çağrınızı 60 saniye içinde cevaplamadı.`,
      );

      await sendCallStatusPushIfOffline(
        currentCall.callee,
        callId,
        'Cevapsız çağrı',
        `${currentCall.caller} tarafından gelen çağrı cevaplanmadı.`,
      );
    },60000));

    break;
  }
  case 'callAccept':case 'callReject':{
    if(!me)break;

    const to=safeNick(d.to);
    const callId=String(d.callId||'').trim();
    const call=callStateFor(callId);

    if(!to||!callId||!call)break;

    if(
      normalizeUsername(to)!==call.callerKey ||
      normalizeUsername(me)!==call.calleeKey ||
      call.state!=='ringing'
    ){
      break;
    }

    clearCallTimer(callId);

    if(d.type==='callAccept'){
      call.state='active';
      call.acceptedAt=Date.now();
    }else{
      endActiveCall(callId);
    }

    const recipient=socketFor(call.caller);

    send(
      recipient,
      {
        type:d.type==='callAccept'
          ? 'callAccepted'
          : 'callRejected',
        from:me,
        to:call.caller,
        callId,
      }
    );

    if(d.type==='callReject'){
      await sendCallStatusPushIfOffline(
        call.caller,
        callId,
        'Çağrı reddedildi',
        `${me} çağrınızı reddetti.`,
      );
    }

    break;
  }
  case 'callTimeout':{
    if(!me)break;

    const to=safeNick(d.to);
    const callId=String(d.callId||'').trim();
    const call=callStateFor(callId);

    if(!to||!callId||!call)break;

    if(
      normalizeUsername(me)!==call.callerKey ||
      normalizeUsername(to)!==call.calleeKey ||
      call.state!=='ringing'
    ){
      break;
    }

    endActiveCall(callId);

    const recipient=socketFor(call.callee);

    send(recipient,{
      type:'callTimeout',
      from:call.caller,
      to:call.callee,
      callId,
    });

    await sendCallStatusPushIfOffline(
      call.callee,
      callId,
      'Çağrı sonlandırıldı',
      `${call.caller} tarafından çağrı süresi doldu.`,
    );

    break;
  }
  case 'callOffer':case 'callAnswer':case 'callIce':{
    if(!me)break;

    const to=safeNick(d.to);
    const callId=String(d.callId||'').trim();
    const call=callStateFor(callId);

    if(!to||!callId||!call||call.state!=='active')break;

    if(!isCallPeer(call,me,to))break;

    const recipient=socketFor(to);

    send(recipient,{
      ...d,
      from:me,
      callId,
    });

    break;
  }
  case 'callEnd':{
    if(!me)break;

    const to=safeNick(d.to);
    const callId=String(d.callId||'').trim();
    const call=callStateFor(callId);

    if(!to||!callId||!call)break;

    if(!isCallParty(call,me))break;

    if(!isCallPeer(call,me,to))break;

    endActiveCall(callId);

    const recipient=socketFor(to);

    send(
      recipient,
      {
        type:'callEnded',
        from:me,
        to,
        callId,
      }
    );

    await sendCallStatusPushIfOffline(
      to,
      callId,
      'Çağrı sonlandırıldı',
      `${me} çağrıyı sonlandırdı.`,
    );

    break;
  }
  case 'fileTransferOffer':
  case 'fileTransferAnswer':
  case 'fileTransferIce':
  case 'fileTransferAccept':
  case 'fileTransferReject':
  case 'fileTransferComplete':
  case 'fileTransferFailed':{
    if(!me)break;

    const to=safeNick(d.to);
    const transferId=String(d.transferId||'').trim();

    if(!to||!transferId)break;

    /*
     * --------------------------------------------------------
     * TRANSFER LIFECYCLE GATE
     * --------------------------------------------------------
     *
     * Aynı transferId terminal duruma geldikten sonra:
     *
     *   OFFER
     *   ANSWER
     *   ICE
     *   ACCEPT
     *
     * gibi gecikmiş event'ler artık yeni transfer başlatamaz.
     */

    const lifecycle=getFileTransferLifecycle(
      me,
      to,
      transferId
    );

    if(
      lifecycle &&
      isTerminalFileTransferState(lifecycle.state)
    ){
      /*
       * COMPLETE sonrası sender'ın kendi doğrulaması başarısız
       * olabilir. Bu özel durumda COMPLETED -> FAILED geçişine
       * izin verilir.
       *
       * Bunun dışındaki gecikmiş signaling event'leri terminal
       * transferi yeniden canlandıramaz.
       */
      const allowCompletionFailure =
        lifecycle.state === 'completed' &&
        d.type === 'fileTransferFailed';

      if(!allowCompletionFailure){
        console.log(
          `[FILE_TRANSFER] terminal signal ignored ` +
          `type=${String(d.type||'')} ` +
          `transferId=${transferId} ` +
          `state=${lifecycle.state}`
        );

        break;
      }

      console.log(
        `[FILE_TRANSFER] completed -> failed override ` +
        `transferId=${transferId}`
      );
    }

    /*
     * İlk OFFER yeni transferin başlangıcıdır.
     * Diğer signaling event'leri mevcut transferi aktif tutar.
     */
    if(d.type==='fileTransferOffer'){
      updateFileTransferLifecycle(
        me,
        to,
        transferId,
        'active'
      );
    }

    const routedEvent=prepareFileTransferSignal(to,{
      ...d,
      from:me,
      to,
      transferId,
    });

    if(!routedEvent)break;

    /*
     * Terminal event ise lifecycle'i terminal yap.
     *
     * COMPLETE / FAILED / REJECTED'den sonra eski signaling
     * event'leri artık kabul edilmeyecek.
     */
    let terminalState=null;

    if(d.type==='fileTransferComplete'){
      terminalState='completed';
    }else if(d.type==='fileTransferFailed'){
      terminalState='failed';
    }else if(d.type==='fileTransferReject'){
      terminalState='rejected';
    }

    if(terminalState){
      updateFileTransferLifecycle(
        me,
        to,
        transferId,
        terminalState
      );

      updatePrivateFileMessageTransferState(
        me,
        to,
        transferId,
        terminalState,
      );
    }

    const recipient=socketFor(to);
    const recipientConnected=!!recipient;
    const recipientForeground=recipientConnected && isForegroundActive(to);

    let deliveredLive=false;

    /*
     * Dosya OFFER'ı yalnızca alıcı gerçekten foreground'da ise
     * canlı WebSocket üzerinden teslim edilir.
     *
     * Android arka planda WebSocket'i bir süre açık tutabilir. Eski
     * davranışta bu durumda OFFER socket'e gönderiliyor ve FCM hiç
     * gönderilmiyordu. Kullanıcı bu yüzden dosya bildirimi alamıyordu.
     *
     * Background durumda OFFER + ICE pending kuyruğunda tutulur ve
     * FCM alıcıyı uygulamaya geri getirir.
     */
    if(recipientForeground){
      deliveredLive=send(recipient,routedEvent);
    }

    if(!deliveredLive){
      if(terminalState){
        /*
         * Recipient offline ise eski signaling kuyruğunu terminal
         * event ile değiştir.
         *
         * Böylece reconnect sonrası eski OFFER/ICE/ANSWER zinciri
         * yeniden çalıştırılmaz.
         */
        storeTerminalPendingFileTransfer(
          to,
          routedEvent
        );
      }else{
        storePendingFileTransfer(
          to,
          routedEvent
        );
      }

      /*
       * FCM yalnızca yeni dosya OFFER'ı için gönderilir.
       * Böylece terminal event'leri kullanıcıya yeni dosya bildirimi
       * gibi görünmez.
       */
      if(
        d.type==='fileTransferOffer' &&
        messageNotificationsEnabled(to)
      ){
        await sendFcmPush(to,{
          data:{
            type:'privateFileMessage',
            messageId:'',
            clientMessageId:transferId,
            sender:me,
            recipient:to,
            fileId:transferId,
            fileName:String(d.fileName||'Dosya'),
            fileSize:String(Number(d.fileSize||0)),
          },
          android:{
            priority:'high',
            ttl:3600000,
          },
        });
      }
    }

    /*
     * Terminal transfer için pending signaling state'i temizle.
     *
     * Canlı socket'e gönderildiyse zaten gerekli event karşı tarafa
     * ulaştı. Offline durumda ise storeTerminal... yalnızca terminal
     * event'i bırakmıştır.
     */
    if(terminalState && deliveredLive){
      clearPendingFileTransfer(
        to,
        transferId
      );
    }

    if(terminalState){
      // Terminal transfer için eski signaling fingerprint/sequence
      // state'ini de temizle. Lifecycle tombstone 10 dakika boyunca
      // transferId'nin yeniden canlanmasını engellemeye devam eder.
      const signalKey=pendingFileTransferKey(
        to,
        transferId
      );

      fileTransferSignalState.delete(signalKey);

      console.log(
        `[FILE_TRANSFER] terminal cleanup ` +
        `type=${String(d.type||'')} ` +
        `transferId=${transferId} ` +
        `deliveredLive=${deliveredLive}`
      );
    }

    break;
  }
 }
 });ws.on('close',()=>disconnect(ws));ws.on('error',()=>disconnect(ws));
});
server.listen(PORT,'0.0.0.0',()=>console.log(`ZeroLog server listening on ${PORT}`));
