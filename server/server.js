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
const sockets=new Map(); // nick -> primary foreground ws
const backgroundSockets=new Map(); // normalized nick -> Map(transferId -> {ws,transferId})
const backgroundSocketByWs=new Map(); // ws -> transferId

// Reliable WebSocket file-transfer sessions. File bytes are relayed only;
// the server does not persist file contents.
const reliableFileTransfers=new Map(); // transferId -> session
const RELIABLE_FILE_TRANSFER_TTL_MS=60*60*1000;
const RELIABLE_FILE_MAX_CHUNK_BYTES=128*1024;
// Keep up to two full sender windows in memory while the receiver socket is
// waking/reconnecting. With 128 KiB chunks this is about 16 MiB per transfer.

// File contents are never persisted to disk.
const RELIABLE_FILE_MAX_PENDING_CHUNKS=128;
const RELIABLE_FILE_MAX_PENDING_BYTES=64*1024*1024;
// O(1) global accounting for queued relay bytes. File contents remain RAM-only.
let reliablePendingTotalBytes=0;
const RELIABLE_FILE_MAX_SIZE=1024*1024*1024;
const RELIABLE_FILE_META_PREFIX='reliable-file-';

// WebSocket bağlantısı açık kalsa bile uygulamanın gerçek UI durumunu
// takip eder. foreground dışındaki kullanıcılar çağrı açısından offline
// kabul edilir ve FCM üzerinden native çağrı bildirimi alır.
const appStates=new Map(); // normalized username -> foreground/background
const appStateUpdatedAt=new Map(); // normalized username -> last lifecycle/heartbeat time
const APP_FOREGROUND_HEARTBEAT_TTL_MS=45*1000;
const LOGIN_RATE_WINDOW_MS=15*60*1000;
const LOGIN_RATE_MAX_FAILURES=5;
const LOGIN_RATE_BASE_DELAY_MS=1000;
const LOGIN_RATE_MAX_DELAY_MS=60*1000;
const loginFailures=new Map();

function clientAddress(ws){
  const address=String(ws && ws._remoteAddress || '').trim();
  return address || 'unknown';
}

function loginRateKey(ws,username){
  return `${clientAddress(ws)}|${normalizeUsername(username)}`;
}

function loginRateCheck(ws,username){
  const key=loginRateKey(ws,username);
  const now=Date.now();
  const entry=loginFailures.get(key);
  if(!entry)return {allowed:true,key};
  if(now-entry.firstAt>LOGIN_RATE_WINDOW_MS){
    loginFailures.delete(key);
    return {allowed:true,key};
  }
  const failures=Math.max(0,Number(entry.failures)||0);
  const delay=failures>=LOGIN_RATE_MAX_FAILURES
    ? Math.min(LOGIN_RATE_MAX_DELAY_MS,LOGIN_RATE_BASE_DELAY_MS*Math.pow(2,failures-LOGIN_RATE_MAX_FAILURES))
    : 0;
  if(delay>0 && now-entry.lastAt<delay){
    return {allowed:false,key,retryAfterMs:delay-(now-entry.lastAt)};
  }
  return {allowed:true,key};
}

function loginRateFailure(key){
  const now=Date.now();
  const current=loginFailures.get(key);
  if(!current || now-current.firstAt>LOGIN_RATE_WINDOW_MS){
    loginFailures.set(key,{failures:1,firstAt:now,lastAt:now});
  }else{
    current.failures=(Number(current.failures)||0)+1;
    current.lastAt=now;
  }
}

function loginRateSuccess(key){
  loginFailures.delete(key);
}

const loginRateCleanupInterval=setInterval(()=>{
  const now=Date.now();
  for(const [key,entry] of loginFailures){
    if(!entry || now-Number(entry.lastAt||0)>LOGIN_RATE_WINDOW_MS){
      loginFailures.delete(key);
    }
  }
},LOGIN_RATE_WINDOW_MS);
loginRateCleanupInterval.unref();

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


function reliableFileMetaName(transferId){
  const hash=crypto.createHash('sha256').update(String(transferId||'')).digest('hex');
  return `${RELIABLE_FILE_META_PREFIX}${hash}.json`;
}

function persistReliableFileSession(session){
  if(!session || !session.transferId)return;
  const safe={
    transferId:session.transferId,
    from:session.from,
    to:session.to,
    fromKey:session.fromKey,
    toKey:session.toKey,
    fileName:session.fileName,
    fileSize:session.fileSize,
    sha256:session.sha256,
    clientMessageId:session.clientMessageId,
    messageId:session.messageId,
    deliveryToken:session.deliveryToken||'',
    state:session.state,
    accepted:session.accepted===true,
    receivedBytes:Number(session.receivedBytes)||0,
    lastReceivedSeq:Number.isSafeInteger(session.lastReceivedSeq)
      ? session.lastReceivedSeq : -1,
    pendingEnd:session.pendingEnd||null,
    lastWakePushAt:Number(session.lastWakePushAt)||0,
    wakePushCount:Number(session.wakePushCount)||0,
    failureReason:session.failureReason||'',
    failureEvents:session.failureEvents||null,
    failureAcks:session.failureAcks||null,
    terminalUntil:Number(session.terminalUntil)||0,
    updatedAt:Number(session.updatedAt)||Date.now(),
  };
  try{
    const target=path.join(DATA,reliableFileMetaName(session.transferId));
    const temp=`${target}.tmp`;
    fs.writeFileSync(temp,JSON.stringify(safe),{mode:0o600});
    fs.renameSync(temp,target);
  }catch(error){
    console.error(`[FILE_TRANSFER] metadata save failed: ${error && error.message || error}`);
  }
}

function deleteReliableFileMeta(transferId){
  try{
    fs.unlinkSync(path.join(DATA,reliableFileMetaName(transferId)));
  }catch{}
}

function removeReliableFileSession(transferId){
  const key=String(transferId||'').trim();
  const session=reliableFileTransfers.get(key);
  if(session){
    const pending=Number(session.pendingBytes)||0;
    reliablePendingTotalBytes=Math.max(0,reliablePendingTotalBytes-pending);
    session.pendingBytes=0;
    session.pendingChunks=[];
    reliableFileTransfers.delete(key);
  }else{
    reliableFileTransfers.delete(key);
  }
  deleteReliableFileMeta(key);
}

function loadReliableFileSessions(){
  try{
    for(const file of fs.readdirSync(DATA)){
      if(!file.startsWith(RELIABLE_FILE_META_PREFIX) || !file.endsWith('.json'))continue;
      const meta=load(file,null);
      if(!meta || !meta.transferId || !meta.fromKey || !meta.toKey)continue;
      if(!Number.isSafeInteger(Number(meta.fileSize)) ||
         Number(meta.fileSize)<=0 || Number(meta.fileSize)>RELIABLE_FILE_MAX_SIZE ||
         !/^[a-f0-9]{64}$/.test(String(meta.sha256||'')))continue;
      if(meta.state==='completed' || meta.state==='failed' || meta.state==='rejected'){
        const terminalUntil=Number(meta.terminalUntil)||0;
        if(meta.state==='failed' && terminalUntil>Date.now()){
          const session={
            ...meta,
            fileSize:Number(meta.fileSize),
            pendingChunks:[],
            pendingBytes:0,
            receiverWs:null,
            failureAcks:{
              sender:meta.failureAcks && meta.failureAcks.sender===true,
              receiver:meta.failureAcks && meta.failureAcks.receiver===true,
            },
            terminalUntil,
            updatedAt:Number(meta.updatedAt)||Date.now(),
          };
          reliableFileTransfers.set(String(meta.transferId),session);
        }else if(meta.state!=='completed'){
          deleteReliableFileMeta(meta.transferId);
        }
        continue;
      }
      const session={
        ...meta,
        fileSize:Number(meta.fileSize),
        receivedBytes:Number(meta.receivedBytes)||0,
        lastReceivedSeq:Number.isSafeInteger(Number(meta.lastReceivedSeq))
          ? Number(meta.lastReceivedSeq) : -1,
        pendingChunks:[],
        pendingBytes:0,
        receiverWs:null,
        pendingEnd:meta.pendingEnd||null,
        lastWakePushAt:Number(meta.lastWakePushAt)||0,
        wakePushCount:Number(meta.wakePushCount)||0,
        updatedAt:Number(meta.updatedAt)||Date.now(),
      };
      reliableFileTransfers.set(String(meta.transferId),session);
    }
  }catch(error){
    console.error(`[FILE_TRANSFER] metadata load failed: ${error && error.message || error}`);
  }
}

function cleanupReliableFileTransfers(){
  const now=Date.now();

  for(const [transferId,session] of reliableFileTransfers){
    if(!session){
      removeReliableFileSession(transferId);
      continue;
    }
    if(session.state==='failed' || session.state==='rejected'){
      if(Number(session.terminalUntil||0)<=now){
        removeReliableFileSession(transferId);
      }
      continue;
    }
    if(
      !session.updatedAt ||
      now-session.updatedAt>RELIABLE_FILE_TRANSFER_TTL_MS
    ){
      removeReliableFileSession(transferId);
    }
  }
}

function reliableFileSession(transferId){
  cleanupReliableFileTransfers();
  return reliableFileTransfers.get(String(transferId||'').trim())||null;
}

// Keep the Node/ws socket buffer bounded. A mobile receiver can consume
// chunks much slower than the sender can enqueue them; blindly calling
// ws.send() lets several megabytes accumulate in the native socket buffer and
// makes the receiver appear to stall around the same percentage. Returning
// false here is intentionally treated by the reliable relay as backpressure,
// not as a connection failure.
const RELIABLE_FILE_SOCKET_HIGH_WATER_BYTES=2*1024*1024;

function reliablePendingBytes(){
  return reliablePendingTotalBytes;
}

function reliableFileFrameSequence(buffer){
  if(!Buffer.isBuffer(buffer) || buffer.length<11)return -1;
  if(buffer[0]!==0x5a || buffer[1]!==0x4c || buffer[2]!==0x46 || buffer[3]!==0x32 || buffer[4]!==1){
    return -1;
  }
  const idLength=buffer.readUInt16BE(5);
  const headerLength=11+idLength;
  if(idLength<=0 || idLength>256 || buffer.length<=headerLength)return -1;
  return buffer.readUInt32BE(7+idLength);
}

function queueReliableFileChunk(session,buffer){
  if(!session || !Buffer.isBuffer(buffer)) return false;
  if(!Array.isArray(session.pendingChunks)) session.pendingChunks=[];
  const seq=reliableFileFrameSequence(buffer);
  if(seq<0)return false;

  // The sender may replay the same outstanding frame after a lost ACK.
  // Never enqueue the same sequence twice while the receiver socket is
  // unavailable or under backpressure. Duplicate frames are harmless once
  // delivered to the receiver, but duplicate relay buffering wastes the
  // bounded RAM budget and can make large transfers fail spuriously.
  for(const pending of session.pendingChunks){
    if(reliableFileFrameSequence(pending)===seq)return true;
  }

  if(session.pendingChunks.length>=RELIABLE_FILE_MAX_PENDING_CHUNKS) return false;

  const currentBytes=Number(session.pendingBytes)||0;
  if(
    currentBytes+buffer.length>RELIABLE_FILE_MAX_PENDING_BYTES ||
    reliablePendingBytes()+buffer.length>RELIABLE_FILE_MAX_PENDING_BYTES
  ){
    return false;
  }

  session.pendingChunks.push(Buffer.from(buffer));
  session.pendingBytes=currentBytes+buffer.length;
  reliablePendingTotalBytes+=buffer.length;
  session.updatedAt=Date.now();
  return true;
}

function sendBinary(ws,buffer){
  if(
    !ws ||
    ws.readyState!==1 ||
    ws.isAlive===false ||
    !Buffer.isBuffer(buffer) ||
    buffer.length===0
  ){
    return false;
  }

  try{
    if(
      Number(ws.bufferedAmount||0)+buffer.length>
      RELIABLE_FILE_SOCKET_HIGH_WATER_BYTES
    ){
      return false;
    }

    ws.send(buffer);
    return true;
  }catch(error){
    console.error('[FILE_TRANSFER] binary send failed:',error && error.message || error);
    disconnect(ws);
    return false;
  }
}

function reliableFileOffer(session){
  return {
    type:'fileTransferOffer',
    from:session.from,
    to:session.to,
    transferId:session.transferId,
    fileName:session.fileName,
    fileSize:session.fileSize,
    sha256:session.sha256,
  };
}

function failReliableFileTransfer(session,reason,sourceWs=null){
  if(!session || !session.transferId)return false;

  const transferId=String(session.transferId).trim();
  session.state='failed';
  session.updatedAt=Date.now();

  // A failed transfer must release any relay-buffered chunks immediately.
  // Terminal failure metadata is persisted separately for ACK/replay, so
  // retaining binary payloads for the 10-minute terminal TTL would only waste
  // the global RAM relay budget.
  const pendingBytes=Number(session.pendingBytes)||0;
  if(pendingBytes>0){
    reliablePendingTotalBytes=Math.max(
      0,
      reliablePendingTotalBytes-pendingBytes,
    );
  }
  session.pendingBytes=0;
  session.pendingChunks=[];

  updateReliableFileMessage(
    session.from,
    session.to,
    transferId,
    'failed',
  );

  const eventForSender={
    type:'fileTransferFailed',
    from:session.to,
    to:session.from,
    transferId,
    reason:String(reason||'Dosya transferi başarısız oldu.'),
  };
  const eventForReceiver={
    type:'fileTransferFailed',
    from:session.from,
    to:session.to,
    transferId,
    reason:String(reason||'Dosya transferi başarısız oldu.'),
  };

  const sender=fileSocketFor(session.from,transferId);
  const receiver=fileSocketFor(session.to,transferId);

  session.state='failed';
  session.failureReason=String(reason||'Dosya transferi başarısız oldu.');
  session.failureEvents={
    sender:eventForSender,
    receiver:eventForReceiver,
  };
  session.failureAcks={sender:false,receiver:false};
  session.terminalUntil=Date.now()+10*60*1000;
  session.updatedAt=Date.now();
  persistReliableFileSession(session);

  const deliveredSender=send(sender,eventForSender);
  const deliveredReceiver=send(receiver,eventForReceiver);

  if(!deliveredSender){
    storeTerminalPendingFileTransfer(session.from,eventForSender);
  }
  if(!deliveredReceiver){
    storeTerminalPendingFileTransfer(session.to,eventForReceiver);
  }

  return deliveredSender || deliveredReceiver;
}

async function sendReliableFileOffer(session){
  if(!session || !session.transferId)return false;

  const recipient=fileSocketFor(session.to,session.transferId);

  /*
   * A dedicated background socket is the preferred transport endpoint.
   * FCM remains the durable wake-up path when no transfer socket exists.
   * The FCM payload is DATA-only and HIGH priority so Android can start the
   * dataSync foreground service from the background.
   */
  if(recipient && recipient.isAlive!==false){
    const backgroundEndpoint=isBackgroundSocket(recipient);
    const foregroundEndpoint=isForegroundActive(session.to);
    const delivered=send(recipient,reliableFileOffer(session));

    if(delivered){
      console.log(
        `[FILE_TRANSFER] OFFER live transfer=${session.transferId} ` +
        `to=${session.to} endpoint=${backgroundEndpoint?'background':'foreground'}`
      );

      if(foregroundEndpoint || backgroundEndpoint){
        return true;
      }
    }
  }

  /*
   * Presence can legitimately be stale for a short period: Android may have
   * killed the primary socket, or the appState heartbeat may still say
   * "foreground" while the WebSocket is already gone. In that case refusing
   * the FCM wake-up strands the durable transfer indefinitely.
   *
   * FCM is only a wake-up path, not the file transport. If no live
   * transfer/foreground socket accepted the OFFER above, always allow the
   * data-only FCM wake-up to start/reconnect the receiver.
   */
  const pushed=await sendFcmPush(session.to,{
    data:{
      type:'privateFileMessage',
      sender:session.from,
      recipient:session.to,
      fileId:session.transferId,
      transferId:session.transferId,
      fileName:session.fileName,
      fileSize:String(session.fileSize),
      sha256:session.sha256,
      clientMessageId:session.clientMessageId,
      deliveryToken:session.deliveryToken||'',
      messageId:session.messageId,
    },
    android:{
      priority:'high',
      ttl:3600000,
    },
  });

  if(pushed){
    session.lastWakePushAt=Date.now();
    session.wakePushCount=(Number(session.wakePushCount)||0)+1;
    session.updatedAt=Date.now();
    persistReliableFileSession(session);
    console.log(
      `[FILE_TRANSFER] FCM_WAKE transfer=${session.transferId} ` +
      `count=${session.wakePushCount}`
    );
  }

  return pushed;
}

function updateReliableFileMessage(from,to,transferId,status,extra={}){
  const arr=getPrivate(from,to);
  const index=arr.findIndex(item =>
    item &&
    item.type==='privateFileMessage' &&
    String(item.fileId||'')===String(transferId||'')
  );

  if(index<0)return null;

  arr[index]={
    ...arr[index],
    transferStatus:status,
    ...extra,
  };

  if(status==='completed'){
    arr[index].delivered=true;
    arr[index].transferBytes=Number(arr[index].fileSize)||0;
    arr[index].deliveredAt=Date.now();
  }

  save(privateFile(from,to),arr);
  return arr[index];
}

function deliverTerminalFileFailures(ws,username){
  const key=normalizeUsername(username);
  if(!key)return;
  for(const session of reliableFileTransfers.values()){
    if(!session || session.state!=='failed')continue;
    const isSender=session.fromKey===key;
    const isReceiver=session.toKey===key;
    if(!isSender && !isReceiver)continue;
    const role=isSender?'sender':'receiver';
    const acks=session.failureAcks||{};
    if(acks[role]===true)continue;
    const event=session.failureEvents && session.failureEvents[role];
    if(!event)continue;
    if(send(ws,event)){
      session.updatedAt=Date.now();
    }
  }
}

async function handleReliableFileEvent(ws,d,me){
  const type=String(d && d.type || '');

  if(![
    'fileTransferStart',
    'fileTransferAccept',
    'fileTransferReject',
    'fileTransferChunkAck',
    'fileTransferEnd',
    'fileTransferComplete',
    'fileTransferFailed',
    'fileTransferFailedAck',
     'fileTransferResume',
  ].includes(type)){
    return false;
  }

  if(!me)return true;

  const transferId=String(d.transferId||'').trim();
  if(!transferId)return true;

  if(type==='fileTransferStart'){
    const to=safeNick(d.to);
    const fileName=String(d.fileName||'Dosya').trim().slice(0,512);
    const fileSize=Number(d.fileSize||0);
    const sha256=String(d.sha256||'').trim().toLowerCase();
    const clientMessageId=String(d.clientMessageId||transferId).trim();

    if(
      !to ||
      !fileName ||
      !Number.isSafeInteger(fileSize) ||
      fileSize<=0 ||
      fileSize>RELIABLE_FILE_MAX_SIZE ||
      !/^[a-f0-9]{64}$/.test(sha256)
    ){
      send(ws,{
        type:'fileTransferFailed',
        transferId,
        reason:'Geçersiz dosya bilgisi.',
      });
      return true;
    }

    if(normalizeUsername(to)===normalizeUsername(me)){
      send(ws,{
        type:'fileTransferFailed',
        transferId,
        reason:'Dosya kendinize gönderilemez.',
      });
      return true;
    }

    if(!privateMessagesEnabled(to)){
      send(ws,{
        type:'fileTransferFailed',
        transferId,
        reason:'Karşı kullanıcı özel mesajları kabul etmiyor.',
      });
      return true;
    }

    cleanupReliableFileTransfers();

    const existing=reliableFileTransfers.get(transferId);
    if(existing){
      if(
        existing.fromKey!==normalizeUsername(me) ||
        existing.toKey!==normalizeUsername(to)
      ){
        send(ws,{
          type:'fileTransferFailed',
          transferId,
          reason:'Transfer kimliği zaten kullanımda.',
        });
        return true;
      }

      send(ws,{
        type:'fileTransferStartAck',
        transferId,
        status:'stored',
      });
      return true;
    }

    const msg={
      id:makeMessageId(),
      clientMessageId,
      type:'privateFileMessage',
      from:me,
      to,
      fileId:transferId,
      fileName,
      fileSize,
      ts:Date.now(),
      expiresAt:Date.now()+PRIVATE_MESSAGE_TTL_MS,
      delivered:false,
      deliveryToken:crypto.randomBytes(24).toString('hex'),
      read:false,
      transferStatus:'waiting',
      transferBytes:0,
    };

    const stored=addPrivate(me,to,msg);

    const session={
      transferId,
      from:me,
      to,
      fromKey:normalizeUsername(me),
      toKey:normalizeUsername(to),
      fileName,
      fileSize,
      sha256,
      clientMessageId,
      messageId:stored.id,
      deliveryToken:stored.deliveryToken||'',
      state:'waiting',
      accepted:false,
      receivedBytes:0,
      pendingChunks:[],
      pendingBytes:0,
      pendingEnd:null,
      receiverWs:null,
      updatedAt:Date.now(),
    };

    reliableFileTransfers.set(transferId,session);

    send(ws,{
      type:'fileTransferStartAck',
      transferId,
      messageId:stored.id,
      clientMessageId:stored.clientMessageId,
      status:'stored',
    });

    /*
     * The private-file message and the transfer OFFER are two different
     * concerns:
     *
     *   1) the chat message must reach an already-connected chat client;
     *   2) the transfer service must receive a wake-up/OFFER when the app is
     *      backgrounded or terminated.
     *
     * Never make the chat message depend on FCM success. In particular, the
     * previous implementation could send the OFFER successfully over the
     * foreground socket while never sending the actual privateFileMessage,
     * leaving the transfer invisible in the chat history.
     *
     * The reliable session remains the server-side source of truth. FCM is
     * an additional wake-up path, not the transfer itself.
     */
    const recipient=socketFor(to);
    const foregroundRecipient=
      recipient &&
      recipient.isAlive!==false &&
      isForegroundActive(to) &&
      !isBackgroundSocket(recipient)
        ? recipient
        : null;

    let liveMessageDelivered=false;

    if(foregroundRecipient){
      liveMessageDelivered=send(foregroundRecipient,{
        ...stored,
        transferStatus:'waiting',
        transferBytes:0,
      });

      if(!liveMessageDelivered){
        console.warn(
          `[FILE_TRANSFER] MESSAGE live delivery failed ` +
          `transfer=${session.transferId} to=${session.to}`
        );
      }
    }

    const account=accountFor(to);
    const autoAccept=
      !account || account.autoAcceptFileTransfers!==false;

    /*
     * If the receiver has an active foreground chat, deliver the OFFER
     * directly so the transfer can start without waiting for FCM.
     *
     * If the receiver is not foreground, sendReliableFileOffer() uses the
     * transfer-specific background socket when present and otherwise sends
     * the DATA-only FCM wake-up.
     */
    let offerDelivered=false;

    if(foregroundRecipient){
      offerDelivered=send(
        foregroundRecipient,
        reliableFileOffer(session)
      );

      if(!offerDelivered){
        await sendReliableFileOffer(session);
      }
    }else if(autoAccept){
      offerDelivered=await sendReliableFileOffer(session);
    }else{
      // Manual acceptance still needs a durable way to notify the user.
      offerDelivered=await sendReliableFileOffer(session);
    }

    /*
     * A live foreground message is intentionally independent from
     * offerDelivered. If the OFFER fails during a socket transition, the
     * session remains durable and deliverReliableFileTransfers() will replay
     * it after reconnect.
     */
    console.log(
      `[FILE_TRANSFER] START transfer=${session.transferId} ` +
      `messageLive=${liveMessageDelivered} offer=${offerDelivered} ` +
      `autoAccept=${autoAccept}`
    );

    return true;
  }

  const session=reliableFileSession(transferId);
  if(!session){
    send(ws,{
      type:'fileTransferFailed',
      transferId,
      reason:'Dosya transferi bulunamadı veya süresi doldu.',
    });
    return true;
  }

  session.updatedAt=Date.now();

  const meKey=normalizeUsername(me);
  const isSender=meKey===session.fromKey;
  const isReceiver=meKey===session.toKey;

  if(type==='fileTransferAccept'){
    if(!isReceiver){
      return true;
    }

    if(session.state==='completed' || session.state==='failed' || session.state==='rejected'){
      return true;
    }

    // A foreground/background wake-up can race and send ACCEPT twice. Keep
    // the first live receiver socket pinned so a second socket cannot steal
    // the binary stream midway through a transfer.
    if(
      session.accepted &&
      session.receiverWs &&
      session.receiverWs.readyState===1 &&
      session.receiverWs!==ws
    ){
      return true;
    }

    session.accepted=true;
    session.state='accepted';
    persistReliableFileSession(session);

    /*
     * ACCEPT is the reliable receiver-side delivery point for the file
     * message. At this moment the receiving transfer endpoint has actually
     * received the metadata and taken ownership of the transfer. Mark the
     * chat message delivered now; completion remains a separate
     * transferStatus='completed' state.
     */
    const deliveredFileMessage=markPrivateMessageDelivered(
      session.from,
      session.to,
      session.messageId,
      session.clientMessageId,
      ''
    );

    if(deliveredFileMessage){
      send(
        socketFor(session.from),
        {
          type:'messageDelivered',
          messageId:deliveredFileMessage.id||session.messageId||null,
          clientMessageId:
            deliveredFileMessage.clientMessageId||
            session.clientMessageId||
            null,
          from:session.to,
          to:session.from,
          deliveredTo:session.to,
          ts:deliveredFileMessage.deliveredAt||Date.now(),
        }
      );
    }

    // Pin the receiver socket that actually accepted this transfer.
    // A later background/foreground socket must not steal the binary stream.
    session.receiverWs=ws;

    const sender=fileSocketFor(session.from,transferId);

    // The receiver may accept while the sender's foreground socket is
    // reconnecting. The session is already persisted in memory, so do not
    // destroy a valid transfer merely because the sender is momentarily
    // unavailable. deliverReliableFileTransfers() will replay ACCEPT when
    // the sender reconnects.
    const acceptForSender={
      type:'fileTransferAccept',
      from:session.to,
      to:session.from,
      transferId,
    };

    const deliveredAccept=send(sender,acceptForSender);

    // ACCEPT is part of the durable transfer state. If the sender socket is
    // momentarily unavailable/stale, retain the ACCEPT for the sender instead
    // of leaving the sender permanently stuck at "Gönderim bekliyor".
    // deliverReliableFileTransfers() also replays ACCEPT from session.state
    // on the sender's next authenticated connection; the pending event closes
    // the gap for the normal pending-signaling delivery path.
    if(!deliveredAccept){
      storePendingFileTransfer(session.from,acceptForSender);
    }

    console.log(
      `[FILE_TRANSFER] ACCEPT transfer=${transferId} ` +
      `from=${session.to} to=${session.from} ` +
      `senderLive=${deliveredAccept}`
    );

    // Receiver is now authoritative for this transfer. Any chunks that
    // arrived while its socket was temporarily unavailable can be replayed.
    flushReliableFileChunks(session);

    return true;
  }

  if(type==='fileTransferReject'){
    if(!isReceiver)return true;

    session.state='rejected';
    updateReliableFileMessage(
      session.from,
      session.to,
      session.transferId,
      'rejected',
    );

    send(fileSocketFor(session.from,transferId),{
      type:'fileTransferReject',
      from:session.to,
      to:session.from,
      transferId,
    });

    removeReliableFileSession(transferId);
    return true;
  }

  if(type==='fileTransferChunkAck'){
    if(!isReceiver)return true;

    const receivedSeq=Number(d.receivedSeq);
    if(!Number.isSafeInteger(receivedSeq) || receivedSeq<0)return true;
    if(receivedSeq>session.lastReceivedSeq){
      session.lastReceivedSeq=receivedSeq;
      session.receivedBytes=Math.min(
        session.fileSize,
        (receivedSeq+1)*RELIABLE_FILE_MAX_CHUNK_BYTES
      );
      session.updatedAt=Date.now();

      // The in-memory sequence is authoritative during a live transfer.
      // Persist less often to avoid turning every progress ACK into a disk
      // write. On reconnect the receiver sends its durable local sequence,
      // which supersedes this checkpoint.
      const shouldPersist =
        !Number.isSafeInteger(session.lastPersistedSeq) ||
        receivedSeq-session.lastPersistedSeq>=16 ||
        session.receivedBytes>=session.fileSize;

      if(shouldPersist){
        session.lastPersistedSeq=receivedSeq;
        persistReliableFileSession(session);
      }
    }

    send(fileSocketFor(session.from,transferId),{
      type:'fileTransferChunkAck',
      from:session.to,
      to:session.from,
      transferId,
      receivedSeq,
    });

    return true;
  }

  if(type==='fileTransferResume'){
    if(!isSender && !isReceiver)return true;
    if(session.state==='failed' || session.state==='rejected')return true;

    const role=String(d.role||'').toLowerCase();
    if(role!=='sender' && role!=='receiver') return true;
    if(role==='sender' && !isSender) return true;
    if(role==='receiver' && !isReceiver) return true;

    const reported=Number(d.lastReceivedSeq);
    const maxSeq=Math.max(
      -1,
      Math.ceil(session.fileSize/RELIABLE_FILE_MAX_CHUNK_BYTES)-1
    );
    const resumeFrom=String(d.from||'').trim();
    const resumeTo=String(d.to||'').trim();
    const resumeName=String(d.fileName||'').trim();
    const resumeSize=Number(d.fileSize);
    const resumeSha=String(d.sha256||'').trim().toLowerCase();
    const protocolVersion=Number(d.protocolVersion);
    if(
      resumeFrom.toLowerCase()!==String(session.from||'').toLowerCase() ||
      resumeTo.toLowerCase()!==String(session.to||'').toLowerCase() ||
      resumeName!==String(session.fileName||'') ||
      resumeSize!==session.fileSize ||
      resumeSha!==String(session.sha256||'').toLowerCase() ||
      protocolVersion!==1 ||
      !Number.isSafeInteger(reported) ||
      reported<-1 ||
      reported>maxSeq
    ){
      failReliableFileTransfer(
        session,
        'Resume metadata doğrulaması başarısız.',
        ws,
      );
      return true;
    }

    if(isReceiver){
      session.receiverWs=ws;
      session.accepted=true;
      session.state='accepted';
      if(Number.isSafeInteger(reported) && reported>=-1){
        /*
         * The receiver's durable .part/manifest is authoritative for the
         * receiver role. Never advance it to an older server ACK: after a
         * process crash the server may remember an ACK that was sent before
         * the receiver's latest durable manifest was flushed. In that case
         * forcing the higher server sequence would create a hole in the
         * receiver's local file. The sender will rewind/replay from this
         * receiver-reported sequence.
         */
        session.lastReceivedSeq=reported;
        session.receivedBytes=Math.min(
          session.fileSize,
          Math.max(0,(reported+1)*RELIABLE_FILE_MAX_CHUNK_BYTES)
        );
      }
      session.updatedAt=Date.now();
      persistReliableFileSession(session);
    }

    send(ws,{
      type:'fileTransferResumeState',
      from:session.to,
      to:session.from,
      transferId,
      lastReceivedSeq:Number(session.lastReceivedSeq)||-1,
      receivedBytes:Number(session.receivedBytes)||0,
      state:session.state,
      fileName:session.fileName,
      fileSize:session.fileSize,
      sha256:session.sha256,
      protocolVersion:1,
    });

    if(isReceiver){
      send(fileSocketFor(session.from,transferId),{
        type:'fileTransferResumeState',
        from:session.to,
        to:session.from,
        transferId,
        lastReceivedSeq:Number(session.lastReceivedSeq)||-1,
        receivedBytes:Number(session.receivedBytes)||0,
        state:session.state,
        fileName:session.fileName,
        fileSize:session.fileSize,
        sha256:session.sha256,
        protocolVersion:1,
      });
      flushReliableFileChunks(session);
      deliverPendingReliableFileEnd(session);
    }
    return true;
  }

  if(type==='fileTransferEnd'){
    if(!isSender || !session.accepted)return true;

    // Idempotent retry after the receiver already completed the file.
    if(session.state==='completed'){
      send(ws,{
        type:'fileTransferComplete',
        from:session.to,
        to:session.from,
        transferId,
        fileSize:session.fileSize,
        sha256:session.sha256,
      });
      return true;
    }

    if(session.state!=='accepted')return true;

    const fileSize=Number(d.fileSize||0);
    const sha256=String(d.sha256||'').trim().toLowerCase();

    if(
      fileSize!==session.fileSize ||
      !/^[a-f0-9]{64}$/.test(sha256) ||
      sha256!==session.sha256
    ){
      failReliableFileTransfer(
        session,
        'Dosya bitiş/doğrulama bilgisi eşleşmedi.',
        ws,
      );
      return true;
    }

    /*
     * The sender's END is only a declaration. The receiver must receive the
     * END, flush/hash the actual .part file and explicitly confirm with
     * fileTransferComplete. This is the authoritative completion point.
     */
    session.pendingEnd={
      fileSize:session.fileSize,
      sha256:session.sha256,
    };
    session.updatedAt=Date.now();
    persistReliableFileSession(session);

    const receiver=fileSocketFor(session.to,transferId);

    if(receiver){
      // Never let END overtake chunks waiting in the bounded relay queue.
      // deliverPendingReliableFileEnd() will release it after the queued
      // binary frames have been flushed.
      deliverPendingReliableFileEnd(session);
    }

    console.log(
      `[FILE_TRANSFER] END_DECLARED transfer=${transferId} ` +
      `receiver=${receiver?'live':'pending'}`
    );

    return true;
  }

  if(type==='fileTransferComplete'){
    if(!isReceiver || !session.accepted)return true;

    // COMPLETE is idempotent. The receiver may retry after a lost ACK or
    // reconnect; never turn an already completed transfer into FAILED just
    // because pendingEnd was cleared by the first successful completion.
    if(session.state==='completed'){
      send(fileSocketFor(session.from,transferId),{
        type:'fileTransferComplete',
        from:session.to,
        to:session.from,
        transferId,
        fileSize:session.fileSize,
        sha256:session.sha256,
      });
      send(ws,{
        type:'fileTransferCompleteAck',
        from:session.to,
        to:session.to,
        transferId,
      });
      return true;
    }

    const fileSize=Number(d.fileSize||0);
    const sha256=String(d.sha256||'').trim().toLowerCase();

    if(
      !session.pendingEnd ||
      fileSize!==session.fileSize ||
      !/^[a-f0-9]{64}$/.test(sha256) ||
      sha256!==session.sha256
    ){
      failReliableFileTransfer(
        session,
        'Alıcı dosya doğrulamasını tamamlayamadı.',
        ws,
      );
      return true;
    }

    session.state='completed';
    session.pendingEnd=null;
    persistReliableFileSession(session);

    const completed=updateReliableFileMessage(
      session.from,
      session.to,
      session.transferId,
      'completed',
      {
        transferBytes:session.fileSize,
      },
    );

    if(completed){
      send(fileSocketFor(session.from,transferId),{
        type:'fileTransferComplete',
        from:session.to,
        to:session.from,
        transferId,
        fileSize:session.fileSize,
        sha256:session.sha256,
      });

      send(socketFor(session.from),completed);
      send(ws,completed);
    }

    // The initial privateFileMessage wake-up is intentionally data-only so
    // Android can start the background transfer service. Once the verified
    // file is committed, send a separate completion notification. This keeps
    // "dosya alındı" visible even when the app was terminated during transfer.
    if(!isForegroundActive(session.to)){
      await sendFileStoredPush(session.to,{
        type:'privateFileStored',
        sender:session.from,
        to:session.to,
        recipient:session.to,
        fileId:transferId,
        transferId,
        fileName:session.fileName,
        fileSize:session.fileSize,
      });
    }

    // Explicit ACK to the receiver: the receiver may safely retry COMPLETE
    // across a transient socket transition until the server confirms that
    // the terminal state has been committed.
    send(ws,{
      type:'fileTransferCompleteAck',
      from:session.to,
      to:session.to,
      transferId,
    });

    session.updatedAt=Date.now();

    console.log(
      `[FILE_TRANSFER] COMPLETE transfer=${transferId} ` +
      `from=${session.from} to=${session.to}`
    );

    // Keep the terminal session briefly so a lost sender COMPLETE ACK can
    // be recovered by an idempotent END retry after reconnect.
    return true;
  }

  if(type==='fileTransferFailedAck'){
    const failedSession=reliableFileTransfers.get(transferId);
    if(!failedSession || failedSession.state!=='failed')return true;
    const ackKey=normalizeUsername(me);
    if(ackKey===failedSession.fromKey){
      failedSession.failureAcks={...(failedSession.failureAcks||{}),sender:true};
    }else if(ackKey===failedSession.toKey){
      failedSession.failureAcks={...(failedSession.failureAcks||{}),receiver:true};
    }else{
      return true;
    }
    failedSession.updatedAt=Date.now();
    if(failedSession.failureAcks.sender===true && failedSession.failureAcks.receiver===true){
      removeReliableFileSession(transferId);
    }else{
      persistReliableFileSession(failedSession);
    }
    return true;
  }

  if(type==='fileTransferFailed'){
    if(!isSender && !isReceiver)return true;

    // A late failure from an old socket/event must never overwrite an
    // already verified terminal completion.
    if(session.state==='completed'){
      if(isSender){
        send(ws,{
          type:'fileTransferComplete',
          from:session.to,
          to:session.from,
          transferId,
          fileSize:session.fileSize,
          sha256:session.sha256,
        });
      }
      return true;
    }

    failReliableFileTransfer(
      session,
      String(d.reason||'Dosya transferi başarısız oldu.'),
      ws,
    );
    return true;
  }
  return true;
}

function flushReliableFileChunks(session){
  if(!session || !session.accepted || session.state!=='accepted'){
    return;
  }

  if(!Array.isArray(session.pendingChunks) || session.pendingChunks.length===0){
    return;
  }

  const recipient=fileSocketFor(session.to,session.transferId);
  if(!recipient){
    return;
  }

  const pending=session.pendingChunks;

  for(let index=0;index<pending.length;index++){
    const buffer=pending[index];

    if(!sendBinary(recipient,buffer)){
      // Keep the failed chunk and every chunk after it. They must remain
      // ordered because the sender's outstanding window is sequential.
      session.pendingChunks=pending.slice(index);
      session.updatedAt=Date.now();
      return;
    }

    const sentLength=Buffer.isBuffer(buffer)?buffer.length:0;
    session.pendingBytes=Math.max(0,(Number(session.pendingBytes)||0)-sentLength);
    reliablePendingTotalBytes=Math.max(0,reliablePendingTotalBytes-sentLength);
    session.updatedAt=Date.now();
  }

  session.pendingChunks=[];

  // If END was received while the socket was under backpressure, release it
  // only after every queued binary frame has actually been sent.
  deliverPendingReliableFileEnd(session);
}

function handleReliableFileBinary(ws,buffer,me){
  if(!me || !Buffer.isBuffer(buffer))return false;

  // ZLF2 + version + uint16 transferIdLength + transferId + uint32 seq + payload.
  if(
    buffer.length<11 ||
    buffer[0]!==0x5a ||
    buffer[1]!==0x4c ||
    buffer[2]!==0x46 ||
    buffer[3]!==0x32 ||
    buffer[4]!==1
  ){
    return false;
  }

  const idLength=buffer.readUInt16BE(5);
  const headerLength=11+idLength;

  if(
    idLength<=0 ||
    idLength>256 ||
    buffer.length<=headerLength ||
    buffer.length>headerLength+RELIABLE_FILE_MAX_CHUNK_BYTES
  ){
    return true;
  }

  const transferId=buffer.toString('utf8',7,7+idLength).trim();
  const seq=buffer.readUInt32BE(7+idLength);
  const payload=buffer.subarray(headerLength);

  const session=reliableFileSession(transferId);
  if(!session){
    return true;
  }

  if(
    normalizeUsername(me)!==session.fromKey ||
    !session.accepted ||
    session.state!=='accepted'
  ){
    return true;
  }

  const maxSeq=Math.max(
    0,
    Math.ceil(session.fileSize/RELIABLE_FILE_MAX_CHUNK_BYTES)-1
  );
  if(seq>maxSeq){
    failReliableFileTransfer(
      session,
      'Dosya parça numarası dosya boyutunu aşıyor.',
      ws,
    );
    return true;
  }

  const expectedChunkBytes=seq===maxSeq
    ? session.fileSize-(seq*RELIABLE_FILE_MAX_CHUNK_BYTES)
    : RELIABLE_FILE_MAX_CHUNK_BYTES;
  if(payload.length!==expectedChunkBytes){
    failReliableFileTransfer(
      session,
      'Dosya parçasının boyutu geçersiz.',
      ws,
    );
    return true;
  }

  const recipient=fileSocketFor(session.to,transferId);

  /*
   * Receiver socket geçici olarak yok olabilir:
   * foreground -> background transfer servisi geçişi,
   * Android process/socket yeniden kurulması veya kısa bağlantı
   * değişimleri transferin kendisini başarısız saymamalıdır.
   *
   * Session TTL içinde korunur. Receiver yeniden bağlandığında
   * deliverReliableFileTransfers() mevcut ACCEPT/OFFER durumunu
   * tekrar senkronize eder.
   */
  if(!recipient){
    // Keep both a per-transfer and global RAM relay budget while the receiver
    // socket is transitioning. File contents are never written to disk.
    if(session.pendingChunks.length>=RELIABLE_FILE_MAX_PENDING_CHUNKS){
      failReliableFileTransfer(
        session,
        'Alıcı bağlantısı çok uzun süre kurulamadı.',
        ws,
      );
      return true;
    }

    if(queueReliableFileChunk(session,buffer)) return true;
  }

  /*
   * If earlier chunks are queued, they must reach the receiver before
   * this newly arriving chunk. Otherwise the receiver can legitimately
   * reject the newer sequence as out-of-order.
   */
  if(Array.isArray(session.pendingChunks) && session.pendingChunks.length){
    flushReliableFileChunks(session);

    if(Array.isArray(session.pendingChunks) && session.pendingChunks.length){
      /*
       * The receiver disappeared again while flushing. Queue the current
       * chunk behind the older pending chunks so ordering is preserved.
       */
      if(queueReliableFileChunk(session,buffer)) return true;

      failReliableFileTransfer(
        session,
        'Alıcı bağlantısı çok uzun süre kurulamadı.',
        ws,
      );
      return true;
    }
  }

  session.updatedAt=Date.now();

  if(!sendBinary(recipient,buffer)){
    /*
     * sendBinary failure can be a transient socket transition. Preserve
     * this chunk instead of destroying the transfer session.
     */
    if(queueReliableFileChunk(session,buffer)) return true;

    failReliableFileTransfer(
      session,
      'Alıcı bağlantısı çok uzun süre kurulamadı.',
      ws,
    );
    return true;
  }

  flushReliableFileChunks(session);

  return true;
}

function deliverPendingReliableFileEnd(session){
  if(
    !session ||
    !session.pendingEnd ||
    session.state!=='accepted'
  )return false;

  const receiver=fileSocketFor(session.to,session.transferId);
  if(!receiver)return false;

  // END must never overtake queued binary chunks. If the receiver socket is
  // still above its high-water mark, keep pendingEnd for the next flush.
  if(Number(receiver.bufferedAmount||0)>RELIABLE_FILE_SOCKET_HIGH_WATER_BYTES){
    return false;
  }

  const delivered=send(receiver,{
    type:'fileTransferEnd',
    from:session.from,
    to:session.to,
    transferId:session.transferId,
    fileSize:session.pendingEnd.fileSize,
    sha256:session.pendingEnd.sha256,
  });

  if(delivered){
    session.pendingEndDeliveredAt=Date.now();
    session.updatedAt=Date.now();
  }

  return delivered;
}

function deliverReliableFileTransfers(ws,username){
  const key=normalizeUsername(username);

  for(const session of reliableFileTransfers.values()){
    if(!session)continue;

    const isSender=normalizeUsername(session.from)===key;
    const isReceiver=normalizeUsername(session.to)===key;

    if(!isSender && !isReceiver)continue;

    if(session.state==='completed'){
      // Sender may have been offline when the receiver completed the file.
      // Replay the terminal COMPLETE so its local progress cannot remain
      // stuck at "transferring".
      if(isSender){
        send(ws,{
          type:'fileTransferComplete',
          from:session.to,
          to:session.from,
          transferId:session.transferId,
          fileSize:session.fileSize,
          sha256:session.sha256,
        });
      }
      continue;
    }

    if(session.state==='waiting' && isReceiver){
      const message=findPrivateMessageByClientId(
        session.from,
        session.to,
        session.clientMessageId,
      );

      if(message){
        send(ws,message);
      }

      send(ws,reliableFileOffer(session));
      continue;
    }

    if(session.state==='accepted' && isSender){
      // The receiver may have accepted while the sender socket was
      // temporarily disconnected. Replaying ACCEPT is idempotent.
      send(ws,{
        type:'fileTransferAccept',
        from:session.to,
        to:session.from,
        transferId:session.transferId,
      });
      continue;
    }

    if(session.state==='accepted' && isReceiver){
      // Replaying OFFER lets a receiver that lost its ACCEPT during a
      // reconnect re-synchronize the transfer. Queued chunks and a pending
      // END are replayed in order.
      send(ws,reliableFileOffer(session));
      flushReliableFileChunks(session);

      // If END was declared while the receiver was unavailable, release it
      // only after queued chunks have been delivered in order.
      deliverPendingReliableFileEnd(session);
    }
  }
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

function deliverPendingFileTransfers(ws,username,transferId=''){
  const requestedTransferId=String(transferId||'').trim();
  cleanupPendingFileTransfers();

  const targetKey=normalizeUsername(username);

  for(const [key,pending] of pendingFileTransfers){
    if(!pending || key.split('|')[0]!==targetKey)continue;

    if(
      requestedTransferId &&
      String(pending.transferId||'').trim()!==requestedTransferId
    )continue;

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
    if(normalizeUsername(nick)===targetKey &&
       ws && ws.readyState===1 &&
       ws.isAlive!==false){
      return ws;
    }
  }

  return null;
}

function backgroundSocketFor(username,transferId=''){
  const targetKey=normalizeUsername(username);
  const id=String(transferId||'').trim();

  if(!targetKey || !id)return null;

  const transfers=backgroundSockets.get(targetKey);
  if(!transfers)return null;

  const entry=transfers.get(id);

  if(
    entry &&
    entry.ws &&
    entry.ws.readyState===1 &&
    entry.ws.isAlive!==false &&
    entry.transferId===id
  ){
    return entry.ws;
  }

  if(entry){
    transfers.delete(id);
    backgroundSocketByWs.delete(entry.ws);
  }

  if(transfers.size===0){
    backgroundSockets.delete(targetKey);
  }

  return null;
}

function isBackgroundSocket(ws){
  return backgroundSocketByWs.has(ws);
}

function fileSocketFor(username,transferId=''){
  /*
   * Once a receiver has accepted a reliable transfer, pin that exact socket
   * for the lifetime of the active session. This prevents a late
   * foreground/background socket from stealing the binary stream midway.
   */
  const id=String(transferId||'').trim();

  if(id){
    const session=reliableFileTransfers.get(id);

    if(
      session &&
      session.toKey===normalizeUsername(username) &&
      session.receiverWs &&
      session.receiverWs.readyState===1 &&
      session.receiverWs.isAlive!==false
    ){
      return session.receiverWs;
    }
  }

  /*
   * Before ACCEPT, prefer an active transfer-specific background socket.
   * If none exists, use the normal foreground socket.
   */
  const background=backgroundSocketFor(username,transferId);
  if(background)return background;

  if(isForegroundActive(username)){
    const foreground=socketFor(username);
    if(foreground)return foreground;
  }

  return socketFor(username);
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
async function sendFileStoredPush(username,event){
  const target=safeNick(username);
  if(!target)return false;

  // Presence can be stale while the primary WebSocket is already gone.
  // Only suppress FCM when a real live foreground socket exists.
  const liveForeground=socketFor(target);
  if(liveForeground && isForegroundActive(target))return false;

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
    data:{
      type:'privateFileStored',
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
    },
  });
}

async function sendFileTransferPush(username,event){
  const target=safeNick(username);
  if(!target)return false;

  // Kullanıcı uygulamayı aktif olarak kullanıyorsa WebSocket üzerinden
  // offer zaten teslim edilir; ikinci bildirim üretme. Sadece presence'a
  // güvenme: Android'de heartbeat gecikmiş/stale kalabilir.
  const liveForeground=socketFor(target);
  if(liveForeground && isForegroundActive(target))return false;

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
    data:{
      type:'privateFileMessage',
      sender:from,
      to:target,
      recipient:target,
      fileId:transferId,
      transferId,
      fileName,
      fileSize,
      sha256:String(event && event.sha256 || '').trim().toLowerCase(),
    },
    // IMPORTANT: keep file-transfer wake-ups DATA-ONLY.
    // A notification payload can be handled by Android's system tray while
    // the app is backgrounded, without invoking onMessageReceived(). The
    // native FCM service must receive this callback to start the foreground
    // transfer worker when the app process is terminated. The foreground
    // service itself owns the persistent transfer notification.
    android:{
      priority:'high',
      ttl:3600000,
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
  if(!ws || ws.readyState!==1 || ws.isAlive===false)return false;

  try{
    ws.send(JSON.stringify(data));
    return true;
  }catch{
    // Socket kapanışını tek merkezden yönet. Özellikle aynı hesap için
    // background transfer servisi ikinci WebSocket açmışsa, burada doğrudan
    // offline yayınlamak canlı primary socket'i yanlışlıkla offline gösterir.
    disconnect(ws);

    try{ws.close();}catch{}
    return false;
  }
}
function broadcast(data,except=null){
  for(const ws of users.keys()){
    if(ws===except || isBackgroundSocket(ws))continue;
    send(ws,data);
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
      if(!isForegroundActive(username)){
        return false;
      }

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

    if(!isForegroundActive(username))continue;

    if(!isSelf && !presenceVisible(username))continue;

    result[username]=profileDataFor(account);
  }

  return result;
}

function listUsers(){
  return [...sockets.keys()]
    .filter(username=>isForegroundActive(username))
    .filter(username=>presenceVisible(username))
    .sort((a,b)=>a.localeCompare(b));
}
function updatePresence(){
  for(const ws of users.keys()){
    if(isBackgroundSocket(ws))continue;

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
    if(isBackgroundSocket(ws))continue;

    const nick=users.get(ws);
    if(!nick || !isForegroundActive(nick))continue;

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
    if(isBackgroundSocket(ws))continue;

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
    if(isBackgroundSocket(ws))continue;

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

function markPrivateMessageDelivered(
  a,
  b,
  messageId,
  clientMessageId,
  deliveryToken=''
){
  const arr=getPrivate(a,b);

  const index=arr.findIndex(item=>{
    if(messageId && (item && item.id)===messageId)return true;
    if(clientMessageId && (item && item.clientMessageId)===clientMessageId)return true;
    return false;
  });

  if(index<0)return null;

  const target=arr[index];

  // Only the actual recipient may acknowledge delivery. The authenticated
  // WebSocket identity is authoritative; the client-supplied "from" is only
  // used to select the sender's conversation.
  if(
    normalizeUsername(target.to)!==normalizeUsername(b) ||
    normalizeUsername(target.from)!==normalizeUsername(a)
  ){
    return null;
  }

  // Text-message delivery can only be acknowledged by the exact delivery
  // token issued with that message. This blocks stale/unsolicited ACKs from
  // changing a new message to delivered.
  if(
    target.type==='privateMessage' &&
    String(target.deliveryToken||'') &&
    String(target.deliveryToken||'')!==String(deliveryToken||'')
  ){
    return null;
  }

  if(target.read===true){
    return arr[index];
  }

  arr[index]={
    ...arr[index],
    delivered:true,
    deliveredAt:arr[index].deliveredAt||Date.now(),
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

  const target=arr[index];

  // Only the message recipient can generate a read receipt for the sender.
  if(
    normalizeUsername(target.to)!==normalizeUsername(reader) ||
    normalizeUsername(target.from)!==normalizeUsername(sender)
  ){
    return null;
  }

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

function privateMessageStatusSync(username){
  const target=normalizeUsername(username);
  const result=[];

  try{
    for(const file of fs.readdirSync(DATA)){
      if(!file.startsWith('private-') || !file.endsWith('.json'))continue;

      const list=load(file,[]);
      if(!Array.isArray(list))continue;

      for(const msg of list){
        if(!msg || normalizeUsername(msg.from)!==target)continue;
        if(!msg.id && !msg.clientMessageId)continue;
        if(messageExpiresAt(msg) && messageExpiresAt(msg)<=Date.now())continue;

        result.push({
          messageId:String(msg.id||''),
          clientMessageId:String(msg.clientMessageId||''),
          delivered:msg.delivered===true,
          read:msg.read===true,
        });
      }
    }
  }catch{}

  return result.slice(-300);
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

  for(const session of reliableFileTransfers.values()){
    if(session && session.receiverWs===ws){
      session.receiverWs=null;
      session.updatedAt=Date.now();
    }
  }

  users.delete(ws);

  const backgroundKey=backgroundSocketByWs.get(ws);

  if(backgroundKey){
    backgroundSocketByWs.delete(ws);

    const transfers=backgroundSockets.get(nickKey);

    if(transfers){
      const entry=transfers.get(backgroundKey);
      if(entry && entry.ws===ws){
        transfers.delete(backgroundKey);
      }

      if(transfers.size===0){
        backgroundSockets.delete(nickKey);
      }
    }

    const primary=socketFor(nick);

    if(primary){
      const currentState=appStates.get(nickKey);
      appStates.set(
        nickKey,
        currentState==='background' ? 'background' : 'foreground'
      );
      appStateUpdatedAt.set(nickKey,Date.now());
    }else if(backgroundSockets.has(nickKey)){
      appStates.set(nickKey,'background');
      appStateUpdatedAt.set(nickKey,Date.now());
    }else{
      appStates.delete(nickKey);
      appStateUpdatedAt.delete(nickKey);
      broadcastUserOffline(nick);
    }

    updatePresence();
    return;
  }

  const currentPrimary=socketFor(nick);

  // This socket is an old/non-primary connection.
  if(currentPrimary && currentPrimary!==ws){
    updatePresence();
    return;
  }

  if(currentPrimary===ws){
    sockets.delete(nick);

    // Never promote a background transfer socket to primary. If the
    // foreground session closes while one or more background transfers
    // are active, normal messages must use FCM rather than a headless
    // file socket.
    if(backgroundSockets.has(nickKey)){
      appStates.set(nickKey,'background');
      appStateUpdatedAt.set(nickKey,Date.now());
      broadcastUserOffline(nick);
      updatePresence();
      return;
    }
  }

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

  appStates.delete(nickKey);
  appStateUpdatedAt.delete(nickKey);

  broadcastUserOffline(nick);
  updatePresence();
}
const server=http.createServer((req,res)=>{
  res.setHeader('Access-Control-Allow-Origin','*');

  if(req.url==='/health'){
    res.writeHead(200,{'Content-Type':'application/json'});
    res.end(JSON.stringify({
      ok:true,
      service:'zerolog',
      users:sockets.size,
      rooms:rooms.length,
    }));
    return;
  }

  if(req.url==='/delivery' && req.method==='POST'){
    let body='';
    let tooLarge=false;

    req.on('data',chunk=>{
      if(body.length>16384){
        tooLarge=true;
        return;
      }
      body+=chunk.toString();
    });

    req.on('end',()=>{
      if(tooLarge){
        res.writeHead(413,{'Content-Type':'application/json'});
        res.end(JSON.stringify({ok:false,error:'payload_too_large'}));
        return;
      }

      let d;
      try{
        d=JSON.parse(body||'{}');
      }catch{
        res.writeHead(400,{'Content-Type':'application/json'});
        res.end(JSON.stringify({ok:false,error:'invalid_json'}));
        return;
      }

      const sender=safeNick(d.sender||d.from);
      const recipient=safeNick(d.recipient||d.to);
      const messageId=String(d.messageId||'').trim();
      const clientMessageId=String(d.clientMessageId||'').trim();
      const deliveryToken=String(d.deliveryToken||'').trim();

      if(
        !sender ||
        !recipient ||
        (!messageId && !clientMessageId) ||
        !deliveryToken
      ){
        res.writeHead(400,{'Content-Type':'application/json'});
        res.end(JSON.stringify({ok:false,error:'invalid_delivery_receipt'}));
        return;
      }

      const delivered=markPrivateMessageDelivered(
        sender,
        recipient,
        messageId,
        clientMessageId,
        deliveryToken,
      );

      if(!delivered){
        res.writeHead(403,{'Content-Type':'application/json'});
        res.end(JSON.stringify({ok:false,error:'delivery_rejected'}));
        return;
      }

      const senderSocket=socketFor(sender);
      if(senderSocket){
        send(senderSocket,{
          type:'messageDelivered',
          messageId:delivered.id||messageId,
          clientMessageId:delivered.clientMessageId||clientMessageId,
          from:recipient,
          to:sender,
          deliveredTo:recipient,
          ts:delivered.deliveredAt||Date.now(),
        });
      }

      console.log(
        `[MESSAGE] DELIVERED_FCM id=${delivered.id||messageId} ` +
        `sender=${sender} recipient=${recipient}`
      );

      res.writeHead(200,{'Content-Type':'application/json'});
      res.end(JSON.stringify({ok:true}));
    });

    return;
  }

  res.writeHead(200,{'Content-Type':'text/plain; charset=utf-8'});
  res.end('Zerolog Signaling & Chat Server Aktif');
});
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
wss.on('connection',(ws,req)=>{
  ws._rooms=new Set();
  ws._remoteAddress=req && req.socket ? req.socket.remoteAddress : '';
  ws.isAlive=true;
  ws.on('pong',()=>{ws.isAlive=true;});
  ws.on('message',async (buf,isBinary)=>{
    const me=users.get(ws);

    if(isBinary){
      handleReliableFileBinary(ws,buf,me);
      return;
    }

 let d;
 try{d=JSON.parse(buf.toString());}catch{return;}

 if(await handleReliableFileEvent(ws,d,me)){
   return;
 }

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

    if(String(process.env.ZEROLOG_MAINTENANCE||'').trim()==='1'){
      send(ws,{
        type:'authError',
        code:'SERVER_MAINTENANCE',
        message:'Sunucuda bakım çalışması yapılıyor. Lütfen daha sonra tekrar deneyin.',
      });
      return;
    }

    const rate=loginRateCheck(ws,nick);
    if(!rate.allowed){
      send(ws,{
        type:'authError',
        code:'LOGIN_RATE_LIMITED',
        message:'Çok fazla başarısız giriş denemesi. Lütfen biraz sonra tekrar deneyin.',
        retryAfterMs:rate.retryAfterMs,
      });
      return;
    }

    const account=accounts[key];

    if(!account || !verifyPassword(password,account.passwordHash)){
      loginRateFailure(rate.key);
      send(ws,{type:'authError',code:'INVALID_CREDENTIALS',message:'Kullanıcı adı veya şifre hatalı.'});
      return;
    }

    loginRateSuccess(rate.key);

    const loginStateKey=normalizeUsername(account.username);
    const old=sockets.get(account.username);
    const backgroundTransfer=d.backgroundTransfer===true;
    const backgroundTransferId=String(d.backgroundTransferId||'').trim();

    if(old && old!==ws && !backgroundTransfer){
      const sameAppInstallation =
        !!fcmToken &&
        !!account.fcmToken &&
        String(account.fcmToken) === String(fcmToken);

      if(sameAppInstallation){
        console.log(
          `[AUTH] replacing previous socket for same FCM installation ` +
          `username=${account.username}`
        );
        disconnect(old);
        try{old.terminate();}catch{}
      }

      if(!sockets.has(account.username)){
        // Previous socket belonged to the same app installation and was
        // replaced above. Continue with this login.
      }else{
      /*
       * A network/proxy outage can leave the primary WebSocket object open
       * on Node even though the client is already gone. In that state the
       * old socket must not permanently block the next login attempt.
       *
       * isAlive=false is set by the 10s heartbeat when no pong is received.
       * For foreground sessions also honor the application heartbeat TTL.
       * Background/paused sessions are not evicted solely by app-state TTL.
       */
      const foregroundState=appStates.get(loginStateKey)==='foreground';
      const lastStateAt=Number(appStateUpdatedAt.get(loginStateKey)||0);
      const foregroundStale=
        foregroundState &&
        (!lastStateAt ||
         Date.now()-lastStateAt>APP_FOREGROUND_HEARTBEAT_TTL_MS);

      const stalePrimary=
        old.readyState!==1 ||
        old.isAlive===false ||
        foregroundStale;

      if(stalePrimary){
        console.warn(
          `[AUTH] removing stale primary socket username=${account.username} ` +
          `readyState=${old.readyState} isAlive=${old.isAlive} ` +
          `foregroundStale=${foregroundStale}`
        );

        disconnect(old);

        try{old.terminate();}catch{}
      }else{
        send(ws,{type:'authError',code:'ACCOUNT_IN_USE',message:'Bu hesap başka bir cihazda aktif.'});
        return;
      }
      }
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

    if(backgroundTransfer){
      // Headless file-transfer socket hiçbir zaman normal uygulamanın
      // primary socket'ini devralmamalıdır. Aksi halde normal mesajlar,
      // profile updates ve delivery/read event'leri yalnızca dosya
      // servisinin dinlediği socket'e gider ve kaybolur.
      if(!backgroundTransferId){
        send(ws,{
          type:'authError',
          code:'BACKGROUND_TRANSFER_ID_REQUIRED',
          message:'Arka plan dosya aktarımı için transferId gereklidir.',
        });
        users.delete(ws);
        try{ws.close();}catch{}
        break;
      }

      const transferMap=
        backgroundSockets.get(loginStateKey)||new Map();

      const oldBackground=transferMap.get(backgroundTransferId);

      if(oldBackground && oldBackground.ws!==ws){
        backgroundSocketByWs.delete(oldBackground.ws);
        users.delete(oldBackground.ws);
        try{oldBackground.ws.close();}catch{}
      }

      transferMap.set(backgroundTransferId,{
        ws,
        transferId:backgroundTransferId,
      });

      const reliableSession=reliableFileTransfers.get(backgroundTransferId);
      if(reliableSession){
        // A fresh headless socket is a new wake-up opportunity. Reset the
        // bounded FCM retry counter so a later process death can be recovered.
        reliableSession.lastWakePushAt=0;
        reliableSession.wakePushCount=0;
        reliableSession.updatedAt=Date.now();
        persistReliableFileSession(reliableSession);
      }

      backgroundSockets.set(loginStateKey,transferMap);
      backgroundSocketByWs.set(
        ws,
        backgroundTransferId
      );

      // Background transfer sockets are transport-only. Never let them
      // change the primary app's presence state. Preserve the primary
      // lifecycle state when a foreground socket exists; otherwise this
      // account has no primary presence connection.
      if(sockets.has(account.username)){
        const currentState=appStates.get(loginStateKey);
        appStates.set(
          loginStateKey,
          currentState==='background' ? 'background' : 'foreground'
        );
      }else{
        appStates.set(loginStateKey,'background');
      }
      appStateUpdatedAt.set(loginStateKey,Date.now());
    }else{
      sockets.set(account.username,ws);
      appStates.set(loginStateKey,'foreground');
      appStateUpdatedAt.set(loginStateKey,Date.now());
    }

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

    deliverPendingFileTransfers(
      ws,
      account.username,
      backgroundTransfer ? backgroundTransferId : ''
    );

    deliverReliableFileTransfers(ws,account.username);
    deliverTerminalFileFailures(ws,account.username);

    const pending=privateMessagesEnabled(account.username)
      ? pendingPrivateMessages(account.username)
      : [];

    if(pending.length){
      send(ws,{
        type:'pendingPrivateMessages',
        messages:pending,
      });
    }

    const ownMessageStatuses=privateMessageStatusSync(account.username);
    if(ownMessageStatuses.length){
      send(ws,{
        type:'privateMessageStatusSync',
        messages:ownMessageStatuses,
      });
    }

    // A headless transfer socket must never publish presence.
    if(!backgroundTransfer){
      broadcastUserOnline(account.username);
    }
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

    // Headless transfer sockets never own account presence. Their
    // appState/appHeartbeat messages must not promote a background user
    // back to foreground.
    if(isBackgroundSocket(ws)){
      break;
    }

    const state=String(d.state||'').trim().toLowerCase();

    if(state!=='foreground' && state!=='background')break;

    const stateKey=normalizeUsername(me);
    const previousState=appStates.get(stateKey);
    appStates.set(stateKey,state);
    appStateUpdatedAt.set(stateKey,Date.now());

    if(d.type==='appState'){
      console.log(
        `[APP_STATE] ${me} -> ${state}`
      );
    }

    if(previousState!==state){
      if(state==='foreground'){
        broadcastUserOnline(me);
      }else{
        broadcastUserOffline(me);
      }
      updatePresence();
    }

    if(state==='foreground'){
      // Uygulama arka plandayken kuyruklanan dosya-transfer event'leri
      // yeniden görünür olduğunda hemen teslim edilmeli.
      deliverPendingFileTransfers(ws,me);
      deliverTerminalFileFailures(ws,me);
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
      ...profile,
      type:'profile',
      profileType:profile.type,
      username:account.username,
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
      ...profile,
      type:'profile',
      profileType:profile.type,
      username:account.username,
    });

    for(const peer of users.keys()){
      if(isBackgroundSocket(peer))continue;

      send(peer,{
        type:'profileUpdated',
        username:account.username,
        profileType:profile.type,
        profileRevision:profile.profileRevision,
        avatarId:profile.avatarId,
        about:profile.about,
        photoAvailable:profile.photoAvailable===true,
        // Profil güncellemesinde tam fotoğrafı da gönder. Böylece remote
        // avatar için ayrı getProfile yarışına gerek kalmaz; profileUpdated
        // tek başına tutarlı bir snapshot taşır.
        photoData:profile.photoData||'',
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
  case 'roomMessage':{if(!me)break;purgeExpiredRoomMessages();const id=String(d.room);if(!ws._rooms.has(id))break;const text=cleanText(d.text);if(!text)break;const ts=Date.now();const msg={id:makeMessageId(),type:'roomMessage',room:id,from:me,text,ts,expiresAt:ts+PRIVATE_MESSAGE_TTL_MS};const arr=roomMessages.get(id)||[];arr.push(msg);roomMessages.set(id,arr);save(`room-${id}.json`,arr);for(const [peer] of users){if(isBackgroundSocket(peer))continue;if((peer._rooms && peer._rooms.has(id)))send(peer,msg);}break;}
  case 'privateHistory':{if(!me)break;const peer=safeNick(d.peer);const messages=purgeExpiredPrivateMessages(me,peer);send(ws,{type:'privateHistory',peer,messages});break;}
  case 'privateFileMessage':{
    if(!me)break;

    const to=safeNick(d.to);
    const fileId=String(d.fileId||'').trim();
    const fileName=String(d.fileName||'').trim().slice(0,512);
    const fileSize=Number(d.fileSize||0);
    const clientMessageId=String(d.clientMessageId||'').trim();

    if(!to||!fileId||!fileName||!Number.isFinite(fileSize)||fileSize<=0)break;

    /*
     * privateFileMessage event'i transferi ALAN socket'ten gelir.
     * Ancak sohbet mesajının yönü transferin orijinal yönü olmalıdır:
     *
     *   me = alıcı
     *   to = orijinal gönderici
     *
     * Bu yüzden mesajı (to -> me) yönünde kaydediyoruz. Eski kod (me -> to)
     * kaydettiği için dosya geçmişi ters tarafta görünür, statusSync yanlış
     * kullanıcıya bağlanır ve sender/receiver önizleme durumu bozulurdu.
     */
    const existing=findPrivateMessageByClientId(
      to,
      me,
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
      from:to,
      to:me,
      fileId,
      fileName,
      fileSize,
      ts:Date.now(),
      expiresAt:Date.now()+PRIVATE_MESSAGE_TTL_MS,
      // Transfer tamamlandığı için orijinal sender bu olayı zaten alıcıdan
      // geri almıştır; ayrıca delivery durumunu bekletmeye gerek yok.
      delivered:true,
      transferStatus:'completed',
      transferBytes:fileSize,
    };

    const stored=addPrivate(to,me,msg);

    // Completion event'ini gönderen socket'e (receiver) değil, dosyanın
    // orijinal sahibine ACK olarak geri bildir.
    send(socketFor(to),{
      type:'messageAck',
      messageId:stored.id||null,
      clientMessageId:stored.clientMessageId||null,
      status:'stored',
    });

    // Orijinal sender'ın chat'i açık/arka planda olabilir. Live socket varsa
    // dosya mesajını gönder; yoksa sender'ın normal private-message FCM
    // kanalını kullan.
    const senderSocket=socketFor(to);
    const senderForeground=!!senderSocket && isForegroundActive(to);

    if(senderForeground){
      send(senderSocket,stored);
    }else if(messageNotificationsEnabled(to)){
      await sendFcmPush(to,{
        data:{
          type:'privateFileStored',
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
      deliveryToken:crypto.randomBytes(24).toString('hex'),
    };

    const stored=addPrivate(me,to,msg);

    console.log(
      `[MESSAGE] STORED id=${stored.id||''} from=${me} to=${to} ` +
      `clientMessageId=${stored.clientMessageId||''}`
    );

    send(ws,{
      type:'messageAck',
      messageId:stored.id||null,
      clientMessageId:stored.clientMessageId||null,
      status:'stored',
    });

    const recipient=socketFor(to);
    let deliveredLive=false;

    if(recipient){
      // Arka plandaki ama hâlâ canlı ana WebSocket de gerçek bir teslim
      // endpoint'idir. Alıcı transport katmanı messageDelivered ACK'i verir.
      deliveredLive=send(recipient,stored);
    }

    if(!deliveredLive && messageNotificationsEnabled(to)){
      const pushed=await sendFcmPush(to,{
        // DATA-ONLY: native Android service bildirimi oluşturur.
        data:{
          type:'privateMessage',
          messageId:String(stored.id||''),
          clientMessageId:String(stored.clientMessageId||''),
          sender:String(stored.from||''),
          recipient:String(stored.to||''),
          text:String(stored.text||''),
          deliveryToken:String(stored.deliveryToken||''),
        },
        android:{
          priority:'high',
          ttl:86400000,
        },
      });

      // FCM push kabulü teslim anlamına gelmez.
      // Gerçek delivered durumu yalnızca alıcı istemcinin
      // messageDelivered ACK'i ile oluşturulmalıdır.
    }

    break;
  }
  case 'messageDelivered':{
    if(!me)break;

    const from=safeNick(d.from);
    const messageId=String(d.messageId||'').trim();
    const clientMessageId=String(d.clientMessageId||'').trim();
    const deliveryToken=String(d.deliveryToken||'').trim();

    if(!from || (!messageId && !clientMessageId))break;

    const delivered=markPrivateMessageDelivered(
      from,
      me,
      messageId,
      clientMessageId,
      deliveryToken
    );

    if(!delivered){
      console.warn(
        `[MESSAGE] DELIVERED rejected from=${me} sender=${from} ` +
        `messageId=${messageId} clientMessageId=${clientMessageId}`
      );
      break;
    }

    console.log(
      `[MESSAGE] DELIVERED id=${delivered.id||messageId} ` +
      `sender=${from} recipient=${me}`
    );

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

    if(!read){
      console.warn(
        `[MESSAGE] READ rejected reader=${me} sender=${from} ` +
        `messageId=${messageId} clientMessageId=${clientMessageId}`
      );
      break;
    }

    console.log(
      `[MESSAGE] READ id=${read.id||messageId} sender=${from} reader=${me}`
    );

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
      // The callee (or caller) is already participating in another call.
      // Reject the new invite explicitly instead of silently dropping it.
      const busyRecipient = socketFor(me);
      send(
        busyRecipient,
        {
          type:'callRejected',
          from:to,
          to:me,
          callId,
          reason:'busy',
        }
      );

      if(!busyRecipient && callNotificationsEnabled(me)){
        await sendCallStatusPushIfOffline(
          me,
          callId,
          'Çağrı meşgul',
          `${to} şu anda başka bir çağrıda.`,
        );
      }
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
      // COMPLETED is authoritative. A late FAILED from an older socket/event
      // must never roll a verified transfer back to failed.
      const allowCompletionFailure = false;

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

    const recipient=fileSocketFor(to,transferId);
    const recipientConnected=!!recipient;
    const recipientForeground=!!socketFor(to) && isForegroundActive(to);

    let deliveredLive=false;

    /*
     * KRİTİK: Established transfer signaling'i yalnızca foreground
     * durumuna bağlamak güvenilir değildir.
     *
     * ACCEPT / SDP / ICE / COMPLETE gibi event'ler, karşı cihazın
     * WebSocket'i bağlı olduğu sürece canlı socket'e teslim edilmelidir.
     * Aksi halde heartbeat 45 saniyelik TTL'nin dışına çıktığında
     * sunucu event'i pending kuyruğuna alır; ancak bu event'ler için
     * FCM gönderilmediğinden sender/receiver sonsuza kadar bekler.
     * Bu özellikle kullanıcıda "Kabul ediliyor…" durumunda kalan
     * transferin doğrudan sebebidir.
     *
     * İlk metadata OFFER ise foreground/background davranışını korur:
     * foreground'da canlı teslim, background'da pending + FCM.
     * Transfer başladıktan sonraki tüm signaling event'leri bağlı
     * socket'e doğrudan teslim edilir. Socket yoksa pending kuyruğu
     * kullanılır.
     */
    const isInitialOffer=
      d.type==='fileTransferOffer' &&
      d.sdp==null;

    if(recipientConnected && (!isInitialOffer || recipientForeground)){
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
            sha256:String(d.sha256||'').trim().toLowerCase(),
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
loadReliableFileSessions();

const reliableFileWakeInterval=setInterval(async()=>{
  const now=Date.now();

  for(const session of reliableFileTransfers.values()){
    if(!session || (session.state!=='waiting' && session.state!=='accepted'))continue;
    const endpoint=backgroundSocketFor(session.to,session.transferId);
    const foreground=socketFor(session.to);
    if(endpoint || foreground)continue;

    const lastPush=Number(session.lastWakePushAt)||0;
    const pushCount=Number(session.wakePushCount)||0;

    // FCM is a wake-up, not the file transport. Retry a missed wake-up for
    // a bounded period so a single delayed/lost push cannot strand a file.
    if(
      pushCount>=12 ||
      (lastPush>0 && now-lastPush<60000)
    ){
      continue;
    }

    try{
      await sendReliableFileOffer(session);
    }catch(error){
      console.error(
        `[FILE_TRANSFER] wake retry failed transfer=${session.transferId}:`,
        error && error.message || error
      );
    }
  }

  cleanupReliableFileTransfers();
},15000);

reliableFileWakeInterval.unref();

server.listen(PORT,'0.0.0.0',()=>console.log(`ZeroLog server listening on ${PORT}`));
