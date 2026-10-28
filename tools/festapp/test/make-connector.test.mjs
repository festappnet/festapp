import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, mkdir, chmod, symlink, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { assemble, writeGenerated } from '../../../integrations/make/scripts/build.mjs';
import { loadToken, createSdk, evidenceWriter, runInactiveScenario, assertReviewerContext, ensureScenariosInactive } from '../../../integrations/make/scripts/lib/make-sdk.mjs';
import { orderDataSchemas } from '../src/operations/orders.mjs';
import { MAKE_CLIENT_ID, MAKE_SCOPES, MAKE_READ_OPERATIONS, MAKE_LIMITS } from '../src/remote/make-contract.mjs';
import { scopesForOperation } from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import { makeDocumentation } from '../src/remote/make-transport.mjs';
import { Operations } from '../src/operations/catalog.mjs';
const root = new URL('../../../integrations/make/', import.meta.url);
const json = async path => JSON.parse(await readFile(new URL(path, root), 'utf8'));
const app = await json('app.json');
const temporary = async t => {const path=await mkdtemp(join(tmpdir(),'festapp-make-contract-'));t.after(()=>rm(path,{recursive:true,force:true}));return pathToFileURL(path+'/');};

test('SQL report variants retain optional provider blocks, numeric/text money, nullable product types and extensions', async () => {
    const sample = (await json('src/samples.json'))['orders.report'];
    const report = sample.report;
    report.products.push({ product_id:'123', product_title:'Admission', type_id:null, type_title:null, confirmed_count:0 });
    report.timeline.payments.push({ day:'2026-10-28', currency:'CZK', received:'100.01', returned:0 });
    Object.assign(report.money_by_currency[0], { received:100, stripe_received:'100.00', stripe_refunded:'0.00', disputed:'1.00', available_after_disputes:'99.00', external_unattributed:'-2.00' });
    report.future_extension={stable:true};
    assert.deepEqual(orderDataSchemas['orders.report'].parse(sample), sample);
    assert.equal(typeof report.occasion.id,'string');
    report.generated_at='invalid';assert.equal(orderDataSchemas['orders.report'].safeParse(sample).success,false);
});

test('Make interfaces and OpenAPI use operation schemas regardless of sample values, optional blocks or extra keys', async () => {
    const baseline=await assemble(), samples=await json('src/samples.json');
    samples['orders.report'].report.extra_sample_key={never:'a type owner'};
    samples['orders.report'].report.timeline.payments=[{day:'2026-10-28',currency:'CZK',received:3,returned:'0'}];
    samples['orders.report'].report.products=[];samples['orders.report'].report.money_by_currency=[];
    const changed=await assemble({samples});
    for(const [path,content] of baseline) if(path.endsWith('/interface.json'))assert.equal(changed.get(path),content,path);
    const fields=JSON.parse(baseline.get('modules/salesReport/interface.json')).find(f=>f.name==='report').spec;
    assert.equal(fields.find(f=>f.name==='generated_at').type,'date');
    const money=fields.find(f=>f.name==='money_by_currency').spec.spec;
    assert.equal(money.find(f=>f.name==='stripe_received').type,'any');
    const docs=makeDocumentation({issuer:'https://example.invalid',resource:'test'},new Operations({root:'/tmp',orderSummaryOnly:true,allowedOperations:MAKE_READ_OPERATIONS}).catalog);
    assert.deepEqual(Object.keys(docs.components.securitySchemes.oauth.flows.authorizationCode.scopes),MAKE_SCOPES);
    assert(docs.paths['/operations/orders.report'].post.responses['200'].content['application/json'].schema.properties.data.properties.report.properties.timeline);
});

test('single presentation owns groups/scopes; limits preserve omitted versus blank and complete pagination bodies', async () => {
    const files=await assemble(), get=p=>JSON.parse(files.get(p));
    assert.equal(get('connections/common.json').clientId,MAKE_CLIENT_ID);
    assert.deepEqual(get('connections/scope.json'),['openid','offline_access',...new Set(MAKE_READ_OPERATIONS.flatMap(scopesForOperation))]);
    const groups=get('groups.json');assert.deepEqual(groups.flatMap(g=>g.modules).sort(),get('manifest.json').modules.sort());
    const orders=get('modules/listOrders/api.json');
    assert.equal(orders.body.limit,MAKE_LIMITS.pageSize);
    assert.deepEqual(orders.pagination.body,{...orders.body,before:'{{body.data.nextCursor}}'});
    assert(orders.response.limit.includes('keys(parameters)'));
    assert(orders.response.limit.includes(String(MAKE_LIMITS.totalInputCap)));
    assert.equal(get('modules/listOrders/expect.json').find(f=>f.name==='limit').default,MAKE_LIMITS.defaultTotal);
    const presentation=await json('src/catalog.json');presentation.modules[0].operation='orders.cancel';
    await assert.rejects(assemble({presentation}));
});

test('generator rejects extra outputs and symlinks, removes retired modules only inside its owned tree', async t => {
    const directory=await temporary(t), files=await assemble();await writeGenerated(files,{directory});
    await writeGenerated(files,{directory,check:true});
    await writeFile(new URL('obsolete.json',directory),'{}');
    await assert.rejects(writeGenerated(files,{directory,check:true}),/file set drift/);
    const presentation=await json('src/catalog.json');presentation.modules=presentation.modules.filter(m=>m.key!=='getOrder');
    const reduced=await assemble({presentation});await writeGenerated(reduced,{directory});await writeGenerated(reduced,{directory,check:true});
    assert(!(await readdir(new URL('modules/',directory))).includes('getOrder'));
    await symlink('/tmp',new URL('escape',directory));await assert.rejects(writeGenerated(files,{directory}),/Symlink/);
    const outer=await temporary(t);await symlink(directory,new URL('linked',outer));await assert.rejects(writeGenerated(files,{directory:new URL('linked/',outer)}),/real directory/);
});

test('SDK token loader rejects exposed permissions, directories and symlinks', async t => {
    const dir=await temporary(t), file=new URL('token',dir);await writeFile(file,'test-token',{mode:0o600});
    assert.equal(await loadToken(file),'test-token');
    await chmod(file,0o640);await assert.rejects(loadToken(file),/Protected/);await chmod(file,0o600);
    await symlink(file,new URL('link',dir));await assert.rejects(loadToken(new URL('link',dir)));
    await assert.rejects(loadToken(dir),/Protected/);
});

test('SDK fixes origin, paces concurrent calls, sanitizes errors and never retries 403, 429 or uncertain mutations', async () => {
    for(const status of [403,429]){
        let calls=0;const sdk=createSdk(app,'SECRET',{paceMs:0,fetchImpl:async(url,init)=>{calls++;assert(url.startsWith('https://eu1.make.com/api/v2/'));assert.equal(init.redirect,'error');return new Response('SECRET private response',{status});}});
        await assert.rejects(sdk('/test','PUT',{}),e=>e.message.includes(String(status))&&!e.message.includes('SECRET'));assert.equal(calls,1);
    }
    let calls=0;
    const sdk=createSdk(app,'SECRET',{paceMs:0,fetchImpl:async()=>{calls++;throw new Error('SECRET timeout');}});
    await assert.rejects(sdk('/test','POST',{}),/outcome unknown/);assert.equal(calls,1);
    assert.throws(()=>createSdk({...app,zone:'evil.invalid'},'SECRET'));
    assert.throws(()=>sdk('//evil.invalid'));
    let active=0,max=0;const paced=createSdk(app,'SECRET',{paceMs:0,fetchImpl:async()=>{active++;max=Math.max(max,active);await new Promise(r=>setTimeout(r,5));active--;return Response.json({ok:true});}});
    await Promise.all([paced('/one'),paced('/two')]);assert.equal(max,1);
});

test('scenario cleanup covers start/run failures and records a stop failure alongside the original failure', async () => {
    for(const stage of ['start','run']){
        const paths=[];await assert.rejects(runInactiveScenario(async(path)=>{paths.push(path);if(path.endsWith('/'+stage))throw new Error(stage);return{};},123),new RegExp(stage));
        assert.equal(paths.at(-1),'/scenarios/123/stop');
    }
    await assert.rejects(runInactiveScenario(async path=>{if(!path.endsWith('/start'))throw new Error(path);return{};},123),e=>e instanceof AggregateError&&e.errors.length===2);
});

test('run evidence is exclusive and leaves historical files and previous checkpoints unchanged', async t => {
    const directory=await temporary(t), historical=new URL('review-qualification-20261028.json',directory);await writeFile(historical,'history');
    const save=evidenceWriter(directory,'qualification',{freeze:'review-freeze-20261028.json'});
    const first=await save({status:'running'}), bytes=await readFile(new URL(first,directory),'utf8');
    const second=await save({status:'failed',cleanupFailures:[123]});assert.notEqual(first,second);
    assert.equal(await readFile(new URL(first,directory),'utf8'),bytes);assert.equal(await readFile(historical,'utf8'),'history');
    assert.equal(JSON.parse(await readFile(new URL(second,directory))).status,'failed');
});

test('SDK timeout aborts once and never exposes transport details', async () => {
    let calls=0;
    const sdk=createSdk(app,'SECRET',{paceMs:0,timeoutMs:10,fetchImpl:(_url,{signal})=>new Promise((_resolve,reject)=>{calls++;signal.addEventListener('abort',()=>reject(new Error('SECRET timeout')));})});
    const keepAlive=setTimeout(()=>{},100);
    try {await assert.rejects(sdk('/test','PATCH',{}),e=>e.message.includes('outcome unknown')&&!e.message.includes('SECRET'));assert.equal(calls,1);}
    finally {clearTimeout(keepAlive);}
});

test('reviewer guards fail closed on foreign ownership or schedules; cleanup failure remains explicit', async () => {
    const context=await json('src/reviewer.json');
    const response=path=>path.startsWith('/organizations/')?{organization:{productName:'Free',autoPurchasingActivated:false}}:
        path.startsWith('/connections/')?{connection:{teamId:app.teamId,organizationId:app.organizationId,authorId:context.ownerId}}:
        {scenario:{id:Number(path.split('/')[2]),teamId:app.teamId,createdByUser:{id:context.ownerId},isActive:false,scheduling:{type:'on-demand'}}};
    await assertReviewerContext(async path=>response(path),app,context);
    for(const foreign of ['owner','team','schedule'])await assert.rejects(assertReviewerContext(async path=>{
        const r=response(path);if(r.scenario){if(foreign==='owner')r.scenario.createdByUser.id++;if(foreign==='team')r.scenario.teamId++;if(foreign==='schedule')r.scenario.scheduling.type='daily';}return r;
    },app,context));
    let active=true;
    const result=await ensureScenariosInactive(async path=>{if(path.endsWith('/stop'))throw new Error('stop failed');return{scenario:{id:1,isActive:active}};},[1]);
    assert.deepEqual(result,{cleanupFailures:[1],bothScenariosInactive:false});
});
