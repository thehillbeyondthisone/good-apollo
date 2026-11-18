// SPDX-License-Identifier: GPL-2.0-or-later
// Talks to the genuine upstream yaAGC socket protocol; no debug-DSKY mode.
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const root = process.argv[2] || 'D:/apollo-ref/build/agc';
const port = Number(process.argv[3] || 19697);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const rows = Array(16).fill(0), channels = {};
const packets = [], inputs = [];
let lampFrame, socket, child, log = '';
function packet(channel, value) {
  return Buffer.from([channel>>3, 0x40|((channel<<3)&0x38)|((value>>12)&7), 0x80|((value>>6)&63), 0xc0|(value&63)]);
}
function allEights() {
  return rows.slice(1,12).every((value,index) => index===7 ? (value&31)===29 : (value&1023)===(29*32+29));
}
async function key(code, name) {
  inputs.push({time:Date.now(),name,code});
  socket.write(packet(0o15,code));
  await sleep(250);
}
async function connect() {
  for (let attempt=0; attempt<100; attempt++) {
    if (child.exitCode !== null || child.signalCode !== null) throw new Error('Owned yaAGC exited before connection');
    try {
      const candidate = net.createConnection({host:'127.0.0.1',port});
      await new Promise((resolve,reject)=>{candidate.once('connect',resolve);candidate.once('error',reject)});
      return candidate;
    } catch { await sleep(100); }
  }
  throw new Error('yaAGC did not open its socket');
}
async function main() {
  const rope=path.join(root,'LM131R1','MAIN.agc.bin');
  const ropeSha256=crypto.createHash('sha256').update(fs.readFileSync(rope)).digest('hex');
  if(ropeSha256!=='ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5') throw new Error('Pinned rope hash mismatch');
  const listeners=[];
  try {
    for(let candidate=port;candidate<port+10;candidate++) {
      const server=net.createServer();listeners.push(server);
      await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(candidate,'127.0.0.1',resolve)});
    }
  } finally {await Promise.all(listeners.map(server=>new Promise(resolve=>server.close(resolve))));}
  fs.mkdirSync(path.join(root,'runtime'),{recursive:true});
  const runtime=fs.mkdtempSync(path.join(root,'runtime','cli-test-'));
  const args=['--exec='+rope,'--port='+port,'--nodebug','--no-resume','--dump-time=3600','--show-alarms','--cd='+runtime];
  child = spawn(path.join(root,'yaAGC.exe'),args,{cwd:runtime,windowsHide:true});
  const closed=new Promise(resolve=>child.once('close',resolve));
  child.stdout.on('data',data=>log+=data);
  child.stderr.on('data',data=>log+=data);
  child.on('error',error=>log+=error.message);
  try {
    socket=await connect();
    let bytes=Buffer.alloc(0);
    socket.on('data',data=>{
      bytes=Buffer.concat([bytes,data]);
      while(bytes.length>=4) {
        if((bytes[0]&0xc0)!==0 || (bytes[1]&0xc0)!==0x40 || (bytes[2]&0xc0)!==0x80 || (bytes[3]&0xc0)!==0xc0) {
          bytes=bytes.subarray(1);continue;
        }
        const ch=((bytes[0]&31)<<3)|((bytes[1]>>3)&7);
        const value=((bytes[1]&7)<<12)|((bytes[2]&63)<<6)|(bytes[3]&63);
        packets.push({time:Date.now(),channel:ch,value}); channels[ch]=value;
        if(ch===0o10) rows[(value>>11)&15]=value;
        if(!lampFrame && allEights() && ((channels[0o13]||0)&0o1000)) lampFrame={rows:[...rows],channels:{...channels}};
        bytes=bytes.subarray(4);
      }
    });
    await sleep(3000);
    for(const [code,name] of [[17,'VERB'],[3,'3'],[7,'7'],[28,'ENTR'],[16,'0'],[16,'0'],[28,'ENTR']]) await key(code,name);
    await sleep(1000);
    for(const [code,name] of [[17,'VERB'],[3,'3'],[5,'5'],[28,'ENTR']]) await key(code,name);
    await sleep(7000);
    const result={passed:!!lampFrame && !((channels[0o13]||0)&0o1000),ropeSha256,args,runtime,
      initialization:'upstream defaults; zero erasable test initialization',flightPadloadApplied:false,
      lampFrame,finalRows:rows,finalChannels:channels,packetCount:packets.length,inputs};
    fs.writeFileSync(path.join(root,'cli-lamp-result.json'),JSON.stringify(result,null,2));
    fs.writeFileSync(path.join(root,'cli-channel-trace.json'),JSON.stringify(packets));
    console.log(JSON.stringify(result));
    if(!result.passed) process.exitCode=1;
  } finally {
    if(socket) socket.destroy();
    if(child.exitCode===null && child.signalCode===null) child.kill();
    await closed;
    fs.writeFileSync(path.join(root,'cli-lamp.log'),log);
  }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
