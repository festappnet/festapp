import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { fixture as sqlFixture } from '../../../automation/authorization/benchmark.mjs';
import { openDisposableDatabase } from './postgres.mjs';
import { setup, connect, apiRequest } from './api-fixture.mjs';
import { profile, reply } from './fixture.mjs';

test('HTTP product read/save/replay uses the real canonical SQL owner and preserves versions, UUID and current rights',
{skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL},async t=>{
    const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
    await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});
    await db.query("select set_config('festapp.authorization_fixture_project',$1,false)",[process.env.FESTAPP_LOCAL_DB_PROJECT_ID]);
    const f=await sqlFixture(db,1);
    const type=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Admission','entry') returning id",[f.occasion])).rows[0].id);
    await db.query('SET LOCAL ROLE authenticated');
    let loseResponse=false, mutations=0, revokeAfterMutation=false, service;
    const backend=async(url,init)=>{
        if(!url.pathname.startsWith('/rest/v1/rpc/'))return;
        const name=url.pathname.split('/').at(-1),args=JSON.parse(init.body);
        const sql={get_operator_access_v1:['select get_operator_access_v1($1,$2) value',[args.p_organization,args.p_occasion??null]],
            get_product_catalog_page:['select get_product_catalog_page($1,$2,$3,$4,$5) value',[args.p_organization,args.p_occasion,args.p_unit,args.p_after,args.p_limit]],
            manage_product:['select manage_product($1,$2,$3,$4,$5,$6) value',[args.p_occasion,args.p_organization,args.p_unit,args.p_action,args.p_product,args.p_command_id]]}[name];
        if(!sql)return;
        await db.query('SAVEPOINT http_rpc');
        try{
            const data=(await db.query(...sql)).rows[0].value;await db.query('RELEASE SAVEPOINT http_rpc');
            if(name==='manage_product'){
                mutations++;
                if(revokeAfterMutation){service.storage.revoke(service.storage.values('Delegation').find(g=>g.clientId==='api-fixture').id);}
                if(loseResponse){loseResponse=false;return reply({error:'lost response'},503);}
            }
            return reply(data);
        }catch(error){await db.query('ROLLBACK TO SAVEPOINT http_rpc');await db.query('RELEASE SAVEPOINT http_rpc');return reply({code:error.code},error.code==='42501'?403:400);}
    };
    service=await setup(t,{profileValue:profile(undefined,f.org),userId:f.actor,fetchImpl:backend});
    const {tokens}=await connect(service,{occasionIds:[f.occasion],scope:'festapp:ticket-layouts:read festapp:products:read festapp:products:write'});
    const call=(id,args)=>apiRequest(service,tokens,id,{occasionId:f.occasion,...args});
    let response=await call('products.list',{});assert.equal(response.status,200,await response.clone().text());
    const create={commandId:randomUUID(),product:{title:'Admission',price:'100.00',currency_code:'CZK',product_type:type}};
    response=await call('products.save',create);assert.equal(response.status,200,await response.clone().text());
    const created=await response.json();
    response=await call('products.save',create);assert.equal(response.status,200);assert.deepEqual((await response.json()).data,created.data);
    assert.equal((await call('products.save',{...create,product:{...create.product,title:'Changed payload'}})).status,422);
    response=await call('products.list',{});const listed=await response.json();
    const product=listed.data.products.find(p=>p.id===created.data.productId);
    const change={commandId:randomUUID(),product:{id:product.id,expected_aggregate_version:product.aggregate_version,title:'Renamed'}};
    loseResponse=true;
    response=await call('products.save',change);assert.equal(response.status,503);assert.equal((await response.json()).outcome,'unknown');
    response=await call('products.save',change);assert.equal(response.status,200,await response.clone().text());
    const replay=await response.json();assert.equal(replay.data.productId,product.id);
    response=await call('products.save',{...change,commandId:randomUUID(),product:{...change.product,title:'Stale'}});assert.equal(response.status,409);
    await db.query('RESET ROLE');
    const count=await db.query('select count(*)::int n from eshop.products where occasion=$1',[f.occasion]);assert.equal(count.rows[0].n,1);
    await db.query('SET LOCAL ROLE authenticated');
    revokeAfterMutation=true;
    response=await call('products.save',{commandId:randomUUID(),product:{id:product.id,expected_aggregate_version:replay.data.aggregateVersion,title:'Accepted before revoke'}});
    assert.equal(response.status,401);assert.equal((await response.json()).outcome,'unknown');
    const reads=mutations;assert.equal((await call('products.save',create)).status,401);assert.equal(mutations,reads);
    await db.query('RESET ROLE');
    assert.equal((await db.query('select title from eshop.products where id=$1',[product.id])).rows[0].title,'Accepted before revoke');
});

test('committed HTTP product effects survive a lost reply, fresh SQL connections, OAuth reconnect and revocation',
{skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL},async t=>{
    // Intentionally committed fixture in the explicitly marked disposable DB.
    // Every RPC uses a fresh connection/transaction, as a real PostgREST call.
    const url=process.env.FESTAPP_MCP_TEST_DATABASE_URL,admin=await openDisposableDatabase(url);
    t.after(()=>admin.end());await admin.query('BEGIN');
    await admin.query("select set_config('festapp.authorization_fixture_project',$1,false)",[process.env.FESTAPP_LOCAL_DB_PROJECT_ID]);
    const f=await sqlFixture(admin,1);
    const type=Number((await admin.query("insert into eshop.product_types(occasion,title,type) values($1,'Committed admission','entry') returning id",[f.occasion])).rows[0].id);
    await admin.query('COMMIT');
    let lose=false,revoke=false,service,calls=0;
    const backend=async(url,init)=>{
        const name=url.pathname.split('/').at(-1),a=JSON.parse(init.body??'{}');
        const query={get_operator_access_v1:['select get_operator_access_v1($1,$2) value',[a.p_organization,a.p_occasion??null]],
            get_product_catalog_page:['select get_product_catalog_page($1,$2,$3,$4,$5) value',[a.p_organization,a.p_occasion,a.p_unit,a.p_after,a.p_limit]],
            manage_product:['select manage_product($1,$2,$3,$4,$5,$6) value',[a.p_occasion,a.p_organization,a.p_unit,a.p_action,a.p_product,a.p_command_id]]}[name];
        if(!query)return;
        const rpc=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
        try{
            await rpc.query('BEGIN');await rpc.query('SET LOCAL ROLE authenticated');
            await rpc.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true),set_config('festapp.email_wake','scheduled',true)",[f.actor]);
            const value=(await rpc.query(...query)).rows[0].value;await rpc.query('COMMIT');
            if(name==='manage_product'){
                calls++;
                if(revoke)service.storage.revoke(service.storage.values('Delegation').find(g=>g.clientId==='api-fixture'&&!g.revoked).id);
                if(lose){lose=false;return reply({error:'response lost after COMMIT'},503);}
            }
            return reply(value);
        }catch(error){await rpc.query('ROLLBACK');return reply({code:error.code},error.code==='42501'?403:400);}
        finally{await rpc.end();}
    };
    service=await setup(t,{profileValue:profile(undefined,f.org),userId:f.actor,fetchImpl:backend});
    const consent={occasionIds:[f.occasion],scope:'festapp:ticket-layouts:read festapp:products:read festapp:products:write'};
    let {tokens}=await connect(service,consent);
    const request={occasionId:f.occasion,commandId:randomUUID(),product:{title:'Committed admission',price:'100.00',currency_code:'CZK',product_type:type}};
    lose=true;let response=await apiRequest(service,tokens,'products.save',request);
    assert.equal(response.status,503);assert.equal((await response.json()).outcome,'unknown');
    assert.equal((await admin.query('select count(*)::int n from eshop.products where occasion=$1',[f.occasion])).rows[0].n,1);
    // A new grant/session has no authority to create a replacement UUID. The
    // canonical product receipt is keyed by actor + original command, so replay
    // under the newly consented binding resolves the original committed result.
    service.storage.revoke(service.storage.values('Delegation').find(g=>g.clientId==='api-fixture').id);
    ({tokens}=await connect(service,consent));
    response=await apiRequest(service,tokens,'products.save',request);assert.equal(response.status,200,await response.clone().text());
    const product=(await response.json()).data;
    assert.equal((await admin.query('select count(*)::int n from eshop.products where occasion=$1',[f.occasion])).rows[0].n,1);
    assert.equal((await admin.query('select count(*)::int n from client_mutation_receipts where command_id=$1 and actor_id=$2',[request.commandId,f.actor])).rows[0].n,1);
    revoke=true;
    const change={occasionId:f.occasion,commandId:randomUUID(),product:{id:product.productId,expected_aggregate_version:product.aggregateVersion,title:'Commit before revoke'}};
    response=await apiRequest(service,tokens,'products.save',change);assert.equal(response.status,401);assert.equal((await response.json()).outcome,'unknown');
    assert.equal((await admin.query('select title from eshop.products where id=$1',[product.productId])).rows[0].title,'Commit before revoke');
    const before=calls;assert.equal((await apiRequest(service,tokens,'products.save',change)).status,401);assert.equal(calls,before);
    revoke=false;({tokens}=await connect(service,consent));
    response=await apiRequest(service,tokens,'products.save',change);assert.equal(response.status,200,await response.clone().text());
    // Live SQL rights still govern replay, even for a valid token and receipt.
    await admin.query('delete from occasion_users where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await admin.query('delete from unit_users where unit=$1 and "user"=$2',[f.unit,f.actor]);
    response=await apiRequest(service,tokens,'products.save',change);assert.equal(response.status,403,await response.clone().text());
    assert.equal((await admin.query('select count(*)::int n from eshop.products where occasion=$1',[f.occasion])).rows[0].n,1);
    assert.equal((await admin.query('select count(*)::int n from email_messages where occasion=$1',[f.occasion])).rows[0].n,0);
});
