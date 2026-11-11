import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {compilationProvenance} from '../lib/web_build_cache.mjs';
import {fixture} from './web_build_fixture.mjs';

test('canonical receipt receives compact original compiler provenance and full packaging fingerprint',t=>{
 const f=fixture(t);f.put('build/web/main.js','compiled');const target='cloudflare';const records=f.components(target);
 for(const [c,record]of Object.entries(records))f.put(`build/web-components/${c}.json`,JSON.stringify(record));
 const initial=compilationProvenance(f.root,target,f.tools);
 assert.equal(initial.components.flutter.source,records.flutter.source);assert.equal(initial.components.flutter.outputHash,records.flutter.outputHash);
 f.put('automation/release/help/topic.html','fresh help');const changed=compilationProvenance(f.root,target,f.tools);
 assert.deepEqual(changed.components,initial.components);assert.notEqual(changed.inputFingerprints.bundle,initial.inputFingerprints.bundle);
});
test('missing or changed raw compiler provenance cannot seal the canonical receipt',t=>{
 const f=fixture(t);f.put('build/web/main.js','compiled');const records=f.components('static');
 for(const [c,record]of Object.entries(records))f.put(`build/web-components/${c}.json`,JSON.stringify(record));
 delete records.flutter.source;f.put('build/web-components/flutter.json',JSON.stringify(records.flutter));
 assert.throws(()=>compilationProvenance(f.root,'static',f.tools),/provenance invalid/);
});
