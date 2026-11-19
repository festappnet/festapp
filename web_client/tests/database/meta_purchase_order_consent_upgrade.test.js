import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import pg from 'pg';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from './disposable_database.js';
const read=path=>readFileSync(new URL('../../../'+path,import.meta.url),'utf8');

test('order consent migration preserves historical pending grants and Complianz capture prepares with website readiness',async()=>{
 const url=process.env.DATABASE_URL;assert(url,'A disposable SQL runtime is required');assertLocalDatabaseUrl(url);
 const db=new pg.Client({connectionString:url});await db.connect();
 try {
  await assertDisposableDatabase(db);
  await db.query("BEGIN; SET LOCAL ROLE postgres; SET LOCAL TIME ZONE 'Europe/Prague'; SET LOCAL festapp.email_wake='scheduled'");
  await db.query(read('database/tests/helpers/assertions.sql'));
  await db.query(read('database/tests/helpers/form_measurement_fixture.sql'));
  const x=(await db.query('SELECT pg_temp.fixture(NULL) x')).rows[0].x;
  await db.query(`UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=$1`,[x.organization]);
  await db.query(`UPDATE public.forms SET is_open=true,data=data||'{"analytics":{"enabled":true}}' WHERE id=$1`,[x.form]);
  await db.query(`UPDATE public.units SET data=data||'{"measurement_consent_bridge":true,"measurement_websites":["https://tickets.example"]}' WHERE id=$1`,[x.unit]);
  await db.query('SELECT public.reserve_public_link_internal(\'form\',$1,$2,true)',[x.form,x.link]);
  await db.query(`INSERT INTO analytics.organization_policy(organization,meta_capi_enabled,enabled,revision,operator,reason) VALUES($1,true,true,1,'fixture','order consent upgrade')`,[x.organization]);
  await db.query(`INSERT INTO analytics.meta_purchase_connectors(unit,dataset,vault_secret,website_origin,enabled) VALUES($1,'123456',vault.create_secret(repeat('t',40)),'https://tickets.example',true)`,[x.unit]);
  await db.query('INSERT INTO analytics.meta_purchase_forms(form,unit) VALUES($1,$2)',[x.form,x.unit]);
  await db.query('SELECT public.purge_meta_purchase_data_internal()');
  await db.query("SELECT set_config('request.jwt.claim.sub','',true)");
  const snapshot=(await db.query(`SELECT jsonb_build_object('source','klaro','timestamp','2020-01-01T00:00:00.000Z',
   'websiteOrigin','https://tickets.example','consentRevision',public.unit_measurement_consent_scope_internal($1)->>'consentRevision',
   'revision',public.get_meta_purchase_consent($2)->>'revision','userAgent','Upgrade regression',
   'ad_storage',true,'ad_user_data',true,'ad_personalization',true) s`,[x.unit,x.link])).rows[0].s;
  await db.query("SELECT set_config('request.jwt.claim.sub','',true)");
  const checkout=async consent=>{
   const r=(await db.query(`SELECT public.create_ticket_order_client_sync_v1(pg_temp.checkout($1::jsonb)||jsonb_build_object('metaPurchaseConsent',$2::jsonb),gen_random_uuid(),gen_random_uuid()) r`,[x,consent])).rows[0].r;
   assert.equal(String(r.data.code),'200');return r.data.order.id;
  };
  const historical=await checkout(snapshot);
  // Reconstruct the exact old persisted format before executing the actual forward.
  await db.query(`UPDATE analytics.meta_purchase_deliveries SET consent_snapshot=$2::jsonb-'revision'-'userAgent',consent_decided_at='2020-01-01T00:00:00Z' WHERE order_id=$1`,[historical,snapshot]);
  await db.query(read('supabase/migrations/20261120010000_meta_purchase_order_consent.sql'));
  const saved=(await db.query('SELECT consent_at,consent_snapshot FROM analytics.meta_purchase_deliveries WHERE order_id=$1',[historical])).rows[0];
  assert.equal(saved.consent_snapshot.timestamp,undefined);
  assert.equal(Date.parse(saved.consent_snapshot.capturedAt),saved.consent_at.getTime());
  assert.equal(saved.consent_snapshot.decidedAt,'2020-01-01T00:00:00.000Z');
  const binding=(await db.query(`INSERT INTO analytics.website_consent_bindings(unit,website_origin,platform,provider_config,version,enabled,confirmed_revision,confirmed_at)
   VALUES($1,'https://tickets.example','html','{"provider":"complianz","policyId":"42"}',1,true,$2,clock_timestamp()) RETURNING id,version`,[x.unit,snapshot.consentRevision])).rows[0];
  const modern={...snapshot,source:'complianz',binding,transportExpiresAt:Date.now()+59000};delete modern.timestamp;
  const complianz=await checkout(modern);
  // Settings are organization-admin operations; a unit manager is insufficient.
  // Match the settings fixture in meta_purchase_consent_test.sql.
  await db.query(`INSERT INTO public.organization_users(organization,"user",is_admin) VALUES($1,$2,true) ON CONFLICT(organization,"user") DO UPDATE SET is_admin=true`,[x.organization,x.actor]);
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[x.actor]);
  assert.equal((await db.query('SELECT public.can_manage_unit_meta_purchase($1) allowed',[x.unit])).rows[0].allowed,true,'settings fixture must authorize the organization admin');
  await db.query(`UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://different.example"}' WHERE id=$1`,[x.organization]);
  assert.equal((await db.query('SELECT public.get_unit_meta_purchase($1) r',[x.unit])).rows[0].r.website_ready,true,'Complianz binding supplies website readiness without the standalone-origin shortcut');
  await db.query(`UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=$1`,[x.organization]);
  await db.query("SELECT set_config('request.jwt.claim.sub','',true); SELECT set_config('request.jwt.claim.role','service_role',true)");
  for(const id of [historical,complianz]) {
   const payment=(await db.query('SELECT payment_info FROM eshop.orders WHERE id=$1',[id])).rows[0].payment_info;
   const txn=(await db.query(`INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,ingest_source)
    SELECT bank_account,100,'CZK',clock_timestamp(),'fio_api' FROM eshop.payment_info WHERE id=$1 RETURNING id`,[payment])).rows[0].id;
   await db.query("SELECT public.apply_transaction_pairing($1,$2,'manual_attach','user')",[txn,payment]);
   const leases=(await db.query('SELECT * FROM public.claim_meta_purchase_deliveries(20)')).rows;
   const lease=leases.find(r=>String(r.order_id)===String(id));assert(lease,'paid order must be claimable');
   const prepared=(await db.query('SELECT public.prepare_meta_purchase_delivery($1,$2) p',[id,lease.lease])).rows[0].p;
   assert(prepared,'historical and Complianz grants must survive capture through prepare');
  }
 } finally {await db.query('ROLLBACK').catch(()=>{});await db.end();}
});
