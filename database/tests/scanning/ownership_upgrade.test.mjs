import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assertLocalDatabaseUrl(connectionString);
const fixture=await readFile(new URL('./fixture.sql',import.meta.url),'utf8');
const cutover=await readFile(new URL('../../functions/scanning/ownership.sql',import.meta.url),'utf8');

test('historical scanner groups are repaired atomically and database ownership stays unique',async()=>{
 const db=new Client({connectionString});await db.connect();
 try {
  await assertDisposableDatabase(db);await db.query('BEGIN');
  await db.query("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='20s'");
  await db.query(fixture);
  await db.query('ALTER TABLE public.occasions DROP CONSTRAINT IF EXISTS occasions_scanner_credential_unique');
  const f=[];for(let i=0;i<5;i++)f.push((await db.query('SELECT public.scanner_test_fixture() fx')).rows[0].fx);
  const ids=f.map(x=>x.occasion);
  const before=(await db.query('SELECT o.id,o.organization,o.occasion_hidden,s.epoch FROM public.occasions o JOIN public.scanner_settings s ON s.occasion_id=o.id WHERE o.id=ANY($1::bigint[]) ORDER BY o.id',[ids])).rows;
  const byId=new Map(before.map(x=>[Number(x.id),x]));
  await db.query('UPDATE public.occasions_hidden SET secret=$1 WHERE id=$2',['AAAAA',byId.get(ids[4]).occasion_hidden]);
  f[4].scan_code='AAAAA';
  const sessionData=[];
  for(const fx of f)sessionData.push((await db.query('SELECT public.open_scanner_session($1) response',[fx.scan_code])).rows[0].response.data);
  const sessions=sessionData.map(s=>s.session_id);
  await db.query('UPDATE public.occasions SET occasion_hidden=$1 WHERE id=$2',[byId.get(ids[0]).occasion_hidden,ids[1]]);
  await db.query('UPDATE public.occasions_hidden SET secret=NULL WHERE id=$1',[byId.get(ids[2]).occasion_hidden]);
  await db.query('UPDATE public.occasions SET occasion_hidden=$1 WHERE id=$2',[byId.get(ids[2]).occasion_hidden,ids[3]]);
  assert.equal((await db.query('SELECT count(*)::int n FROM public.get_scanner_occasion_for_scan_code_internal($1)',[f[0].scan_code])).rows[0].n,0);
  await db.query('SAVEPOINT old_session');
  await assert.rejects(db.query('SELECT public.scanner_session_internal($1,$2)',[sessionData[0].session_id,sessionData[0].token]),e=>e.code==='PT401'&&e.message==='scanner_session_expired');
  await db.query('ROLLBACK TO SAVEPOINT old_session');
  const symbol=(await db.query('SELECT ticket_symbol FROM eshop.tickets WHERE id=$1',[f[0].tickets[0]])).rows[0].ticket_symbol;
  for(const [fn,args] of [
   ['get_occasion_by_scan_code',[f[0].scan_code]],['get_all_tickets_for_scan',[f[0].scan_code]],
   ['scan_ticket_v2',[symbol,f[0].scan_code]],['scan_ticket',[symbol,f[0].scan_code]],
   ['update_ticket_to_used',[f[0].tickets[0],f[0].scan_code]],
  ])assert.equal((await db.query(`SELECT public.${fn}(${args.map((_,i)=>'$'+(i+1)).join(',')}) response`,args)).rows[0].response.code,401,fn);
  await db.query('SAVEPOINT scope_guard');
  await db.query("SELECT set_config('festapp.scanner_ownership_organizations',$1,true)",[String(byId.get(ids[0]).organization)]);
  await assert.rejects(db.query(cutover),e=>e.code==='P0001'&&e.message.includes('explicit organization scope'));
  await db.query('ROLLBACK TO SAVEPOINT scope_guard');
  assert.equal((await db.query('SELECT count(*)::int n FROM public.occasions WHERE occasion_hidden=$1',[byId.get(ids[0]).occasion_hidden])).rows[0].n,2);
  const scope=(await db.query(`SELECT DISTINCT o.organization FROM public.occasions o JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
   WHERE EXISTS(SELECT 1 FROM public.occasions s WHERE s.occasion_hidden=h.id AND s.id<>o.id)
   OR EXISTS(SELECT 1 FROM public.scanner_revoked_credentials r WHERE r.secret_hash=encode(extensions.digest(h.secret,'sha256'),'hex'))`)).rows.map(x=>x.organization).join(',');
  await db.query("SELECT set_config('festapp.scanner_ownership_organizations',$1,true)",[scope]);
  // Force occupied and permanently retired candidates through the real cutover.
  await db.query("INSERT INTO public.scanner_revoked_credentials(secret_hash,reason) VALUES(encode(extensions.digest('BBBBB','sha256'),'hex'),'rotated') ON CONFLICT DO NOTHING");
  await db.query(`CREATE TEMP SEQUENCE cutover_entropy;
   CREATE OR REPLACE FUNCTION public.generate_scanner_access_code_internal() RETURNS text LANGUAGE sql VOLATILE SECURITY INVOKER
   SET search_path=public,extensions AS $$ SELECT repeat(chr(64+nextval('cutover_entropy')::integer),5) $$;`);
  await db.query(cutover);
  assert.equal((await db.query("SELECT currval('cutover_entropy')::int n")).rows[0].n,6,'occupied and retired candidates are retried');
  const after=(await db.query('SELECT o.id,o.occasion_hidden,h.secret,s.epoch FROM public.occasions o JOIN public.occasions_hidden h ON h.id=o.occasion_hidden JOIN public.scanner_settings s ON s.occasion_id=o.id WHERE o.id=ANY($1::bigint[]) ORDER BY o.id',[ids])).rows;
  const afterById=new Map(after.map(x=>[Number(x.id),x]));
  const codes=ids.slice(0,4).map(id=>afterById.get(id).secret);
  assert.ok(codes.every(c=>/^[A-Z0-9]{5}$/.test(c)),'repaired code format');assert.equal(new Set(codes).size,4);
  for(const id of ids.slice(0,4)) {
   const row=afterById.get(id);assert.equal(Number(row.epoch),Number(byId.get(id).epoch)+1);
   assert.equal((await db.query('SELECT id FROM public.get_scanner_occasion_for_scan_code_internal($1)',[row.secret])).rows[0].id,String(id));
  }
  assert.equal(afterById.get(ids[4]).secret,f[4].scan_code,'unaffected credential preserved');
  assert.equal(afterById.get(ids[4]).epoch,byId.get(ids[4]).epoch,'unaffected epoch preserved');
  const states=(await db.query('SELECT id,revoked_at FROM public.scanner_sessions WHERE id=ANY($1::uuid[])',[sessions])).rows;
  for(const s of states)assert.equal(Boolean(s.revoked_at),s.id!==sessions[4],'only repaired event sessions revoked');
  assert.equal((await db.query('SELECT (public.scanner_session_internal($1,$2)).occasion_id id',[sessionData[4].session_id,sessionData[4].token])).rows[0].id,String(ids[4]),'unaffected live session remains usable');
  assert.equal((await db.query('SELECT count(*)::int n FROM public.get_scanner_occasion_for_scan_code_internal($1)',[f[0].scan_code])).rows[0].n,0,'old shared proof remains dead');
  assert.equal((await db.query('SELECT secret FROM public.occasions_hidden WHERE id=$1',[byId.get(ids[0]).occasion_hidden])).rows[0].secret,null,'old bearer cleared without deleting its history');
  assert.equal((await db.query("SELECT count(*)::int n FROM public.scanner_revoked_credentials WHERE secret_hash=encode(extensions.digest($1,'sha256'),'hex')",[f[0].scan_code])).rows[0].n,1,'old shared value remains permanently reserved');
  await db.query(cutover);
  assert.deepEqual((await db.query('SELECT o.id,h.secret,s.epoch FROM public.occasions o JOIN public.occasions_hidden h ON h.id=o.occasion_hidden JOIN public.scanner_settings s ON s.occasion_id=o.id WHERE o.id=ANY($1::bigint[]) ORDER BY o.id',[ids])).rows,after.map(({id,secret,epoch})=>({id,secret,epoch})),'repeat repair is inert');
  await db.query('SAVEPOINT alias_guard');
  await assert.rejects(db.query('UPDATE public.occasions SET occasion_hidden=$1 WHERE id=$2',[afterById.get(ids[0]).occasion_hidden,ids[1]]),e=>e.code==='23505'&&e.constraint==='occasions_scanner_credential_unique');
  await db.query('ROLLBACK TO SAVEPOINT alias_guard');
  await db.query('UPDATE public.occasions SET occasion_hidden=NULL WHERE id=ANY($1::bigint[])',[ids.slice(0,2)]);
  assert.equal((await db.query('SELECT count(*)::int n FROM public.occasions WHERE id=ANY($1::bigint[]) AND occasion_hidden IS NULL',[ids.slice(0,2)])).rows[0].n,2,'multiple unconfigured occasions remain valid');
 } finally {await db.query('ROLLBACK');await db.end();}
});
