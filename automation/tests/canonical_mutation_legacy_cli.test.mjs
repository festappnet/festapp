import test from 'node:test';import assert from 'node:assert/strict';import {assertLegacyUrlRewriteAllowed} from '../image-migration/lib/canonical-write-boundary.js';
test('historical bulk rewrite cannot write canonical or unidentified targets',async()=>{
 for(const rows of [[{canonical_mutations:true}],[],[{}]]) await assert.rejects(assertLegacyUrlRewriteAllowed({query:async()=>({rows})}),/Legacy URL rewrite is disabled/);
 await assert.rejects(assertLegacyUrlRewriteAllowed({query:async()=>{throw Error('metadata unavailable')}}),/metadata unavailable/);
});
test('read-only recovery and explicitly unprotected targets retain their prior behavior',async()=>{
 await assertLegacyUrlRewriteAllowed({query:()=>{assert.fail('dry run does not need a write eligibility probe')}},{dryRun:true});
 await assertLegacyUrlRewriteAllowed({query:async()=>({rows:[{canonical_mutations:false}]})});
});
