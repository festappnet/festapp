import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {withPaymentUpgradeFixture} from './payment_upgrade_fixture.js';
const tables=['eshop.orders','eshop.payment_info','eshop.tickets','eshop.orders_history','eshop.stripe_checkout_attempts','eshop.stripe_payment_movements','eshop.stripe_disputes','eshop.stripe_event_inbox','eshop.stripe_capabilities','eshop.stripe_admission_decisions','public.email_messages'];
test('additive Barion migration preserves populated bank/Stripe facts and email receipts',async()=>{
 await withPaymentUpgradeFixture('hardening',async db=>{
  for(const file of ['database/tests/helpers/assertions.sql','database/tests/helpers/payment_lifecycle_fixture.sql','database/tests/scanning/fixture.sql','database/tests/payment_providers/upgrade_fixture.sql'])await db.query(fs.readFileSync(new URL('../../../'+file,import.meta.url),'utf8'));
  const snapshot=async()=>{const out={};for(const table of tables)out[table]=(await db.query(`SELECT md5(coalesce(jsonb_agg(to_jsonb(t)-'barion_connection_id' ORDER BY (to_jsonb(t)-'barion_connection_id')::text)::text,'[]')) digest FROM ${table} t`)).rows[0].digest;return out;};
  assert(Number((await db.query("SELECT count(*) FROM public.email_messages WHERE workflow_state='accepted'")).rows[0].count)>0);
  const before=await snapshot();
  await db.query(fs.readFileSync(new URL('../../../supabase/migrations/20261106180000_barion_sandbox_connector.sql',import.meta.url),'utf8'));
  assert.deepEqual(await snapshot(),before);
  assert.equal((await db.query("SELECT count(*)::int n FROM eshop.barion_connections")).rows[0].n,0,'no account or sales activated by migration');
 });
});
