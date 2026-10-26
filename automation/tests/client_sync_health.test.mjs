import assert from 'node:assert/strict';
import test from 'node:test';
import { buildHealthSql, evaluateHealth } from '../release/client_sync_health.mjs';

const healthy={occasion:{id:643},registry:{notReady:0},dirty:{unclaimedOldestSeconds:0,claimedOldestSeconds:0},revisionLag:0,publication:{liveP95Ms:20000,structuralP95Ms:30000},projectionDrift:0,receipts:{stuck:0},head:{publicationPending:false},endpoint:{status:200,hashesValid:true}};

test('healthy report passes all read-only gates',()=>assert.deepEqual(evaluateHealth(healthy),{ok:true,failures:[]}));
test('drift, stale claims, SLO and retention delivery failures fail closed',()=>{
  const result=evaluateHealth({...healthy,dirty:{unclaimedOldestSeconds:11,claimedOldestSeconds:121},publication:{liveP95Ms:25001,structuralP95Ms:45001},projectionDrift:1,head:{publicationPending:true},endpoint:{status:200,hashesValid:false}});
  assert.equal(result.ok,false);
  assert.equal(result.failures.length,7);
});
test('health SQL is read-only and target-scoped',()=>{
  const sql=buildHealthSql({organization:9,occasionLink:'csmostrava2026',artifactRetentionDays:7});
  assert.match(sql,/o\.organization=9/);
  assert.match(sql,/projectionDrift/);
  assert.match(sql,/festapp_client_sync_publication_tick_v1/);
  assert.doesNotMatch(sql,/(?:^|;)\s*(?:UPDATE|DELETE|INSERT|REVOKE|GRANT)\b/im);
});
