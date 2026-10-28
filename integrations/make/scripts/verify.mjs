import { readFile } from 'node:fs/promises';
import { loadToken, createSdk, evidenceWriter, evidenceDirectory, safeFailure, cleanSourceRevision } from './lib/make-sdk.mjs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root = new URL('../', import.meta.url);
const read = async p => JSON.parse(await readFile(new URL(p, root), 'utf8'));
const app = await read('app.json'), manifest = await read('src/generated/manifest.json');
const sourceRevision=cleanSourceRevision(root);
const get = createSdk(app, await loadToken());
const save = evidenceWriter(evidenceDirectory(), 'readback', {sourceRevision,freeze:'review-freeze-20261028.json'});
try {
const prefix = '/sdk/apps/'+app.name+'/'+app.version;
const meta = (await get(prefix+'?cols[]=name&cols[]=label&cols[]=version&cols[]=description&cols[]=theme&cols[]=language&cols[]=docs&cols[]=public&cols[]=inReview')).app;
for(const field of ['name','label','version','description','theme','language'])assert.equal(meta[field],app[field],'App metadata mismatch: '+field);
assert.equal(meta.docs,await readFile(new URL('SETUP.md',root),'utf8'),'Make README differs from source. Save SETUP.md in the native README editor.');
assert.equal(createHash('sha256').update(meta.docs).digest('hex'),manifest.readmeSha256);
const liveModules=(await get(prefix+'/modules')).appModules;
assert.deepEqual(liveModules.map(m=>m.name).sort(),[...manifest.modules].sort());
for(const module of liveModules){const expected=await read('src/generated/modules/'+module.name+'/module.json');
    for(const field of ['label','description','crud'])if(expected[field]!==undefined)assert.equal(module[field],expected[field],module.name+' '+field);}
assert.deepEqual((await get(prefix+'/rpcs')).appRpcs.map(r=>r.name).sort(),[...manifest.rpcs].sort());
const connections=(await get('/sdk/apps/'+app.name+'/connections')).appConnections;
assert.equal(connections.length,1);assert.equal(connections[0].name,app.connectionName);
const functions=(await get(prefix+'/functions')).appFunctions;assert.equal(functions.length,0,'No parser/prototype functions may remain.');
// Make qualifies local RPC references on save. Normalize only that exact SDK rewrite.
const normalized = value => JSON.parse(JSON.stringify(value).replaceAll('rpc://app%23'+app.name+'@'+app.version+'/occasions', 'rpc://occasions'));
let checked=0;
for(const [path]of Object.entries(manifest.files)){
    if(path==='schemas.json'||path.endsWith('/module.json')||path.endsWith('/rpc.json'))continue;
    const remote=path.startsWith('connections/')?'/sdk/apps/connections/'+app.connectionName+'/'+path.split('/').at(-1).replace('.json','')
        :prefix+'/'+path.replace('.json','');
    assert.deepEqual(normalized(await get(remote)),await read('src/generated/'+path),'Make source mismatch: '+path);checked++;
}
const logoBytes=await get(prefix+'/icon/512','GET',undefined,{binary:true});assert.equal(logoBytes.subarray(1,4).toString(),'PNG');
const receipt={at:new Date().toISOString(),app:app.name,version:app.version,zone:app.zone,definitionSectionsMatched:checked,
    generatedManifestSha256:createHash('sha256').update(await readFile(new URL('src/generated/manifest.json',root))).digest('hex'),
    sourceLogoSha256:manifest.logoSha256,renderedLogoSha256:createHash('sha256').update(logoBytes).digest('hex'),
    visibilityAtReadback:meta.public?'public':'private',inReview:meta.inReview??meta.in_review??null,
    reviewStateSource:'SDK selected inReview field when available; native Review tab and confirmation email retain the workflow history.',
    modules:manifest.modules,connectionCount:1,rpcCount:1,prototypeFunctionCount:0,tokenValuesIncluded:false};
await save({...receipt,status:'verified'});
process.stdout.write('PASS: live Make definitions, metadata, README and logo match the frozen source; '+checked+' sections verified.\n');

} catch(error) { await save({status:'failed',error:safeFailure(error)}); throw error; }
