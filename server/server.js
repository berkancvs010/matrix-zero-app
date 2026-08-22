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
const privateMessages=new Map();
const users=new Map(); // ws -> nick
const sockets=new Map(); // nick -> ws
const callTimers=new Map();

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
      if(sockets.get(nick)===ws)sockets.delete(nick);
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
function cleanText(v){return String((v != null ? v : '')).trim().slice(0,2000);}
function makeMessageId(){
  return `${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
}
function normalizeRoomMessages(list, roomId){
  if(!Array.isArray(list))return [];
  let changed=false;
  const result=list.map((msg,index)=>{
    if(!msg || typeof msg!=='object')return msg;
    if(msg.id)return msg;
    changed=true;
    return {
      ...msg,
      id:`legacy-${roomId}-${msg.ts||0}-${index}`
    };
  });
  return changed ? result.slice(-300) : result;
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
function getPrivate(a,b){const k=pairKey(a,b);if(!privateMessages.has(k))privateMessages.set(k,load(privateFile(a,b),[]));return privateMessages.get(k);}
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
  users.delete(ws);
  if(sockets.get(nick)===ws)sockets.delete(nick);
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
      profileType:'avatar',
      avatarId:null,
      about:'',
      photoData:''
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
    });

    sendUserDirectory(ws);

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

    if(!isSelf && !presenceVisible(account.username)){
      send(ws,{
        type:'profileRejected',
        reason:'PROFILE_NOT_VISIBLE',
        username:account.username,
      });
      break;
    }

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
          reason:'PHOTO_REQUIRED',
        });
        break;
      }
    }

    account.profileType=profileType;
    account.avatarId=avatarId;
    account.about=about;
    account.photoData=photoData;

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

      if(
        peerNick &&
        normalizeUsername(peerNick)!==
          normalizeUsername(account.username) &&
        !presenceVisible(account.username)
      ){
        continue;
      }

      send(peer,{
        type:'profileUpdated',
        username:account.username,
        profileType:profile.type,
        ...profile,
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

    accounts[key]=account;
    saveAccounts();

    send(ws,{
      type:'notificationSettings',
      messageNotificationsEnabled:
        account.messageNotificationsEnabled!==false,
      callNotificationsEnabled:
        account.callNotificationsEnabled!==false,
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
  case 'joinRoom':{if(!me)break;const id=String(d.room);if(!rooms.some(r=>r.id===id))break;ws._rooms.add(id);send(ws,{type:'roomHistory',room:id,messages:roomMessages.get(id)||[]});updatePresence();break;}
  case 'leaveRoom':{ws._rooms.delete(String(d.room));updatePresence();break;}
  case 'roomMessage':{if(!me)break;const id=String(d.room);if(!ws._rooms.has(id))break;const text=cleanText(d.text);if(!text)break;const msg={id:makeMessageId(),type:'roomMessage',room:id,from:me,text,ts:Date.now()};const arr=roomMessages.get(id)||[];arr.push(msg);roomMessages.set(id,arr);save(`room-${id}.json`,arr);for(const [peer] of users){if((peer._rooms && peer._rooms.has(id)))send(peer,msg);}break;}
  case 'privateHistory':{if(!me)break;const peer=safeNick(d.peer);send(ws,{type:'privateHistory',peer,messages:getPrivate(me,peer)});break;}
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
        clientMessageId,
        status:'stored',
      });

      const recipient=socketFor(to);

      if(recipient){
        send(recipient,existing);
      }

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

    if(recipient){
      send(recipient,stored);
    }else if(messageNotificationsEnabled(to)){
      await sendFcmPush(to,{
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
        clientMessageId,
        status:'stored',
      });

      const recipient=socketFor(to);

      if(recipient){
        send(recipient,existing);
      }

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

    if(recipient){
      send(recipient,stored);
    }else if(messageNotificationsEnabled(to)){
      await sendFcmPush(to,{
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

    clearCallTimer(callId);

    const recipient=socketFor(to);

    send(recipient,{
      type:'callInvite',
      from:me,
      to,
      callId,
    });

    // Online kullanıcı çağrıyı WebSocket üzerinden zaten alır.
    // FCM yalnızca gerçekten offline durumda devreye girer.
    if(!recipient && callNotificationsEnabled(to)){
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
      callTimers.delete(callId);

      const currentRecipient=socketFor(to);
      const currentCaller=socketFor(me);

      send(currentRecipient,{
        type:'callTimeout',
        from:me,
        to,
        callId,
      });

      send(currentCaller,{
        type:'callTimeout',
        from:to,
        to:me,
        callId,
      });

      await sendCallStatusPushIfOffline(
        me,
        callId,
        'Cevapsız çağrı',
        `${to} çağrınızı 60 saniye içinde cevaplamadı.`,
      );

      await sendCallStatusPushIfOffline(
        to,
        callId,
        'Cevapsız çağrı',
        `${me} tarafından gelen çağrı cevaplanmadı.`,
      );
    },60000));

    break;
  }
  case 'callAccept':case 'callReject':{
    if(!me)break;

    const to=safeNick(d.to);
    const targetKey=normalizeUsername(to);
    const callId=String(d.callId||'').trim();

    if(callId)clearCallTimer(callId);

    const recipientName=[...sockets.keys()]
      .find(nick=>normalizeUsername(nick)===targetKey);

    const recipient=recipientName ? sockets.get(recipientName) : null;

    send(
      recipient,
      {
        type:d.type==='callAccept'
          ? 'callAccepted'
          : 'callRejected',
        from:me,
        to,
        callId,
      }
    );

    if(d.type==='callReject'){
      await sendCallStatusPushIfOffline(
        to,
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

    if(!to||!callId)break;

    clearCallTimer(callId);

    const targetKey=normalizeUsername(to);

    const recipientName=[...sockets.keys()]
      .find(nick=>normalizeUsername(nick)===targetKey);

    const recipient=recipientName ? sockets.get(recipientName) : null;

    send(recipient,{
      type:'callTimeout',
      from:me,
      to,
      callId,
    });

    await sendCallStatusPushIfOffline(
      to,
      callId,
      'Çağrı sonlandırıldı',
      `${me} tarafından çağrı süresi doldu.`,
    );

    break;
  }

  case 'callOffer':case 'callAnswer':case 'callIce':{
    if(!me)break;

    const to=safeNick(d.to);
    const targetKey=normalizeUsername(to);

    const recipientName=[...sockets.keys()]
      .find(nick=>normalizeUsername(nick)===targetKey);

    const recipient=recipientName ? sockets.get(recipientName) : null;

    send(recipient,{...d,from:me});

    break;
  }

  case 'callEnd':{
    if(!me)break;

    const to=safeNick(d.to);
    const callId=String(d.callId||'').trim();

    if(callId)clearCallTimer(callId);
    const targetKey=normalizeUsername(to);

    const recipientName=[...sockets.keys()]
      .find(nick=>normalizeUsername(nick)===targetKey);

    const recipient=recipientName ? sockets.get(recipientName) : null;

    send(
      recipient,
      {
        type:'callEnded',
        from:me,
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

    const targetKey=normalizeUsername(to);

    const recipientName=[...sockets.keys()]
      .find(nick=>normalizeUsername(nick)===targetKey);

    const recipient=recipientName ? sockets.get(recipientName) : null;

    // Sunucu yalnızca WebRTC signaling taşır.
    // Dosya verisi kesinlikle sunucuya gönderilmez.
    send(recipient,{
      ...d,
      from:me,
      to,
      transferId,
    });

    break;
  }
 }
 });ws.on('close',()=>disconnect(ws));ws.on('error',()=>disconnect(ws));
});
server.listen(PORT,'0.0.0.0',()=>console.log(`ZeroLog server listening on ${PORT}`));
