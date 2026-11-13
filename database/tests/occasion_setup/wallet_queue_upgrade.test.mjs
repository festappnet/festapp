import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));const {Client}=require('pg');
assertLocalDatabaseUrl(process.env.DATABASE_URL);
const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();await assertDisposableDatabase(db);
const read=p=>readFileSync(new URL('../../../'+p,import.meta.url),'utf8');
const scalar=async(sql,values=[]) => (await db.query(sql,values)).rows[0].v;
try{
 await db.query('BEGIN');await db.query("SET LOCAL request.jwt.claim.role='service_role'");
 await test('legacy active leases block contraction and identity-preserving adoption is restartable',async()=>{
  // Reconstruct only the original provider registry and owner, inside a rollback.
  await db.query("ALTER TABLE eshop.ticket_wallet_objects ADD COLUMN lease uuid,ADD COLUMN lease_until timestamptz,ADD COLUMN next_attempt timestamptz DEFAULT now(),ADD COLUMN last_synced timestamptz,ADD COLUMN failures integer DEFAULT 0,ADD COLUMN last_error text");
  const history=read('supabase/migrations/20261110230000_ticket_wallet.sql');
  const oldSync=history.split('-- Source: database/functions/ticket_wallet/sync.sql\n')[1].split('-- Source:')[0];
  await db.query(oldSync);
  const org=await scalar("INSERT INTO public.organizations(title) VALUES('Upgrade fixture') RETURNING id v");
  await db.query("INSERT INTO eshop.ticket_wallet_integrations(organization,issuer,environment,web_origin) VALUES($1,'1234','upgrade','https://queue.invalid')",[org]);
  for(let n=1;n<=4;n++)await db.query("INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id,lease,lease_until,failures,last_error) VALUES($1,$2,-1,'1234','upgrade','1234.upgrade-'||$1::bigint::text,'1234.upgrade-class',gen_random_uuid(),now()+interval '1 minute',$3,'uncertain')",[-900000-n,org,n]);
  await db.query(read('supabase/migrations/20261113090000_ticket_wallet_queue_expand.sql'));
  await db.query('SAVEPOINT active');
  await assert.rejects(()=>db.query(read('supabase/migrations/20261113090100_ticket_wallet_queue_contract.sql')),/wallet_legacy_leases_not_drained|wallet_cutover_requires_pause/);
  await db.query('ROLLBACK TO SAVEPOINT active');
  await db.query('UPDATE eshop.ticket_wallet_integrations SET paused=true');
  await db.query("UPDATE eshop.ticket_wallet_objects SET lease_until=now()-interval '1 second'");
  await db.query(read('supabase/migrations/20261113090100_ticket_wallet_queue_contract.sql'));
  // A producer may already have enqueued an old identity during expansion.
  await db.query('SELECT public.enqueue_ticket_wallet_internal(ARRAY[$1::bigint])',[-900001]);
  for(let n=0;n<5;n++)await db.query('SELECT public.maintain_ticket_wallet(1)');
  assert.equal(await scalar("SELECT count(*)::int v FROM eshop.ticket_wallet_work WHERE organization=$1 AND kind='object'",[org]),4);
  assert.equal(await scalar("SELECT count(*)::int v FROM eshop.ticket_wallet_work WHERE organization=$1 AND kind='class'",[org]),1);
  assert.equal(await scalar("SELECT bool_and(applied=0) v FROM eshop.ticket_wallet_work WHERE organization=$1",[org]),true);
  assert.equal(await scalar("SELECT count(*)::int v FROM information_schema.columns WHERE table_schema='eshop' AND table_name='ticket_wallet_objects' AND column_name IN ('lease','lease_until','next_attempt','last_synced','failures','last_error')"),0);
  assert.equal(await scalar("SELECT to_regprocedure('public.finish_ticket_wallet(bigint,uuid,boolean)') IS NULL v"),true);
  assert.equal(await scalar("SELECT count(*)::int v FROM eshop.ticket_wallet_objects WHERE organization=$1 AND object_id LIKE '1234.upgrade-%'",[org]),4);
  await db.query('SELECT public.maintain_ticket_wallet(100)');
  assert.equal(await scalar("SELECT count(*)::int v FROM eshop.ticket_wallet_work WHERE organization=$1 AND kind='object'",[org]),4);
 });
}finally{await db.query('ROLLBACK');await db.end();}
