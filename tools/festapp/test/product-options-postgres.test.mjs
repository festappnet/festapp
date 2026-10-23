import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase} from './postgres.mjs';
import {Operations} from '../src/operations/catalog.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
async function install(db){for(const name of ['20261023163000_product_admin_read_semantics.sql','20261023170000_product_schedule_commands.sql','20261023190000_inventory_summary_reads.sql','20261023210000_product_authoring_options.sql'])await db.query(await readFile(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8'));}
async function setup(t){const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,2);return{db,f};}
function executor(db,f){const calls=[];const owner={root:'/tmp/festapp-product-options',profile:{organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:['products.options'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action({rpc:async(name,args)=>{assert.equal(name,'get_product_catalog_options');const data=(await db.query('select get_product_catalog_options($1,$2,$3,$4,$5,$6) value',[args.p_occasion,args.p_organization,args.p_unit,args.p_kind,args.p_after,args.p_limit])).rows[0].value;calls.push({kind:args.p_kind,rows:data.options.length,jsonBytes:Buffer.byteLength(JSON.stringify(data))});return{data,error:null};}},{userId:f.actor})};const ops=new Operations(owner);return{calls,list:(kind,after)=>ops.invoke('products.options',{occasionId:f.occasion,kind,...(after?{after}:{})})};}

test('unused product authoring choices match UI metadata and are bounded independently of products or spots',options,async t=>{
 const {db,f}=await setup(t);const types=(await db.query("insert into eshop.product_types(occasion,title,type) select $1,case when n=1 then null else 'Choice '||n end,'entry' from generate_series(1,125)n returning id",[f.occasion])).rows.map(r=>Number(r.id));
 const pool=Number((await db.query("insert into inventory_pools(occasion,title,type) values($1,'Shared stock','food') returning id",[f.occasion])).rows[0].id);
 const contexts=(await db.query("insert into inventory_contexts(inventory_pool,title,block_date,data) select $1,case when n=1 then null else 'Context '||n end,case when n=1 then null else '2026-10-24'::date end,jsonb_build_object('secret','private-context-data') from generate_series(1,125)n returning id",[pool])).rows.map(r=>Number(r.id));
 await db.query('insert into eshop.spots(occasion,inventory_context) select $1,$2 from generate_series(1,1000)',[f.occasion,contexts[0]]);
 const foreign=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 const foreignType=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Foreign','entry') returning id",[foreign])).rows[0].id);
 await db.query('SET LOCAL ROLE authenticated');
 const ui=(await db.query('select get_product_catalog($1,$2,$3) value',[f.org,f.occasion,f.unit])).rows[0].value.catalog;
 const emptyPage=(await db.query('select get_product_catalog_page($1,$2,$3) value',[f.org,f.occasion,f.unit])).rows[0].value.catalog;
 assert.deepEqual(ui.products,[]);assert.equal(ui.product_types.length,125);assert.equal(ui.inventory_contexts.length,125);assert.deepEqual(emptyPage.product_types,[]);assert.deepEqual(emptyPage.inventory_contexts,[]);
 const ex=executor(db,f);
 for(const [kind,ids]of [['product_types',types],['inventory_contexts',contexts]]){let after;const seen=[];
  do{const result=await ex.list(kind,after);assert.equal(result.ok,true,JSON.stringify(result));const page=result.data;assert(page.options.length<=50);assert(!JSON.stringify(page).includes('private-context-data'));seen.push(...page.options.map(r=>r.id));after=page.nextCursor;
   for(const row of page.options){if(kind==='product_types')assert.deepEqual(row,ui.product_types.find(r=>r.id===row.id));else{const c=ui.inventory_contexts.find(r=>r.id===row.id);assert.deepEqual(row,{id:c.id,title:c.title,inventoryPoolId:c.inventory_pool,poolTitle:c.pool_title,poolType:c.pool_type,blockDate:c.block_date});}}
  }while(after);assert.deepEqual(seen,ids);assert(!seen.includes(foreignType)||kind!=='product_types');
 }
 assert.equal(ex.calls.length,6);
 // A choice page must not invoke the full catalog, sales aggregates or raw spots.
 await db.query('RESET ROLE');await db.query("create or replace function public.get_product_catalog_data_internal(p_occasion bigint,p_after bigint default null,p_limit integer default null) returns json language plpgsql as $$ begin raise exception 'full catalog is not an authoring choice dependency'; end $$");await db.query('SET LOCAL ROLE authenticated');assert.equal((await ex.list('product_types')).ok,true);assert.equal((await ex.list('inventory_contexts')).ok,true);
 t.diagnostic('product-options-json '+JSON.stringify(ex.calls));
});

test('product option boundaries enforce scope, input limits and private grants; product pages use actual product occasion',options,async t=>{
 const {db,f}=await setup(t);const type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Own','entry') returning id",[f.occasion])).rows[0].id);
 const foreign=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);
 await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Mismatched legacy row',1,'CZK')",[foreign,type]);await db.query('SET LOCAL ROLE authenticated');
 assert.deepEqual((await db.query('select get_product_catalog_page($1,$2,$3) value',[f.org,f.occasion,f.unit])).rows[0].value.catalog.products,[]);
 for(const [kind,org,unit,after,limit,code]of [[null,f.org,f.unit,null,50,'22023'],['unknown',f.org,f.unit,null,50,'22023'],['product_types',f.org,f.unit,null,null,'22023'],['inventory_contexts',f.org,f.unit,0,50,'22023'],['product_types',f.org,f.unit,null,101,'22023'],['product_types',f.org+999,f.unit,null,50,'42501'],['inventory_contexts',f.org,f.unit+999,null,50,'42501']]){await db.query('SAVEPOINT denied');await assert.rejects(db.query('select get_product_catalog_options($1,$2,$3,$4,$5,$6)',[f.occasion,org,unit,kind,after,limit]),e=>e.code===code);await db.query('ROLLBACK TO SAVEPOINT denied');await db.query('RELEASE SAVEPOINT denied');}
 await db.query('RESET ROLE');await db.query("update eshop.product_types set title=repeat('x',1048577) where id=$1",[type]);await db.query('SET LOCAL ROLE authenticated');await db.query('SAVEPOINT oversize');await assert.rejects(db.query("select get_product_catalog_options($1,$2,$3,'product_types',NULL,1)",[f.occasion,f.org,f.unit]),e=>e.code==='54000');await db.query('ROLLBACK TO SAVEPOINT oversize');await db.query('RELEASE SAVEPOINT oversize');
 await db.query('RESET ROLE');await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 const owners=['get_product_type_rows_internal','get_product_context_rows_internal','get_product_catalog_options','get_product_catalog_data_internal'];const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');const assertions=contract.split('\n').filter(l=>owners.some(n=>l.includes("to_regprocedure('public."+n+'(')));assert.equal(assertions.length,4);await db.query('DO $$ BEGIN\n'+assertions.join('\n')+'\nEND $$;');
 for(const role of ['anon','service_role'])assert.equal((await db.query("select has_function_privilege($1,'get_product_catalog_options(bigint,bigint,bigint,text,bigint,integer)','execute') allowed",[role])).rows[0].allowed,false);
 for(const signature of ['get_product_type_rows_internal(bigint,bigint[])','get_product_context_rows_internal(bigint,bigint[],boolean)'])assert.equal((await db.query("select has_function_privilege('authenticated',$1,'execute') allowed",[signature])).rows[0].allowed,false);
});
