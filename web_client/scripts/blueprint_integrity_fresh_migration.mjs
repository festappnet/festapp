// Forward DDL qualification on the second, explicitly owned full local backend.
import pg from 'pg';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
const url=new URL(process.env.BLUEPRINT_DATABASE_URL??'');
assert.equal(url.hostname,'127.0.0.1');assert(['59822','60922'].includes(url.port));
const expectedProject=url.port==='60922'?'festapp-blueprint-mcp-closure-fresh-20261020':'festapp-blueprint-1000-fresh-20261020';
const root=resolve(new URL('../..',import.meta.url).pathname);
const snapshot='/Users/miakh/source/festapp-blueprint-1000-e2e-20261020/canonical-source-snapshot';
const c=new pg.Client({connectionString:url.href});
const one=async(sql,args=[]) => (await c.query(sql,args)).rows[0];
try{
 await c.connect();
 assert.equal((await one('select project from festapp_test_support.disposable_environment where singleton')).project,expectedProject);
 await c.query("set statement_timeout='20s';set lock_timeout='5s'");
 const report={project:expectedProject,port:Number(url.port),freshForwardMigrations:(await one('select count(*)::int n from festapp_test_support.applied_migrations')).n};
 await c.query(readFileSync(resolve(root,'database/tests/helpers/assertions.sql'),'utf8'));
 await c.query(readFileSync(resolve(root,'database/tests/blueprint/fixtures.sql'),'utf8'));
 // Reinstall the immutable predecessor's business owners, then create genuine
 // sold/held rows before applying this release's additive forward DDL.
 const sources=['blueprint/update_blueprint_client_sync_v1.sql','blueprint/swap_spot_tickets_client_sync_v1.sql','eshop_waitlist/tickets.sql','eshop_waitlist/commands.sql','eshop/create_ticket_order.sql','eshop_waitlist/accept_offer.sql','eshop/finalize_ticket_order.sql','blueprint/save.sql','blueprint/validation.sql','eshop/select_spot.sql','eshop/analyze_new_order_spots.sql','eshop/confirm_blueprint_order_change.sql','eshop/get_blueprint.sql','eshop/get_blueprint_for_edit.sql','blueprint/staged_tenant_readers.sql'];
 await c.query('begin');
 for(const file of sources)await c.query(readFileSync(resolve(snapshot,'database/functions',file),'utf8'));
 await c.query('commit');
 const f=(await one('select public.blueprint_test_fixture_internal() f')).f;
 await c.query("select set_config('request.jwt.claim.sub',$1,false)",[f.actor]);
 const saved=(await one('select public.update_blueprint_client_sync_v1($1,$2) r',[f.request,randomUUID()])).r;assert.equal(saved.status,'applied');
 const spots=saved.data.seatBindings.map(b=>b.spotId), held=randomUUID(),buyer=randomUUID();
 const bank=(await one("insert into eshop.bank_accounts(title,type,supported_currencies) values('Fresh qualification bank','FIO',array['CZK']) returning id")).id;
 await c.query('insert into eshop.unit_bank_accounts(unit,bank_account) select unit,$1 from public.occasions where id=$2',[bank,f.occasion]);
 await c.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim.role','anon',false)");
 await c.query('set role anon');
 assert.equal((await one('select public.select_spot($1,$2,$3,true) r',[f.formKey,held,spots[0]])).r.code,200);
 assert.equal((await one('select public.select_spot($1,$2,$3,true) r',[f.formKey,buyer,spots[1]])).r.code,200);
 const command=randomUUID(),client=randomUUID(),input={form:f.formKey,email:`fresh-${f.occasion}@example.invalid`,secret:buyer,ticket:[{spot:spots[1]}]};
 const sold=(await one('select public.create_ticket_order_client_sync_v1($1,$2,$3) r',[input,command,client])).r;assert.equal(sold.code,200,JSON.stringify(sold));
 await c.query('reset role');
 const state=async()=> (await one(`select jsonb_build_object(
  'blueprint',(select to_jsonb(b) from eshop.blueprints b where b.id=$1),
  'bindings',(select jsonb_agg(to_jsonb(b) order by b.node_id) from eshop.blueprint_seat_bindings b where blueprint=$1),
  'spots',(select jsonb_agg(to_jsonb(s) order by id) from eshop.spots s where blueprint=$1),
  'orders',(select jsonb_agg(to_jsonb(o) order by id) from eshop.orders o where occasion=$2),
  'tickets',(select jsonb_agg(to_jsonb(t) order by id) from eshop.tickets t where occasion=$2),
  'history',(select jsonb_agg(to_jsonb(h) order by id) from eshop.orders_history h where "order"=$3),
  'payment',(select to_jsonb(p) from eshop.payment_info p join eshop.orders o on o.payment_info=p.id where o.id=$3)
 ) state`,[f.blueprint,f.occasion,sold.data.order.id])).state;
 const before=await state();
 const migrations=['20261021010000_blueprint_reservation_integrity.sql','20261021020000_blueprint_release_integration.sql'];
 const migration=migrations.map(name=>readFileSync(resolve(root,'supabase/migrations',name),'utf8')).join('\n');
 await c.query(migration);
 assert.deepEqual(await state(),before,'forward migration preserves sold price/labels/history, active hold, layout revision and bindings');
 assert.equal((await one("select to_regprocedure('public.get_blueprint_legacy_rollout_internal(uuid,uuid,bigint)') public_legacy,to_regprocedure('public.get_blueprint_for_edit_legacy_rollout_internal(text)') admin_legacy")).public_legacy,null);
 assert.equal((await one("select to_regprocedure('public.get_blueprint_for_edit_legacy_rollout_internal(text)') legacy")).legacy,null);
 const read=(await one('select public.get_blueprint($1,$2,$3) r',[held,f.formKey,f.blueprint])).r;
 assert.equal(read.code,200);assert(read.data.expiresAt);
 await c.query('set role anon');
 const replay=(await one('select public.create_ticket_order_client_sync_v1($1,$2,$3) r',[input,command,client])).r;
 assert.equal(replay.data.order.id,sold.data.order.id);
 await c.query('reset role');
 await c.query(readFileSync(resolve(root,'database/tests/blueprint/integrity_source_parity_test.sql'),'utf8'));
 await c.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[f.actor]);
 await c.query('begin');
 await c.query('update eshop.blueprints set layout=null where id=$1',[f.blueprint]);
 const missing=(await one('select public.get_blueprint_for_edit((select link from public.occasions where id=$1)) r',[f.occasion])).r;
 assert.equal(missing.reason,'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
 await c.query('rollback');
 report.preexistingFixture={occasion:f.occasion,blueprint:f.blueprint,heldSpot:spots[0],soldSpot:spots[1],order:sold.data.order.id};
 report.aggregateBeforeAfterSha256=createHash('sha256').update(JSON.stringify(before)).digest('hex');
 report.migrationSha256=createHash('sha256').update(migration).digest('hex');
 report.unchangedAggregate=true;report.receiptReplay=true;report.ownExpiryReadback=true;report.installedSourceParity=true;report.stagedReadersAbsent=true;report.adminMissingLayoutFailClosed=true;
 const evidence=resolve(root,process.env.FESTAPP_BLUEPRINT_EVIDENCE_DIR??'.codex-artifacts/blueprint/run');
 mkdirSync(evidence,{recursive:true});
 writeFileSync(resolve(evidence,'sql-fresh-forward-qualification.json'),JSON.stringify(report,null,2)+'\n');
 console.log(`PASS fresh ${report.freshForwardMigrations}-migration catalog, preexisting sold/held aggregate preservation, receipt replay and source parity`);
}finally{await c.query('rollback');await c.end();}
