// Local-only baseline: canonical SQL -> actual MCP executor -> serialized DTO.
// Fixture changes, including DDL, are always rolled back. No HTTP/provider calls.
import assert from 'node:assert/strict';
import { readFile, writeFile, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { performance } from 'node:perf_hooks';
import { gzipSync } from 'node:zlib';
import { fixture } from '../authorization/benchmark.mjs';
import { openDisposableDatabase } from '../../tools/festapp/test/postgres.mjs';
import { Operations } from '../../tools/festapp/src/operations/catalog.mjs';
const outputFlag=process.argv.indexOf('--output');
assert(outputFlag<0 || process.argv[outputFlag+1], '--output requires a new evidence file path');
const output=outputFlag<0 ? new URL('../../docs/reports/admin-data-network-baseline-2026-10-23.json',import.meta.url) : pathToFileURL(resolve(process.argv[outputFlag+1]));
try { await stat(output); throw new Error('Evidence exists; choose a new --output path to preserve the baseline'); }
catch(error) { if(error.code!=='ENOENT') throw error; }
const connection = process.env.FESTAPP_MCP_TEST_DATABASE_URL;
assert(connection && connection === process.env.FESTAPP_AUTHORIZATION_DATABASE_URL, 'Set both explicit disposable database URLs to the same marked local fixture');
const db = await openDisposableDatabase(connection);
const measures = [];
try {
    await db.query('BEGIN');
    await db.query('SET LOCAL ROLE postgres');
    await db.query(await readFile(new URL('../../supabase/migrations/20261023093000_shared_product_catalog.sql', import.meta.url),'utf8'));
    await db.query('RESET ROLE');
    const f = await fixture(db, 1);
    const type = Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Audit admission','entry') returning id", [f.occasion])).rows[0].id);
    let measurement;
    const client = { rpc: async (name,args) => {
        assert.equal(name,'get_product_catalog');
        measurement.domainRpcCalls++;
        const start = performance.now();
        const data = (await db.query('select get_product_catalog($1,$2,$3) value',[args.p_organization,args.p_occasion,args.p_unit])).rows[0].value;
        measurement.databaseCallMsSingleSample = +(performance.now()-start).toFixed(3);
        const body = JSON.stringify(data);
        measurement.databaseReturnedProducts = data.catalog.products.length;
        measurement.databaseJsonBytes = Buffer.byteLength(body);
        measurement.databaseGzipBytes = gzipSync(body).length;
        return {data,error:null};
    }};
    const owner = { root: '/tmp/festapp-local-data-audit', profile:{organizationId:f.org,tenantId:'fixture',name:'audit',backendOrigin:'http://127.0.0.1:61022'}, allowedOperations:['products.list'],
        delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized: action=>action(client,{userId:f.actor}) };
    const operations = new Operations(owner);
    let previous = 0;
    for (const count of [100,1000]) {
        await db.query('RESET ROLE');
        await db.query("insert into eshop.products(occasion,product_type,title,description,price,currency_code,data,is_hidden,maximum) select $1,$2,'Audit product '||n,repeat('Synthetic audit description. ',8),100,'CZK','{}',false,100 from generate_series($3::int,$4::int) n",[f.occasion,type,previous+1,count]);
        await db.query('SET LOCAL ROLE authenticated');
        let after;
        for (const page of [1,2]) {
            measurement={fixtureProducts:count,page,requestedLimit:50,domainRpcCalls:0};
            const result=await operations.invoke('products.list',{occasionId:f.occasion,limit:50,...(after?{after}:{})});
            assert.equal(result.ok,true,JSON.stringify(result.error));
            measurement.mcpReturnedProducts=result.data.products.length;
            measurement.mcpDataJsonBytes=Buffer.byteLength(JSON.stringify(result.data));
            assert.equal(measurement.databaseReturnedProducts,count);
            assert.equal(measurement.mcpReturnedProducts,50);
            measures.push(measurement);after=result.data.nextCursor;
        }
        previous=count;
    }
} finally {
    try { await db.query('ROLLBACK'); } finally { await db.end(); }
}
const report={date:'2026-10-23',sourceMain:'0fd16f4374b065c578ecee3f647fda40cb17b37b',scope:'marked, mail-fenced disposable PostgreSQL only; all fixture data and DDL rolled back',
    interpretation:'Actual product MCP executor and canonical catalog RPC. Bytes are serialized JSON and an illustrative gzip result, not measured HTTP wire traffic. Timing is one local sample, not a production performance claim. No orders, seats or planned changes in these synthetic catalogs. Session/delegation lookups are stubbed and excluded from domainRpcCalls.',measures};
await writeFile(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
for(const m of measures) console.log(`${m.fixtureProducts} products, page ${m.page}: DB ${m.databaseReturnedProducts} / MCP ${m.mcpReturnedProducts} products; ${m.databaseJsonBytes} uncompressed DB JSON bytes`);
