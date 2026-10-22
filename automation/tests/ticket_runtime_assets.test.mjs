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
  assert.equal(result.replace('      staticPatterns: ["/home/deno/functions/_shared/ticket-assets/**/*"],\n',''),source);
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

// Upgrade the exact router option used by the affected production runtime.
test('existing top-level-only assets are upgraded for gallery fonts and artwork',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ticket-gallery-assets-'));
 try {
  const file=path.join(dir,'index.ts');
  fs.writeFileSync(file,'    const worker = await EdgeRuntime.userWorkers.create({\n      staticPatterns: ["/home/deno/functions/_shared/ticket-assets/*.ttf"],\n      servicePath,\n    })\n');
  assert.equal(spawnSync('python3',[patch,file]).status,0);
  assert.match(fs.readFileSync(file,'utf8'),/ticket-assets\/\*\*\/\*/);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test('preview manifest proves gallery versions and rejects mutated bytes',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'preview-manifest-'));
 const root=new URL('../../supabase/functions/_shared/ticket-assets/',import.meta.url);
 const proof=new URL('../hetzner-supabase/runtime/ticket-font-asset-proof.py',import.meta.url).pathname;
 try{
  fs.cpSync(root,dir,{recursive:true});
  const result=spawnSync('python3',[proof,dir],{encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  const files=JSON.parse(result.stdout);assert.ok(files['preview-manifest.json']);assert.ok(files['backgrounds/concert-stub-v2.png']);assert.ok(files['backgrounds/concert-stub-v3.png']);
  fs.appendFileSync(path.join(dir,'backgrounds/concert-stub-v3.png'),'mutation');
  assert.notEqual(spawnSync('python3',[proof,dir]).status,0);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
