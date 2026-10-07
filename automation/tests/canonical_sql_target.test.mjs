import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {executeProtectedCanonicalSql,loadCanonicalTarget} from '../lib/canonical_sql_target.mjs';

test('issued API tenant config accepts derived profile, rejects Studio/cloud and incorrect pin',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'canonical-target-test-'));
 const configFile=path.join(root,'project.conf');
 const config=origin=>`BACKEND_ACTIVATION_PHASE=canonical\nBACKEND_ACTIVATION_TENANT_ID=csmostrava2026\nBACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=${origin}\nBACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=public-fixture\nBACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=12\nFORCE_OCCASION_LINK=csmostrava2026\nWEB_LINK=https://csmostrava.festapp.net\n`;
 try {
  fs.writeFileSync(configFile,config('https://api.festapp.net'));
  const target=loadCanonicalTarget(root,{configFile});
  assert.equal(target.organization,12);
  assert.match(target.profileSha256,/^[a-f0-9]{64}$/);
  for(const origin of ['https://supabase.festapp.net','https://fixture.supabase.co']) {
   fs.writeFileSync(configFile,config(origin));assert.throws(()=>loadCanonicalTarget(root,{configFile}),/API origin/);
  }
  fs.writeFileSync(configFile,config('https://api.festapp.net')+'BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256=wrong\n');
  assert.throws(()=>loadCanonicalTarget(root,{configFile}),/profile mismatch/);
 } finally {fs.rmSync(root,{recursive:true,force:true});}
});

function executor(identity='backend-01\nruntime_123\n') {
 const calls=[];
 const run=async (command,args,input)=>{
  calls.push({command,args,input});
  return {stdout:calls.length===1?JSON.stringify({expected_hostname:'backend-01',database:'runtime_123'}):calls.length===2?identity:'[{"ok":1}]'};
 };
 return {calls,run};
}
const request={root:'/project',guard:'DO $scope$ BEGIN END $scope$;',query:'SELECT 1 AS ok;',operation:'read'};
test('protected SQL validates host/runtime and returns rows from a read-only transaction',async()=>{
 const mock=executor();
 assert.deepEqual(await executeProtectedCanonicalSql(request,mock),[{ok:1}]);
 const call=mock.calls[2];
 assert.match(call.args.at(-1),/-d 'runtime_123'/);
 assert.match(call.input,/^BEGIN READ ONLY;/);
 assert.match(call.input,/current_database\(\)<>'runtime_123'/);
 assert.match(call.input,/SELECT COALESCE\(jsonb_agg/);
 assert.match(call.input,/ROLLBACK;$/);
 assert.ok(call.input.indexOf('database_identity')<call.input.indexOf('$scope$'));
});
test('protected SQL refuses mismatched host or active database before SQL execution',async()=>{
 for(const identity of ['other-host\nruntime_123\n','backend-01\npostgres\n']) {
  const mock=executor(identity);
  await assert.rejects(executeProtectedCanonicalSql(request,mock),/database mismatch/);
  assert.equal(mock.calls.length,2);
 }
});
test('approved write mode uses one atomic transaction and the verified runtime database',async()=>{
 const mock=executor();
 assert.deepEqual(await executeProtectedCanonicalSql({...request,operation:'write',query:'DO $approved$ BEGIN END $approved$;'},mock),[]);
 assert.match(mock.calls[2].input,/^BEGIN;/);
 assert.match(mock.calls[2].input,/COMMIT;$/);
 assert.doesNotMatch(mock.calls[2].input,/jsonb_agg/);
});
