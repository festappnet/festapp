// Real disposable SQL -> current UI/MCP projections, paired with the exact
// pre-cutover UI RPC source. No HTTP/provider call or production fixture.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fixture} from '../authorization/benchmark.mjs';
import {openDisposableDatabase} from '../../tools/festapp/test/postgres.mjs';
import {Operations} from '../../tools/festapp/src/operations/catalog.mjs';
const base='c6dea8392c6f56be2993447b970a28e46b9467b5';
const original=execFileSync('git',['show',base+':database/functions/inventory/get_inventory_pools_by_occasion_link.sql'],{cwd:new URL('../../',import.meta.url),encoding:'utf8'});
const migration=await readFile(new URL('../../supabase/migrations/20261023190000_inventory_summary_reads.sql',import.meta.url),'utf8');
const url=process.env.FESTAPP_MCP_TEST_DATABASE_URL;
assert(url&&url===process.env.FESTAPP_AUTHORIZATION_DATABASE_URL,'Set both explicit marked disposable URLs to the same database');
const db=await openDisposableDatabase(url);const measures=[];let plan;
try {
 await db.query('BEGIN');
 for(const name of ['20261023163000_product_admin_read_semantics.sql','20261023170000_product_schedule_commands.sql','20261023180000_atomic_standing_inventory.sql']) await db.query(await readFile(new URL('../../supabase/migrations/'+name,import.meta.url),'utf8'));
 await db.query(migration);const f=await fixture(db,1);
 const pool=Number((await db.query("insert into inventory_pools(occasion,title,sellable_capacity) values($1,'Inventory audit',NULL) returning id",[f.occasion])).rows[0].id);
 const context=Number((await db.query("insert into inventory_contexts(inventory_pool,title) values($1,'Context audit') returning id",[pool])).rows[0].id);
 await db.query("insert into resources(inventory_pool,occasion,title,capacity) values($1,$2,'Supply A',50),($1,$2,'Supply B',50)",[pool,f.occasion]);
 let record;
 const owner={root:'/tmp/festapp-stock-read-audit',profile:{organizationId:f.org,tenantId:'fixture',name:'audit',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:['inventory.pools.list','inventory.contexts.list'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action({rpc:async(name,args)=>{
  record.domainRpcCalls++;
  const pools=name==='get_inventory_catalog';assert(pools||name==='get_inventory_context_catalog');
  const data=(await db.query(pools?'select get_inventory_catalog($1,$2,$3,NULL,$4,$5) value':'select get_inventory_context_catalog($2,$1,$3,$6,$4,$5) value',pools?[args.p_organization,args.p_occasion,args.p_unit,args.p_after,args.p_limit]:[args.p_organization,args.p_occasion,args.p_unit,args.p_after,args.p_limit,args.p_pool])).rows[0].value;
  record.databaseJsonBytes+=Buffer.byteLength(JSON.stringify(data));
  record.returnedPools+=data.pools?.length??0;record.returnedContexts+=data.inventory_contexts?.length??0;
  assert.equal(data.spots,undefined);return {data,error:null};
 }},{userId:f.actor})};
 const ops=new Operations(owner);let previous=0;
 for(const size of [100,1000]) {
  await db.query('RESET ROLE');
  await db.query('insert into eshop.spots(occasion,inventory_context) select $1,$2 from generate_series(1,$3::int)',[f.occasion,context,size-previous]);
  await db.query('update resources set capacity=$2 where inventory_pool=$1',[pool,size/2]);
  await db.query("update eshop.spots set secret='11111111-2222-4333-8444-555555555555',secret_expiration_time=now()+interval '1 hour' where id=(select id from eshop.spots where inventory_context=$1 order by id limit 1)",[context]);
  await db.query('SAVEPOINT baseline');await db.query(original);await db.query('SET LOCAL ROLE authenticated');
  const before=(await db.query('select get_inventory_pools_by_occasion_link($1) value',[f.link])).rows[0].value;
  assert.equal(before.spots.length,size);await db.query('ROLLBACK TO SAVEPOINT baseline');await db.query('RELEASE SAVEPOINT baseline');
  await db.query('SET LOCAL ROLE authenticated');
  const ui=(await db.query("select get_inventory_catalog($1,$2,$3,NULL,NULL,NULL,'summary') value",[f.org,f.occasion,f.unit])).rows[0].value;
  assert.equal(ui.spots,undefined);assert.equal(ui.inventory_contexts[0].physical_count,size);assert.equal(ui.inventory_contexts[0].held_count,1);
  record={fixtureSpots:size,baselineRpcCalls:1,baselineReturnedSpots:before.spots.length,baselineJsonBytes:Buffer.byteLength(JSON.stringify(before)),uiRpcCalls:1,uiReturnedSpots:0,uiJsonBytes:Buffer.byteLength(JSON.stringify(ui)),domainRpcCalls:0,databaseJsonBytes:0,returnedPools:0,returnedContexts:0};
  const pools=await ops.invoke('inventory.pools.list',{occasionId:f.occasion,limit:50});assert.equal(pools.ok,true,JSON.stringify(pools));
  const contexts=await ops.invoke('inventory.contexts.list',{occasionId:f.occasion,poolId:pool,limit:50});assert.equal(contexts.ok,true,JSON.stringify(contexts));
  assert.equal(pools.data.pools[0].physical_count,size);assert.equal(contexts.data.inventory_contexts[0].held_count,1);
  assert(!JSON.stringify([ui,pools.data,contexts.data]).includes('11111111-2222-4333-8444-555555555555'));
  record.mcpDataJsonBytes=Buffer.byteLength(JSON.stringify(pools.data))+Buffer.byteLength(JSON.stringify(contexts.data));measures.push(record);previous=size;
 }
 await db.query('RESET ROLE');
 const source=await readFile(new URL('../../database/functions/inventory/inventory_catalog.sql',import.meta.url),'utf8');
 const sql=source.match(/AS \$\$\s*([\s\S]*?)\$\$/)[1].replaceAll('p_occasion','$1::bigint').replaceAll('p_pools','$2::bigint[]').replaceAll('p_contexts','$3::bigint[]');
 plan=(await db.query('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+sql,[f.occasion,[pool],[context]])).rows[0]['QUERY PLAN'];
} finally {try {await db.query('ROLLBACK');}finally {await db.end();}}
const report={date:'2026-10-23',baselineSource:base,baselineSqlSha256:createHash('sha256').update(original).digest('hex'),migration:'20261023190000_inventory_summary_reads.sql',migrationSha256:createHash('sha256').update(migration).digest('hex'),interpretation:'Exact pre-cutover UI RPC and current UI/MCP owners on the same marked, mail-fenced PostgreSQL fixture. Serialized SQL and DTO JSON bytes are actual results, not HTTP wire traffic. Session/delegation lookups are stubbed/excluded. Two MCP reads represent pool summary plus context detail. Counts refer to spots, not people. All fixture data/DDL rolled back. Inner facts SELECT plan is a local sample, not a production latency benchmark.',measures,plan};
await writeFile(new URL('../../docs/reports/admin-inventory-summary-network-2026-10-23.json',import.meta.url),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
for(const m of measures) console.log(`${m.fixtureSpots} spots: old UI ${m.baselineJsonBytes} B / ${m.baselineReturnedSpots} spots; current UI ${m.uiJsonBytes} B / 0 spots; MCP ${m.databaseJsonBytes} B in ${m.domainRpcCalls} reads`);
