import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, cpSync, rmSync, symlinkSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
const script = resolve('automation/hetzner-supabase/runtime/function-bundle-selection.py');
function fixture(t) {
    const root = mkdtempSync(join(tmpdir(), 'festapp-function-selection-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const base = join(root, 'base'), source = join(root, 'source'), stage = join(root, 'stage');
    for (const name of ['alpha', 'beta', '_shared', 'main']) mkdirSync(join(base, name), { recursive: true });
    writeFileSync(join(base, 'alpha/index.ts'), 'import { value } from "../_shared/common.ts"; export const result = value;');
    writeFileSync(join(base, 'alpha/retired.ts'), 'export const retired = true;');
    writeFileSync(join(base, 'beta/index.ts'), 'export const worker = "old-schema-compatible";');
    writeFileSync(join(base, '_shared/common.ts'), 'export const value = 1;');
    writeFileSync(join(base, 'main/index.ts'), 'export const router = "installed";');
    writeFileSync(join(base, 'deno.lock'), '{}');
    cpSync(base, source, { recursive: true });
    writeFileSync(join(source, 'alpha/index.ts'), 'import { value } from "../_shared/common.ts"; export const result = value + 1;');
    rmSync(join(source, 'alpha/retired.ts'));
    writeFileSync(join(source, 'beta/index.ts'), 'export const worker = "requires-unreleased-schema";');
    mkdirSync(stage);
    cpSync(join(source, 'alpha'), join(stage, 'alpha'), { recursive: true });
    const run = (command, args) => spawnSync('python3', [script, command, '--root', command === 'select' ? source : base, ...args], { encoding: 'utf8' });
    const inventory = run('inventory', []); assert.equal(inventory.status, 0, inventory.stderr);
    const inventoryPath = join(root, 'base.json'); writeFileSync(inventoryPath, inventory.stdout);
    const select = () => run('select', ['--base', inventoryPath, '--functions', 'alpha']);
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
