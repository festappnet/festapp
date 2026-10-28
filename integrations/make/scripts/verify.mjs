import { readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root = new URL('../', import.meta.url);
const read = async p => JSON.parse(await readFile(new URL(p, root), 'utf8'));
const app = await read('app.json'), manifest = await read('src/generated/manifest.json');
const token = (await readFile(homedir()+'/.config/festapp/make-api-token','utf8')).trim();
let lastRead = 0;
const get = async path => {
    await new Promise(resolve => setTimeout(resolve, Math.max(0, lastRead + 2200 - Date.now())));
    lastRead = Date.now();
    const response = await fetch('https://'+app.zone+'/api/v2'+path,{headers:{authorization:'Token '+token}});
    assert(response.ok, 'Readback failed: '+path+' HTTP '+response.status);
    const text = await response.text(); return JSON.parse(text);
};
const prefix = '/sdk/apps/'+app.name+'/'+app.version;
const meta = (await get(prefix+'?cols[]=name&cols[]=label&cols[]=version&cols[]=description&cols[]=theme&cols[]=language&cols[]=docs&cols[]=public&cols[]=inReview')).app;
for(const field of ['name','label','version','description','theme','language'])assert.equal(meta[field],app[field],'App metadata mismatch: '+field);
assert.equal(meta.docs,await readFile(new URL('SETUP.md',root),'utf8'),'Make README differs from source. Save SETUP.md in the native README editor.');
assert.equal(createHash('sha256').update(meta.docs).digest('hex'),manifest.readmeSha256);
assert.deepEqual((await get(prefix+'/modules')).appModules.map(m=>m.name).sort(),[...manifest.modules].sort());
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
const logo=await fetch('https://'+app.zone+'/api/v2'+prefix+'/icon/512',{headers:{authorization:'Token '+token}});
assert(logo.ok,'Make app logo must be present');
const logoBytes=Buffer.from(await logo.arrayBuffer());assert.equal(logoBytes.subarray(1,4).toString(),'PNG');
const receipt={at:new Date().toISOString(),app:app.name,version:app.version,zone:app.zone,definitionSectionsMatched:checked,
    generatedManifestSha256:createHash('sha256').update(await readFile(new URL('src/generated/manifest.json',root))).digest('hex'),
    sourceLogoSha256:manifest.logoSha256,renderedLogoSha256:createHash('sha256').update(logoBytes).digest('hex'),
    visibilityAtReadback:meta.public?'public':'private',inReview:meta.inReview??meta.in_review??false,
    modules:manifest.modules,connectionCount:1,rpcCount:1,prototypeFunctionCount:0,tokenValuesIncluded:false};
await writeFile(new URL('evidence/source-readback-20261028.json',root),JSON.stringify(receipt,null,2)+'\n');
process.stdout.write('PASS: live Make definitions, metadata, README and logo match the frozen source; '+checked+' sections verified.\n');
