import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {execFileSync,spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {fingerprint,componentBuild,pruneCache,stampFlutterMetadata,dependencyDigest} from '../lib/web_build_cache.mjs';
import {fixture} from './web_build_fixture.mjs';

test('actual dirty, untracked, generated, mode, SDK and tenant inputs invalidate',t=>{
 const f=fixture(t);const key=()=>fingerprint(f.root,'flutter','static',f.tools).key;
 for(const file of ['lib/main.dart','lib/build/real_source.dart','pubspec.lock','packages/local/lib/local.dart','assets/logo.png','web/index.html','docs/guide.md','lib/untracked.dart','web/generated.json','.env.local']){
  const before=key();f.put(file,'changed');assert.notEqual(key(),before,file);
 }
 let before=key();f.tools.sdk='revision-b';assert.notEqual(key(),before);
 before=key();f.put('automation/project.conf','DOMAIN=other.test\nVERSION=2.0.0\nOCCASION_SETUP_ENABLED=true\n');assert.notEqual(key(),before);
 before=key();fs.chmodSync(path.join(f.root,'lib/main.dart'),0o755);assert.notEqual(key(),before);
});
test('web-only source leaves Flutter key stable and changes Vite key; unknown inputs affect both',t=>{
 const f=fixture(t);const key=c=>fingerprint(f.root,c,'static',f.tools).key;
 const flutter=key('flutter'),vite=key('vite');f.put('web_client/src/app.js','two');assert.equal(key('flutter'),flutter);assert.notEqual(key('vite'),vite);
 const both=[key('flutter'),key('vite')];f.put('automation/new-generator.mjs');assert.notEqual(key('flutter'),both[0]);assert.notEqual(key('vite'),both[1]);
});
test('defines invalidate and noncanonical compiler flags cannot populate canonical cache',t=>{
 const f=fixture(t),before=fingerprint(f.root,'flutter','static',f.tools).key;
 f.put('automation/project.conf',fs.readFileSync(path.join(f.root,'automation/project.conf'),'utf8')+'OCCASION_SETUP_ENABLED=true\n');
 assert.notEqual(fingerprint(f.root,'flutter','static',f.tools).key,before);
 const script=fileURLToPath(new URL('../lib/web_build_cache.mjs',import.meta.url));
 const result=spawnSync(process.execPath,[script,'component','flutter','static','flutter','build','web','--release','--unexpected-define'],{cwd:f.root,encoding:'utf8'});
 assert.notEqual(result.status,0);assert.match(result.stderr,/Unsupported compiler parameters/);
});
test('proven SDK reuses version-only Flutter and stamps fresh PackageInfo/HTML metadata',t=>{
 const f=fixture(t);const policy=JSON.parse(fs.readFileSync(path.join(f.root,'automation/web_build_inputs.json'))).flutterVersionPackaging;
 Object.assign(f.tools,policy);f.put('pubspec.yaml','name: festapp\nversion: 1.0.0+1\n');f.put('web/index.html','window.__FESTAPP_BUILD_VERSION__ = "1.0.0+1";');
 const key=(component,tools=f.tools)=>fingerprint(f.root,component,'static',tools).key;
 const unknown={...f.tools,sdkRevision:'unproven-sdk'};
 const before={flutter:key('flutter'),vite:key('vite'),bundle:key('bundle'),unknown:key('flutter',unknown)};
 f.put('automation/project.conf',fs.readFileSync(path.join(f.root,'automation/project.conf'),'utf8').replace('VERSION=1.0.0+1','VERSION=1.0.1+2'));
 f.put('pubspec.yaml','name: festapp\nversion: 1.0.1+2\n');f.put('web/index.html','window.__FESTAPP_BUILD_VERSION__ = "1.0.1+2";');
 assert.equal(key('flutter'),before.flutter);assert.notEqual(key('vite'),before.vite);assert.notEqual(key('bundle'),before.bundle);assert.notEqual(key('flutter',unknown),before.unknown);
 f.put('build/web/index.html','window.__FESTAPP_BUILD_VERSION__ = "1.0.0+1";');
 f.put('build/web/version.json',JSON.stringify({app_name:'festapp',package_name:'festapp',version:'1.0.0',build_number:'1'}));
 f.put('build/web/main.dart.js','unchanged compiler output');
 f.put('build/web/flutter_bootstrap.js','serviceWorkerVersion: "123456789"');
 stampFlutterMetadata(f.root,path.join(f.root,'build/web'));
 const metadata=JSON.parse(fs.readFileSync(path.join(f.root,'build/web/version.json')));
 assert.equal(metadata.version,'1.0.1');assert.equal(metadata.build_number,'2');assert.equal(metadata.package_name,'festapp');
 assert.match(fs.readFileSync(path.join(f.root,'build/web/index.html'),'utf8'),/1\.0\.1\+2/);
 assert.equal(fs.readFileSync(path.join(f.root,'build/web/main.dart.js'),'utf8'),'unchanged compiler output');
 assert.equal(fs.readFileSync(path.join(f.root,'build/web/flutter_bootstrap.js'),'utf8'),'serviceWorkerVersion: "1.0.1-2"');
});
test('help content skips both compilers while packaging fingerprint changes',t=>{
 const f=fixture(t);const key=c=>fingerprint(f.root,c,'static',f.tools).key;
 const before=Object.fromEntries(['flutter','vite','bundle'].map(c=>[c,key(c)]));
 f.put('automation/release/help/new-topic.md','Fresh help copy');
 assert.equal(key('flutter'),before.flutter);assert.equal(key('vite'),before.vite);assert.notEqual(key('bundle'),before.bundle);
});
test('frozen pnpm install timestamps do not invalidate installed dependency bytes',t=>{
 const f=fixture(t),directory=path.join(f.root,'.private/installed');
 const put=(file,data)=>f.put('.private/installed/'+file,JSON.stringify(data));
 put('.modules.yaml',{prunedAt:'old',nodeLinker:'isolated'});put('.pnpm-workspace-state-v1.json',{lastValidatedTimestamp:1,projects:{app:'same'}});
 put('package/lib.js',{code:'real dependency'});const before=dependencyDigest(directory,true);
 put('.modules.yaml',{prunedAt:'new',nodeLinker:'isolated'});put('.pnpm-workspace-state-v1.json',{lastValidatedTimestamp:2,projects:{app:'same'}});
 assert.equal(dependencyDigest(directory,true),before);
 put('package/lib.js',{code:'changed dependency'});assert.notEqual(dependencyDigest(directory,true),before);
 const changed=dependencyDigest(directory,true);put('.modules.yaml',{prunedAt:'new',nodeLinker:'hoisted'});assert.notEqual(dependencyDigest(directory,true),changed);
});
test('installed dependency alias changes invalidate even when both targets were already hashed',t=>{
 const f=fixture(t),directory=path.join(f.root,'.private/graph');
 f.put('.private/graph/a/entry.js','library a');f.put('.private/graph/b/entry.js','library b');
 const link=path.join(directory,'z-library');fs.symlinkSync('a',link,'dir');const before=dependencyDigest(directory,true);
 fs.unlinkSync(link);fs.symlinkSync('b',link,'dir');assert.notEqual(dependencyDigest(directory,true),before);
});
test('hit copies immutable output; corruption, disabled cache and interrupted write rebuild',async t=>{
 const f=fixture(t);
 const command=[process.execPath,'-e','require("fs").mkdirSync("build/component",{recursive:true});require("fs").writeFileSync("build/component/main.js","compiled")'];
 const options={...f,component:'flutter',target:'static',output:path.join(f.root,'build/component'),command};
 const build=async extra=>{const result=await componentBuild({...options,...extra});return result;};
 const a=await build();const entry=path.join(f.home,'flutter',a.key);const entryFile=path.join(entry,'files/main.js');
 const stamp=fs.statSync(entryFile).mtimeMs;await build();assert.equal(fs.statSync(entryFile).mtimeMs,stamp);
 f.put('docs/plans/packaging.md','new packaging revision');
 execFileSync('git',['-C',f.root,'add','docs/plans/packaging.md']);
 execFileSync('git',['-C',f.root,'-c','user.name=Test','-c','user.email=test@example.test','commit','-qm','packaging']);
 assert.equal((await build()).source,a.source,'reuse retains original compilation revision');
 assert.notEqual(execFileSync('git',['-C',f.root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),a.source);
 fs.writeFileSync(path.join(options.output,'main.js'),'stamped');assert.equal(fs.readFileSync(entryFile,'utf8'),'compiled');
 fs.writeFileSync(entryFile,'corrupt');await build();assert.equal(fs.readFileSync(entryFile,'utf8'),'compiled');
 for(const field of ['source','tools']) {
  const metadataPath=path.join(entry,'entry.json'),metadata=JSON.parse(fs.readFileSync(metadataPath));
  delete metadata[field];fs.writeFileSync(metadataPath,JSON.stringify(metadata));await build();
  assert.ok(JSON.parse(fs.readFileSync(metadataPath))[field],`incomplete ${field} provenance rebuilds`);
 }
 fs.rmSync(path.join(entry,'entry.json'));await build();assert.ok(fs.existsSync(path.join(entry,'entry.json')));
 await build({enabled:false});assert.equal(fs.readFileSync(path.join(options.output,'main.js'),'utf8'),'compiled');
 fs.mkdirSync(entry+'.tmp-interrupted');await build();assert.ok(fs.existsSync(path.join(entry,'entry.json')));
});
test('concurrent requesters compile once without parallel Flutter processes',async t=>{
 const f=fixture(t);const command=[process.execPath,'-e','const f=require("fs");f.appendFileSync("build/count","x");setTimeout(()=>{f.mkdirSync("build/component",{recursive:true});f.writeFileSync("build/component/main.js","compiled")},100)'];
 fs.mkdirSync(path.join(f.root,'build'));
 const options={...f,component:'flutter',target:'static',output:path.join(f.root,'build/component'),command};
 await Promise.all([componentBuild(options),componentBuild(options)]);
 assert.equal(fs.readFileSync(path.join(f.root,'build/count'),'utf8'),'x');
});
test('failed compiler never publishes; dead owner recovers; retention protects locked entry',async t=>{
 const f=fixture(t);const key=fingerprint(f.root,'flutter','static',f.tools).key;
 const entry=path.join(f.home,'flutter',key);fs.mkdirSync(entry+'.lock',{recursive:true});
 fs.writeFileSync(path.join(entry+'.lock','owner.json'),JSON.stringify({pid:2147483647,host:os.hostname()}));
 await assert.rejects(componentBuild({...f,component:'flutter',target:'static',output:path.join(f.root,'build/component'),command:[process.execPath,'-e','process.exit(3)']}),/compilation failed/);
 assert.ok(!fs.existsSync(entry));
 fs.mkdirSync(entry);fs.mkdirSync(entry+'.lock');pruneCache(f.home,0,0);assert.ok(fs.existsSync(entry));
 const interrupted=entry+'.tmp-interrupted';fs.mkdirSync(interrupted);fs.utimesSync(interrupted,new Date(0),new Date(0));
 fs.rmSync(entry+'.lock',{recursive:true});pruneCache(f.home,0,0);assert.ok(!fs.existsSync(entry));assert.ok(!fs.existsSync(interrupted));
});
