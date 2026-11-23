import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, cpSync, rmSync, symlinkSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
const script = resolve('automation/hetzner-supabase/runtime/function-bundle-selection.py');
function fixture(t, functionName = 'alpha') {
    const root = mkdtempSync(join(tmpdir(), 'festapp-function-selection-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const base = join(root, 'base'), source = join(root, 'source'), stage = join(root, 'stage');
    for (const name of ['alpha', 'beta', '_shared', 'main']) mkdirSync(join(base, name), { recursive: true });
    writeFileSync(join(base, 'alpha/index.ts'), 'import { value } from "../_shared/common.ts"; export const result = value;');
    writeFileSync(join(base, 'alpha/retired.ts'), 'export const retired = true;');
    writeFileSync(join(base, 'beta/index.ts'), 'export const worker = "old-schema-compatible";');
    writeFileSync(join(base, '_shared/common.ts'), 'export const value = 1;');
    writeFileSync(join(base, '_shared/unrelated.ts'), 'export const unrelated = true;');
    writeFileSync(join(base, 'main/index.ts'), 'export const router = "installed";');
    writeFileSync(join(base, 'deno.lock'), '{}');
    cpSync(base, source, { recursive: true });
    writeFileSync(join(source, 'alpha/index.ts'), 'import { value } from "../_shared/common.ts"; export const result = value + 1;');
    rmSync(join(source, 'alpha/retired.ts'));
    writeFileSync(join(source, 'beta/index.ts'), 'export const worker = "requires-unreleased-schema";');
    mkdirSync(stage);
    if (functionName !== 'alpha') cpSync(join(source, 'alpha'), join(source, functionName), { recursive: true });
    cpSync(join(source, functionName), join(stage, functionName), { recursive: true });
    const run = (command, args) => spawnSync('python3', [script, command, '--root', command === 'select' ? source : base, ...args], { encoding: 'utf8' });
    const inventory = run('inventory', []); assert.equal(inventory.status, 0, inventory.stderr);
    const inventoryPath = join(root, 'base.json'); writeFileSync(inventoryPath, inventory.stdout);
    const select = (shared = []) => run('select', ['--base', inventoryPath, '--functions', functionName, '--shared-modules', shared.join(',')]);
    const selection = select(); assert.equal(selection.status, 0, selection.stderr);
    const manifest = join(root, 'manifest.json'); writeFileSync(manifest, JSON.stringify({ selection: JSON.parse(selection.stdout) }));
    return { root, base, source, stage, manifest, run, select,
        stageSelected: () => run('stage', ['--stage', stage, '--manifest', manifest]) };
}
test('selected release replaces one complete Function and preserves unrelated worker, router, shared code and lock', t => {
    const f = fixture(t), result = f.stageSelected(); assert.equal(result.status, 0, result.stderr);
    for (const name of ['beta/index.ts', '_shared/common.ts', 'main/index.ts', 'deno.lock'])
        assert.equal(readFileSync(join(f.stage, name), 'utf8'), readFileSync(join(f.base, name), 'utf8'));
    assert.equal(readFileSync(join(f.stage, 'alpha/index.ts'), 'utf8'), readFileSync(join(f.source, 'alpha/index.ts'), 'utf8'));
    assert.throws(() => readFileSync(join(f.stage, 'alpha/retired.ts')));
});
test('selected release can stage a new Function while preserving existing directories', t => {
    const f = fixture(t, 'new-contact'), result = f.stageSelected();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(join(f.stage, 'new-contact/index.ts'), 'utf8'), readFileSync(join(f.source, 'new-contact/index.ts'), 'utf8'));
    assert.deepEqual(readdirSync(f.stage).sort(), [...readdirSync(f.base), 'new-contact'].sort());
    for (const name of ['alpha/index.ts', 'beta/index.ts', '_shared/common.ts', 'main/index.ts', 'deno.lock'])
        assert.equal(readFileSync(join(f.stage, name), 'utf8'), readFileSync(join(f.base, name), 'utf8'));
});
test('shared and lock upgrades require a full coordinated release', t => {
    for (const name of ['_shared/common.ts', 'deno.lock']) {
        const f = fixture(t); writeFileSync(join(f.source, name), 'changed');
        assert.notEqual(f.select().status, 0);
    }
});
test('changed installed base or injected archive path cannot stage', t => {
    const drift = fixture(t); writeFileSync(join(drift.base, 'beta/index.ts'), 'changed by another release');
    assert.notEqual(drift.stageSelected().status, 0);
    const injected = fixture(t); mkdirSync(join(injected.stage, '_shared'));
    assert.notEqual(injected.stageSelected().status, 0);
});
test('source closure is recomputed and manifest omissions do not authorize new shared code', t => {
    const f = fixture(t); const manifest = JSON.parse(readFileSync(f.manifest)); manifest.selection.dependencies = {};
    writeFileSync(f.manifest, JSON.stringify(manifest)); assert.notEqual(f.stageSelected().status, 0);
});
test('dynamic imports, missing modules and symlinks fail closed', t => {
    for (const source of ['const module = "../_shared/common.ts"; import(module);', 'import "../_shared/missing.ts";']) {
        const f = fixture(t); writeFileSync(join(f.source, 'alpha/index.ts'), source); assert.notEqual(f.select().status, 0);
    }
    const link = fixture(t); symlinkSync(join(link.base, 'main'), join(link.base, 'unexpected'));
    assert.notEqual(link.run('inventory', []).status, 0);
});

test('every canonical source Function is explicitly classified by the production bundle policy',()=>{
 const policy=JSON.parse(readFileSync(resolve('automation/hetzner-supabase/merge/runtime-writer-policy.json'),'utf8'));
 const excluded=new Set(Object.keys(policy.canonical_function_security.excluded));
 const source=readdirSync(resolve('supabase/functions'),{withFileTypes:true}).filter(entry=>entry.isDirectory()&&entry.name!=='_shared');
 assert.deepEqual(source.filter(entry=>!Object.hasOwn(policy.edge_functions,entry.name)&&!excluded.has(entry.name)).map(entry=>entry.name),[]);
 assert.equal(Object.hasOwn(policy.edge_functions,'apple-wallet'),true);
 assert.equal(Object.hasOwn(policy.canonical_function_security.resolved,'apple-wallet'),true);
});

test('full bundle installer upgrades observed legacy router limits and rejects unknown limits', t => {
 const source=readFileSync(resolve('automation/hetzner-supabase/runtime/install-production-function-bundle.sh'),'utf8');
 const start=source.indexOf("if grep -Eq '^[[:space:]]*const memoryLimitMb");
 const end=source.indexOf('\nfi\n[[ -z ',start);
 assert(start>=0&&end>start,'isolate the actual staged-router limit checks');
 const patch=source.slice(start,end);
 const stage=mkdtempSync(join(tmpdir(),'festapp-router-limits-'));
 t.after(()=>rmSync(stage,{recursive:true,force:true}));
 mkdirSync(join(stage,'main'));
 // Exercise the same sed expressions with BSD's explicit empty backup suffix.
 const nativeSed=process.platform==='darwin' ? "sed() { if [[ $1 == -Ei ]]; then shift; command sed -E -i '' \"$@\"; else command sed \"$@\"; fi; }\n" : '';
 const run=(memory,timeout)=>{
  writeFileSync(join(stage,'main/index.ts'),`  const memoryLimitMb = ${memory}\n  const workerTimeoutMs = ${timeout}\n  const requestAbsentTimeoutMs = 60_000\n`);
  return spawnSync('bash',['-c','set -euo pipefail\nfail() { echo "$*" >&2; exit 1; }\n'+nativeSed+patch],{encoding:'utf8',env:{...process.env,STAGE:stage}});
 };
 for(const [memory,timeout] of [['150','1 * 60 * 1000'],['256','400_000'],['512','7 * 60 * 1000']]) {
  const result=run(memory,timeout);
  assert.equal(result.status,0,result.stderr);
  assert.equal(readFileSync(join(stage,'main/index.ts'),'utf8'),'  const memoryLimitMb = 512\n  const workerTimeoutMs = 7 * 60 * 1000\n  const requestAbsentTimeoutMs = 60_000\n');
 }
 assert.notEqual(run('1024','400_000').status,0);
 assert.notEqual(run('512','300_000').status,0);
});

test('selected source closure accepts built-in Node modules without adding shared files or changing the lock',t=>{
 const f=fixture(t);
 const entry=join(f.source,'alpha/index.ts');
 writeFileSync(entry,'import net from "node:net";\n'+readFileSync(entry,'utf8'));
 const result=f.select();assert.equal(result.status,0,result.stderr);
 const selected=JSON.parse(result.stdout);
 assert.deepEqual(selected.external_imports,['node:net']);
 assert.deepEqual(Object.keys(selected.dependencies),['_shared/common.ts']);
});

function selectedShared(t) {
 const f=fixture(t);
 writeFileSync(join(f.source,'_shared/common.ts'),'export const value = 2;');
 const selected=f.select(['_shared/common.ts']);assert.equal(selected.status,0,selected.stderr);
 writeFileSync(f.manifest,JSON.stringify({selection:JSON.parse(selected.stdout)}));
 mkdirSync(join(f.stage,'_shared'));
 cpSync(join(f.source,'_shared/common.ts'),join(f.stage,'_shared/common.ts'));
 return f;
}
test('explicit shared module updates preserve every unrelated Function, router, shared file and lock',t=>{
 const f=selectedShared(t),result=f.stageSelected();assert.equal(result.status,0,result.stderr);
 assert.equal(readFileSync(join(f.stage,'_shared/common.ts'),'utf8'),'export const value = 2;');
 for(const name of ['beta/index.ts','main/index.ts','_shared/unrelated.ts','deno.lock'])
  assert.equal(readFileSync(join(f.stage,name),'utf8'),readFileSync(join(f.base,name),'utf8'));
});
test('shared module hashes and exact selected file set reject tampering and injected files',t=>{
 const tampered=selectedShared(t);writeFileSync(join(tampered.stage,'_shared/common.ts'),'tampered');
 assert.notEqual(tampered.stageSelected().status,0);
 const extra=selectedShared(t);writeFileSync(join(extra.stage,'_shared/unrelated.ts'),'injected');
 assert.notEqual(extra.stageSelected().status,0);
});
test('shared selection rejects new modules, nested paths, traversal and symlinks',t=>{
 for(const name of ['_shared/new.ts','_shared/nested/common.ts','_shared/../main/index.ts']){
  const f=fixture(t);assert.notEqual(f.select([name]).status,0,name);
 }
 const f=fixture(t);rmSync(join(f.source,'_shared/common.ts'));
 symlinkSync(join(f.source,'_shared/unrelated.ts'),join(f.source,'_shared/common.ts'));
 assert.notEqual(f.select(['_shared/common.ts']).status,0);
});
test('selected shared code cannot pull changed unselected dependencies or a changed lock',t=>{
 const f=fixture(t);
 writeFileSync(join(f.source,'_shared/common.ts'),'import "../beta/index.ts"; export const value = 2;');
 assert.notEqual(f.select(['_shared/common.ts']).status,0);
 const changedLock=fixture(t);writeFileSync(join(changedLock.source,'deno.lock'),'changed');
 assert.notEqual(changedLock.select(['_shared/common.ts']).status,0);
});
for (const exact of [false, true]) test(
    `canonical builder packages ${exact ? 'an exact shared replacement' : 'explicit shared code with a Function'} for the pinned base`, t=>{
 const f=fixture(t),repo=join(f.root,'repo'),output=join(f.root,'bundles');
 const locale='_shared/translations/translations.cs.ts';
 if (exact) {
  for (const root of [f.source,f.base]) {
   mkdirSync(join(root,'_shared/translations'));
   writeFileSync(join(root,locale),'export const copy = "original";');
   writeFileSync(join(root,'_shared/translations/translations.en.ts'),'export const copy = "unchanged";');
  }
  const current=f.run('inventory',[]);
  assert.equal(current.status,0,current.stderr);
  writeFileSync(join(f.root,'base.json'),current.stdout);
  writeFileSync(join(f.source,locale),'export const copy = "new";');
 }
 mkdirSync(join(repo,'automation/hetzner-supabase/runtime'),{recursive:true});
 mkdirSync(join(repo,'automation/hetzner-supabase/merge'),{recursive:true});
 mkdirSync(join(repo,'supabase'),{recursive:true});
 cpSync(f.source,join(repo,'supabase/functions'),{recursive:true});
 writeFileSync(join(repo,'supabase/functions/_shared/common.ts'),'export const value = 2;');
 for(const name of ['function-bundle-selection.py','build-production-function-bundle.sh'])
  cpSync(resolve('automation/hetzner-supabase/runtime',name),join(repo,'automation/hetzner-supabase/runtime',name));
 writeFileSync(join(repo,'automation/hetzner-supabase/merge/runtime-writer-policy.json'),JSON.stringify({canonical_function_security:{excluded:{main:{}}},edge_functions:{alpha:{}}}));
 const git=(...args)=>{const r=spawnSync('git',['-C',repo,...args],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
 git('init','-b','main');git('add','-A');
 git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','-c','core.hooksPath=/dev/null','commit','-m','fixture source');
 git('update-ref','refs/remotes/origin/main',git('rev-parse','HEAD'));
 const built=spawnSync('bash',[join(repo,'automation/hetzner-supabase/runtime/build-production-function-bundle.sh')],{
  cwd:repo,encoding:'utf8',env:{...process.env,FESTAPP_FUNCTION_BUNDLE_ACK:'build-reviewed-production-function-bundle',FESTAPP_FUNCTION_BUNDLE_OUTPUT_DIR:output,
   FESTAPP_FUNCTION_BUNDLE_BASE_INVENTORY:join(f.root,'base.json'),
   ...(exact ? {FESTAPP_FUNCTION_BUNDLE_EXACT_SHARED_MODULES:`_shared/common.ts,${locale}`} :
       {FESTAPP_FUNCTION_BUNDLE_FUNCTIONS:'alpha',FESTAPP_FUNCTION_BUNDLE_SHARED_MODULES:'_shared/common.ts'})}});
 assert.equal(built.status,0,built.stderr);
 const run=join(output,readdirSync(output)[0]),manifest=join(run,'manifest.json');
 assert.deepEqual(JSON.parse(readFileSync(manifest,'utf8')).packaged_directories,exact ? ['_shared'] : ['_shared','alpha']);
 const extracted=join(f.root,'extracted');mkdirSync(extracted);
 const untar=spawnSync('tar',['-xzf',join(run,'functions.tar.gz'),'-C',extracted],{encoding:'utf8'});assert.equal(untar.status,0,untar.stderr);
 assert.deepEqual(readdirSync(join(extracted,'_shared')).sort(),exact ? ['common.ts','translations'] : ['common.ts']);
 if (exact) assert.deepEqual(readdirSync(join(extracted,'_shared/translations')),['translations.cs.ts']);
 const staged=f.run(exact ? 'stage-exact-shared' : 'stage',['--stage',extracted,'--manifest',manifest]);assert.equal(staged.status,0,staged.stderr);
 if (exact) {
  assert.deepEqual(readFileSync(join(extracted,locale)),readFileSync(join(f.source,locale)));
  assert.deepEqual(readFileSync(join(extracted,'_shared/translations/translations.en.ts')),
   readFileSync(join(f.base,'_shared/translations/translations.en.ts')));
 }
 for(const name of ['beta/index.ts','main/index.ts','_shared/unrelated.ts','deno.lock'])
  assert.equal(readFileSync(join(extracted,name),'utf8'),readFileSync(join(f.base,name),'utf8'));
});

test('exact shared update preserves worker-only dependencies and every unselected byte', t => {
    const f = fixture(t);
    const module = '_shared/common.ts';
    const dependency = 'import "./assets.ts"; ';
    for (const root of [f.base, f.source]) {
        writeFileSync(join(root, '_shared/assets.ts'), 'Deno.readFile("./ticket-font.ttf");');
        writeFileSync(join(root, module), dependency + 'export const value = 1;');
    }
    const inventory = f.run('inventory', []);
    writeFileSync(join(f.root, 'base.json'), inventory.stdout);
    const patch = join(f.root, 'patch');
    mkdirSync(join(patch, '_shared'), { recursive: true });
    const writePatch = content => {
        writeFileSync(join(f.source, module), content);
        writeFileSync(join(patch, module), content);
        const plan = spawnSync('python3', [script, 'plan-exact-shared', '--root', f.source,
            '--base', join(f.root, 'base.json'), '--shared-modules', module], { encoding: 'utf8' });
        assert.equal(plan.status, 0, plan.stderr);
        writeFileSync(f.manifest, JSON.stringify({ exact_shared_replacement: JSON.parse(plan.stdout) }));
    };
    const stageExact = () => f.run('stage-exact-shared', ['--stage', patch, '--manifest', f.manifest]);
    writePatch(dependency + 'import "./unrelated.ts"; export const value = 2;');
    assert.match(stageExact().stderr, /changes dependencies/);
    writePatch(dependency + 'export const value = 2;');
    writeFileSync(join(patch, '_shared/unrelated.ts'), 'export const injected = true;');
    assert.match(stageExact().stderr, /unexpected bytes or paths/);
    rmSync(join(patch, '_shared/unrelated.ts'));
    mkdirSync(join(patch, '_shared/unexpected'));
    assert.match(stageExact().stderr, /unexpected paths/);
    rmSync(join(patch, '_shared/unexpected'), { recursive: true });
    writeFileSync(join(f.base, 'main/index.ts'), 'export const router = "newer";');
    assert.match(stageExact().stderr, /tree changed/);
    writeFileSync(join(f.base, 'main/index.ts'), 'export const router = "installed";');
    const staged = stageExact();
    assert.equal(staged.status, 0, staged.stderr);
    for (const [name] of Object.entries(JSON.parse(inventory.stdout).files)) {
        assert.deepEqual(readFileSync(join(patch, name)),
            readFileSync(join(name === module ? f.source : f.base, name)), name);
    }
});
