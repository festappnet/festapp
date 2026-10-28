import { readFile, writeFile, mkdir, readdir, lstat, unlink, rmdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { Operations } from '../../../tools/festapp/src/operations/catalog.mjs';
import { MAKE_CLIENT_ID, MAKE_READ_OPERATIONS, MAKE_SCOPES, MAKE_LIMITS } from '../../../tools/festapp/src/remote/make-contract.mjs';
import { scopesForOperation } from '../../../packages/festapp_contracts/mcp-permissions.mjs';
const { z } = createRequire(new URL('../../../tools/festapp/package.json', import.meta.url))('zod');
const root = new URL('../', import.meta.url);
export async function assemble({ samples: sampleOverride, presentation: presentationOverride } = {}) {
const read = async p => JSON.parse(await readFile(new URL(p, root), 'utf8'));
const app = await read('app.json'), presentation = presentationOverride ?? await read('src/catalog.json');
const samples = sampleOverride ?? await read('src/samples.json'), connection = await read('src/connection.json');
const ops = new Operations({ root: fileURLToPath(root), orderSummaryOnly: true, allowedOperations: MAKE_READ_OPERATIONS });
const catalog = new Map(ops.catalog.map(d => [d.id, d]));
const schemas = Object.fromEntries([...catalog].map(([id,d]) => [id, { input: z.toJSONSchema(d.input, { io: 'input' }), output: z.toJSONSchema(d.output, { io: 'output' }) }]));
const title = value => value.replace(/([a-z])([A-Z])/g, '$1 $2').replaceAll('_',' ').replaceAll('.', ' ').toLowerCase()
    .replace(/occasion/g, 'event').replace(/\bid\b/g, 'ID').replace(/^./, s => s.toUpperCase());
// Make has no scalar union type. Mixed non-null types use `any` without
// coercion; nullable single types retain their declared Make type.
function concrete(schema = {}) {
    const alternatives = schema.anyOf ?? (Array.isArray(schema.type) ? schema.type.map(type => ({ ...schema, type })) : [schema]);
    const values = alternatives.filter(s => s.type !== 'null');
    return values.length === 1 ? values[0] : {};
}
function field(name, schema) {
    const effective = concrete(schema);
    const out = { name, label: title(name), type: ({ string: 'text', integer: 'number', number: 'number', boolean: 'boolean', object: 'collection', array: 'array' })[effective.type] ?? 'any' };
    if (effective.format === 'date-time') out.type = 'date';
    if (effective.type === 'object') {
        // Dynamic records have no fixture-owned keys. A collection preserves
        // their values; schemas.json retains the canonical value schema.
        out.spec = Object.entries(effective.properties ?? {}).map(([k,v]) => field(k,v));
    }
    if (effective.type === 'array') {
        const item = field('item', effective.items); delete item.name; delete item.label; out.spec = item;
    }
    return out;
}
function input(name, schema, required) {
    const s = concrete(schema), out = field(name,schema);
    delete out.spec;
    if (required) out.required = true;
    if (s.default !== undefined) out.default = s.default;
    if (s.description) out.help = s.description;
    const validate = {};
    if (s.minimum !== undefined) validate.min = s.minimum;
    if (s.maximum !== undefined) validate.max = s.maximum;
    if (s.maxLength !== undefined) validate.max = s.maxLength;
    if (s.pattern) validate.pattern = s.pattern;
    if (Object.keys(validate).length) out.validate = validate;
    if (name === 'occasionId') {
        delete out.validate;
        Object.assign(out, { label: 'Event ID', type: 'select', options: 'rpc://occasions', mappable: true,
            help: 'Select one consented event by its ID. Events with the same name remain separate.' });
    }
    return out;
}
const limit = { name: 'limit', type: 'uinteger', label: 'Limit', default: MAKE_LIMITS.defaultTotal,
    help: 'The maximum number of results to be worked with during one execution cycle. Clear this field to return all results within the documented technical limits.', validate: { min: 1, max: MAKE_LIMITS.totalInputCap } };
const errorMessage = "[{{statusCode}}] {{ifempty(body.error.code, ifempty(body.error, 'REQUEST_FAILED'))}}: {{switch(body.error.code, 'FORBIDDEN', 'You do not have access to this event or operation.', 'INVALID_INPUT', 'Check the event ID, order ID and input values.', 'PAGINATION_LIMIT_EXCEEDED', 'The requested export exceeds the technical pagination limit.', ifempty(body.error.message, 'The request could not be completed.'))}}";
const base = { baseUrl: 'https://mcp.vstupenky.online', headers: { authorization: 'Bearer {{connection.accessToken}}', accept: 'application/json' },
    response: { valid: '{{body.ok}}', error: { message: errorMessage } },
    log: { sanitize: ['request.headers.authorization','request.headers.Authorization'] } };
const files = new Map(), put = (p,v) => files.set(p,JSON.stringify(v,null,2)+'\n');
connection.info.response.error.message = errorMessage;
put('base.json',base); put('connections/api.json',connection);
put('connections/common.json',{clientId:MAKE_CLIENT_ID});
put('connections/parameters.json',[{name:'accountLabel',type:'text',label:'Connection label',help:'Name this connection to distinguish it from connections to other accounts or events.'}]);
put('connections/scope.json',['openid','offline_access',...MAKE_SCOPES]);
put('connections/scopes.json',Object.fromEntries(['openid','offline_access',...MAKE_SCOPES].map(s=>[s,s])));
put('schemas.json',schemas);
const modules = [];
assert.equal(new Set(presentation.modules.map(m => m.key)).size, presentation.modules.length, 'Duplicate module key');
for (const m of presentation.modules) {
    assert(/^[A-Za-z][A-Za-z0-9]*$/.test(m.key), 'Invalid module key');
    assert(m.group && (!m.operation || (MAKE_READ_OPERATIONS.includes(m.operation) && catalog.get(m.operation)?.domainReadOnly)), 'Unknown or writable operation');
}
for (const m of presentation.modules) {
    const path = 'modules/'+m.key+'/';
    if (!m.operation) {
        const cases = MAKE_READ_OPERATIONS.flatMap(id=>[JSON.stringify('/make/v1/operations/'+id),JSON.stringify('/make/v1/operations/'+id)]).join(', ');
        const url = "https://mcp.vstupenky.online{{switch(parameters.url, "+cases+", '/make/v1/operations/forbidden')}}";
        put(path+'api.json',{ url, method:"{{ifempty(parameters.method, 'POST')}}", type:'raw',
            headers:{'{{...}}':"{{pick(toCollection(parameters.headers, 'key', 'value'), 'Accept', 'Content-Type', 'X-Request-ID')}}",'content-type':'application/json',authorization:'Bearer {{connection.accessToken}}'},
            qs:{'{{...}}':"{{toCollection(parameters.qs, 'key', 'value')}}"},
            body:"{{ifempty(parameters.body, '{}')}}", response:{output:{body:'{{body}}',headers:'{{headers}}',statusCode:'{{statusCode}}'}},log:{sanitize:['request.body','request.headers.authorization','request.headers.Authorization']} });
        const pairs=[{name:'key',label:'Key',type:'text'},{name:'value',label:'Value',type:'text'}];
        put(path+'expect.json',[{name:'url',label:'URL',type:'text',required:true,help:'Enter a path relative to https://mcp.vstupenky.online, for example /make/v1/operations/context.inspect. This API exposes five authorized read operations only.'},
            {name:'method',label:'Method',type:'select',required:true,default:'POST',options:['GET','POST','PUT','PATCH','DELETE','HEAD','OPTIONS'].map(value=>({label:value,value})),help:'The current read API supports POST; unsupported methods return HTTP 405.'},
            {name:'headers',label:'Headers',type:'array',spec:pairs,help:'Supported additional headers: Accept, Content-Type and X-Request-ID. Authorization is supplied by the connection; authentication, host and pagination-control overrides are not forwarded.'},
            {name:'qs',label:'Query string',type:'array',spec:pairs},
            {name:'body',label:'Body',type:'text',default:'{}',help:'JSON object matching the canonical operation input. POST is the only transport method.'}]);
        put(path+'interface.json',[{name:'body',label:'Body',type:'collection'},{name:'headers',label:'Headers',type:'collection'},{name:'statusCode',label:'Status code',type:'number'}]);
        put(path+'scope.json',[...MAKE_SCOPES]);put(path+'samples.json',{});
        put(path+'module.json',{name:m.key,label:m.label,description:m.description,typeId:12,connection:app.connectionName});
    } else {
        const d=catalog.get(m.operation);assert(d?.domainReadOnly, 'Only canonical read operations can be generated');
        const s=schemas[m.operation].input, spec=Object.entries(s.properties).filter(([name])=>name!=='before'&&name!=='limit').map(([name,schema])=>input(name,schema,s.required?.includes(name)));
        const list=['access.inspect','orders.list'].includes(m.operation);
        if (!list) for(const parameter of spec) if(parameter.name==='occasionId') parameter.mode='edit';
        if(list)spec.push(limit);
        const body=Object.fromEntries(Object.entries(s.properties).filter(([name])=>name!=='before').map(([name])=>[name,name==='limit'?MAKE_LIMITS.pageSize:s.required?.includes(name)?'{{parameters.'+name+'}}':'{{ifempty(parameters.'+name+', omit)}}']));
        const api={url:'/make/v1/operations/'+m.operation,method:'POST',type:'json',body,response:{output:'{{body.data}}'}};
        let output=schemas[m.operation].output.properties.data;
        if(list){const collection=m.operation==='access.inspect'?'occasions':'orders';api.response={iterate:'{{body.data.'+collection+'}}',output:'{{item}}',limit:`{{if(contains(keys(parameters), 'limit'), ifempty(parameters.limit, ${MAKE_LIMITS.totalInputCap}), ${MAKE_LIMITS.defaultTotal})}}`};output=output.properties[collection].items;}
        if(m.operation==='orders.inspect'){api.response.output='{{first(body.data.orders)}}';output=output.properties.orders.items;}
        if(m.operation==='orders.report')api.response.output="{{set(body.data, 'report.generated_at', parseDate(body.data.report.generated_at))}}";
        if(m.operation==='orders.list'){
            api.headers={'x-festapp-make-page':'{{ifempty(pagination.page, 1)}}','x-festapp-make-total-limit':'{{parameters.limit}}'};
            api.pagination={condition:'{{body.data.nextCursor != null}}',body:{...body,before:'{{body.data.nextCursor}}'}};
        }
        const sample=samples[m.operation];
        const dataSchema=d.output.shape.data.unwrap();
        dataSchema.parse(m.operation==='orders.report'?sample:m.operation==='access.inspect'?{units:[],occasions:[sample]}:{occasionId:sample.occasionId,orders:[sample],nextCursor:null});
        const out=field('data',output);
        put(path+'module.json',{name:m.key,label:m.label,description:m.description,typeId:list?9:4,connection:app.connectionName,crud:'read'});
        put(path+'api.json',api);put(path+'expect.json',spec);put(path+'interface.json',out.spec??[]);put(path+'scope.json',scopesForOperation(m.operation));put(path+'samples.json',sample);
    }
    modules.push(m.key);
}
put('rpcs/occasions/api.json',{url:'/make/v1/operations/access.inspect',method:'POST',type:'json',body:{},response:{limit:MAKE_LIMITS.rpcSampleLimit,iterate:'{{body.data.occasions}}',output:{label:'{{item.title}} ({{item.id}})',value:'{{item.id}}'}}});
put('rpcs/occasions/parameters.json',[]);
put('rpcs/occasions/rpc.json',{name:'occasions',label:'Accessible events',connection:app.connectionName});
put('groups.json',[...new Set(presentation.modules.map(m=>m.group))].map(label=>({label,modules:presentation.modules.filter(m=>m.group===label).map(m=>m.key)})));
const manifest={app:app.name,version:app.version,metadata:app,readmeSha256:createHash('sha256').update(await readFile(new URL('SETUP.md',root))).digest('hex'),logoSha256:createHash('sha256').update(await readFile(new URL('../chatgpt/assets/logo.png',root))).digest('hex'),modules,rpcs:['occasions'],files:Object.fromEntries([...files].map(([p,s])=>[p,createHash('sha256').update(s).digest('hex')]))};
put('manifest.json',manifest);
return files;
}

// Never follow symlinks, including the generated root. Only this tree is owned.
async function inventory(directory, prefix = '') {
    const stat = await lstat(fileURLToPath(directory).replace(/\/$/, ''));
    assert(stat.isDirectory() && !stat.isSymbolicLink(), 'Generated directory must be a real directory');
    const paths = [];
    for (const entry of await readdir(directory, { withFileTypes: true })) {
        assert(!entry.isSymbolicLink(), 'Symlink in generated tree');
        const path = prefix + entry.name;
        if (entry.isDirectory()) paths.push(...await inventory(new URL(entry.name+'/', directory), path+'/'));
        else { assert(entry.isFile(), 'Non-regular generated file'); paths.push(path); }
    }
    return paths;
}
export async function writeGenerated(files, { check = false, directory = new URL('src/generated/', root) } = {}) {
    try { await lstat(directory); } catch (error) { if (error.code !== 'ENOENT' || check) throw error; await mkdir(directory, {recursive:true}); }
    const actual = await inventory(directory);
    if (check) assert.deepEqual(actual.sort(), [...files.keys()].sort(), 'Generated file set drift');
    else for (const path of actual) if (!files.has(path)) await unlink(new URL(path, directory));
    for (const [path, content] of files) {
        assert(!path.split('/').some(p => p === '..' || p === '') && !path.startsWith('/'), 'Invalid generated path');
        const target = new URL(path, directory);
        if (check) assert.equal(await readFile(target,'utf8'), content, 'Canonical generated drift: '+path);
        else { await mkdir(new URL('.',target),{recursive:true}); await writeFile(target,content); }
    }
    if (!check) {
        const prune = async dir => { for(const e of await readdir(dir,{withFileTypes:true})) if(e.isDirectory()) {const child=new URL(e.name+'/',dir);await prune(child);if(!(await readdir(child)).length)await rmdir(child);} };
        await prune(directory);
    }
}
if (process.argv[1] && fileURLToPath(import.meta.url) === fileURLToPath(new URL('file://' + process.argv[1]))) {
    const files = await assemble();
    await writeGenerated(files, {check:process.argv.includes('--check')});
    process.stdout.write('PASS: canonical generated tree ('+files.size+' files).\n');
}
