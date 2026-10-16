// Executed by proxy_body_contract.test.mjs in the Caddy network namespace.
import http from 'node:http';
import assert from 'node:assert/strict';
const server=http.createServer(async(req,res)=>{
 let bytes=0;
 try{for await(const chunk of req) bytes+=chunk.length;}catch{return;}
 res.setHeader('Content-Type','application/json');
 res.end(JSON.stringify({bytes,ip:req.headers['x-festapp-client-ip'],forwarded:req.headers.forwarded,xff:req.headers['x-forwarded-for']}));
});
server.on('upgrade',(req,socket)=>{socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');socket.on('data',chunk=>socket.write(chunk));});
await new Promise(resolve=>server.listen(8000,'127.0.0.1',resolve));
async function send(path,size,chunked=false){
 return new Promise((resolve,reject)=>{
  const req=http.request({host:'127.0.0.1',port:8080,path,method:'POST',headers:{'X-Festapp-Client-IP':'6.6.6.6','CF-Connecting-IP':'6.6.6.7','X-Forwarded-For':'6.6.6.8',Forwarded:'for=6.6.6.9',...(chunked?{}:{'Content-Length':size})}},res=>{
   let body='';res.on('data',c=>body+=c);res.on('end',()=>resolve({status:res.statusCode,body}));
  });
  req.on('error',reject);
  let left=size;const chunk=Buffer.alloc(65536);
  function write(){while(left>0){const n=Math.min(left,chunk.length);left-=n;if(!req.write(chunk.subarray(0,n))){req.once('drain',write);return;}}req.end();}write();
 });
}
try{
 for(const path of ['/storage/v1/object/fixture','/storage/v1/upload/resumable','/storage/v1/object/copy']){
  const r=await send(path,50*1024**2+1024);assert.equal(r.status,200,r.body);
  const data=JSON.parse(r.body);assert.equal(data.bytes,50*1024**2+1024);assert.equal(data.ip,'127.0.0.1');assert.equal(data.xff,'127.0.0.1');assert.equal(data.forwarded,undefined);
 }
 for(const [path,size] of [['/storage/v1/object/fixture',53*1024**2],['/rest/v1/rpc/fixture',33*1024**2],['/auth/v1/token',65*1024]]){
  for(const chunked of [false,true]){const r=await send(path,size,chunked);assert.equal(r.status,413,`${path} chunked=${chunked}: ${r.status}`);}
 }
 assert.equal((await send('/rest/v1/rpc/fixture',1024)).status,200);
 await new Promise((resolve,reject)=>{
  const req=http.request({host:'127.0.0.1',port:8080,path:'/realtime/v1/websocket',headers:{Connection:'Upgrade',Upgrade:'websocket'}});
  req.on('error',reject);req.on('upgrade',(res,socket)=>{assert.equal(res.statusCode,101);socket.once('data',data=>{assert.equal(data.toString(),'fixture');socket.destroy();resolve();});socket.write('fixture');});req.end();
 });
 console.log('Proxy: 50MiB Storage, fixed/chunked caps, trusted headers and websocket passed');
}finally{server.closeAllConnections();server.close();}
