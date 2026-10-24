import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import pg from 'pg';
import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
const source = process.env.DATABASE_URL;
const fixtureFile = new URL('../../../database/tests/eshop/payment_reference_reservations_test.sql', import.meta.url);
async function connect(url) {const c=new pg.Client({connectionString:url});await c.connect();await c.query("SET statement_timeout='20s'; SET lock_timeout='15s'; SET request.jwt.claim.role='service_role'; SET festapp.email_wake='scheduled'");return c;}
test('real PostgreSQL connections serialize physical aliases and same-source replay', {skip:!source},async()=>{
 const base=new URL(source);
 assert.ok(['127.0.0.1','localhost'].includes(base.hostname)&&base.port==='55432'&&base.pathname==='/festapp_local_references_v2',
  'Requires the explicitly isolated reference fixture database, never a live/default database');
 const target='reference_concurrency_'+randomUUID().replaceAll('-','');
 const adminUrl=new URL(base);adminUrl.pathname='/postgres';const admin=await connect(adminUrl.toString());
 const targetUrl=new URL(base);targetUrl.pathname='/'+target;
 let control;const writers=[];
 try {
  await admin.query(`CREATE DATABASE ${target} TEMPLATE festapp_local_references_v2`);
  control=await connect(targetUrl.toString());
  const fixture=await fs.readFile(fixtureFile,'utf8');await control.query(fixture.slice(0,fixture.indexOf('DO $$\nDECLARE x')));
  const x=(await control.query('SELECT pg_temp.reference_fixture() AS x')).rows[0].x;
  for(let n=0;n<12;n++)writers.push(await connect(targetUrl.toString()));
  const payments=[];
  for(let n=0;n<12;n++)payments.push((await control.query('SELECT pg_temp.reference_payment($1,$2) AS p',[n%2?x.form:x.aliasForm,n%2?x.account:x.alias])).rows[0].p);
  await control.query('BEGIN');await control.query('SELECT 1 FROM eshop.payment_reference_namespaces WHERE id=$1 FOR UPDATE',[x.namespace]);
  const pending=writers.map(async(writer,n)=>{
   await writer.query('BEGIN');
   try {
    const row=(await writer.query('SELECT public.reserve_payment_reference_internal($1,$2,$3,$4,$5) AS symbol',
     [payments[n],n%2?x.form:x.aliasForm,'race:'+n,{mode:'sequence',from:'1205'},'b'.repeat(64)])).rows[0];
    await writer.query('COMMIT');return row.symbol;
   }catch(error){await writer.query('ROLLBACK');throw error;}
  });
  // Establish simultaneous blocked statements, rather than assuming Promise.all
  // itself proves overlap. The namespace lock is then the single release point.
  let blocked=0;
  for(let attempt=0;attempt<100&&blocked<2;attempt++){
   blocked=Number((await control.query("SELECT count(*) n FROM pg_stat_activity WHERE datname=$1 AND wait_event_type='Lock'",[target])).rows[0].n);
   if(blocked<2)await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert.ok(blocked>=2,'at least two live connections contend before release');await control.query('COMMIT');
  const symbols=await Promise.all(pending);assert.equal(new Set(symbols).size,12);
  assert.deepEqual(symbols.map(Number).sort((a,b)=>a-b),Array.from({length:12},(_,n)=>1205+n));
  const payment=(await control.query('SELECT pg_temp.reference_payment($1,$2) p',[x.form,x.account])).rows[0].p;
  const same=await Promise.all(writers.slice(0,2).map(writer=>writer.query('SELECT public.reserve_payment_reference_internal($1,$2,$3,$4,$5) symbol',
   [payment,x.form,'same-source',{mode:'random',preferred_digits:4,max_digits:10},'c'.repeat(64)])));
  assert.equal(same[0].rows[0].symbol,same[1].rows[0].symbol);
  assert.equal(Number((await control.query("SELECT count(*) n FROM eshop.payment_reference_reservations WHERE namespace_id=$1 AND source_ref='same-source'",[x.namespace])).rows[0].n),1);
  await writers[0].query('BEGIN');
  await writers[0].query('SELECT public.reserve_payment_reference_internal($1,$2,$3,$4,$5)',[payment,x.form,'rollback',{mode:'exact',value:'77'},'d'.repeat(64)]);
  await writers[0].query('ROLLBACK');
  assert.equal(Number((await control.query("SELECT count(*) n FROM eshop.payment_reference_reservations WHERE source_ref='rollback'")).rows[0].n),0);
  const waitlistSql=await fs.readFile(new URL('../../../database/tests/eshop_orders/waitlist_lifecycle_test.sql',import.meta.url),'utf8');
  await control.query(waitlistSql.slice(0,waitlistSql.indexOf('DO $$\nDECLARE x')));
  for(const count of [1,2]){
   const w=(await control.query('SELECT pg_temp.fixture(1) x')).rows[0].x;
   const bank=(await control.query('SELECT bank_account FROM eshop.unit_bank_accounts WHERE unit=$1',[w.unit])).rows[0].bank_account;
   await control.query("UPDATE eshop.bank_accounts SET account_number='19-2000145399/0800' WHERE id=$1",[bank]);
   await control.query('SELECT public.enroll_payment_reference_account($1)',[bank]);
   await control.query("INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES($1,'active',$2)",[w.organization,'a'.repeat(64)]);
   const regular=(await control.query('SELECT public.create_ticket_order_client_sync_v1(pg_temp.checkout($1),$2,$3) r',[w,randomUUID(),randomUUID()])).rows[0].r;
   assert.equal(regular.data.code,200);
   const registered=(await control.query('SELECT pg_temp.register($1,$2) r',[w,count])).rows[0].r;
   const ticketIds=(await control.query('SELECT pg_temp.ticket_ids($1) ids',[registered.order])).rows[0].ids;
   await control.query('SELECT public.update_order_and_tickets_to_storno_221($1)',[regular.data.order.id]);
   const offer=(await control.query('SELECT pg_temp.offer($1,$2,1) w',[w,registered.order])).rows[0].w;
   const accepted=(await control.query('SELECT pg_temp.accept($1,$2,$3) r',[w,offer,[ticketIds[0]]])).rows[0].r;
   assert.equal(accepted.data.code,200);
   assert.equal(accepted.data.conversion,count===1?'in_place':'split');
   const paymentId=accepted.data.order.payment_info.id;
   assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.payment_reference_reservations WHERE payment_info_id=$1',[paymentId])).rows[0].n),1);
   assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.order_product_ticket WHERE "order"=$1 AND ticket=$2',[accepted.data.order.id,ticketIds[0]])).rows[0].n),1);
  }
  const replacementFixture=(await control.query('SELECT pg_temp.fixture(NULL) x')).rows[0].x;
  const replacementBank=(await control.query('SELECT bank_account FROM eshop.unit_bank_accounts WHERE unit=$1',[replacementFixture.unit])).rows[0].bank_account;
  await control.query("UPDATE eshop.bank_accounts SET account_number='19-2000145399/0800' WHERE id=$1",[replacementBank]);
  await control.query('SELECT public.enroll_payment_reference_account($1)',[replacementBank]);
  await control.query("INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES($1,'active',$2)",[replacementFixture.organization,'a'.repeat(64)]);
  const spot=(await control.query('INSERT INTO eshop.spots(title,product,occasion) VALUES($1,$2,$3) RETURNING id',['Replacement fixture',replacementFixture.product,replacementFixture.occasion])).rows[0].id;
  const original=(await control.query('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) r',[{form:replacementFixture.key,email:'replace@example.invalid',ticket:[{spot}]},randomUUID(),randomUUID()])).rows[0].r;
  assert.equal(original.data.code,200);
  const rejected=(await control.query('SELECT public.replace_blueprint_order_client_sync_v1($1,$2,$3) r',[[spot],{email:'replace@example.invalid',ticket:[{spot:999999999999}]},randomUUID()])).rows[0].r;
  assert.equal(rejected.status,'rejected');
  assert.equal((await control.query('SELECT state FROM eshop.orders WHERE id=$1',[original.data.order.id])).rows[0].state,'ordered','failed finalization rolls source cancellation back');
  const replaced=(await control.query('SELECT public.replace_blueprint_order_client_sync_v1($1,$2,$3) r',[[spot],{email:'replace@example.invalid'},randomUUID()])).rows[0].r;
  assert.equal(replaced.data.code,200);
  assert.equal((await control.query('SELECT state FROM eshop.orders WHERE id=$1',[original.data.order.id])).rows[0].state,'storno');
  assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.payment_reference_reservations WHERE payment_info_id=ANY($1::bigint[])',[[original.data.order.payment_info.id,replaced.data.order.payment_info.id]])).rows[0].n),2,'old and replacement references remain permanently reserved');
  await control.query('COMMIT');
  const expectedReservations=Number((await control.query('SELECT count(*) n FROM eshop.payment_reference_reservations WHERE namespace_id=$1',[x.namespace])).rows[0].n);
  const outputRoot=await fs.mkdtemp(path.join(os.tmpdir(),'festapp-reference-inventory-'));
  try{
   execFileSync(process.execPath,[new URL('../../../automation/payment-references/inventory.mjs',import.meta.url).pathname,
    '--organization-id',String(x.org),'--output-dir',path.join(outputRoot,'review')],{env:{...process.env,DATABASE_URL:targetUrl.toString()},encoding:'utf8'});
   const manifestText=await fs.readFile(path.join(outputRoot,'review','manifest.json'),'utf8');
   assert.match(JSON.parse(manifestText).manifest_sha256,/^[a-f0-9]{64}$/);
   assert.ok(!manifestText.includes('@example.invalid'),'inventory contains no customer contact payload');
   assert.equal(Number((await control.query('SELECT count(*) n FROM eshop.payment_reference_reservations WHERE namespace_id=$1',[x.namespace])).rows[0].n),expectedReservations,'inventory is read-only');
  }finally{await fs.rm(outputRoot,{recursive:true,force:true});}
  // Dump only registry data into a clone with identical live parent rows. This
  // exercises real pg_dump SQL, nullable live FKs, cursors and restore locking.
  const dump=execFileSync('pg_dump',[targetUrl.toString(),'--data-only','--inserts','--table=eshop.payment_reference*'],{encoding:'utf8'});
  await Promise.all(writers.splice(0).map(c=>c.end()));await control.end();control=null;
  const restoredName=target+'_restore',restoredUrl=new URL(base);restoredUrl.pathname='/'+restoredName;
  await admin.query(`CREATE DATABASE ${restoredName} TEMPLATE ${target}`);
  const restored=await connect(restoredUrl.toString());
  try{
   await restored.query('TRUNCATE eshop.payment_reference_reservations,eshop.payment_reference_accounts,eshop.payment_reference_sequences,eshop.payment_reference_form_watermarks,eshop.payment_reference_namespaces,eshop.payment_reference_scopes');
   await restored.query(dump.split('\n').filter(line=>!line.startsWith('\\restrict')&&!line.startsWith('\\unrestrict')&&!line.startsWith('SET transaction_timeout')).join('\n'));
   assert.equal(Number((await restored.query('SELECT count(*) n FROM eshop.payment_reference_reservations WHERE namespace_id=$1',[x.namespace])).rows[0].n),expectedReservations);
   assert.equal(Number((await restored.query('SELECT count(*) n FROM eshop.payment_reference_sequences WHERE namespace_id=$1',[x.namespace])).rows[0].n),2);
   await restored.query("UPDATE eshop.payment_reference_namespaces SET allocation_enabled=false; UPDATE eshop.payment_reference_scopes SET phase='paused'");
   await assert.rejects(restored.query('SELECT public.reserve_payment_reference_internal($1,$2,$3,$4,$5)',[payment,x.form,'same-source',{mode:'random',preferred_digits:4,max_digits:10},'c'.repeat(64)]),/SCOPE_NOT_ACTIVE/);
  }finally{await restored.end();await admin.query(`DROP DATABASE ${restoredName}`);}
 } finally {
  if(control)await control.query('ROLLBACK').catch(()=>{});
  await Promise.all(writers.map(c=>c.end()));if(control)await control.end();
  await admin.query(`DROP DATABASE IF EXISTS ${target}`);await admin.end();
 }
});
