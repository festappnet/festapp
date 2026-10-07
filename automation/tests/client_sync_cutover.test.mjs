#!/usr/bin/env node

import assert from 'node:assert/strict';
import test from 'node:test';
import {
  activationMissingConfirmations,
  buildActivateSql,
  buildDisableSql,
  buildPreparePublicationSql,
  buildPreflightSql,
  executeDisableLifecycle,
  executeEnableLifecycle,
} from '../release/client_sync_cutover.mjs';

const target = { organization: 9, occasionLink: 'occasion-under-test' };

test('activation derives revocations from the latest canonical registry', () => {
  const sql = buildActivateSql(target);
  assert.match(sql, /SELECT DISTINCT source_relation/);
  assert.match(sql, /REVOKE INSERT, UPDATE, DELETE/);
  assert.match(sql, /SET cutover_ready=true/);
  assert.match(sql, /get_app_config_v219/);
  assert.match(sql, /another occasion already has client_sync_v1 enabled/);
  assert.doesNotMatch(sql, /occasion_id\s*=\s*643/i);
});

test('publication preparation enqueues one canonical full build without enabling the flag', () => {
  const sql = buildPreparePublicationSql(target);
  assert.match(sql, /client_sync\.cutover\.enable/);
  assert.match(sql, /client_projection_dirty_keys/);
  assert.match(sql, /live_public/);
  assert.doesNotMatch(sql, /'true'::jsonb/);
});

test('preflight is read-only and reports the two activation gates', () => {
  const sql = buildPreflightSql(target);
  assert.match(sql, /ordinaryDmlTables/);
  assert.match(sql, /pgauditRolesConfigured/);
  assert.doesNotMatch(
    sql,
    /(?:^|;)\s*(?:UPDATE|DELETE|INSERT|REVOKE)\b/im,
  );
});

test('kill switch only disables the target capability', () => {
  const sql = buildDisableSql(target);
  assert.match(sql, /'false'::jsonb/);
  assert.match(sql, /expected one target occasion/);
  assert.doesNotMatch(sql, /cutover_ready\s*=\s*false/i);
});

test('activation accepts an explicit audit-retention risk decision', () => {
  expectMissing(
    [
      '--audit-risk-accepted',
      '--full-registry-activation',
      '--evidence=reviewed.json',
      '--authority=authority.json',
      '--confirm=occasion-under-test',
    ],
    [],
  );
});

test('enable publishes and verifies the head before changing the flag', async () => {
  const calls = [];
  await executeEnableLifecycle({
    preflight: async () => calls.push('preflight'),
    preparePublication: async () => calls.push('prepare'),
    publishInitialHead: async () => calls.push('publish'),
    verifyPublishedHead: async () => calls.push('verify'),
    setEnabledFlag: async () => calls.push('flag'),
  });
  assert.deepEqual(calls, ['preflight','prepare','publish','verify','flag']);
});

test('disable leaves the flag enabled until exact head deletion is verified', async () => {
  const calls = [];
  await executeDisableLifecycle({
    preflight: async () => calls.push('preflight'),
    deletePublicHead: async () => calls.push('delete'),
    verifyNotPublished: async () => calls.push('verify404'),
    setDisabledFlag: async () => calls.push('flag'),
  });
  assert.deepEqual(calls, ['preflight','delete','verify404','flag']);
});

test('disable failure before verification never changes the flag', async () => {
  const calls = [];
  await assert.rejects(executeDisableLifecycle({
    preflight: async () => calls.push('preflight'),
    deletePublicHead: async () => { calls.push('delete'); throw new Error('R2 unavailable'); },
    verifyNotPublished: async () => calls.push('verify404'),
    setDisabledFlag: async () => calls.push('flag'),
  }), /R2 unavailable/);
  assert.deepEqual(calls, ['preflight','delete']);
});

function expectMissing(args, expected) {
  assert.deepEqual(
    activationMissingConfirmations(args, target.occasionLink),
    expected,
  );
}

import {assertCanonicalActivation, buildCanonicalTargetGuard, canonicalQuery, loadCanonicalTarget} from '../lib/canonical_sql_target.mjs';
import {mutationContractionManifest,validateMutationEvidence} from '../client-sync/canonical_mutation_contraction.mjs';
const canonical={tenantId:'test',generation:1,organization:9,occasionLink:'occasion-under-test'};
test('live activation mismatch fails before SQL',async()=>{
 let queried=false;
 await assert.rejects(canonicalQuery({target:canonical,query:'SELECT 1'},{fetchActivation:async()=>({schemaVersion:1,tenantId:'other',backend:'canonical',generation:1}),executeSql:async()=>{queried=true;}}),/activation mismatch/);
 assert.equal(queried,false);
});
test('canonical SQL executor guards organization/occasion after live generation verification',async()=>{
 let query;
 await canonicalQuery({target:canonical,query:'SELECT 1 AS ok;'},{fetchActivation:async()=>({schemaVersion:1,tenantId:'test',backend:'canonical',generation:1}),executeSql:async sql=>{query=sql;return [{ok:1}];}});
 assert.match(query,/organization=9 AND link='occasion-under-test'/);
 assert.ok(query.indexOf('canonical_target')<query.indexOf('SELECT 1 AS ok'));
 assert.throws(()=>buildCanonicalTargetGuard({...canonical,generation:0}),/invalid/);
});
test('former cloud compiled configuration never supplies a live target',()=>assert.throws(()=>loadCanonicalTarget(new URL('../..',import.meta.url).pathname),/canonical activation phase required/));
test('bounded contraction does not activate or revoke unrelated tables',()=>{
 const m=mutationContractionManifest();
 assert.equal(m.completeAclBoundary,false);
 assert.deepEqual(m.pendingSharedBoundaries,['public.places']);
 assert.doesNotMatch(m.sql,/cutover_ready\s*=\s*true|client_sync_v1|REVOKE.*public.events|CASCADE/);
 assert.match(m.sql,/has_any_column_privilege/);
 assert.match(m.sql,/pg_has_role/);
 assert.match(m.sql,/DROP FUNCTION IF EXISTS public.update_activities\(bigint,jsonb\)/);
 assert.doesNotMatch(m.sql,/DROP FUNCTION IF EXISTS public.update_activities\(bigint\);/);
});
test('operator booleans cannot satisfy shared usage evidence',()=>{
 assert.throws(()=>validateMutationEvidence({legacyWriterGateConfirmed:true},canonical,mutationContractionManifest({includeSharedPlaces:true})),/evidence rejected/);
 assert.ok(activationMissingConfirmations(['--legacy-writer-gate-confirmed','--audit-risk-accepted','--confirm=occasion-under-test'],canonical.occasionLink).includes('--evidence=<dated-artifact>'));
});

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {verifyEvidenceArtifacts,validateMutationAuthority} from '../client-sync/canonical_mutation_contraction.mjs';
import {createHash} from 'node:crypto';
function usageEvidence() {
 const m=mutationContractionManifest({includeSharedPlaces:true});
 return {schemaVersion:1,scope:m.scope,...canonical,capturedAt:'2026-10-07T12:00:00Z',sqlSha256:m.sqlSha256,
  g2:{activationVerified:true,appliedMigrationHashesVerified:true,effectiveAclInventoried:true,functionHashesVerified:true,enabledOccasionsInventoried:true,externalBoundariesClosed:true,artifactReference:'inventory'},
  usage:{from:'2026-10-05T12:00:00Z',to:'2026-10-07T12:00:00Z',tokenLifetimeHours:1,maximumOfflineWriterHours:48,uncoveredIntervals:[],legacyWrites:0,rolesCovered:['anon','authenticated'],postgrestSqlCoverage:true,serviceIntegrationCoverage:true,artifactReference:'logs'},
  expectedConsumers:['test/web','other/android'],sharedConsumers:['test','other'].map((tenantId,i)=>({tenantId,platform:i?'android':'web',supportedRelease:'build-10',minimumWriteBuild:'build-10',bootstrapRoute:'v219',writeRoute:'canonical RPC',writeGateEnforced:true,oldWriterAccessDenied:true,evidenceReference:'matrix'})),mixedClientWindow:{editorWritesRestricted:true,evidenceReference:'matrix'}};
}
const evidenceOptions={now:new Date('2026-10-07T12:00:00Z')};
test('dated shared evidence accepts only the reviewed complete proposal',()=>{
 const e=usageEvidence(),m=mutationContractionManifest({includeSharedPlaces:true});
 assert.equal(validateMutationEvidence(e,canonical,m,evidenceOptions),true);
 for(const modify of [x=>x.sharedConsumers.pop(),x=>x.usage.legacyWrites=1,x=>x.usage.uncoveredIntervals=['gap'],x=>x.usage.maximumOfflineWriterHours=49,x=>x.sqlSha256='wrong',x=>x.g2.externalBoundariesClosed=false,x=>x.mixedClientWindow.editorWritesRestricted=false]){
  const broken=usageEvidence();modify(broken);assert.throws(()=>validateMutationEvidence(broken,canonical,m,evidenceOptions),/evidence rejected/);
 }
});
test('shared SQL requires separate exact G4 authority',()=>{
 const m=mutationContractionManifest({includeSharedPlaces:true});
 assert.throws(()=>validateMutationAuthority({approved:true},canonical,m),/separate G4/);
 validateMutationAuthority({...canonical,approved:true,reference:'authorized-operation',sqlSha256:m.sqlSha256,action:'shared-mutation-contraction'},canonical,m);
});
test('hashed evidence references reject altered files',()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mutation-evidence-test-'));
 try {
  const e=usageEvidence(),bytes='fixture evidence';
  fs.writeFileSync(path.join(directory,'proof.txt'),bytes);
  e.artifacts=['inventory','logs','matrix'].map(id=>({id,file:'proof.txt',sha256:createHash('sha256').update(bytes).digest('hex')}));
  verifyEvidenceArtifacts(e,directory);
  fs.writeFileSync(path.join(directory,'proof.txt'),'modified');
  assert.throws(()=>verifyEvidenceArtifacts(e,directory),/digest mismatch/);
 }finally{fs.rmSync(directory,{recursive:true,force:true});}
});
test('even canonical phase rejects cloud origin selection',()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mutation-target-test-'));
 try{
  fs.mkdirSync(path.join(directory,'automation'));
  fs.writeFileSync(path.join(directory,'automation/project.conf'),'BACKEND_ACTIVATION_PHASE=canonical\nBACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=https://former.supabase.co\nSUPABASE_URL=https://former.supabase.co\n');
  assert.throws(()=>loadCanonicalTarget(directory),/cloud fallback forbidden/);
 }finally{fs.rmSync(directory,{recursive:true,force:true});}
});
