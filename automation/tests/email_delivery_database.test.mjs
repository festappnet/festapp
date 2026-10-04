import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const target=process.env.EMAIL_TEST_DATABASE_URL;
const expected='postgresql://postgres:postgres@127.0.0.1:55434/postgres';
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
test('real pg_net wakes only after commit; two sessions cannot send the same intent twice',{skip:!target},async()=>{
 assert.equal(target,expected,'only the isolated email rehearsal database is allowed');
 const a=new Client({connectionString:target}),b=new Client({connectionString:target});await a.connect();await b.connect();
 const original=(await a.query('SELECT * FROM public.email_capacity')).rows[0];
 const key=`functional-${randomUUID()}`;let message;let requests=0;
 const server=http.createServer((req,res)=>{let body='';req.on('data',data=>body+=data);req.on('end',()=>{assert.equal(typeof JSON.parse(body).requestSecret,'string');requests++;res.writeHead(204);res.end();});});
 await new Promise(resolve=>server.listen(0,'0.0.0.0',resolve));
 const url=`http://host.docker.internal:${server.address().port}/wake`;
 const enqueue=()=>a.query("SELECT public.enqueue_email('custom','{\"organization\":1}', 'single-fixture@example.invalid','{}',$1) result",[key]);
 try{
  await a.query('UPDATE public.email_capacity SET paused=false,worker_url=$1,quota_at=now(),max_rate=1,daily_quota=100,provider_sent_24h=0,shared_account=false,next_send_at=now()', [url]);
  await a.query('BEGIN');await enqueue();await pause(300);assert.equal(requests,0,'no wake before commit');await a.query('ROLLBACK');await pause(300);assert.equal(requests,0,'rolled-back intent never wakes');
  await a.query('BEGIN');message=(await enqueue()).rows[0].result.message_id;
  assert.equal((await enqueue()).rows[0].result.message_id,message,'same command joins transaction intent');
  await pause(300);assert.equal(requests,0);await a.query('COMMIT');
  for(let i=0;i<50&&requests===0;i++)await pause(100);
  assert.equal(requests,1,'one coalesced post-commit HTTP wake');
  await a.query('UPDATE public.email_capacity SET worker_url=NULL');
  const claims=await Promise.all([a.query('SELECT public.claim_email() row'),b.query('SELECT public.claim_email() row')]);
  const rows=claims.map(r=>r.rows[0].row).filter(Boolean);assert.equal(rows.length,1,'one preparation owner');const row=rows[0];assert.equal(row.message_id,message);
  await a.query('SELECT public.prepare_email($1,$2,$3)',[message,row.lease_token,{sealed:'functional-snapshot'}]);
  const begins=await Promise.all([a.query('SELECT public.begin_email_send($1,$2) result',[row.attempt_id,row.lease_token]),b.query('SELECT public.begin_email_send($1,$2) result',[row.attempt_id,row.lease_token])]);
  assert.deepEqual(begins.map(r=>r.rows[0].result.disposition).sort(),['replay','send']);
  await a.query("SELECT public.finish_email_attempt($1,$2,'unknown',NULL,'functional_disconnect')",[row.attempt_id,row.lease_token]);
  assert.equal((await b.query('SELECT public.claim_email() row')).rows[0].row,null,'uncertain result never reclaims');
 }finally{
  await a.query('ROLLBACK');
  if(message){await a.query('DELETE FROM public.email_attempts WHERE message_id=$1',[message]);await a.query('DELETE FROM public.email_messages WHERE message_id=$1',[message]);}
  // Restore the exact paused local authority, never leave a provider enabled.
  await a.query('UPDATE public.email_capacity SET paused=$1,worker_url=$2,quota_at=$3,max_rate=$4,daily_quota=$5,provider_sent_24h=$6,shared_account=$7,next_send_at=$8',[original.paused,original.worker_url,original.quota_at,original.max_rate,original.daily_quota,original.provider_sent_24h,original.shared_account,original.next_send_at]);
  server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await a.end();await b.end();
 }
});
