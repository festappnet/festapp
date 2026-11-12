import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync,spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {componentBuild,fingerprint} from '../lib/web_build_cache.mjs';
import {fixture} from './web_build_fixture.mjs';

test('embed generator preserves mtime on repeat and regenerates changed contracts',t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-embed-generator-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const put=(file,data)=>{const target=path.join(root,file);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,data);};
 put('automation/lib/write_if_changed.cjs',fs.readFileSync(new URL('../lib/write_if_changed.cjs',import.meta.url)));
 put('web_client/scripts/build_embed.mjs',fs.readFileSync(new URL('../../web_client/scripts/build_embed.mjs',import.meta.url)));
 put('web_client/src/embed/host.js','globalThis.consent = true; globalThis.contract = 1;\n');
 fs.symlinkSync(fileURLToPath(new URL('../../web_client/node_modules',import.meta.url)),path.join(root,'web_client/node_modules'),'dir');
 fs.mkdirSync(path.join(root,'web_client/public'));
 const run=()=>execFileSync(process.execPath,[path.join(root,'web_client/scripts/build_embed.mjs')],{stdio:'pipe'});
 run();const target=path.join(root,'web_client/public/embed.js'),before=fs.readFileSync(target,'utf8'),mtime=fs.statSync(target).mtimeMs;
 assert.match(before,/consent = true/);
 run();assert.equal(fs.readFileSync(target,'utf8'),before);assert.equal(fs.statSync(target).mtimeMs,mtime);
 put('web_client/src/embed/host.js','globalThis.consent = true; globalThis.contract = 2;\n');run();assert.notEqual(fs.readFileSync(target,'utf8'),before);
});


test('clean web build prepares the real scanner asset before fingerprinting and only compiles afterward',async t=>{
 const sourceRoot=fileURLToPath(new URL('../../',import.meta.url));
 const pkg=JSON.parse(fs.readFileSync(path.join(sourceRoot,'web_client/package.json')));
 const builder=fs.readFileSync(path.join(sourceRoot,'automation/build_web_bundle.sh'),'utf8');
 const policy=JSON.parse(fs.readFileSync(path.join(sourceRoot,'automation/web_build_inputs.json')));
 const prepare='pnpm --dir web_client run prepare:build';
 assert.ok(builder.includes(prepare),'the release builder must use the shared input preparation');
 assert.ok(builder.indexOf(prepare)<builder.indexOf('python3 automation/release/build_receipt.py capture'),
  'all generated inputs must exist before the build receipt captures them');
 assert.equal(pkg.scripts.build,'pnpm run prepare:build && pnpm run compile');
 assert.equal(pkg.scripts.compile,'vite build','cached compilation must not generate inputs');
 assert.deepEqual(policy.viteCommand,['pnpm','run','compile']);
 assert.ok(builder.includes('cd web_client && '+policy.viteCommand.join(' ')));

 const f=fixture(t);
 f.put('.gitignore',fs.readFileSync(path.join(f.root,'.gitignore'),'utf8')+'**/node_modules/\n');
 f.put('web_client/package.json',JSON.stringify(pkg));
 f.put('web_client/scripts/build_scanner_decoder.mjs',fs.readFileSync(path.join(sourceRoot,'web_client/scripts/build_scanner_decoder.mjs')));
 fs.symlinkSync(path.join(sourceRoot,'web_client/node_modules'),path.join(f.root,'web_client/node_modules'),'dir');
 f.put('web_client/index.html','<!doctype html><script type="module" src="/src/app.js"></script>');
 f.put('web_client/src/app.js','console.log("scanner fixture");');
 const rejected=spawnSync(process.execPath,[path.join(sourceRoot,'automation/lib/web_build_cache.mjs'),
  'component','vite','static','bash','-c','cd web_client && pnpm run build'],{cwd:f.root,encoding:'utf8'});
 assert.notEqual(rejected.status,0);
 assert.match(rejected.stderr,/Unsupported compiler parameters/,'cached compilation rejects the input-mutating build entry');
 const assets=path.join(f.root,'web_client/public/web-assets');
 fs.mkdirSync(assets,{recursive:true});
 assert.deepEqual(fs.readdirSync(assets),[],'fresh checkout has no generated decoder');
 // Exercise the actual pinned-package decoder producer from the shared step.
 // Other generators are covered separately; this fixture isolates the missing asset.
 const decoder=pkg.scripts['prepare:build'].split(' && ').find(command=>command.includes('scripts/build_scanner_decoder.mjs'));
 assert.ok(decoder,'scanner input must belong to shared preparation');
 execFileSync('bash',['-euc',decoder],{cwd:path.join(f.root,'web_client'),stdio:'pipe'});
 const names=fs.readdirSync(assets);
 assert.equal(names.length,1);assert.match(names[0],/^zxing-reader-[a-f0-9]{16}\.wasm$/);
 const decoderFile=path.join(assets,names[0]),bytes=fs.readFileSync(decoderFile);
 assert.deepEqual([...bytes.subarray(0,4)],[0,97,115,109],'real WebAssembly decoder bytes');
 const before=fingerprint(f.root,'vite','static',f.tools).key;
 // Run the real compile-only payload directly: pnpm's CI dependency verifier
 // must not try to install into this synthetic project with linked dependencies.
 await componentBuild({...f,component:'vite',target:'static',output:path.join(f.root,'web_client/dist'),
  command:[process.execPath,path.join(sourceRoot,'web_client/node_modules/vite/bin/vite.js'),'build','web_client']});
 assert.equal(fingerprint(f.root,'vite','static',f.tools).key,before,'compilation consumes stable prepared inputs');
 assert.deepEqual(fs.readFileSync(path.join(f.root,'web_client/dist/web-assets',names[0])),bytes);
 fs.appendFileSync(decoderFile,'changed');
 assert.notEqual(fingerprint(f.root,'vite','static',f.tools).key,before,'scanner bytes remain protected compiler inputs');
});
