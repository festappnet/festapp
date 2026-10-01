import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
const patch = new URL('../hetzner-supabase/runtime/patch-function-proof-routes.py', import.meta.url).pathname;
test('runtime exposes exactly the Google proof endpoints and fails on upstream router drift',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-google-router-'));
  const file=path.join(dir,'index.ts');
  try {
    fs.writeFileSync(file,"if (req.method !== 'OPTIONS' && VERIFY_JWT) { verify(); }\nconst service_name = path_parts[1];\n");
    assert.equal(spawnSync('python3',[patch,file]).status,0);
    const source=fs.readFileSync(file,'utf8');
    assert.match(source,/google-auth-start/);assert.match(source,/google-auth-callback/);assert.match(source,/google-auth-complete/);
    assert.doesNotMatch(source,/register|send-email/);
    assert.equal(spawnSync('python3',[patch,file]).status,0);
    assert.equal(fs.readFileSync(file,'utf8'),source);
    fs.writeFileSync(file,'if (VERIFY_JWT) { verify(); }');
    assert.notEqual(spawnSync('python3',[patch,file]).status,0);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
