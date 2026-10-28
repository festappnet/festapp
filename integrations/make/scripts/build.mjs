import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { Operations } from '../../../tools/festapp/src/operations/catalog.mjs';
import { MAKE_READ_OPERATIONS } from '../../../tools/festapp/src/remote/make-transport.mjs';
import { scopesForOperation } from '../../../packages/festapp_contracts/mcp-permissions.mjs';
const { z } = createRequire(new URL('../../../tools/festapp/package.json', import.meta.url))('zod');
const root = new URL('../', import.meta.url), check = process.argv.includes('--check');
const read = async p => JSON.parse(await readFile(new URL(p, root), 'utf8'));
const app = await read('app.json'), draft = await read('catalog-draft.json');
const samples = await read('src/samples.json'), connection = await read('src/connection.json');
const ops = new Operations({ root: fileURLToPath(root), orderSummaryOnly: true, allowedOperations: MAKE_READ_OPERATIONS });
const catalog = new Map(ops.catalog.map(d => [d.id, d]));
const schemas = Object.fromEntries([...catalog].map(([id,d]) => [id, { input: z.toJSONSchema(d.input, { io: 'input' }), output: z.toJSONSchema(d.output, { io: 'output' }) }]));
const title = value => value.replace(/([a-z])([A-Z])/g, '$1 $2').replaceAll('_',' ').replaceAll('.', ' ').toLowerCase()
    .replace(/occasion/g, 'event').replace(/\bid\b/g, 'ID').replace(/^./, s => s.toUpperCase());
function concrete(schema) {
    const s = schema?.anyOf ? schema.anyOf.find(x => x.type !== 'null') ?? {} : schema ?? {};
    return Array.isArray(s.type) ? { ...s, type: s.type.find(type => type !== 'null') } : s;
}
function inferred(value) {
    if (value === null || value === undefined) return {};
    if (Array.isArray(value)) return { type: 'array', items: inferred(value[0]) };
    if (typeof value === 'object') return { type: 'object', properties: Object.fromEntries(Object.entries(value).map(([k,v]) => [k,inferred(v)])) };
    return { type: typeof value };
}
function field(name, schema, sample) {
    const s = concrete(schema), effective = s.type ? s : inferred(sample);
    const out = { name, label: title(name), type: ({ string: 'text', integer: 'number', number: 'number', boolean: 'boolean', object: 'collection', array: 'array' })[effective.type] ?? 'any' };
    if (name === 'generated_at' || effective.format === 'date-time') out.type = 'date';
    if (effective.type === 'object') {
        const props = { ...effective.properties };
        if (s.additionalProperties !== false && sample && typeof sample === 'object')
            for (const [k,v] of Object.entries(sample)) props[k] ??= inferred(v);
        out.spec = Object.entries(props).map(([k,v]) => field(k,v,sample?.[k]));
    }
    if (effective.type === 'array') {
        const item = field('item', effective.items, sample?.[0]); delete item.name; delete item.label; out.spec = item;
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
const limit = { name: 'limit', type: 'uinteger', label: 'Limit', default: 10,
    help: 'The maximum number of results to be worked with during one execution cycle. Clear this field to return all results within the documented technical limits.', validate: { min: 1, max: 3200 } };
const errorMessage = "[{{statusCode}}] {{ifempty(body.error.code, ifempty(body.error, 'REQUEST_FAILED'))}}: {{switch(body.error.code, 'FORBIDDEN', 'You do not have access to this event or operation.', 'INVALID_INPUT', 'Check the event ID, order ID and input values.', 'PAGINATION_LIMIT_EXCEEDED', 'The requested export exceeds the technical pagination limit.', ifempty(body.error.message, 'The request could not be completed.'))}}";
const base = { baseUrl: 'https://mcp.vstupenky.online', headers: { authorization: 'Bearer {{connection.accessToken}}', accept: 'application/json' },
    response: { valid: '{{body.ok}}', error: { message: errorMessage } },
    log: { sanitize: ['request.headers.authorization','request.headers.Authorization'] } };
const files = new Map(), put = (p,v) => files.set(p,JSON.stringify(v,null,2)+'\n');
connection.info.response.error.message = errorMessage;
put('base.json',base); put('connections/api.json',connection);
put('connections/common.json',{clientId:'festapp-make'});
put('connections/parameters.json',[{name:'accountLabel',type:'text',label:'Connection label',help:'Name this connection to distinguish it from connections to other accounts or events.'}]);
put('connections/scope.json',['openid','offline_access',...draft.allowedScopes]);
put('connections/scopes.json',Object.fromEntries(['openid','offline_access',...draft.allowedScopes].map(s=>[s,s])));
put('schemas.json',schemas);
const modules = [];
for (const m of draft.modules) {
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
        put(path+'scope.json',[...draft.allowedScopes]);put(path+'samples.json',{});
        put(path+'module.json',{name:m.key,label:m.label,description:m.description,typeId:12,connection:app.connectionName});
    } else {
        const d=catalog.get(m.operation);assert(d?.domainReadOnly, 'Only canonical read operations can be generated');
        const s=schemas[m.operation].input, spec=Object.entries(s.properties).filter(([name])=>name!=='before'&&name!=='limit').map(([name,schema])=>input(name,schema,s.required?.includes(name)));
        const list=['access.inspect','orders.list'].includes(m.operation);
        if (!list) for(const parameter of spec) if(parameter.name==='occasionId') parameter.mode='edit';
        if(list)spec.push(limit);
        const body=Object.fromEntries(Object.entries(s.properties).filter(([name])=>name!=='before').map(([name])=>[name,name==='limit'?50:s.required?.includes(name)?'{{parameters.'+name+'}}':'{{ifempty(parameters.'+name+', omit)}}']));
        const api={url:'/make/v1/operations/'+m.operation,method:'POST',type:'json',body,response:{output:'{{body.data}}'}};
        let output=schemas[m.operation].output.properties.data;
        if(list){const collection=m.operation==='access.inspect'?'occasions':'orders';api.response={iterate:'{{body.data.'+collection+'}}',output:'{{item}}',limit:"{{if(contains(keys(parameters), 'limit'), ifempty(parameters.limit, 3200), 10)}}"};output=output.properties[collection].items;}
        if(m.operation==='orders.inspect'){api.response.output='{{first(body.data.orders)}}';output=output.properties.orders.items;}
        if(m.operation==='orders.report')api.response.output="{{set(body.data, 'report.generated_at', parseDate(body.data.report.generated_at))}}";
        if(m.operation==='orders.list'){
            api.headers={'x-festapp-make-page':'{{ifempty(pagination.page, 1)}}','x-festapp-make-total-limit':'{{parameters.limit}}'};
            api.pagination={condition:'{{body.data.nextCursor != null}}',body:{...body,before:'{{body.data.nextCursor}}'}};
        }
        const sample=samples[m.operation];
        const dataSchema=d.output.shape.data.unwrap();
        dataSchema.parse(m.operation==='orders.report'?sample:m.operation==='access.inspect'?{units:[],occasions:[sample]}:{occasionId:sample.occasionId,orders:[sample],nextCursor:null});
        const out=field('data',output,sample);
        put(path+'module.json',{name:m.key,label:m.label,description:m.description,typeId:list?9:4,connection:app.connectionName,crud:'read'});
        put(path+'api.json',api);put(path+'expect.json',spec);put(path+'interface.json',out.spec??[]);put(path+'scope.json',scopesForOperation(m.operation));put(path+'samples.json',sample);
    }
    modules.push(m.key);
}
put('rpcs/occasions/api.json',{url:'/make/v1/operations/access.inspect',method:'POST',type:'json',body:{},response:{limit:500,iterate:'{{body.data.occasions}}',output:{label:'{{item.title}} ({{item.id}})',value:'{{item.id}}'}}});
put('rpcs/occasions/parameters.json',[]);
put('rpcs/occasions/rpc.json',{name:'occasions',label:'Accessible events',connection:app.connectionName});
put('groups.json',[{label:'Events',modules:['listOccasions','salesReport']},{label:'Orders',modules:['listOrders','getOrder']},{label:'Other',modules:['apiCall']}]);
const manifest={app:app.name,version:app.version,metadata:app,readmeSha256:createHash('sha256').update(await readFile(new URL('SETUP.md',root))).digest('hex'),logoSha256:createHash('sha256').update(await readFile(new URL('../chatgpt/assets/logo.png',root))).digest('hex'),modules,rpcs:['occasions'],files:Object.fromEntries([...files].map(([p,s])=>[p,createHash('sha256').update(s).digest('hex')]))};
put('manifest.json',manifest);
for(const [p,s]of files){const target=new URL('src/generated/'+p,root);if(check){assert.equal(await readFile(target,'utf8'),s,'Canonical generated drift: '+p);}else{await mkdir(new URL('.',target),{recursive:true});await writeFile(target,s);}}
process.stdout.write((check?'PASS: canonical source/export match; ':'Built ')+files.size+' files, five modules, one connection, one transport.\n');
