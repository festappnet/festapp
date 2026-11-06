import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {openSync,closeSync,readFileSync} from 'node:fs';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
export function receiptPath(path,existing=false){
 if(!path)throw Error('Receipt file path required');
 if(existing)JSON.parse(readFileSync(path,'utf8'));
 const fd=openSync(path,'a');closeSync(fd);return path;
}
export async function withDatabase(action,{count=1,connectionString=process.env.DATABASE_URL,Client=require('pg').Client}={}){
 assertLocalDatabaseUrl(connectionString);
 const clients=[],fixtures=[],claims=[];
 try{
  for(let i=0;i<count;i++){
   const c=new Client({connectionString,application_name:'notification-scalability-benchmark'});clients.push(c);
   await c.connect();await assertDisposableDatabase(c);
   claims.push((await c.query("SELECT current_setting('request.jwt.claim.sub',true) value")).rows[0]?.value ?? '');
   await c.query("SET statement_timeout='120s'; SET lock_timeout='2s'");
  }
  return await action(clients,fixtures);
 }finally{
  try{if(fixtures.length){
   await clients[0].query("SELECT set_config('request.jwt.claim.sub',$1,false)",[claims[0]]);
   for(const f of fixtures)await cleanupFixture(clients[0],f);
  }}finally{await Promise.allSettled(clients.map(c=>c.end()));}
 }
}
export async function timed(c,query,params){const t=performance.now();const r=await c.query(query,params);return {r,ms:performance.now()-t};}
export function percentile(xs,p){return [...xs].sort((a,b)=>a-b)[Math.min(xs.length-1,Math.ceil(xs.length*p)-1)];}
export function assertEqual(a,b,why){if(a!==b)throw Error(`${why}: ${a} !== ${b}`);}
export async function setupFixture(c,fixtures,events,recipients){
 const {rows:[{id:org}]}=await c.query("INSERT INTO public.organizations(title) VALUES('Notification scalability benchmark') RETURNING id");
 const users=Array.from({length:recipients},()=>randomUUID());const f={org,users};fixtures.push(f);
 await c.query('INSERT INTO auth.users(id) SELECT unnest($1::uuid[])',[users]);
 await c.query("INSERT INTO public.user_info(id,organization,email_readonly) SELECT u,$2,'viewer-'||u||'@example.invalid' FROM unnest($1::uuid[]) u",[users,org]);
 const {rows:[{id:oc}]}=await c.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Measured orders',$2,now(),now()+interval '1 day') RETURNING id",[org,randomUUID()]);f.oc=oc;
 await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) SELECT $1,unnest($2::uuid[]),true',[oc,users]);
 await c.query("INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES($1,now()-interval '60 days')",[org]);
 await c.query(`INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 SELECT $1,'ordered',public.generate_order_symbol(),i,jsonb_build_object('name','Buyer '||i,'email','buyer'||i||'@example.invalid') FROM generate_series(1,$2::int) i`,[oc,events]);
 const before=(await c.query('SELECT pg_current_wal_insert_lsn() lsn')).rows[0].lsn;
 const publication=await timed(c,`SELECT public.notification_center_publish_internal($1,$2,'order_created','bench:'||o.id,
 jsonb_build_object('orderId',o.id,'count',CASE WHEN o.order_sequence%10=0 THEN NULL ELSE o.order_sequence%3+1 END,
 'formContext',jsonb_build_object('allowsMultiple',true)),NULL,now()-interval '1 day')
 FROM eshop.orders o WHERE o.occasion=$2`,[org,oc]);
 const publicationWal=Number((await c.query('SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),$1) n',[before])).rows[0].n);
 return Object.assign(f,{events,recipients,publicationMs:publication.ms,publicationWal});
}
export async function cleanupFixture(c,f){
 await c.query('DELETE FROM public.notification_center_events WHERE organization=$1',[f.org]);
 if(f.oc)await c.query('DELETE FROM eshop.orders WHERE occasion=$1',[f.oc]);
 if(f.oc)await c.query('DELETE FROM public.occasion_users WHERE occasion=$1',[f.oc]);
 if(f.oc)await c.query('DELETE FROM public.occasions WHERE id=$1',[f.oc]);
 await c.query('DELETE FROM public.organization_users WHERE organization=$1',[f.org]);
 await c.query('DELETE FROM public.user_info WHERE id=ANY($1::uuid[])',[f.users]);
 await c.query('DELETE FROM public.organizations WHERE id=$1',[f.org]);
 await c.query('DELETE FROM auth.users WHERE id=ANY($1::uuid[])',[f.users]);
}
