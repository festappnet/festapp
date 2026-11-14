import assert from 'node:assert/strict';
import { createServer, request } from 'node:https';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHmac } from 'node:crypto';
import { createWebhookSender } from '../src/remote/webhook-delivery.mjs';
export async function webhookReceiver(t){
 const dir=mkdtempSync(join(tmpdir(),'festapp-webhook-e2e-'));
 execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',join(dir,'key'),'-out',join(dir,'cert'),'-days','1','-subj','/CN=hooks.example.com','-addext','subjectAltName=DNS:hooks.example.com'],{stdio:'ignore'});
 const cert=readFileSync(join(dir,'cert')),receipts=[];let status=202;
 const server=createServer({key:readFileSync(join(dir,'key')),cert},(req,res)=>{
  const chunks=[];req.on('data',x=>chunks.push(x));req.on('end',()=>{receipts.push({headers:req.headers,body:Buffer.concat(chunks).toString('utf8')});res.writeHead(status);res.end();});
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(async()=>{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));rmSync(dir,{recursive:true,force:true});});
 const send=createWebhookSender({resolve:async()=>[{address:'8.8.8.8',family:4}],requestImpl:(url,options,callback)=>request(url,{...options,ca:cert,port:server.address().port,lookup:(_h,o,cb)=>o.all?cb(null,[{address:'127.0.0.1',family:4}]):cb(null,'127.0.0.1',4)},callback)});
 return{send,receipts,status:value=>{status=value;},verify(receipt,secret){const h=receipt.headers;const signature='v1,'+createHmac('sha256',Buffer.from(secret.slice(6),'base64')).update(h['webhook-id']+'.'+h['webhook-timestamp']+'.'+receipt.body).digest('base64');assert(h['webhook-signature'].split(' ').includes(signature));}};
}
