import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p));
const hash=b=>createHash('sha256').update(b).digest('hex');
test('new phase digests, embedded drivers and current contracts agree without rewriting history',()=>{
 const historical=execFileSync('git',['ls-files','supabase/migrations'],{cwd:root,encoding:'utf8'}).trim().split('\n');
 const before=new Map(historical.map(p=>[p,hash(read(p))]));
 const release=JSON.parse(read('automation/hetzner-supabase/runtime/data-security-release.json'));
 assert.equal(release.phases.length,4);
 for(const phase of release.phases) {
  assert.equal(hash(read(phase.file)),phase.sha256);
  assert.equal(hash(read(phase.driver)),phase.driver_sha256);
  assert(read(phase.driver).includes(read(phase.file)));
 }
 for(const [file,digest] of Object.entries({...release.contracts,...release.client_sources}))assert.equal(hash(read(file)),digest);
 execFileSync('python3',['automation/assemble-data-security-migrations.py','--check'],{cwd:root});
 for(const [p,digest] of before)assert.equal(hash(read(p)),digest,p);
});

test('global release eligibility has one source owner and no organization activation list',()=>{
 const source=read('database/functions/client_sync/canonical_mutation_write_release.sql').toString();
 const body=source.slice(source.indexOf('CREATE OR REPLACE FUNCTION'));
 const migration=read('supabase/migrations/20261018220000_global_canonical_mutation_release.sql').toString();
 assert(migration.endsWith(body));
 assert.match(migration,/DROP COLUMN organization_ids;/);
 assert.doesNotMatch(source,/organization_ids|organization_id|organizationIds/);
});
