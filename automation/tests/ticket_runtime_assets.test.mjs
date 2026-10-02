import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const patch=new URL('../hetzner-supabase/runtime/patch-function-static-assets.py',import.meta.url).pathname;
test('font enters the actual worker options without altering auth or routing',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ticket-assets-'));
 try {
  const file=path.join(dir,'index.ts');
  const source='verifyJWT(req);\n    const worker = await EdgeRuntime.userWorkers.create({\n      servicePath,\n      envVars,\n    })\n';
  fs.writeFileSync(file,source);
  assert.equal(spawnSync('python3',[patch,file]).status,0);
  const result=fs.readFileSync(file,'utf8');
  assert.equal(result.replace('      staticPatterns: ["/home/deno/functions/_shared/ticket-assets/*.ttf"],\n',''),source);
  assert.equal(spawnSync('python3',[patch,file]).status,0);
  assert.equal(fs.readFileSync(file,'utf8'),result);
  fs.writeFileSync(file,'unrecognized router');
  assert.notEqual(spawnSync('python3',[patch,file]).status,0);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test('runtime upgrades retain the font helper used by the bundle installer',()=>{
 const upgrade=fs.readFileSync(new URL('../hetzner-supabase/runtime/upgrade-installed-production-runtime.sh',import.meta.url),'utf8');
 assert.match(upgrade,/install_runtime_file "\$SCRIPT_DIR\/patch-function-static-assets.py" "\$COMPOSE_DIR\/patch-function-static-assets.py"/);
 const installer=fs.readFileSync(new URL('../hetzner-supabase/runtime/install-production-function-bundle.sh',import.meta.url),'utf8');
 assert.match(installer,/patch-function-static-assets.py/);
});
