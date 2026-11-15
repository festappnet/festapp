import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {createTestWorkspace} from './runtime_workspace.js';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from './disposable_database.js';
const read=p=>readFileSync(new URL('../../../'+p,import.meta.url),'utf8');
async function workspace(run){
 const lease=await createTestWorkspace();assertLocalDatabaseUrl(lease.databaseUrl);
 const clients=[];let pending=[];
 const connect=async()=>{const c=new pg.Client({connectionString:lease.databaseUrl});await c.connect();clients.push(c);await assertDisposableDatabase(c);await c.query("SET statement_timeout='20s'; SET lock_timeout='15s'; SET festapp.email_wake='scheduled'");return c;};
 try{
  const control=await connect();await control.query(read('database/tests/helpers/assertions.sql'));await control.query(read('database/tests/helpers/payment_lifecycle_fixture.sql'));await control.query(read('database/tests/customer_order_changes/fixture.sql'));
  const scalar=async(sql,args=[])=>Object.values((await control.query(sql,args)).rows[0])[0];
  const x=await scalar('SELECT pg_temp.customer_fixture()');
  await control.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[x.actor]);
  const writers=[await connect(),await connect()];
  const service=async c=>c.query("SET request.jwt.claim.role='service_role'; SET request.jwt.claim.sub=''; SET ROLE service_role");
  await Promise.all(writers.map(service));
  const gateway=async(c,action,token,op,payload,command,fingerprint=null)=>
   (await c.query('SELECT public.customer_order_change_gateway($1,$2,NULL,$3,$4,$5,$6) r',[action,token,op,payload,command,fingerprint])).rows[0].r;
  const cap=(op,payload)=>scalar('SELECT pg_temp.customer_cap($1,$2,$3)',[x,op,payload]);
  async function race(jobs){
   await control.query('BEGIN');await control.query('SELECT public.lock_blueprint_scope_internal(ARRAY[$1::bigint])',[x.occasion]);
   await control.query('SELECT 1 FROM public.forms WHERE id=$1 FOR UPDATE',[x.form]);
   const pids=writers.map(c=>c.processID);pending=jobs.map((job,i)=>job(writers[i]).then(value=>({value}),error=>({error})));
   let blocked=0;
   try{
    for(let i=0;i<200;i++){
     blocked=Number(await scalar("SELECT count(*) FROM pg_stat_activity WHERE pid=ANY($1) AND wait_event_type='Lock'",[pids]));
     if(blocked===jobs.length)break;await new Promise(resolve=>setTimeout(resolve,10));
    }
    if(blocked!==jobs.length){await control.query('COMMIT');const diagnostics=await Promise.all(pending);assert.fail('Both writers must reach barrier: '+JSON.stringify(diagnostics.map(r=>r.error?{code:r.error.code,message:r.error.message}:{value:r.value})));}
    await control.query('COMMIT');return await Promise.all(pending);
   }finally{await control.query('ROLLBACK');await Promise.all(pending);pending=[];}
  }
  await run({control,scalar,x,writers,gateway,cap,race});
 }finally{await Promise.allSettled(pending);await Promise.all(clients.map(c=>c.end()));await lease.release();}
}
test('one write capability has one winner across distinct simultaneous commands',async()=>workspace(async({scalar,x,writers,gateway,cap,race})=>{
 const payload={order:{[x.field]:'777 111 222'}},token=await cap('edit',payload),a=randomUUID(),b=randomUUID();
 const preview=await gateway(writers[0],'preview',token,'edit',payload,a);
 const outcomes=await race([c=>gateway(c,'command',token,'edit',payload,a,preview.fingerprint),c=>gateway(c,'command',token,'edit',payload,b,preview.fingerprint)]);
 assert.equal(outcomes.filter(r=>r.value?.code===200).length,1);assert.equal(outcomes.filter(r=>r.error?.code==='42501').length,1);
 assert.equal(Number(await scalar('SELECT count(*) FROM eshop.customer_order_change_events WHERE order_id=$1',[x.order])),1);
}));
test('simultaneous exact retries return one committed result and one refund-free audit',async()=>workspace(async({scalar,x,writers,gateway,cap,race})=>{
 const payload={order:{[x.field]:'777 222 333'}},token=await cap('edit',payload),command=randomUUID();const preview=await gateway(writers[0],'preview',token,'edit',payload,command);
 const outcomes=await race([c=>gateway(c,'command',token,'edit',payload,command,preview.fingerprint),c=>gateway(c,'command',token,'edit',payload,command,preview.fingerprint)]);
 assert.equal(outcomes.filter(r=>r.value?.code===200).length,2);assert.equal(Number(await scalar('SELECT count(*) FROM eshop.customer_order_change_events WHERE command_id=$1',[command])),1);
 assert.equal(Number(await scalar('SELECT count(*) FROM eshop.refund_requests WHERE order_id=$1',[x.order])),0);
}));
test('withdrawal and organizer approval serialize without a canceled-yet-withdrawn order',async()=>workspace(async({scalar,x,writers,gateway,cap,race})=>{
 let policy=(await scalar('SELECT public.customer_order_policy_internal($1)',[x.form])).policy;policy.cancel.mode='approval_required';
 await scalar('SELECT public.save_customer_order_policy_internal($1,$2)',[x.form,policy]);
 const token=await cap('cancel',{}),command=randomUUID();let preview=await gateway(writers[0],'preview',token,'cancel',{},command);await gateway(writers[0],'command',token,'cancel',{},command,preview.fingerprint);
 const request=(await scalar("SELECT to_jsonb(r) FROM eshop.customer_order_change_requests r WHERE order_id=$1 AND status='open'",[x.order]));
 const payload={requestId:request.id},withdraw=await cap('withdraw',payload),withdrawCommand=randomUUID();preview=await gateway(writers[0],'preview',withdraw,'withdraw',payload,withdrawCommand);
 await writers[1].query('RESET ROLE');await writers[1].query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[x.actor]);await writers[1].query('SET ROLE authenticated');
 const outcomes=await race([c=>gateway(c,'command',withdraw,'withdraw',payload,withdrawCommand,preview.fingerprint),async c=>(await c.query("SELECT public.command_customer_order_request($1,'approve',$2,$3,NULL) r",[request.id,randomUUID(),request.updated_at])).rows[0].r]);
 assert.equal(outcomes.filter(r=>r.value?.code===200).length,1);assert.equal(outcomes.filter(r=>r.error?.code==='40001').length,1);
 const status=await scalar('SELECT status FROM eshop.customer_order_change_requests WHERE id=$1',[request.id]);const state=await scalar('SELECT state FROM eshop.orders WHERE id=$1',[x.order]);
 assert.ok(status==='withdrawn'&&state==='ordered'||status==='approved'&&state==='storno');
}));
test('a saved stricter policy and a customer confirmation share the same fence',async()=>workspace(async({scalar,x,writers,gateway,cap,race})=>{
 const payload={order:{[x.field]:'777 333 444'}},token=await cap('edit',payload),command=randomUUID();const preview=await gateway(writers[0],'preview',token,'edit',payload,command);
 const policy=(await scalar('SELECT public.customer_order_policy_internal($1)',[x.form])).policy;policy.edit.enabled=false;
 await writers[1].query('RESET ROLE');await writers[1].query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[x.actor]);await writers[1].query('SET ROLE authenticated');
 const form={id:Number(x.form),occasion:Number(x.occasion),expected_aggregate_version:0,customer_self_service:policy};
 const outcomes=await race([c=>gateway(c,'command',token,'edit',payload,command,preview.fingerprint),async c=>(await c.query('SELECT public.update_form_client_sync_v1($1,$2) r',[form,randomUUID()])).rows[0].r]);
 assert.equal(outcomes[1].value?.code,200);assert.ok(outcomes[0].value?.code===200||outcomes[0].error?.code==='42501');
 const phone=await scalar("SELECT data->>'phone' FROM eshop.orders WHERE id=$1",[x.order]);assert.equal(phone,outcomes[0].value?'777 333 444':null);
 assert.equal((await scalar('SELECT public.customer_order_policy_internal($1)',[x.form])).policy.edit.enabled,false);
}));

test('two term moves competing for the last place keep one allocation and one unchanged order', async()=>workspace(async({control,scalar,x,writers,gateway,cap,race})=>{
 await control.query("UPDATE public.forms SET term_start_at=now()+interval '3 days',term_end_at=now()+interval '3 days 2 hours' WHERE id=$1",[x.form]);
 const target=await scalar("INSERT INTO public.forms(occasion,title,bank_account,is_open,participant_capacity,term_start_at,term_end_at) VALUES($1,'Target term',$2,true,1,now()+interval '4 days',now()+interval '4 days 2 hours') RETURNING id",[x.occasion,x.bank]);
 const type=await scalar("INSERT INTO eshop.product_types(occasion,title,type) VALUES($1,'Target admission','spot') RETURNING id",[x.occasion]);
 const product=await scalar("INSERT INTO eshop.products(occasion,title,product_type,price,currency_code,is_hidden,maximum) VALUES($1,'Target ticket',$2,1000,'CZK',false,1) RETURNING id",[x.occasion,type]);
 await control.query("INSERT INTO public.form_fields(form,title,type,product_type,is_ticket_field,is_hidden,is_required) VALUES($1,'Admission','product_type',$2,true,false,true)",[target,type]);
 const until=new Date(Date.now()+86400000).toISOString();
 await scalar('SELECT public.save_customer_order_policy_internal($1,$2)',[target,{move:{enabled:true,allowed_until:until,targets:[]}}]);
 const policy=(await scalar('SELECT public.customer_order_policy_internal($1)',[x.form])).policy;
 policy.move={enabled:true,allowed_until:until,targets:[{formId:Number(target),products:{[x.product]:Number(product)},fields:{}}]};
 await scalar('SELECT public.save_customer_order_policy_internal($1,$2)',[x.form,policy]);
 // Use the actual checkout owner for the second customer, on the same source form.
 const formKey=await scalar('SELECT key FROM public.forms WHERE id=$1',[x.form]);
 const checkout=await scalar('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3)',[{form:formKey,email:'second@example.test',fields:[{[x.field]:'+420777333444'}],ticket:[{fields:[{product_type:Number(x.product)}]}]},randomUUID(),randomUUID()]);
 assert.equal(checkout.status,'applied',JSON.stringify(checkout));
 const second={...x,order:checkout.data.order.id,readToken:'c'.repeat(64)};
 await scalar('SELECT public.issue_order_overview_internal($1,$2,$3)',[second.order,{tokenHash:await scalar("SELECT encode(extensions.digest($1,'sha256'),'hex')",[second.readToken]),contentHash:'a'.repeat(64),sealed:{}},randomUUID()]);
 const payload={targetFormId:Number(target)},first=await cap('move',payload),other=await scalar('SELECT pg_temp.customer_cap($1,$2,$3)',[second,'move',payload]);
 const ids=[randomUUID(),randomUUID()];
 const previews=await Promise.all([gateway(writers[0],'preview',first,'move',payload,ids[0]),gateway(writers[1],'preview',other,'move',payload,ids[1])]);
 assert.ok(previews.every(p=>p.effect==='move'),JSON.stringify(previews));
 const outcomes=await race([c=>gateway(c,'command',first,'move',payload,ids[0],previews[0].fingerprint),c=>gateway(c,'command',other,'move',payload,ids[1],previews[1].fingerprint)]);
 assert.equal(outcomes.filter(r=>r.value?.code===200).length,1);
 assert.equal(outcomes.filter(r=>r.error?.code==='40001').length,1,JSON.stringify(outcomes));
 assert.equal(Number(await scalar('SELECT count(*) FROM eshop.orders WHERE id=ANY($1) AND form=$2',[[x.order,second.order],target])),1);
 assert.equal(Number(await scalar('SELECT count(*) FROM eshop.orders WHERE id=ANY($1) AND form=$2',[[x.order,second.order],x.form])),1);
 assert.equal(Number(await scalar('SELECT count(*) FROM eshop.refund_requests WHERE order_id=ANY($1)',[[x.order,second.order]])),0);
}));

test('scanner admission and confirmed cancellation cannot both succeed',async()=>workspace(async({control,scalar,x,writers,gateway,cap,race})=>{
 await scalar('SELECT pg_temp.payment_pair($1,1000)',[x]);
 const policy=(await scalar('SELECT public.customer_order_policy_internal($1)',[x.form])).policy;policy.cancel.refund_mode='manual';
 await scalar('SELECT public.save_customer_order_policy_internal($1,$2)',[x.form,policy]);
 const secret='TEST_'+randomUUID(),hidden=await scalar('INSERT INTO public.occasions_hidden(secret) VALUES($1) RETURNING id',[secret]);
 await control.query('UPDATE public.occasions SET occasion_hidden=$1 WHERE id=$2',[hidden,x.occasion]);
 await control.query('INSERT INTO public.scanner_settings(occasion_id,config) VALUES($1,public.scanner_default_settings_internal($1))',[x.occasion]);
 const session=await scalar("SELECT public.open_scanner_session($1,NULL,'Race check')",[secret]);assert.equal(session.code,200);
 const symbol=await scalar('SELECT ticket_symbol FROM eshop.tickets WHERE id=$1',[x.ticket]);
 const lookup=await scalar('SELECT public.lookup_scanner_ticket($1,$2,$3)',[session.data.session_id,session.data.token,symbol]);assert.equal(lookup.code,200);
 const op={operation_id:randomUUID(),origin_session_id:session.data.session_id,ticket_id:Number(x.ticket),action:'admit_ticket',snapshot_id:null,settings_revision:lookup.settings_revision,eligibility_fingerprint:lookup.data.eligibility_fingerprint,confirm_unpaid:false,captured_at:new Date().toISOString()};
 const token=await cap('cancel',{}),command=randomUUID(),preview=await gateway(writers[0],'preview',token,'cancel',{},command);assert.equal(preview.effect,'cancel_manual_refund');
 await writers[1].query('RESET ROLE');await writers[1].query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[x.actor]);await writers[1].query('SET ROLE authenticated');
 const outcomes=await race([c=>gateway(c,'command',token,'cancel',{},command,preview.fingerprint),async c=>(await c.query('SELECT public.sync_scanner_operations($1,$2,$3) r',[session.data.session_id,session.data.token,JSON.stringify([op])])).rows[0].r]);
 const admitted=outcomes[1].value?.data?.[0]?.outcome==='accepted',cancelled=outcomes[0].value?.code===200;
 assert.notEqual(admitted,cancelled,JSON.stringify(outcomes));
 assert.equal(await scalar('SELECT state FROM eshop.tickets WHERE id=$1',[x.ticket]),cancelled?'storno':'used');
 assert.equal(Number(await scalar('SELECT count(*) FROM eshop.refund_requests WHERE order_id=$1',[x.order])),0);
}));
