import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import pg from 'pg';
import {assertDisposableDatabase} from './disposable_database.js';
const root=path.resolve(import.meta.dirname,'../../..');
const tables=['eshop.orders','eshop.payment_info','eshop.tickets','eshop.orders_history','eshop.stripe_checkout_attempts','eshop.stripe_payment_movements','eshop.stripe_disputes','eshop.stripe_event_inbox','eshop.stripe_capabilities','eshop.stripe_admission_decisions','public.email_messages'];
test('populated connector upgrade preserves economic facts, leases, receipts, tickets, history and email byte-for-byte', async()=>{
 assert(process.env.DATABASE_URL, 'explicit disposable DATABASE_URL required');
 const target=new URL(process.env.DATABASE_URL);target.username='supabase_admin';
 const db=new pg.Client({connectionString:target.toString()});await db.connect();
 try {
  await assertDisposableDatabase(db); await db.query("BEGIN; SET LOCAL festapp.email_wake='scheduled'; SET LOCAL request.jwt.claim.role='service_role'");
  assert.equal((await db.query("SELECT to_regprocedure('public.payment_sale_policy_internal()') IS NULL ready")).rows[0].ready,true,'requires the frozen connector state before hardening');
  for(const file of ['database/tests/helpers/assertions.sql','database/tests/helpers/payment_lifecycle_fixture.sql','database/tests/scanning/fixture.sql','database/tests/payment_providers/upgrade_fixture.sql'])await db.query(fs.readFileSync(path.join(root,file),'utf8'));
  const snapshot=async()=>{const values={};for(const table of tables)values[table]=(await db.query(`SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,'[]')) digest FROM ${table} t`)).rows[0].digest;return values;};
  assert(Number((await db.query("SELECT count(*) FROM public.email_messages WHERE workflow_state='accepted'")).rows[0].count)>0,'populated email receipt required');
  assert(Number((await db.query("SELECT count(*) FROM eshop.payment_info WHERE payment_method='bank' AND deposit_amount=250 AND paid=250")).rows[0].count)>0,'actual bank deposit fixture required');
  const before=await snapshot();
  await db.query(fs.readFileSync(path.join(root,'supabase/migrations/20261106160000_payment_provider_hardening.sql'),'utf8'));
  assert.deepEqual(await snapshot(),before);
  assert.equal((await db.query("SELECT has_function_privilege('anon','public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[])','EXECUTE') allowed")).rows[0].allowed,false);
 } finally {await db.query('ROLLBACK');await db.end();}
});
