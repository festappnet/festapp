import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, existsSync, readdirSync, mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {evidenceDirectory} from '../authorization/evidence.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const read=name=>readFileSync(join(root,name),'utf8');
const hash=path=>createHash('sha256').update(readFileSync(join(root,path))).digest('hex');

test('retired evidence stays outside the source tree and run folders are ignored',()=>{
    for (const path of [
        'docs/plans/evidence/canonical-authorization-20261020',
        'docs/plans/google-sign-in-reference-2026-10-01',
        'docs/plans/evidence/blueprint-mcp-closure-20261020',
        'docs/plans/evidence/blueprint-b-20261019',
        'docs/plans/evidence/blueprint-typography-20261020',
        'docs/plans/demo-occasions-evidence-2026-10-14',
    ]) assert.equal(existsSync(join(root,path)),false,path);
    for (const run of ['authorization','google-auth','blueprint','demo-occasions'])
        execFileSync('git',['check-ignore','--quiet',`.codex-artifacts/${run}/run/probe.json`],{cwd:root});
});

test('Blueprint archive selection, lock and immutable snapshots agree',()=>{
    const pkg=JSON.parse(read('web_client/package.json'));
    const selected=pkg.dependencies['@festapp/venue-layout'];
    assert.match(selected,/^file:vendor\/[^/]+\.tgz$/);
    const name=selected.slice('file:vendor/'.length);
    assert.deepEqual(readdirSync(join(root,'web_client/vendor')).filter(n=>n.endsWith('.tgz')).sort(),[name]);
    const locked=[...read('web_client/pnpm-lock.yaml').matchAll(/file:vendor\/([\w.-]+\.tgz)/g)].map(m=>m[1]);
    assert.ok(locked.length>0);
    assert.deepEqual([...new Set(locked)],[name]);
    const manifest=JSON.parse(read('vendor/blueprint/manifest.json'));
    assert.deepEqual(Object.keys(manifest.archives).filter(n=>n.endsWith('.tgz')),[name]);
    assert.equal(hash('web_client/vendor/'+name),manifest.archives[name]);
    assert.equal(hash('vendor/blueprint/archive-result.json'),manifest.archiveGateReceiptSha256);
    for(const [path,digest] of Object.entries(manifest.files)) assert.equal(hash('vendor/blueprint/'+path),digest,path);
});

test('capture paths are explicit and missing replay inputs fail before database access',async()=>{
    const folder=mkdtempSync(join(tmpdir(),'festapp-authz-paths-'));
    const previous=process.env.FESTAPP_AUTHORIZATION_EVIDENCE_DIR;
    process.env.FESTAPP_AUTHORIZATION_EVIDENCE_DIR=folder;
    try {
        assert.equal(fileURLToPath(await evidenceDirectory()),folder+'/');
        await assert.rejects(evidenceDirectory('baseline.sql'),/Missing authorization replay input baseline.sql.*Restore paired immutable captures/);
        writeFileSync(join(folder,'baseline.sql'),'-- historical input\n');
        assert.equal(fileURLToPath(await evidenceDirectory('baseline.sql')),folder+'/');
        const env={...process.env,FESTAPP_AUTHORIZATION_EVIDENCE_DIR:folder};
        assert.throws(()=>execFileSync('python3',['automation/authorization/baseline.py'],{cwd:root,env,stdio:'pipe'}),e=>
            /Missing authorization replay inputs.*catalog-before.json.*Restore the paired immutable captures/.test(e.stderr.toString()));
        assert.equal(existsSync(join(folder,'catalog-before.json')),false);
    } finally {
        if(previous===undefined)delete process.env.FESTAPP_AUTHORIZATION_EVIDENCE_DIR;
        else process.env.FESTAPP_AUTHORIZATION_EVIDENCE_DIR=previous;
        rmSync(folder,{recursive:true,force:true});
    }
});


test('completed migration toolchains and duplicate previews stay retired',()=>{
    for (const path of [
        'automation/hetzner-supabase/rehearsal',
        'automation/blueprint_local_e2e.py',
        'automation/blueprint_local_web_client.mjs',
        'automation/blueprint_typography_probe.ts',
        'automation/blueprint_typography_edge_probe.py',
        'automation/verify_cutover_ledger.mjs',
        'docs/archive/audits/unified-app-cutover-commit-inventory-2026-08-23.tsv',
        'automation/image-migration/migrate-files.js',
        'automation/image-migration/rewrite-urls.js',
        'automation/image-migration/private-bucket-cutover.js',
        'docs/design/occasion-card-layout-preview/compact-layout.html',
        'docs/design/occasion-card-layout-preview/real-layout.html',
    ]) assert.equal(existsSync(join(root,path)),false,path);
    assert.ok(existsSync(join(root,'docs/design/occasion-card-layout-preview/index.html')));
    assert.ok(existsSync(join(root,'docs/design/occasion-card-layout-preview/variants.html')));
});


test('retired cloud merge commands do not return alongside active runtime policy',()=>{
    for (const file of ['inventory.mjs','export-source.mjs','export-managed-schemas.mjs',
        'stage-managed-export.mjs','rehearsal-export-clouds.mjs','collision-inventory.mjs',
        'resolve-auth-collisions.mjs','manage-cloud-freeze.mjs','cutover-mode-gate.mjs',
        'repository-cutover-preflight.mjs','hybrid-readiness.mjs'])
        assert.equal(existsSync(join(root,'automation/hetzner-supabase/merge',file)),false,file);
    for (const file of ['source-registry.json','reference-registry.json','runtime-writer-policy.json',
        'runtime-writer-policy.mjs','edge-function-test-coverage.mjs','client-adapter-audit.mjs'])
        assert.ok(existsSync(join(root,'automation/hetzner-supabase/merge',file)),file);
});
