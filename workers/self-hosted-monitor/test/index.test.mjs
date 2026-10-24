import assert from "node:assert/strict";
import test from "node:test";
import { runProbes, probeAbuse } from "../src/index.mjs";

function environment(writes, pingUrl = "https://hc-ping.example/uuid") {
  return {
    HEALTHCHECKS_PING_URL: pingUrl,
    ABUSE_MONITOR_TOKEN: "a".repeat(64), SUPABASE_ANON_KEY: "public-test-key",
    EVIDENCE_BUCKET: { async put(key, value) { writes.push({ key, value: JSON.parse(value) }); } },
  };
}

test("healthy probes persist timestamped and latest evidence then deliver heartbeat", async () => {
  const writes = [];
  const requests = [];
  const fetchImpl = async (url) => {
    requests.push(url);
    if (url.startsWith("https://hc-ping.example/")) return new Response("", { status: 200 });
    if (url.endsWith("/storage/v1/status")) return new Response("", { status: 200 });
    return new Response("", { status: 401 });
  };
  const originalFetch=fetchImpl;
  const monitoredFetch=async(url,init)=>url.endsWith('/get_abuse_monitor_v1')?Response.json(healthyAbuse()):originalFetch(url,init);
  const result = await runProbes(environment(writes), monitoredFetch, new Date("2026-09-02T19:00:00Z"));
  assert.equal(result.pass, true);
  assert.equal(result.results.length, 7);
  assert.deepEqual(writes.map(({ key }) => key), [
    "monitoring/2026-09-02/2026-09-02T19-00-00.000Z.json",
    "monitoring/latest.json",
  ]);
  assert.equal(requests.at(-1), "https://hc-ping.example/uuid");
});

test("failed probe is persisted, sends fail heartbeat and fails the invocation", async () => {
  const writes = [];
  const requests = [];
  const fetchImpl = async (url) => {
    requests.push(url);
    if (url.endsWith("/fail")) return new Response("", { status: 200 });
    if (url.startsWith("https://hc-ping.example/")) return new Response("", { status: 200 });
    return new Response("", { status: 503 });
  };
  await assert.rejects(
    runProbes(environment(writes), fetchImpl, new Date("2026-09-02T19:05:00Z")),
    /external health probe failed/,
  );
  assert.equal(writes[0].value.pass, false);
  assert.equal(requests.at(-1), "https://hc-ping.example/uuid/fail");
});

test("missing alert destination fails closed after retaining probe evidence", async () => {
  const writes = [];
  const fetchImpl = async (url) => url.endsWith("/storage/v1/status")
    ? new Response("", { status: 200 }) : new Response("", { status: 401 });
  await assert.rejects(runProbes(environment(writes, ""), fetchImpl), /not configured/);
  assert.equal(writes.length, 2);
});

function healthyAbuse() {
  const t='2026-09-02T19:00:00Z';
  return {measuredAt:t,policyRevision:1,queue:Object.fromEntries(['auth','commitment','ordinary'].map(k=>[k,{oldestCreatedAt:null,pendingCount:0}])),
    provider:{paused:false,providerOutageStreak:0,quotaMeasuredAt:t},oldestExpiredUsageAt:null,oldestGrowthEvidenceAt:t,
    thresholds:{'monitor.auth.age.seconds':60,'monitor.commitment.age.seconds':300,'monitor.ordinary.age.seconds':3600,
      'monitor.cleanup.age.seconds':300,'monitor.growth.age.seconds':900,'monitor.provider.quota.age.seconds':3600}};
}
test('abuse probe reports backlog and provider failure through the existing monitor',async()=>{
 const state=healthyAbuse();state.queue.commitment.oldestCreatedAt='2026-09-02T18:30:00Z';state.provider.paused=true;
 let request;
 const result=await probeAbuse(environment([]),async(url,init)=>{request=init;return Response.json(state);},new Date('2026-09-02T19:00:00Z'));
 assert.equal(result.pass,false);assert.deepEqual(result.reasons,['commitment_backlog','provider_unavailable']);
 assert.equal(request.headers.apikey,'public-test-key');assert.equal('Authorization' in request.headers,false);
 assert.deepEqual(JSON.parse(request.body),{p_token:'a'.repeat(64)});
});
test('missing abuse capability fails closed without network access',async()=>{
 assert.equal((await probeAbuse({},()=>{throw new Error('must not fetch');},new Date())).reason,'monitor_not_configured');
});
