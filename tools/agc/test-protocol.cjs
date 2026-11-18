// SPDX-License-Identifier: GPL-2.0-or-later
// Verify active-low PRO masking through unchanged yaAGC and fresh observer snapshots.
const fs=require('node:fs'),path=require('node:path'),net=require('node:net');
const crypto=require('node:crypto'),{spawn}=require('node:child_process');
const root=process.argv[2]||'D:/apollo-ref/build/agc';
const port=Number(process.argv[3]||19857),proBit=0o20000;
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const encode=(channel,value)=>Buffer.from([channel>>3,0x40|((channel<<3)&0x38)|((value>>12)&7),0x80|((value>>6)&63),0xc0|(value&63)]);
let child,controller,closed,log='';
async function preflight() {
  const listeners=[];
  try {
    for(let p=port;p<port+10;p++) {
      const server=net.createServer();listeners.push(server);
      await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(p,'127.0.0.1',resolve)});
    }
  } finally {await Promise.all(listeners.map(s=>new Promise(resolve=>s.close(resolve))));}
}
async function connect(targetPort=port) {
  for(let attempt=0;attempt<60;attempt++) {
    if(child.exitCode!==null||child.signalCode!==null) throw new Error('Owned yaAGC exited');
    const socket=net.createConnection({host:'127.0.0.1',port:targetPort});
    try {
      await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('error',reject)});
      socket.setNoDelay(true);return socket;
    } catch {socket.destroy();await wait(100);}
  }
  throw new Error('yaAGC did not start listening');
}
async function observeChannel32(observerPort) {
  const socket=await connect(observerPort);
  try {
    return await new Promise((resolve,reject)=>{
      let pending=Buffer.alloc(0);const packets=[];
      const timer=setTimeout(()=>reject(new Error('No nonzero channel032 snapshot')),1500);
      socket.on('error',error=>{clearTimeout(timer);reject(error)});
      socket.on('data',bytes=>{
        pending=Buffer.concat([pending,bytes]);
        while(pending.length>=4) {
          if((pending[0]&0xc0)!==0||(pending[1]&0xc0)!==0x40||(pending[2]&0xc0)!==0x80||(pending[3]&0xc0)!==0xc0) {
            pending=pending.subarray(1);continue;
          }
          const channel=((pending[0]&31)<<3)|((pending[1]>>3)&7),uBit=!!(pending[0]&0x20);
          const value=((pending[1]&7)<<12)|((pending[2]&63)<<6)|(pending[3]&63);
          pending=pending.subarray(4);packets.push({channel,value,uBit});
          if(channel===0o32&&!uBit) {clearTimeout(timer);resolve({value,valueOctal:value.toString(8).padStart(5,'0'),packets});return;}
        }
      });
    });
  } finally {socket.destroy();}
}
async function fragmentedPacket(channel,value) {
  // Deliberately split all four bytes. SocketAPI must retain partial packets.
  for(const byte of encode(channel,value)) {controller.write(Buffer.from([byte]));await wait(3);}
}
async function main() {
  const rope=path.join(root,'LM131R1','MAIN.agc.bin');
  const ropeSha256=crypto.createHash('sha256').update(fs.readFileSync(rope)).digest('hex');
  if(ropeSha256!=='ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5') throw new Error('Pinned rope hash mismatch');
  await preflight();fs.mkdirSync(path.join(root,'runtime'),{recursive:true});
  const runtime=fs.mkdtempSync(path.join(root,'runtime','protocol-test-'));
  const args=['--exec='+rope,'--port='+port,'--nodebug','--no-resume','--quiet','--dump-time=86400','--cd='+runtime];
  child=spawn(path.join(root,'yaAGC.exe'),args,{cwd:runtime,windowsHide:true});
  closed=new Promise(resolve=>child.once('close',resolve));
  child.stdout.on('data',data=>log+=data);child.stderr.on('data',data=>log+=data);
  child.on('error',error=>log+=error.message);
  try {
    controller=await connect();controller.on('data',()=>{});
    const baseline=await observeChannel32(port+1);
    await fragmentedPacket(0o432,proBit);
    await fragmentedPacket(0o32,0);await wait(120);
    const pressed=await observeChannel32(port+2);
    await fragmentedPacket(0o32,proBit);await wait(120);
    const released=await observeChannel32(port+3);
    const checks={baselineReleased:!!(baseline.value&proBit),pressActiveLow:!(pressed.value&proBit),
      onlyProBitChangesOnPress:(baseline.value^pressed.value)===proBit,
      releaseRestoresBaseline:released.value===baseline.value,
      observerSnapshotsHaveNoMaskPackets:[baseline,pressed,released].every(s=>s.packets.every(p=>!p.uBit))};
    const result={schemaVersion:1,passed:Object.values(checks).every(Boolean),realUpstreamCli:true,ropeSha256,
      flightPadloadApplied:false,port,args,runtime,checks,baseline,pressed,released};
    const output=path.resolve(__dirname,'../../reference/agc-protocol.json');
    fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');
    console.log(JSON.stringify({passed:result.passed,checks,baseline:baseline.valueOctal,pressed:pressed.valueOctal,
      released:released.valueOctal,output}));
    if(!result.passed) process.exitCode=1;
  } finally {
    controller?.destroy();
    if(child.exitCode===null&&child.signalCode===null) child.kill();
    await closed;fs.writeFileSync(path.join(runtime,'protocol-test.log'),log);
  }
}
main().catch(error=>{console.error(error);process.exitCode=1});
