import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:https';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHmac } from 'node:crypto';
import { createWebhookSender, publicWebhookAddress, validateWebhookUrl, webhookRetryAfter } from '../src/remote/webhook-delivery.mjs';
const deliveryId='11111111-1111-4111-8111-111111111111',secret='whsec_'+Buffer.alloc(32,1).toString('base64');

test('destination policy rejects alternate IP syntax, credentials, non-HTTPS and local names',()=>{
 for(const url of ['http://example.com','https://user:pass@example.com','https://example.com:8443/','https://example.com/#x','https://localhost','https://x.local','https://x.internal','https://127.1','https://2130706433','https://0x7f000001','https://[::1]','https://[::ffff:127.0.0.1]','https://example.com\n','https://example.com./'])
  assert.throws(()=>validateWebhookUrl(url));
 assert.equal(validateWebhookUrl('https://hooks.example.com/a?token=x').hostname,'hooks.example.com');
});
test('egress allows global addresses and rejects private, metadata, mapped and reserved ranges',()=>{
 for(const ip of ['8.8.8.8','1.1.1.1','2606:4700:4700::1111','2001:4860:4860::8888'])assert.equal(publicWebhookAddress(ip),true,ip);
 for(const ip of ['0.0.0.0','127.0.0.1','10.0.0.1','169.254.169.254','172.16.0.1','192.168.1.1','100.64.0.1','192.0.2.1','198.18.0.1','203.0.113.1','224.1.1.1','255.255.255.255','::1','::','fe80::1','fc00::1','::ffff:8.8.8.8','::ffff:127.0.0.1','64:ff9b::a00:1','2002:7f00:1::','2001:db8::1','3fff::1','fe80::1%en0','not-an-ip'])assert.equal(publicWebhookAddress(ip),false,ip);
});
test('Retry-After parses delta/date safely',()=>{
 assert.equal(webhookRetryAfter('120'),120);assert.equal(webhookRetryAfter('Wed, 01 Jan 2031 00:00:10 GMT',Date.parse('2031-01-01T00:00:00Z')),10);
 for(const value of [undefined,'-5','garbage','9999999999999999999999999'])assert.equal(webhookRetryAfter(value),0);
});
test('sender blocks private/mixed DNS and resolves afresh on every attempt',async()=>{
 let lookups=0,requests=0;
 const send=createWebhookSender({resolve:async()=>{lookups++;return lookups===1?[{address:'8.8.8.8',family:4},{address:'127.0.0.1',family:4}]:[{address:'169.254.169.254',family:4}];},requestImpl:()=>{requests++;throw Error('must not send');}});
 for(let i=0;i<2;i++)assert.equal((await send({url:'https://hooks.example.com/',body:'{}',deliveryId,secrets:[secret],beforeSend:()=>{}})).errorCategory,'destination');
 assert.equal(lookups,2);assert.equal(requests,0);
});
test('DNS and pre-dispatch authorization are bounded by the total deadline',async()=>{
 const blocked=createWebhookSender({resolve:()=>new Promise(()=>{}),timeoutMs:20});
 const args={url:'https://hooks.example.com/',body:'{}',deliveryId,secrets:[secret],beforeSend:()=>{}};
 assert.equal((await blocked(args)).errorCategory,'timeout');
 const auth=createWebhookSender({resolve:async()=>[{address:'8.8.8.8',family:4}],timeoutMs:20});
 assert.equal((await auth({...args,beforeSend:()=>new Promise(()=>{})})).errorCategory,'timeout');
 let requests=0;
 const denied=createWebhookSender({resolve:async()=>[{address:'8.8.8.8',family:4}],requestImpl:()=>{requests++;}});
 assert.equal((await denied({...args,beforeSend:()=>{throw Object.assign(new Error('private'),{code:'FORBIDDEN'});}})).errorCategory,'revoked');assert.equal(requests,0);
});
test('real TLS receiver verifies signed bytes; redirects are not followed and response bodies are not retained',async t=>{
 const root=mkdtempSync(join(tmpdir(),'festapp-webhook-tls-'));t.after(()=>rmSync(root,{recursive:true,force:true}));
 execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',join(root,'key.pem'),'-out',join(root,'cert.pem'),'-days','1','-subj','/CN=hooks.example.com','-addext','subjectAltName=DNS:hooks.example.com'],{stdio:'ignore'});
 const key=readFileSync(join(root,'key.pem')),cert=readFileSync(join(root,'cert.pem')),received=[];
 const server=createServer({key,cert},(req,res)=>{
  const chunks=[];req.on('data',c=>chunks.push(c));req.on('end',()=>{
   const body=Buffer.concat(chunks).toString('utf8');received.push({body,headers:req.headers});
   const input=req.headers['webhook-id']+'.'+req.headers['webhook-timestamp']+'.'+body;
   assert.equal(req.headers['webhook-signature'],'v1,'+createHmac('sha256',Buffer.alloc(32,1)).update(input).digest('base64'));
   if(req.url==='/redirect'){res.writeHead(302,{location:'http://127.0.0.1/private'});res.end();}
   else if(req.url==='/retry'){res.writeHead(429,{'retry-after':'60'});res.end('do not persist me');}
   else if(req.url==='/gone'){res.writeHead(410);res.end();}
   else if(req.url==='/fail'){res.writeHead(503);res.end();}
   else if(req.url==='/slow'){} // Client timeout must close this socket.
   else{res.writeHead(202);res.flushHeaders();res.write('x'.repeat(65536));}
  });
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(async()=>{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));});
 const send=createWebhookSender({resolve:async()=>[{address:'8.8.8.8',family:4}],timeoutMs:200,
  requestImpl:(url,options,callback)=>{
   assert.equal(options.servername,'hooks.example.com');assert.equal(options.rejectUnauthorized,true);assert.equal(options.agent,false);
   options.lookup('hooks.example.com',{all:false},(_error,address)=>assert.equal(address,'8.8.8.8'));
   // Test-only transport substitution. Keep the real TLS hostname/CA verification.
   return request(url,{...options,port:server.address().port,ca:cert,lookup:(_h,opts,cb)=>opts.all?cb(null,[{address:'127.0.0.1',family:4}]):cb(null,'127.0.0.1',4)},callback);
  }});
 const body='{ "jméno": "Jana" }\n';
 const attempt=path=>send({url:'https://hooks.example.com'+path,body,deliveryId,secrets:[secret],beforeSend:async()=>{}});
 assert.equal((await attempt('/ok')).status,202);
 assert.equal((await attempt('/redirect')).status,302);assert.equal(received.length,2);
 const retry=await attempt('/retry');assert.equal(retry.status,429);assert.equal(retry.retryAfterSeconds,60);assert.equal(Object.hasOwn(retry,'body'),false);
 assert.equal((await attempt('/gone')).status,410);assert.equal((await attempt('/fail')).status,503);assert.equal((await attempt('/slow')).errorCategory,'timeout');
 assert.equal(received.every(v=>v.body===body),true);
});
