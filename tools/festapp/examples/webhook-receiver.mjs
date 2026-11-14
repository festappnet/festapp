// Minimal receiver behind an HTTPS reverse proxy. node >=22.13.
// FESTAPP_WEBHOOK_SECRET is the existing key returned by webhooks.create.
// The SQLite inbox is the durable acceptance boundary; process pending business
// actions from this inbox separately, using source/event_id for deduplication.
import { createHmac, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { chmodSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function verifyWebhook(body,headers,secret,now=Math.floor(Date.now()/1000)){
 if(!Buffer.isBuffer(body)||body.length>262144||!/^whsec_[A-Za-z0-9+/]{43}=$/.test(secret??''))return false;
 const id=headers['webhook-id'],timestamp=headers['webhook-timestamp'],signature=headers['webhook-signature'];
 if(typeof id!=='string'||!/^[0-9a-f-]{36}$/i.test(id)||typeof timestamp!=='string'||!/^\d{1,12}$/.test(timestamp)||
   Math.abs(now-Number(timestamp))>300||typeof signature!=='string'||signature.length>512)return false;
 const expected=createHmac('sha256',Buffer.from(secret.slice(6),'base64')).update(id+'.'+timestamp+'.').update(body).digest();
 return signature.split(' ').some(value=>{
  if(!/^v1,[A-Za-z0-9+/]{43}=$/.test(value))return false;
  const actual=Buffer.from(value.slice(3),'base64');return actual.length===expected.length&&timingSafeEqual(actual,expected);
 });
}
export function receiver({secret,file='festapp-webhook-inbox.sqlite'}){
 const db=new DatabaseSync(file);chmodSync(file,0o600);
 db.exec("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS inbox(delivery_id TEXT PRIMARY KEY,source TEXT NOT NULL,event_id TEXT NOT NULL,body TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',UNIQUE(source,event_id));");
 const server=createServer((req,res)=>{
  if(req.method!=='POST'||req.url!=='/webhooks/festapp'){res.writeHead(404);res.end();return;}
  const chunks=[];let bytes=0;
  req.on('data',chunk=>{bytes+=chunk.length;if(bytes>262144){res.writeHead(413);res.end();req.destroy();}else chunks.push(chunk);});
  req.on('end',()=>{
   if(bytes>262144)return;
   const raw=Buffer.concat(chunks);
   if(!verifyWebhook(raw,req.headers,secret)){res.writeHead(401);res.end();return;}
   let event;try{event=JSON.parse(raw.toString('utf8'));}catch{res.writeHead(400);res.end();return;}
   if(event.specversion!=='1.0'||typeof event.id!=='string'||typeof event.source!=='string'||
     !['net.festapp.order.created.v1','net.festapp.webhook.test.v1'].includes(event.type)){res.writeHead(400);res.end();return;}
   try{
    // INSERT OR IGNORE is atomic and the unique constraints deduplicate retries
    // and the same occurrence arriving through two subscriptions.
    db.prepare('INSERT OR IGNORE INTO inbox(delivery_id,source,event_id,body,state) VALUES(?,?,?,?,?)').run(req.headers['webhook-id'],event.source,event.id,raw.toString('utf8'),event.type.endsWith('.test.v1')?'test':'pending');
    res.writeHead(202);res.end();
   }catch{res.writeHead(503);res.end();} // No acknowledgement before durable write.
  });
 });
 server.requestTimeout=10000;server.headersTimeout=10000;
 server.on('close',()=>db.close());return server;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(!process.env.FESTAPP_WEBHOOK_SECRET)throw new Error('FESTAPP_WEBHOOK_SECRET is required');
 const server=receiver({secret:process.env.FESTAPP_WEBHOOK_SECRET,file:process.env.FESTAPP_WEBHOOK_INBOX});
 server.listen(8443,'127.0.0.1');
 const close=()=>server.close();process.once('SIGINT',close);process.once('SIGTERM',close);
}
