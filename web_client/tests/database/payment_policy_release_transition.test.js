import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from './disposable_database.js';
const require=createRequire(new URL('../../package.json',import.meta.url));
const {Client}=require('pg');
const root=new URL('../../../',import.meta.url);
const transition=await readFile(new URL('automation/payment-policy-release/transition_legacy_email_metadata.sql',root),'utf8');
const assertions=await readFile(new URL('database/tests/helpers/assertions.sql',root),'utf8');
const fixture=await readFile(new URL('database/tests/helpers/payment_lifecycle_fixture.sql',root),'utf8');
async function scenario(run){
 assertLocalDatabaseUrl(process.env.DATABASE_URL);
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 try {await assertDisposableDatabase(db);await db.query('BEGIN');await db.query(assertions);await db.query(fixture);await run(db);}
 finally {await db.query('ROLLBACK').catch(()=>{});await db.end();}
}
async function denied(db,sql,params=[]){
 await db.query('SAVEPOINT denied');
 await assert.rejects(db.query(sql,params),e=>e.code==='42501');
 await db.query('ROLLBACK TO SAVEPOINT denied');
}
test('legacy bank readers delegate a unique stored scope and reject ambiguous or disabled contexts',async()=>scenario(async db=>{
 const x=(await db.query('SELECT pg_temp.payment_fixture() x')).rows[0].x;
 const un=(await db.query('SELECT unit FROM public.occasions WHERE id=$1',[x.occasion])).rows[0].unit;
 await db.query('INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES($1,$2,true)',[x.bank,x.actor]);
 await db.query("SET LOCAL ROLE authenticated");
 assert.equal(Number((await db.query('SELECT count(*) n FROM public.get_my_admin_bank_accounts()')).rows[0].n),1);
 const old=(await db.query('SELECT public.get_bank_transaction_history($1) x',[x.bank])).rows[0].x;
 assert.deepEqual(old,(await db.query('SELECT public.get_bank_transaction_history($1,$2) x',[x.bank,un])).rows[0].x);
 await db.query('RESET ROLE');
 const other=(await db.query("INSERT INTO public.units(organization,title) VALUES($1,'Druhý pořadatel') RETURNING id",[x.organization])).rows[0].id;
 await db.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[other,x.actor]);
 await db.query('SET LOCAL ROLE authenticated');
 await denied(db,'SELECT * FROM public.get_my_admin_bank_accounts()');
 assert.equal(Number((await db.query('SELECT count(*) n FROM public.get_linkable_bank_accounts($1)',[un])).rows[0].n),1,'current clients retain explicit multi-unit access');
 await db.query('RESET ROLE');
 await db.query('INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES($1,$2)',[other,x.bank]);
 await db.query('SET LOCAL ROLE authenticated');
 await denied(db,'SELECT public.get_bank_transaction_history($1)',[x.bank]);
 await db.query('RESET ROLE');
 await db.query('UPDATE public.unit_users SET is_manager=false WHERE unit=$1 AND "user"=$2',[other,x.actor]);
 const change={organizationId:Number(x.organization),unitId:Number(un),method:'bank',mode:'disabled'};
 await db.query('SET LOCAL ROLE authenticated');
 const preview=(await db.query('SELECT public.preview_payment_method_policy($1) p',[change])).rows[0].p;
 await db.query('SELECT public.command_payment_method_policy($1,extensions.gen_random_uuid(),$2)',[change,preview.confirmation]);
 await denied(db,'SELECT * FROM public.get_my_admin_bank_accounts()');
 await denied(db,'SELECT public.get_bank_transaction_history($1)',[x.bank]);
}));
test('one-time legacy transition preserves business identity and never touches prepared, attempted, unknown or foreign messages',async()=>scenario(async db=>{
 const x=(await db.query('SELECT pg_temp.payment_fixture() x')).rows[0].x;
 const un=(await db.query('SELECT unit FROM public.occasions WHERE id=$1',[x.occasion])).rows[0].unit;
 await db.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
 const ids=[];
 for(let i=0;i<4;i++){
  const q=(await db.query(`SELECT public.enqueue_email('order_confirmation',jsonb_build_object('organization',$1::bigint,'unit',$2::bigint,'occasion',$3::bigint),
   (SELECT data->>'email' FROM eshop.orders WHERE id=$4),'{}',extensions.gen_random_uuid()::text,'TICKET_ORDER_CONFIRMATION',now()+interval '1 hour',NULL,$4,
   (SELECT email_payment_version FROM eshop.orders WHERE id=$4)) q`,[x.organization,un,x.occasion,x.order])).rows[0].q;
  ids.push(q.message_id);
 }
 const foreign=(await db.query('SELECT pg_temp.payment_fixture() x')).rows[0].x;
 await db.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
 const foreignUnit=(await db.query('SELECT unit FROM public.occasions WHERE id=$1',[foreign.occasion])).rows[0].unit;
 const foreignMessage=(await db.query(`SELECT public.enqueue_email('order_confirmation',jsonb_build_object('organization',$1::bigint,'unit',$2::bigint,'occasion',$3::bigint),
  (SELECT data->>'email' FROM eshop.orders WHERE id=$4),'{}',extensions.gen_random_uuid()::text,'TICKET_ORDER_CONFIRMATION',now()+interval '1 hour',NULL,$4,
  (SELECT email_payment_version FROM eshop.orders WHERE id=$4)) q`,[foreign.organization,foreignUnit,foreign.occasion,foreign.order])).rows[0].q;
 ids.push(foreignMessage.message_id);
 await db.query("UPDATE public.email_messages SET data=data-'collectionAction'-'paymentTemplateEpoch' WHERE message_id=ANY($1::uuid[])",[ids]);
 await db.query("UPDATE public.email_messages SET prepared='{\"sealed\":\"old-immutable\"}',prepared_at=now() WHERE message_id=$1",[ids[1]]);
 await db.query("UPDATE public.email_messages SET workflow_state='unknown' WHERE message_id=$1",[ids[2]]);
 await db.query("INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES($1,extensions.gen_random_uuid(),'cancelled')",[ids[3]]);
 const before=(await db.query('SELECT to_jsonb(m) x FROM public.email_messages m WHERE message_id=ANY($1::uuid[]) ORDER BY message_id',[ids])).rows.map(r=>r.x);
 const hash=before.find(r=>r.message_id===ids[0]).input_hash;
 await db.query("SELECT set_config('festapp.payment_policy_release.organization',$1,true),set_config('festapp.payment_policy_release.apply','false',true)",[String(x.organization)]);
 await db.query(transition);
 assert.equal((await db.query("SELECT current_setting('festapp.payment_policy_release.eligible') n")).rows[0].n,'1');
 assert.deepEqual((await db.query('SELECT to_jsonb(m) x FROM public.email_messages m WHERE message_id=ANY($1::uuid[]) ORDER BY message_id',[ids])).rows.map(r=>r.x),before,'dry-run changes no envelope');
 await db.query('UPDATE public.email_capacity SET paused=true');
 await db.query("SELECT set_config('festapp.payment_policy_release.apply','true',true)");
 await db.query(transition);
 const after=(await db.query('SELECT to_jsonb(m) x FROM public.email_messages m WHERE message_id=ANY($1::uuid[]) ORDER BY message_id',[ids])).rows.map(r=>r.x);
 for(let i=1;i<ids.length;i++)assert.deepEqual(after.find(r=>r.message_id===ids[i]),before.find(r=>r.message_id===ids[i]));
 const changed=after.find(r=>r.message_id===ids[0]);
 assert.equal(changed.input_hash,hash);assert.equal(changed.workflow_state,'pending');assert.equal(changed.prepared,null);
 const strip=data=>{const copy={...data};delete copy.collectionAction;delete copy.paymentTemplateEpoch;delete copy.paymentPolicyRelease;return copy;};
 assert.deepEqual(strip(changed.data),strip(before.find(r=>r.message_id===ids[0]).data));
 assert.equal(changed.data.collectionAction.allowed,true);
 await db.query(transition);
 assert.equal((await db.query("SELECT current_setting('festapp.payment_policy_release.changed') n")).rows[0].n,'0','transition is idempotent, never a resend');
}));
