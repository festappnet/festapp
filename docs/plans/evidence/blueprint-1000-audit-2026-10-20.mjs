// Diagnostic evidence, not a passing security regression suite.
// Every fixture, temporary function refresh and queued message is rolled back.
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const require = createRequire(resolve(root, 'web_client/package.json'));
const { Client } = require('pg');
const connectionString = process.env.DATABASE_URL;
const target = new URL(connectionString);
assert.equal(target.hostname, '127.0.0.1');
assert.equal(target.port, '55432');
assert.equal(target.pathname, '/postgres');
const c = new Client({ connectionString, application_name: 'blueprint-1000-audit-20261020' });
const refresh = process.env.AUDIT_REFRESH_SOURCES !== '0';
const report = { target: 'disposable-local:55432/postgres', transaction: 'ROLLBACK', mode: refresh ? 'transactionally refreshed repository sources' : 'installed disposable local catalog', sources: [], tests: [], probes: [] };
const sourceFiles = [
  'database/functions/eshop/finalize_ticket_order.sql',
  'database/functions/eshop/create_ticket_order.sql',
  'database/functions/eshop/select_spot.sql',
  'database/functions/eshop/get_blueprint.sql',
  'database/functions/eshop/update_blueprint.sql',
  'database/functions/eshop/update_blueprint_client_sync_v1.sql',
];
const queryOne = async (sql, args = []) => (await c.query(sql, args)).rows[0];
try {
  await c.connect();
  await c.query('BEGIN');
  await c.query("SET LOCAL statement_timeout='20s'; SET LOCAL lock_timeout='3s'");
  const before = await queryOne(`SELECT jsonb_object_agg(proname,md5(pg_get_functiondef(p.oid))) AS hashes
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND proname IN ('finalize_ticket_order_internal_v1','select_spot','get_blueprint','update_blueprint_internal_v1')`);
  for (const path of sourceFiles) {
    const source = readFileSync(resolve(root, path), 'utf8');
    if (refresh) await c.query(source);
    report.sources.push({ path, sha256: createHash('sha256').update(source).digest('hex') });
  }
  const after = await queryOne(`SELECT jsonb_object_agg(proname,md5(pg_get_functiondef(p.oid))) AS hashes
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND proname IN ('finalize_ticket_order_internal_v1','select_spot','get_blueprint','update_blueprint_internal_v1')`);
  report.localCatalogMatchedBeforeRefresh = JSON.stringify(before.hashes) === JSON.stringify(after.hashes);
  report.refreshedDefinitionDifferences = Object.keys(after.hashes).filter(k=>before.hashes[k]!==after.hashes[k]);
  report.functionHashesBefore = before.hashes;
  report.functionHashesTested = after.hashes;
  await c.query(readFileSync(resolve(root, 'database/tests/helpers/assertions.sql'), 'utf8'));
  for (const path of [
    'database/tests/abuse/hold_test.sql',
    'database/tests/eshop/blueprint_authoring_test.sql',
    'database/tests/eshop/get_blueprint_preview_test.sql',
    'database/tests/eshop/get_blueprint_order_sequence_test.sql',
  ]) {
    await c.query('SAVEPOINT audit_case');
    try {
      const sql = readFileSync(resolve(root, path), 'utf8').replace(/^\s*(?:BEGIN|COMMIT|ROLLBACK);\s*$/gmi, '');
      await c.query(sql);
      report.tests.push({ path, passed: true });
    } catch (e) { report.tests.push({ path, passed: false, error: e.message, sqlstate: e.code }); }
    await c.query('ROLLBACK TO SAVEPOINT audit_case');
    if (path.endsWith('get_blueprint_order_sequence_test.sql') && report.tests.at(-1).passed===false) {
      // Diagnose its old direct-link fixture against today's slug registry.
      const sql = readFileSync(resolve(root,path),'utf8').replace(/^\s*(?:BEGIN|COMMIT|ROLLBACK);\s*$/gmi,'')
        .replace("PERFORM set_config('request.jwt.claim.sub',actor::text,true);", "PERFORM public.reserve_public_link_internal('occasion',occ,link,true);\nPERFORM set_config('request.jwt.claim.sub',actor::text,true);");
      try { await c.query(sql); report.tests.at(-1).fixtureDiagnostic = { adaptation: 'register occasion slug through canonical allocator before reader', passed: true }; }
      catch(e) { report.tests.at(-1).fixtureDiagnostic = { passed: false, error:e.message }; }
      await c.query('ROLLBACK TO SAVEPOINT audit_case');
    }
  }
  const org = await queryOne("INSERT INTO public.organizations(title) VALUES('Blueprint audit 1000') RETURNING id");
  const unit = await queryOne("INSERT INTO public.units(title,organization) VALUES('Blueprint audit 1000',$1) RETURNING id", [org.id]);
  const occasion = await queryOne(`INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,features)
    VALUES('Blueprint audit 1000',$1,$2,$3,now(),now()+interval '1 day','[{"code":"blueprint","is_enabled":true}]') RETURNING id`, [org.id, unit.id, randomUUID()]);
  const bank = await queryOne("INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies) VALUES('Audit bank','123/0100','FIO',ARRAY['CZK']) RETURNING id");
  await c.query('INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES($1,$2,1)', [unit.id, bank.id]);
  const bp = await queryOne("INSERT INTO eshop.blueprints(occasion,organization,objects) VALUES($1,$2,'[]') RETURNING id", [occasion.id, org.id]);
  const foreignBp = await queryOne("INSERT INTO eshop.blueprints(occasion,organization,objects) VALUES($1,$2,'[]') RETURNING id", [occasion.id, org.id]);
  const form = await queryOne("INSERT INTO public.forms(occasion,blueprint,title,is_open,bank_account) VALUES($1,$2,'Audit form',true,$3) RETURNING id,key", [occasion.id, bp.id, bank.id]);
  const pt = await queryOne("INSERT INTO eshop.product_types(occasion,title,type) VALUES($1,'Audit seats','spot') RETURNING id", [occasion.id]);
  const product = await queryOne("INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden) VALUES($1,$2,'Audit seat',100,'CZK',false) RETURNING id", [occasion.id, pt.id]);
  await c.query("INSERT INTO public.form_fields(form,product_type,type) VALUES($1,$2,'product_type')", [form.id, pt.id]);
  for (const scenario of ['valid_hold', 'null_secret', 'expired_hold', 'foreign_blueprint_same_occasion', 'foreign_secret']) {
    await c.query('SAVEPOINT security_probe');
    const buyer = randomUUID();
    const spot = await queryOne(`INSERT INTO eshop.spots(occasion,blueprint,product,title,secret,secret_expiration_time)
      VALUES($1,$2,$3,'Audit seat',$4,clock_timestamp()+($5::int * interval '1 second')) RETURNING id`, [
      occasion.id, scenario === 'foreign_blueprint_same_occasion' ? foreignBp.id : bp.id,
      product.id, scenario === 'null_secret' ? null : buyer, scenario === 'expired_hold' ? -60 : 600,
    ]);
    const payload = { form: form.key, email: 'blueprint-audit@example.invalid', ticket: [{ spot: Number(spot.id) }] };
    if (scenario !== 'null_secret') payload.secret = scenario === 'foreign_secret' ? randomUUID() : buyer;
    await c.query('SAVEPOINT rpc_call');
    await c.query("SELECT set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true)");
    await c.query('SET LOCAL ROLE anon');
    let result;
    const command=randomUUID(), client=randomUUID();
    try { result = (await queryOne('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) AS result', [payload, command, client])).result; }
    catch (e) { await c.query('ROLLBACK TO SAVEPOINT rpc_call'); result = { error: e.message, sqlstate: e.code }; }
    if (scenario==='valid_hold' && result.code===200) {
      const repeated=(await queryOne('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) AS result',[payload,command,client])).result;
      assert.deepEqual(repeated,result);
      report.probes.push({scenario:'same_order_command_replay',sameResponse:true});
      const second=(await queryOne('SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) AS result',[payload,randomUUID(),client])).result;
      assert.notEqual(second.code,200);
      report.probes.push({scenario:'new_order_command_already_sold_spot',code:second.code,status:second.status});
    }
    await c.query('RESET ROLE');
    const state = await queryOne('SELECT order_product_ticket IS NOT NULL AS allocated FROM eshop.spots WHERE id=$1', [spot.id]);
    report.probes.push({ scenario, code: result.code, status: result.status, allocated: state.allocated, error: result.error || result.data?.message });
    await c.query('ROLLBACK TO SAVEPOINT security_probe');
  }
  await c.query(`INSERT INTO eshop.spots(occasion,blueprint,product,title)
    SELECT $1,$2,$3,'Seat '||i FROM generate_series(1,1000) i`, [occasion.id, bp.id, product.id]);
  await c.query(`UPDATE eshop.blueprints SET objects=(SELECT jsonb_agg(jsonb_build_object('id',s.id,'type','spot','x',(row_number-1)%40,'y',(row_number-1)/40))
    FROM (SELECT id,row_number() OVER(ORDER BY id)::int AS row_number FROM eshop.spots WHERE blueprint=$1) s),
    configuration='{"dimensions":{"width":40,"height":25}}' WHERE id=$1`, [bp.id]);
  const samples = [];
  for (let i=0;i<8;i++) {
    const start = performance.now();
    const { result } = await queryOne('SELECT public.get_blueprint(NULL,$1,$2) AS result', [form.key, bp.id]);
    assert.equal(result.code, 200);
    if (i>=2) samples.push(performance.now()-start);
    if (i===7) report.publicPayload = { seats: result.data.spots.length, productRows: result.data.products.length, distinctProducts: new Set(result.data.products.map(p=>p.id)).size, bytes: Buffer.byteLength(JSON.stringify(result)) };
  }
  samples.sort((a,b)=>a-b);
  report.localReadTiming = { samples: samples.length, medianMs: samples[Math.floor(samples.length/2)], maxMs: samples.at(-1), includes: 'local DB + pg transport + JSON decode; no HTTP/browser/TLS' };
} finally {
  await c.query('ROLLBACK').catch(()=>{});
  await c.end();
}
console.log(JSON.stringify(report, null, 2));
