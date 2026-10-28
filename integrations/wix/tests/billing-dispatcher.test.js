import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {stageBillingReport,dispatchBillingReceipt,rpcBillingJournal,wixBillingProvider} from '../billing/dispatcher.mjs';
import {prepareReporting} from '../reporting/prepare.mjs';

const app='9c099206-ce3d-43de-bd9d-deb96bb4f51e', instance='01234567-1234-4234-8234-123456789abc';
const terms={reference:'synthetic-partner-terms',serviceFeeOnly:true,grossTicketValueExcluded:true,
 externalTicketCheckoutApproved:true,partnerBillingApproved:true,refundTreatmentConfirmed:true,
 attributionPolicyReference:'synthetic-attribution',refundPolicyReference:'synthetic-refunds',refundConversion:'original-charge'};
const event={createdDate:'2026-10-01T12:00:00.000Z',billingType:'CHARGE',grossRevenue:'2.00',netRevenue:'2.00',wixShare:'0.40'};
const wire={created_date:event.createdDate,billing_type:'CHARGE',gross_revenue:'2',net_revenue:'2.00',wix_share:'0.40',app_id:app,instance_id:instance};
const json=data=>new Response(JSON.stringify(data),{headers:{'Content-Type':'application/json'}});
function fakeWix({send=()=>json({event:wire}),scope=instance}={}) {
 const calls=[];
 const provider=wixBillingProvider({appSecret:'synthetic-secret',fetcher:async(url,init)=>{
  const path=new URL(url).pathname,body=JSON.parse(init.body);calls.push({path,body});
  if(path==='/oauth2/token') {assert.equal(body.instance_id,instance);return json({access_token:'synthetic-token',token_type:'Bearer',expires_in:14400});}
  if(path==='/oauth2/token-info')return json({active:true,clientId:app,instanceId:scope,subjectType:'APP',exp:2000000000});
  assert.equal(path,'/apps/v1/billing-event');assert.equal(init.headers.Authorization,'synthetic-token');
  assert.deepEqual(body.event,Object.fromEntries(Object.entries(wire).filter(([key])=>!['app_id','instance_id'].includes(key)).map(([key,v])=>[key,key==='gross_revenue'?'2.00':v])));
  return send();
 }});return {provider,calls};
}

test('provider acquires and verifies an installation-scoped token before any billing send',async()=>{
 const {provider,calls}=fakeWix();const token=await provider.authorize(instance);await provider.send(token,event);
 assert.deepEqual(calls.map(c=>c.path),['/oauth2/token','/oauth2/token-info','/apps/v1/billing-event']);
 const other=fakeWix({scope:randomUUID()});await assert.rejects(other.provider.authorize(instance),/SCOPE_MISMATCH/);
 assert.equal(other.calls.length,2);
});

test('actual dispatcher decodes the documented provider response and treats uncertain effects as unknown',async()=>{
 for (const [send,state] of [[()=>json({event:wire}),'confirmed'],[()=>json({event:{...wire,instance_id:randomUUID()}}),'unknown'],
  [()=>new Response('bad-json'),'unknown'],[()=>new Response('',{status:503}),'unknown'],
  [()=>new Response('',{status:408}),'unknown'],[()=>{throw Error('committed-before-connection-loss');},'unknown'],
  [()=>new Response('',{status:428}),'rejected']]) {
  let result;
  const journal={claim:async()=>({state:'claimed',attemptId:randomUUID(),instanceId:instance,payload:{requestBody:{event}}}),
   finish:async(...args)=>{result=args[4];}};
  assert.equal((await dispatchBillingReceipt({journal,provider:fakeWix({send}).provider,receiptId:'synthetic',kind:'CHARGE'})).state,state);
  assert.equal(result,state);
 }
});

test('canonical PostgreSQL source through projection and real executor recovery', {skip:!process.env.WIX_BILLING_TEST_DATABASE_URL}, async ()=>{
 const url=new URL(process.env.WIX_BILLING_TEST_DATABASE_URL);
 assert.ok(['127.0.0.1','localhost'].includes(url.hostname));
 const db=new pg.Client({connectionString:url.href});await db.connect();
 try {
  const marker=await db.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton');
  assert.equal(marker.rows[0]?.project,'festapp-wix-billing-20261028');
  const rpc=async(name,params)=>{
   assert.match(name,/^[a-z_]+$/);const entries=Object.entries(params);
   const result=await db.query(`SELECT public.${name}(${entries.map(([key],i)=>`${key} => $${i+1}`).join(',')}) AS value`,entries.map(([,v])=>v));return result.rows[0].value;
  };
  const journal=rpcBillingJournal(rpc),receipt=randomUUID(),refundReceipt=randomUUID(),agreement=randomUUID(),settlement=randomUUID();
  await db.query('BEGIN');
  await db.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
  const org=(await db.query("INSERT INTO public.organizations(title,data) VALUES('Synthetic platform fees','{}') RETURNING id")).rows[0].id;
  const unit=(await db.query("INSERT INTO public.units(title,organization) VALUES('Synthetic fee customer',$1) RETURNING id",[org])).rows[0].id;
  const occ=(await db.query("INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time) VALUES('Synthetic fees',$1,$2,$3,now(),now()+interval '1 day') RETURNING id",[unit,org,`fees-${randomUUID()}`])).rows[0].id;
  const form=(await db.query("INSERT INTO public.forms(occasion,link,is_open,data) VALUES($1,$2,true,'{}') RETURNING id",[occ,`fees-${randomUUID()}`])).rows[0].id;
  const order=(await db.query("INSERT INTO eshop.orders(occasion,form,created_at,price,currency_code,order_sequence,order_symbol) VALUES($1,$2,'2026-09-30T12:00:00Z',100000,'CZK',1,'1A1C1E1F1G') RETURNING id",[occ,form])).rows[0].id;
  await db.query("INSERT INTO eshop.order_checkout_origins(order_id,form_id,channel,instance_id,site_id,verified_at) VALUES($1,$2,'wix',$3,$4,now())",[order,form,instance,randomUUID()]);
  await rpc('register_service_fee_agreement',{p_id:agreement,p_unit:unit,p_reference:'synthetic-individual-contract',p_rate_bps:500,p_from:'2026-01-01T00:00:00Z',p_until:'2027-01-01T00:00:00Z'});
  await rpc('register_service_fee_acquisition',{p_unit:unit,p_channel:'wix',p_acquired_at:'2026-01-01T00:00:00Z',p_evidence:'synthetic-acquisition-proof'});
  const source={id:settlement,agreementId:agreement,kind:'charge',sourceReference:`synthetic-payment-${settlement}`,
   invoiceReference:'synthetic-invoice',paymentEvidenceReference:'synthetic-paid-invoice',allocationEvidenceReference:'synthetic-exact-allocation',
   settledAt:event.createdDate,serviceAt:event.createdDate,currency:'CZK',amountBasis:'settled-service-fee-excluding-tax',feeMinor:'5000',taxMinor:'1050',
   allocations:[{id:receipt,orderId:order,feeMinor:'5000',agreedExpensesMinor:'0',wixShareBps:2000,partnerTermsReference:terms.reference,
    fx:{usdMinorNumerator:'1',sourceMinorDenominator:'25',reference:'synthetic-accounted-fx'}}]};
  await rpc('record_service_fee_settlement',{p_input:source});
  assert.equal(await rpc('record_service_fee_settlement',{p_input:source}),settlement);
  const partial={...source,id:randomUUID(),kind:'refund',originalSettlementId:settlement,sourceReference:`synthetic-refund-${refundReceipt}`,
   settledAt:'2026-10-02T12:00:00.000Z',feeMinor:'1000',taxMinor:'210',allocations:[{id:refundReceipt,orderId:order,
    originalAllocationId:receipt,feeMinor:'1000',agreedExpensesMinor:'0'}]};
  await rpc('record_service_fee_settlement',{p_input:partial});
  await rpc('record_service_fee_settlement',{p_input:{...partial,id:randomUUID(),sourceReference:`synthetic-full-refund-${refundReceipt}`,
   settledAt:'2026-10-03T12:00:00.000Z',feeMinor:'4000',taxMinor:'840',allocations:[{...partial.allocations[0],id:randomUUID(),feeMinor:'4000'}]}});
  const input={schemaVersion:2,period:'2026-10',agreement:terms,receipts:(await rpc('export_wix_service_fee_receipts',{p_organization:org,p_partner_terms:terms.reference})).receipts};
  assert.deepEqual(prepareReporting(input).events.map(e=>e.requestBody.event.grossRevenue),['2.00','-0.40','-1.60']);
  assert.equal(input.receipts[0].basis,undefined);assert.equal(input.receipts[0].feeMinor,'5000'); // never the order price
  await db.query('SAVEPOINT old_report');
  const oldReport=structuredClone(prepareReporting(input).events[0]);delete oldReport.basis.refundSequence;
  await assert.rejects(journal.stage(app,oldReport),/WIX_REPORT_V2_REQUIRED/);await db.query('ROLLBACK TO old_report');
  await stageBillingReport(input,journal);
  const attempt=()=>dispatchBillingReceipt({journal,provider:fakeWix().provider,receiptId:receipt,kind:'CHARGE'});
  await db.query('SAVEPOINT inactive');await assert.rejects(attempt(),/NOT_ACTIVATED/);await db.query('ROLLBACK TO inactive');
  await db.query("UPDATE public.wix_billing_activation SET enabled=true,signed_addendum_reference='synthetic-partner-terms',activation_reference='synthetic',settlement_source_reference='synthetic',acquisition_source_reference='synthetic' WHERE app_id=$1",[app]);
  await db.query('SAVEPOINT digest_conflict');await assert.rejects(journal.stage(app,{...prepareReporting(input).events[0],sourceReference:'changed'}),/DIGEST_CONFLICT/);await db.query('ROLLBACK TO digest_conflict');
  const lost=fakeWix({send:()=>{throw Error('provider committed before response loss');}});
  assert.equal((await dispatchBillingReceipt({journal,provider:lost.provider,receiptId:receipt,kind:'CHARGE'})).state,'unknown');
  assert.equal((await attempt()).state,'unknown');
  let row=await rpc('inspect_wix_billing_delivery',{p_app:app,p_receipt:receipt,p_kind:'CHARGE'});
  await db.query('SAVEPOINT stale');await assert.rejects(rpc('reconcile_wix_billing_delivery',{p_app:app,p_receipt:receipt,p_kind:'CHARGE',p_attempt:randomUUID(),p_digest:row.payload_digest,p_resolution:'accepted',p_evidence_reference:'synthetic-provider-case',p_operator_reference:'synthetic-operator'}),/FENCE/);await db.query('ROLLBACK TO stale');
  await rpc('reconcile_wix_billing_delivery',{p_app:app,p_receipt:receipt,p_kind:'CHARGE',p_attempt:row.attempt_id,p_digest:row.payload_digest,p_resolution:'accepted',p_evidence_reference:'synthetic-provider-case-confirmed',p_operator_reference:'synthetic-operator'});
  assert.equal((await attempt()).state,'confirmed');
  // Process death: a fresh worker must recover an expired sending lease as unknown.
  const staged=prepareReporting(input).events[1];const claimed=await journal.claim(app,refundReceipt,'REFUND');assert.equal(claimed.state,'claimed');
  await db.query("UPDATE public.wix_billing_deliveries SET lease_until=now()-interval '1 second' WHERE receipt_id=$1",[refundReceipt]);
  assert.equal((await journal.claim(app,refundReceipt,'REFUND')).state,'unknown');
  row=await rpc('inspect_wix_billing_delivery',{p_app:app,p_receipt:refundReceipt,p_kind:'REFUND'});
  await rpc('reconcile_wix_billing_delivery',{p_app:app,p_receipt:refundReceipt,p_kind:'REFUND',p_attempt:row.attempt_id,p_digest:row.payload_digest,p_resolution:'proven-not-accepted',p_evidence_reference:'synthetic-absence-confirmed-by-wix',p_operator_reference:'synthetic-operator'});
  const refundProvider=wixBillingProvider({appSecret:'synthetic',fetcher:async(url,init)=>{
   if(url.endsWith('/token'))return json({access_token:'synthetic',token_type:'Bearer',expires_in:14400});
   if(url.endsWith('/token-info'))return json({active:true,clientId:app,instanceId:instance,subjectType:'APP',exp:2000000000});
   return json({event:{...JSON.parse(init.body).event,app_id:app,instance_id:instance}});
  }});
  assert.equal((await dispatchBillingReceipt({journal,provider:refundProvider,receiptId:refundReceipt,kind:'REFUND'})).state,'confirmed');
  // Reject source changes and over-refunds in real transactions.
  for(const [patch,pattern] of [[{feeMinor:'6000'},/REPLAY_CONFLICT/],[{amountBasis:'ticket-face-value'},/REPLAY_CONFLICT/]]) {
   await db.query('SAVEPOINT bad_source');await assert.rejects(rpc('record_service_fee_settlement',{p_input:{...source,...patch}}),pattern);await db.query('ROLLBACK TO bad_source');
  }
  await db.query('SAVEPOINT over_refund');await assert.rejects(rpc('record_service_fee_settlement',{p_input:{...partial,id:randomUUID(),sourceReference:randomUUID(),allocations:[{...partial.allocations[0],id:randomUUID()}]}}),/EXCEEDS_SETTLEMENT/);await db.query('ROLLBACK TO over_refund');
  await db.query("UPDATE public.service_fee_customer_acquisitions SET channel='pre-existing-non-wix' WHERE unit_id=$1",[unit]);
  assert.deepEqual((await rpc('export_wix_service_fee_receipts',{p_organization:org,p_partner_terms:terms.reference})).receipts,[]);
  for (const [name,params] of [
   ['register_service_fee_agreement',{p_id:randomUUID(),p_unit:unit,p_reference:'missing-rate',p_rate_bps:null,p_from:'2027-01-01',p_until:'2028-01-01'}],
   ['register_service_fee_agreement',{p_id:randomUUID(),p_unit:unit,p_reference:'overlap',p_rate_bps:200,p_from:'2026-05-01',p_until:'2026-06-01'}],
   ['register_service_fee_acquisition',{p_unit:unit,p_channel:'direct',p_acquired_at:'2026-01-01',p_evidence:'cannot-relabel'}],
  ]) {
   await db.query('SAVEPOINT invalid_fact');await assert.rejects(rpc(name,params));await db.query('ROLLBACK TO invalid_fact');
  }
  const access=await db.query("SELECT has_function_privilege('authenticated','public.record_service_fee_settlement(jsonb)','EXECUTE') AS writer,has_table_privilege('service_role','public.service_fee_settlements','INSERT') AS direct");
  assert.deepEqual(access.rows[0],{writer:false,direct:false});
  await db.query('SAVEPOINT role_guard');await db.query("SELECT set_config('request.jwt.claim.role','authenticated',true)");
  await assert.rejects(rpc('export_wix_service_fee_receipts',{p_organization:org,p_partner_terms:terms.reference}),/service role required/);await db.query('ROLLBACK TO role_guard');
  const version=randomUUID();
  await rpc('register_service_fee_agreement',{p_id:version,p_unit:unit,p_reference:'future-individual-contract',p_rate_bps:250,p_from:'2027-01-01',p_until:null});
  await rpc('end_service_fee_agreement',{p_id:version,p_until:'2028-01-01',p_evidence:'synthetic-signed-amendment'});
  await rpc('register_service_fee_agreement',{p_id:randomUUID(),p_unit:unit,p_reference:'next-individual-contract',p_rate_bps:300,p_from:'2028-01-01',p_until:null});
  await db.query('ROLLBACK');
  // Independent committed row and two connections prove the claim race, rather
  // than simulating a database that hands the executor an already valid receipt.
  await db.query("UPDATE public.wix_billing_activation SET enabled=true,signed_addendum_reference='synthetic-partner-terms',activation_reference='synthetic',settlement_source_reference='synthetic',acquisition_source_reference='synthetic' WHERE app_id=$1",[app]);
  const race=randomUUID(),raceEvent={...staged,receiptId:race,basis:{...staged.basis,refundSequence:'0'},requestBody:{event}};
  await journal.stage(app,raceEvent);
  const second=new pg.Client({connectionString:url.href});await second.connect();
  try {
   const claims=await Promise.all([journal.claim(app,race,'CHARGE'),second.query('SELECT public.claim_wix_billing_delivery($1,$2,$3) AS value',[app,race,'CHARGE']).then(r=>r.rows[0].value)]);
   assert.deepEqual(claims.map(c=>c.state).sort(),['claimed','sending']);
   await db.query("UPDATE public.wix_billing_deliveries SET lease_until=now()-interval '1 second' WHERE receipt_id=$1",[race]);
   const recovery=await second.query('SELECT public.inspect_wix_billing_delivery($1,$2,$3) AS value',[app,race,'CHARGE']);
   assert.equal(recovery.rows[0].value.state,'unknown');
   assert.equal((await journal.claim(app,race,'CHARGE')).state,'unknown');
  } finally {await second.end();}
  await db.query('DELETE FROM public.wix_billing_attempts WHERE receipt_id=$1',[race]);await db.query('DELETE FROM public.wix_billing_deliveries WHERE receipt_id=$1',[race]);
  const committed=randomUUID();let effects=0;
  await journal.stage(app,{...raceEvent,receiptId:committed});
  const committedProvider=fakeWix({send:()=>{effects++;throw Error('committed-provider-effect');}}).provider;
  assert.equal((await dispatchBillingReceipt({journal,provider:committedProvider,receiptId:committed,kind:'CHARGE'})).state,'unknown');
  const restarted=new pg.Client({connectionString:url.href});await restarted.connect();
  try {
   const restartedJournal=rpcBillingJournal(async(name,params)=>{
    const values=Object.values(params);return (await restarted.query(`SELECT public.${name}(${values.map((_,i)=>'$'+(i+1)).join(',')}) AS value`,values)).rows[0].value;
   });
   assert.equal((await dispatchBillingReceipt({journal:restartedJournal,provider:committedProvider,receiptId:committed,kind:'CHARGE'})).state,'unknown');
   assert.equal(effects,1);
  } finally {await restarted.end();}
  await db.query('DELETE FROM public.wix_billing_attempts WHERE receipt_id=$1',[committed]);await db.query('DELETE FROM public.wix_billing_deliveries WHERE receipt_id=$1',[committed]);
  await db.query('UPDATE public.wix_billing_activation SET enabled=false WHERE app_id=$1',[app]);
 } finally {await db.query('ROLLBACK');await db.end();}
});

// These source regressions execute in this same test file so the dedicated
// activation fixture cannot race another test process using the same app.
import {connectSourceFixture} from './billing-source-fixture.mjs';

test('contract termination commits before a waiting import validates its contract', {skip:!process.env.WIX_BILLING_TEST_DATABASE_URL},async()=>{
 const f=await connectSourceFixture(),other=new pg.Client({connectionString:f.url.href}),observer=new pg.Client({connectionString:f.url.href});
 await other.connect();await observer.connect();let pending;
 try {
  await other.query("SET statement_timeout='10s'");
  const pid=(await other.query('SELECT pg_backend_pid() AS id')).rows[0].id;
  await f.db.query('BEGIN');
  await f.rpc('end_service_fee_agreement',{p_id:f.agreement,p_until:'2026-09-15T00:00:00Z',p_evidence:'synthetic-termination'});
  pending=f.rpc('record_service_fee_settlement',{p_input:f.source},other).then(value=>({value}),error=>({error}));
  let blocked=false;
  for(let i=0;i<100;i++){
   const row=(await observer.query("SELECT wait_event_type='Lock' AS blocked FROM pg_stat_activity WHERE pid=$1",[pid])).rows[0];
   if(row?.blocked){blocked=true;break;}await new Promise(resolve=>setTimeout(resolve,20));
  }
  assert.equal(blocked,true,'import must actually wait on the terminating transaction');
  await f.db.query('COMMIT');
  const result=await pending;assert.match(result.error?.message??'',/FEE_AGREEMENT_OUTSIDE_PERIOD/);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM public.service_fee_settlements WHERE agreement_id=$1',[f.agreement])).rows[0].n,0);
 } finally {await f.db.query('ROLLBACK');if(pending)await pending;await other.end();await observer.end();await f.close();}
});

test('reportable metadata is rejected atomically instead of poisoning future months', {skip:!process.env.WIX_BILLING_TEST_DATABASE_URL},async()=>{
 const f=await connectSourceFixture();
 try {
  const malformed=[a=>{delete a.fx;},a=>{delete a.wixShareBps;},a=>{a.wixShareBps=null;},a=>{a.wixShareBps=10001;},
   a=>{a.fx.usdMinorNumerator='0';},a=>{a.fx.sourceMinorDenominator=2;},a=>{a.fx.reference=17;},a=>{a.fx.reference='\u00a0';},a=>{a.fx.reference='😀'.repeat(501);}];
  for(const change of malformed){const source=structuredClone(f.source);change(source.allocations[0]);
   await assert.rejects(f.rpc('record_service_fee_settlement',{p_input:source}),/INVALID_WIX_FEE_REPORTING_METADATA/);
  }
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM public.service_fee_settlements WHERE agreement_id=$1',[f.agreement])).rows[0].n,0);
  const quarantine=structuredClone(f.source);quarantine.id=randomUUID();quarantine.sourceReference=randomUUID();quarantine.allocations[0].id=randomUUID();
  delete quarantine.allocations[0].partnerTermsReference;delete quarantine.allocations[0].fx;delete quarantine.allocations[0].wixShareBps;
  await f.rpc('record_service_fee_settlement',{p_input:quarantine});
  const valid=structuredClone(f.source);valid.sourceReference='r'.repeat(1000);valid.allocations[0].fx.reference='😀'.repeat(500);
  await f.rpc('record_service_fee_settlement',{p_input:valid});
  const november=structuredClone(f.source);november.id=randomUUID();november.sourceReference=randomUUID();november.allocations[0].id=randomUUID();november.settledAt='2026-11-01T12:00:00.000Z';
  await f.rpc('record_service_fee_settlement',{p_input:november});
  const input=await f.input('2026-11'),report=prepareReporting(input);
  assert.equal(input.receipts.length,2,'unmarked incomplete allocation stays outside the export');
  assert.equal(report.events.length,1);assert.equal(report.events[0].receiptId,november.allocations[0].id);
  assert.equal(input.receipts.find(r=>r.id===valid.allocations[0].id).sourceReference.length,1000);
 } finally {await f.close();}
});

test('confirmed source payloads survive backdated refunds and final exact reversal', {skip:!process.env.WIX_BILLING_TEST_DATABASE_URL},async()=>{
 const f=await connectSourceFixture(),journal=rpcBillingJournal(f.rpc);
 const provider=wixBillingProvider({appSecret:'synthetic',fetcher:async(url,init)=>{
  if(url.endsWith('/token'))return json({access_token:'synthetic',token_type:'Bearer',expires_in:14400});
  if(url.endsWith('/token-info'))return json({active:true,clientId:app,instanceId:f.instance,subjectType:'APP',exp:2000000000});
  return json({event:{...JSON.parse(init.body).event,app_id:app,instance_id:f.instance}});
 }});
 const send=async(id,kind)=>assert.equal((await dispatchBillingReceipt({journal,provider,receiptId:id,kind})).state,'confirmed');
 try {
  await f.db.query("UPDATE public.wix_billing_activation SET enabled=true,signed_addendum_reference='synthetic-partner-terms',activation_reference='synthetic',settlement_source_reference='synthetic',acquisition_source_reference='synthetic' WHERE app_id=$1",[app]);
  await f.rpc('record_service_fee_settlement',{p_input:f.source});
  const existing=f.refund('2026-10-03T12:00:00.000Z');await f.rpc('record_service_fee_settlement',{p_input:existing});
  await stageBillingReport(await f.input('2026-10'),journal);await send(f.source.allocations[0].id,'CHARGE');await send(existing.allocations[0].id,'REFUND');
  const before=await f.rpc('inspect_wix_billing_delivery',{p_app:app,p_receipt:existing.allocations[0].id,p_kind:'REFUND'});
  const late=f.refund('2026-10-02T12:00:00.000Z');await f.rpc('record_service_fee_settlement',{p_input:late});
  await stageBillingReport(await f.input('2026-10'),journal);await send(late.allocations[0].id,'REFUND');
  const after=await f.rpc('inspect_wix_billing_delivery',{p_app:app,p_receipt:existing.allocations[0].id,p_kind:'REFUND'});
  assert.deepEqual(after.payload,before.payload);assert.equal(after.payload_digest,before.payload_digest);assert.equal(after.attempts.length,1);
  const last=f.refund('2026-11-01T12:00:00.000Z');await f.rpc('record_service_fee_settlement',{p_input:last});
  const input=await f.input('2026-11');assert.deepEqual(input.receipts.filter(r=>r.kind==='refund').map(r=>r.refundSequence).sort(),['1','2','3']);
  await stageBillingReport(input,journal);await send(last.allocations[0].id,'REFUND');
  const rows=(await f.db.query("SELECT payload#>'{requestBody,event}' AS event FROM public.wix_billing_deliveries WHERE payload#>>'{basis,organizerAgreementReference}'=$1 AND state='confirmed'",[f.reference])).rows;
  assert.equal(rows.length,4);
  for(const field of ['grossRevenue','netRevenue','wixShare'])assert.equal(rows.reduce((sum,r)=>sum+Math.round(Number(r.event[field])*100),0),0,field);
 } finally {await f.close();}
});
