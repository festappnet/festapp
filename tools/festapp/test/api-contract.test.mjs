import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { publicCatalog, readiness } from '../src/remote/api-contract.mjs';
import { schemaBreaks, compatibilityBreaks } from '../scripts/check-api-compatibility.mjs';

test('contract exposes only supported operations and distinct summary output from canonical runtime schemas',()=>{
    const operator=JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/regional-api/openapi.json',import.meta.url)));
    const summary=JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/regional-api/profiles/order-summary/openapi.json',import.meta.url)));
    assert.equal(operator.openapi,'3.2.1');
    assert.equal(operator['x-oauth-resource'],'https://api.vstupenky.online/integrations');
    assert.deepEqual(Object.values(operator.paths).map(p=>p.post.operationId).sort(),[...publicCatalog().filter(d=>readiness(d).supported).map(d=>d.id),'artifacts.read'].sort());
    assert.notDeepEqual(operator.components.schemas['orders.list.Output'],summary.components.schemas['orders.list.Output']);
    for(const d of publicCatalog())assert.equal(typeof readiness(d).supported,'boolean');
    assert(!operator.paths['/operations/orders.cancel']);
});

test('directional compatibility catches request narrowing, response widening, required, limits, media and security changes',()=>{
    const base={type:'string',enum:['a','b']};
    assert.equal(schemaBreaks(base,{type:'string',enum:['a','b','c']},'request').length,0);
    assert(schemaBreaks(base,{type:'string',enum:['a']},'request').length);
    assert.equal(schemaBreaks(base,{type:'string',enum:['a']},'response').length,0);
    assert(schemaBreaks(base,{type:'string',enum:['a','b','c']},'response').length);
    assert(schemaBreaks({type:'object',properties:{x:{type:'string'}}},{type:'object',properties:{x:{type:'string'}},required:['x']},'request').length);
    assert(schemaBreaks({type:'integer',maximum:50},{type:'integer',maximum:25},'request').length);
    assert(schemaBreaks({type:'string',default:'a'},{type:'string',default:'b'},'request').length);
    const spec=JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/global-api/openapi.json',import.meta.url)));
    assert.deepEqual(compatibilityBreaks(spec,spec),[]);
    const changed=structuredClone(spec);delete changed.paths['/operations/context.inspect'].post.responses['200'].content['application/json'];
    assert(compatibilityBreaks(spec,changed).length);
    const shape=structuredClone(spec);shape.components.schemas['products.list.Input'].properties.limit.maximum=1;
    assert(compatibilityBreaks(spec,shape).length,'referenced component changes must be compared, not only identical $ref strings');
    const security=structuredClone(spec);security.paths['/operations/context.inspect'].post.security=[];
    assert(compatibilityBreaks(spec,security).length);
});

test('schema 3 requires explicit API policy and preserves Make identity, regional resource and summary ceiling',()=>{
    const example=JSON.parse(fs.readFileSync(new URL('../examples/unified-api-config.json',import.meta.url)));
    // Import is synchronous at module scope in runtime; the test never calls a backend.
    return import('../src/remote/config.mjs').then(({parseRemoteConfig})=>{
        const longer=structuredClone(example);longer.clients[0].maxConsentDays=365;assert.equal(parseRemoteConfig(longer).clients[0].maxConsentDays,365);
        const parsed=parseRemoteConfig(example);assert.equal(parsed.clients.find(c=>c.id==='festapp-make').maxConsentDays,7);
        for(const mutate of [
            c=>delete c.clients[0].allowedOperations,
            c=>c.clients[0].allowedOperations.push('unknown.operation'),
            c=>c.clients[1].dataProfile='operator',
            c=>c.clients[1].resources.push(c.issuer+'/mcp'),
            c=>c.clients[1].resources.push(c.endpoints[0].resource),
            c=>c.clients[1].redirectUris=['https://attacker.example/callback'],
            c=>c.endpoints[1].profilePolicy={type:'selected'},
            c=>c.endpoints[1].issuer='https://mcp.vstupenky.online',
            c=>{c.issuer='https://mcp.vstupenky.online';c.endpoints.forEach(e=>e.issuer=c.issuer);},
        ]){const changed=structuredClone(example);mutate(changed);assert.throws(()=>parseRemoteConfig(changed));}
    });
});

 test('proof projections require OAuth and DPoP together without changing data schemas',()=>{
 const read=proof=>JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/global-api/'+(proof==='dpop'?'proofs/dpop/':'')+'openapi.json',import.meta.url)));
 const bearer=read('bearer'),bound=read('dpop');
 for(const route of Object.values(bound.paths)){assert.equal(route.post.security.length,1);assert.deepEqual(route.post.security[0].dpop,[]);assert(route.post.security[0].oauth);assert(route.post.parameters.some(p=>p.name==='DPoP'&&p.required));}
 assert.deepEqual(bearer.components.schemas,bound.components.schemas);assert.notEqual(bearer['x-projection-digest'],bound['x-projection-digest']);
 });

 test('published success examples show success and preview PNG/PDF schemas remain explicit',()=>{
 const spec=JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/global-api/openapi.json',import.meta.url)));
 for(const [path,route] of Object.entries(spec.paths)){const example=route.post.responses['200'].content['application/json']?.example;if(example){assert.equal(example.ok,true,path);assert(!example.error);}}
 const preview=spec.paths['/operations/ticket_layouts.preview'].post.responses['200'].content['application/json'].example;
 assert.equal(preview.data.image.mimeType,'image/png');assert.equal(preview.data.pdf.mimeType,'application/pdf');
 });
