import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {API_DATA_PROFILES,API_PROOF_PROFILES,apiProjectionDirectory} from '../src/remote/endpoints.mjs';
for(const endpoint of ['global-api','regional-api'])for(const profile of API_DATA_PROFILES)for(const proof of API_PROOF_PROFILES)test(`offline reference ${endpoint}/${profile}/${proof} contains schema bundle and matching manifest`,()=>{
    const dir=new URL('../contracts/api-v1/'+apiProjectionDirectory(endpoint,profile,proof)+'/',import.meta.url);
    const manifest=JSON.parse(fs.readFileSync(new URL('manifest.json',dir)));
    const spec=JSON.parse(fs.readFileSync(new URL('openapi.json',dir)));
    const snapshot=JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/'+endpoint+'/contracts/'+manifest.projectionDigest+'/openapi.json',import.meta.url)));
    assert.deepEqual(snapshot,spec);assert.equal(manifest.proofProfile,proof);
    const html=fs.readFileSync(new URL('docs/index.html',dir),'utf8');
    assert(html.includes(manifest.projectionDigest));assert.equal(manifest.projectionDigest,spec['x-projection-digest']);
    assert(html.includes('products.list')||profile==='order-summary');
    assert(html.includes('commandId'));assert(html.includes("connect-src 'none'"));
    assert(!html.includes('https://cdn.redoc.ly/redoc/logo-mini-full.svg'));
    assert(!/<(?:script|link|img)[^>]+(?:src|href)=["']https?:\/\//i.test(html));
    assert(html.length>100000,'full bundled reference, not a route list');
});
