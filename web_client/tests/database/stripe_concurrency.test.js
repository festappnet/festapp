import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import {execFileSync} from 'node:child_process';
import {randomUUID, randomBytes, createHash} from 'node:crypto';
import {assertDisposableDatabase} from './disposable_database.js';
const source=process.env.DATABASE_URL;
const container=process.env.FESTAPP_STRIPE_TEST_CONTAINER || 'supabase_db_festapp-db-tests-pg15';
async function connect(url){const c=new pg.Client({connectionString:url});await c.connect();await c.query("SET statement_timeout='25s'; SET lock_timeout='20s'; SET request.jwt.claim.role='service_role'; SET request.jwt.claim.sub=''; SET festapp.email_wake='scheduled'");return c;}
const hash=s=>createHash('sha256').update(s).digest('hex');
test('Stripe SQL authority serializes checkout, duplicate webhook and refund/admission races',{skip:!source},async()=>{
 const base=new URL(source);
 assert.ok(['127.0.0.1','localhost'].includes(base.hostname)&&base.port&&base.pathname==='/postgres','Only an explicit loopback PostgreSQL harness is allowed');
 assert.match(container,/^supabase_db_festapp-[a-z0-9-]+$/);
 const local=JSON.parse(execFileSync('docker',['inspect',container],{encoding:'utf8'}))[0];
 assert.ok(local.NetworkSettings.Ports['5432/tcp'].some(binding=>binding.HostPort===base.port),'The named local Supabase container must own the database port');
 const identity=await connect(source);
 try {
  await assertDisposableDatabase(identity);
  const project=(await identity.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0].project;
  assert.equal(container,'supabase_db_'+project,'Container must match the owned disposable bootstrap identity');
 }finally{await identity.end();}
 const name='stripe_concurrency_'+randomUUID().replaceAll('-','');
 const adminUrl=new URL(base);adminUrl.pathname='/template1';const admin=await connect(adminUrl.toString());
 const targetUrl=new URL(base);targetUrl.pathname='/'+name;targetUrl.username='supabase_admin';
 let control;const writers=[];
 try{
  // A logical snapshot avoids disconnecting pg_cron/pg_net or other sessions.
  // Scheduler extensions are intentionally absent in this isolated test database.
  const dump=execFileSync('docker',['exec','-e','PGPASSWORD=postgres',container,'pg_dump','-U','postgres','-d','postgres','--no-owner','--exclude-schema=cron','--exclude-schema=net'],{maxBuffer:64*1024*1024}).toString()
   .replace(/^CREATE EXTENSION IF NOT EXISTS (pg_cron|pg_net)[^;]*;/gm,'')
   .replace(/^COMMENT ON EXTENSION (pg_cron|pg_net)[^;]*;/gm,'')
   .replace(/^(GRANT|REVOKE) [^\n]* ON (?:FUNCTION|TABLE|SEQUENCE) (cron|net|graphql_public)\.[^;]*;/gm,'');
  await admin.query(`CREATE DATABASE ${name} TEMPLATE template0`);
  control=await connect(targetUrl.toString());
  await control.query('CREATE SCHEMA cron; CREATE SCHEMA net');
  execFileSync('docker',['exec','-e','PGPASSWORD=postgres','-i',container,'psql','-U','supabase_admin','-d',name,'-v','ON_ERROR_STOP=1','-q'],{input:dump,maxBuffer:4*1024*1024});
  await control.query("SET request.jwt.claim.role='service_role'; SET request.jwt.claim.sub=''; SET festapp.email_wake='scheduled'");
  writers.push(await connect(targetUrl.toString()),await connect(targetUrl.toString()));
  const scalar=async(sql,args=[])=>Object.values((await control.query(sql,args)).rows[0])[0];
  const org=await scalar(`INSERT INTO public.organizations(title,data) VALUES('Stripe concurrency','{"DEFAULT_URL":"https://tickets.example"}') RETURNING id`);
  const unit=await scalar("INSERT INTO public.units(title,organization) VALUES('Race recipient',$1) RETURNING id",[org]);
  await control.query('INSERT INTO eshop.stripe_unit_features(unit_id,enabled) VALUES($1,true)',[unit]);
  const occ=await scalar("INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Race',$1,$2,$3,now(),now()+interval '2 days') RETURNING id",[org,unit,name]);
  const conn=await scalar("INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active) VALUES($1,$2,'acct_raceFixture',false,'connected',false,true,true,true) RETURNING id",[org,unit]);
  await control.query("INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled,online_admission_verified,reservation_policy_verified,dispute_policy_accepted,supported_surfaces) VALUES($1,false,true,true,true,true,ARRAY['web'])",[org]);
  const key=randomUUID();const form=await scalar("INSERT INTO public.forms(occasion,data,is_open,key) VALUES($1,$2,true,$3) RETURNING id",[occ,{payments:{bankEnabled:false,stripeConnectionId:conn}},key]);
  const pt=await scalar("INSERT INTO eshop.product_types(occasion,title,type) VALUES($1,'Tickets','spot') RETURNING id",[occ]);
  const product=await scalar("INSERT INTO eshop.products(product_type,occasion,title,price,currency_code,is_hidden) VALUES($1,$2,'Ticket',123.45,'CZK',false) RETURNING id",[pt,occ]);
  await control.query("INSERT INTO public.form_fields(form,product_type,type) VALUES($1,$2,'product_type')",[form,pt]);
  const token=randomBytes(32).toString('hex');
  const payload={form:key,email:'race@example.test',payment_method:'stripe',payment_type:'full',expected_payment_amount_minor:12345,expected_payment_currency:'CZK',stripe_connection_id:conn,payment_surface:'web',stripePaymentSource:{tokenHash:hash(token),returnHash:hash(randomBytes(32).toString('hex')),contentHash:'c'.repeat(64),sealed:{v:'1',iv:'fixture',ciphertext:'fixture'}},ticket:[{fields:[{product_type:product}]}]};
  const created=await scalar('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3)',[payload,randomUUID(),randomUUID()]);
  assert.equal(Number(created.data.code),200);const order=created.data.order.id;
  const a=(await control.query('SELECT * FROM eshop.stripe_checkout_attempts WHERE order_id=$1',[order])).rows[0];
  // A held form lock and two blocked backend PIDs establish actual overlap.
  async function race(statements){
   await control.query('BEGIN');await control.query('SELECT 1 FROM public.forms WHERE id=$1 FOR UPDATE',[form]);
   const pending=statements.map(async(fn,i)=>{await writers[i].query('BEGIN');try{const value=await fn(writers[i]);await writers[i].query('COMMIT');return {value};}catch(error){await writers[i].query('ROLLBACK');return {error};}});
   let blocked=0;
   for(let n=0;n<150&&blocked<2;n++){blocked=Number(await scalar("SELECT count(*) FROM pg_stat_activity WHERE datname=$1 AND wait_event_type='Lock'",[name]));if(blocked<2)await new Promise(r=>setTimeout(r,10));}
   await control.query('COMMIT');const results=await Promise.all(pending);
   assert.ok(blocked>=2,'two concurrent PostgreSQL writers must block before the barrier releases');return results;
  }
  const claims=await race(writers.map(()=>async w=>(await w.query('SELECT public.claim_stripe_checkout_internal($1,false) r',[token])).rows[0].r));
  for(const r of claims)assert.ifError(r.error);
  assert.deepEqual(claims.map(r=>r.value.disposition).sort(),['busy','dispatch']);
  const lease=claims.find(r=>r.value.disposition==='dispatch').value.lease;
  await control.query("SELECT public.commit_stripe_checkout_session_internal($1,$2,'cs_test_race','https://checkout.stripe.com/c/pay/cs_test_race',$3)",[a.id,lease,Math.round(a.reservation_expires_at.getTime()/1000)]);
  const claim=await scalar("SELECT public.claim_stripe_sync_internal('acct_raceFixture',false,$1,'cs_test_race',NULL)",[a.id]);
  const occurredAt=Math.floor(a.created_at.getTime()/1000);
  const facts={observedAt:new Date().toISOString(),sessionId:'cs_test_race',paymentIntentId:'pi_race',sessionStatus:'complete',movements:[{providerId:'pi_race',kind:'payment',amountMinor:12345,currency:'CZK',occurredAt}],disputes:[]};
  const event={id:'evt_racePaid',bodyHash:'a'.repeat(64),accountId:'acct_raceFixture',livemode:false,type:'checkout.session.completed',created:occurredAt};
  const ingest=(w,e,f)=>w.query('SELECT public.ingest_stripe_payment_internal($1,$2,$3,$4) r',[a.id,claim.lease,e,f]).then(r=>r.rows[0].r);
  // Closing new sales cannot revoke an already reserved, provider-confirmed order.
  const closeToken=randomBytes(32).toString('hex');
  const closePayload={...payload,stripePaymentSource:{...payload.stripePaymentSource,tokenHash:hash(closeToken),returnHash:hash(randomBytes(32).toString('hex'))}};
  const closeOrder=(await scalar('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3)',[closePayload,randomUUID(),randomUUID()])).data.order.id;
  const closeAttempt=(await control.query('SELECT * FROM eshop.stripe_checkout_attempts WHERE order_id=$1',[closeOrder])).rows[0];
  const closeCheckout=await scalar('SELECT public.claim_stripe_checkout_internal($1,false)',[closeToken]);
  await control.query("SELECT public.commit_stripe_checkout_session_internal($1,$2,'cs_test_saleClose','https://checkout.stripe.com/c/pay/cs_test_saleClose',$3)",[closeAttempt.id,closeCheckout.lease,Math.round(closeAttempt.reservation_expires_at.getTime()/1000)]);
  const closeClaim=await scalar("SELECT public.claim_stripe_sync_internal('acct_raceFixture',false,$1,'cs_test_saleClose',NULL)",[closeAttempt.id]);
  const closeFacts={...facts,sessionId:'cs_test_saleClose',paymentIntentId:'pi_saleClose',movements:[{...facts.movements[0],providerId:'pi_saleClose'}]};
  const saleClose=await race([
   async w=>(await w.query('UPDATE public.forms SET is_open=false WHERE id=$1 RETURNING id',[form])).rows[0].id,
   async w=>(await w.query('SELECT public.ingest_stripe_payment_internal($1,$2,$3,$4) r',[closeAttempt.id,closeClaim.lease,{...event,id:'evt_saleClosePaid',bodyHash:'d'.repeat(64)},closeFacts])).rows[0].r,
  ]);
  for(const r of saleClose)assert.ifError(r.error);
  assert.equal(await scalar('SELECT state FROM eshop.orders WHERE id=$1',[closeOrder]),'paid');
  assert.equal(Number(await scalar('SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=$1',[closeAttempt.id])),1);
  const closed=await scalar('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3)',[{...payload,stripePaymentSource:{...payload.stripePaymentSource,tokenHash:hash(randomBytes(32).toString('hex')),returnHash:hash(randomBytes(32).toString('hex'))}},randomUUID(),randomUUID()]);
  assert.notEqual(Number(closed.data.code),200,'new orders must be rejected after closure');
  await control.query('UPDATE public.forms SET is_open=true WHERE id=$1',[form]);
  // Ordinary cancellation cannot reset a card debt while its signed payment commits.
  const cancelToken=randomBytes(32).toString('hex');
  const cancelPayload={...payload,stripePaymentSource:{...payload.stripePaymentSource,tokenHash:hash(cancelToken),returnHash:hash(randomBytes(32).toString('hex'))}};
  const cancelOrder=(await scalar('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3)',[cancelPayload,randomUUID(),randomUUID()])).data.order.id;
  const cancelAttempt=(await control.query('SELECT * FROM eshop.stripe_checkout_attempts WHERE order_id=$1',[cancelOrder])).rows[0];
  const cancelCheckout=await scalar('SELECT public.claim_stripe_checkout_internal($1,false)',[cancelToken]);
  await control.query("SELECT public.commit_stripe_checkout_session_internal($1,$2,'cs_test_cancelRace','https://checkout.stripe.com/c/pay/cs_test_cancelRace',$3)",[cancelAttempt.id,cancelCheckout.lease,Math.round(cancelAttempt.reservation_expires_at.getTime()/1000)]);
  const cancelClaim=await scalar("SELECT public.claim_stripe_sync_internal('acct_raceFixture',false,$1,'cs_test_cancelRace',NULL)",[cancelAttempt.id]);
  const cancelFacts={...facts,sessionId:'cs_test_cancelRace',paymentIntentId:'pi_cancelRace',movements:[{...facts.movements[0],providerId:'pi_cancelRace'}]};
  const cancelled=await race([
   async w=>w.query('SELECT public.cancel_order_domain_internal_v1($1,false)',[cancelOrder]),
   async w=>(await w.query('SELECT public.ingest_stripe_payment_internal($1,$2,$3,$4) r',[cancelAttempt.id,cancelClaim.lease,{...event,id:'evt_cancelRacePaid',bodyHash:'e'.repeat(64)},cancelFacts])).rows[0].r,
  ]);
  assert.match(cancelled[0].error?.message??'',/STRIPE_USE_REFUND_ADMISSION_DECISION/);
  assert.ifError(cancelled[1].error);
  assert.equal(await scalar('SELECT state FROM eshop.orders WHERE id=$1',[cancelOrder]),'paid');
  assert.equal(await scalar('SELECT price::text FROM eshop.orders WHERE id=$1',[cancelOrder]),'123.45');
  assert.equal(Number(await scalar('SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=$1',[cancelAttempt.id])),1);
  const delivered=await race([w=>ingest(w,event,facts),w=>ingest(w,event,{...facts,observedAt:new Date(Date.now()+1).toISOString()})]);
  for(const r of delivered)assert.ifError(r.error);
  assert.deepEqual(delivered[0].value,delivered[1].value,'concurrent retry returns the same receipted mutation despite a newer current provider read');
  assert.equal(Number(await scalar('SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=$1',[a.id])),1);
  assert.equal(Number(await scalar("SELECT count(*) FROM public.email_messages WHERE order_id=$1 AND message_kind='order_tickets'",[order])),1);
  assert.equal(await scalar('SELECT state FROM eshop.orders WHERE id=$1',[order]),'paid');
  const ticket=await scalar('SELECT ticket FROM eshop.order_product_ticket WHERE "order"=$1 LIMIT 1',[order]);
  const refundClaim=await scalar("SELECT public.claim_stripe_sync_internal('acct_raceFixture',false,$1,'cs_test_race',NULL)",[a.id]);
  const refundFacts={...facts,observedAt:new Date().toISOString(),movements:[...facts.movements,{providerId:'re_race',kind:'refund',amountMinor:12345,currency:'CZK',occurredAt}]};
  const raced=await race([
   async w=>(await w.query('SELECT public.ingest_stripe_payment_internal($1,$2,$3,$4) r',[a.id,refundClaim.lease,{...event,id:'evt_raceRefund',bodyHash:'b'.repeat(64),type:'refund.updated'},refundFacts])).rows[0].r,
   async w=>{await w.query('SELECT public.scanner_lock_ticket_internal($1)',[ticket]);await w.query('SELECT public.scanner_admit_ticket_internal($1)',[ticket]);return 'admitted';},
  ]);
  assert.ifError(raced[0].error);
  if(raced[1].error)assert.match(raced[1].error.message,/stripe_admission_hold|ORDER_CANCELLED/);
  assert.equal(await scalar('SELECT state FROM eshop.tickets WHERE id=$1',[ticket]),raced[1].error?'storno':'used','refund preserves only admission that committed before it');
  assert.equal(await scalar('SELECT state FROM eshop.orders WHERE id=$1',[order]),'storno');
  assert.equal(Number(await scalar("SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=$1 AND kind='refund'",[a.id])),1);
  // Replacement and submission share form->unit locks; a stale recipient can
  // either commit before replacement or be rejected, never silently redirected.
  const actor=randomUUID();
  await control.query('INSERT INTO auth.users(id,email) VALUES($1,$2)',[actor,actor+'@stripe.invalid']);
  await control.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[actor,org]);
  await control.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[unit,actor]);
  await control.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[actor]);
  const flow=await scalar('SELECT public.begin_stripe_connection_flow($1,false)',[unit]);
  await control.query("SET request.jwt.claim.role='service_role'");
  const flowClaim=await scalar('SELECT public.claim_stripe_connection_flow_internal($1,$2,false)',[flow.state,actor]);
  await control.query("SET request.jwt.claim.sub=''");
  const freshPayload={...payload,stripePaymentSource:{...payload.stripePaymentSource,tokenHash:hash(randomBytes(32).toString('hex')),returnHash:hash(randomBytes(32).toString('hex'))}};
  const replaced=await race([
   async w=>(await w.query('SELECT public.complete_stripe_connection_flow_internal($1,$2,$3) r',[flowClaim.flowId,flowClaim.lease,{accountId:'acct_raceReplacement',modelVerified:true,ready:true,chargesEnabled:true,cardPaymentsActive:true}])).rows[0].r,
   async w=>(await w.query('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) r',[freshPayload,randomUUID(),randomUUID()])).rows[0].r,
  ]);
  for(const r of replaced)assert.ifError(r.error);
  const submitted=replaced[1].value.data;
  if(Number(submitted.code)===200){
   assert.equal(await scalar('SELECT connection_id FROM eshop.stripe_checkout_attempts WHERE order_id=$1',[submitted.order.id]),conn);
  }else{assert.equal(submitted.errorCode,'STRIPE_RECIPIENT_CHANGED',JSON.stringify(replaced[1].value));}
  assert.equal(await scalar('SELECT connection_id FROM eshop.stripe_checkout_attempts WHERE id=$1',[a.id]),conn);
  assert.equal(await scalar("SELECT data#>>'{payments,stripeConnectionId}' FROM public.forms WHERE id=$1",[form]),replaced[0].value.connectionId);
  const stale=await scalar('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3)',[freshPayload,randomUUID(),randomUUID()]);
  assert.equal(stale.data.errorCode,'STRIPE_RECIPIENT_CHANGED','replacement-first outcome must have a stable public rejection code');

 }finally{
  if(control){await control.query('ROLLBACK').catch(()=>{});await control.end();}
  await Promise.all(writers.map(w=>w.end()));
  await admin.query(`DROP DATABASE IF EXISTS ${name}`);await admin.end();
 }
});
