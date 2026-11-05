#!/usr/bin/env node
// Fixed-arrival disposable workload with a separate publication connection.
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {writeFileSync,readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;assertLocalDatabaseUrl(connectionString);
const setup=new Client({connectionString}),publisher=new Client({connectionString}),worker=new Client({connectionString});
await Promise.all([setup.connect(),publisher.connect(),worker.connect()]);await assertDisposableDatabase(setup);
const users=Array.from({length:5},()=>randomUUID());let org,oc;
const pause=ms=>new Promise(r=>setTimeout(r,Math.max(0,ms)));
try{
 ({rows:[{id:org}]}=await setup.query("INSERT INTO public.organizations(title) VALUES('Notification fixed arrivals') RETURNING id"));
 await setup.query('INSERT INTO auth.users(id) SELECT unnest($1::uuid[])',[users]);
 await setup.query('INSERT INTO public.user_info(id,organization) SELECT unnest($1::uuid[]),$2',[users,org]);
 ({rows:[{id:oc}]}=await setup.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Sustained',$2,now(),now()+interval '1 day') RETURNING id",[org,randomUUID()]));
 await setup.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) SELECT $1,unnest($2::uuid[]),true',[oc,users]);
 await setup.query('INSERT INTO public.notification_center_organizations(organization) VALUES($1)',[org]);
 for(const user of users){
  await setup.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);
  await setup.query('SELECT public.get_notification_center_prepared_badge($1)',[org]);
 }
 for(let i=0;i<10;i++)await worker.query('SELECT public.prepare_notification_center(100)');
 let publishing=true,done=false,processed=0,prepared=0,calls=0;const backlog=[],scheduleLag=[];
 const start=performance.now();
 const produce=(async()=>{try{
  for(let tick=0;tick<240;tick++){
   await pause(start+tick*250-performance.now());scheduleLag.push(performance.now()-(start+tick*250));
   await publisher.query(`WITH orders AS(INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
    SELECT $1,'ordered',public.generate_order_symbol(),$2::int*10+i,jsonb_build_object('name','Buyer '||($2::int*10+i),'email','buyer'||($2::int*10+i)||'@example.invalid')
    FROM generate_series(1,10) i RETURNING id)
    SELECT public.notification_center_publish_internal($3,$1,'order_created','sustain:'||id,jsonb_build_object('orderId',id,'count',2,'formContext',jsonb_build_object('allowsMultiple',true))) FROM orders`,[oc,tick,org]);
  }
 }finally{publishing=false;}})();
 const consume=(async()=>{
  while(!done && performance.now()-start<70000){
   const {rows:[r]}=await worker.query('SELECT public.project_notification_center(500) n');processed+=r.n;calls++;
   prepared+=(await worker.query('SELECT public.prepare_notification_center(100) n')).rows[0].n;
   await worker.query('SELECT public.prepare_notification_center_views(100)');
   const {rows:[q]}=await worker.query(`SELECT count(*)::int pending,coalesce(extract(epoch FROM clock_timestamp()-min(r.pending_since))*1000,0)::float8 age_ms
    FROM public.notification_center_recipients r JOIN public.notification_center_events e ON e.id=r.event_id
    WHERE e.organization=$1 AND r.processed_revision<r.eligible_revision`,[org]);
   backlog.push({atMs:performance.now()-start,...q});
   if(!publishing&&q.pending===0){done=true;break;}
   await pause(25);
  }
 })();
 await Promise.all([produce,consume]);
 const {rows:[totals]}=await setup.query('SELECT count(*)::int deliveries,count(distinct event_id)::int events FROM public.notification_center_deliveries WHERE organization=$1',[org]);
 if(totals.deliveries!==12000)throw Error('Sustained workload failed to drain: '+JSON.stringify(totals));
 const {rows:[summary]}=await setup.query('SELECT sum(activity_count)::int contributions,count(*)::int summaries FROM public.notification_center_batch_summaries WHERE organization=$1',[org]);
 if(summary.contributions!==12000)throw Error('Prepared summaries failed: '+JSON.stringify(summary));
 const p=process.argv[2];const receipt=JSON.parse(readFileSync(p,'utf8'));
 receipt.preparedSustained={projectorSha256:createHash('sha256').update(readFileSync(new URL('../../database/functions/notification_center/core.sql',import.meta.url))).digest('hex'),durationMs:performance.now()-start,nominalEventsPerSecond:40,recipients:5,nominalRecipientRevisionsPerSecond:200,processed,prepared,calls,...totals,...summary,
 maximumScheduleLagMs:Math.max(...scheduleLag),maximumPending:Math.max(...backlog.map(x=>x.pending)),maximumPendingAgeMs:Math.max(...backlog.map(x=>x.age_ms)),lastBacklog:backlog.at(-1),samples:backlog};
 writeFileSync(p,JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify({...receipt.preparedSustained,samples:backlog.length}));
}finally{
 try{if(oc){await setup.query('DELETE FROM public.notification_center_events WHERE organization=$1',[org]);await setup.query('DELETE FROM eshop.orders WHERE occasion=$1',[oc]);await setup.query('DELETE FROM public.occasion_users WHERE occasion=$1',[oc]);await setup.query('DELETE FROM public.occasions WHERE id=$1',[oc]);await setup.query('DELETE FROM public.user_info WHERE id=ANY($1::uuid[])',[users]);await setup.query('DELETE FROM public.organizations WHERE id=$1',[org]);await setup.query('DELETE FROM auth.users WHERE id=ANY($1::uuid[])',[users]);}}
 finally{await Promise.all([setup.end(),publisher.end(),worker.end()]);}
}
