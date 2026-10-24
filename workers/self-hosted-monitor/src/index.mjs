const TARGETS = ["api.festapp.net", "rehearsal-api.festapp.net"];
const CHECKS = [
  { path: "/storage/v1/status", expectedStatus: 200 },
  { path: "/auth/v1/health", expectedStatus: 401 },
  { path: "/rest/v1/", expectedStatus: 401 },
];

async function probe(fetchImpl, host, check) {
  const started = Date.now();
  try {
    const response = await fetchImpl(`https://${host}${check.path}`, {
      method: "GET",
      redirect: "manual",
      signal: AbortSignal.timeout(10_000),
      headers: { "user-agent": "festapp-external-health/1" },
    });
    return {
      host,
      path: check.path,
      expected_status: check.expectedStatus,
      observed_status: response.status,
      duration_ms: Date.now() - started,
      pass: response.status === check.expectedStatus,
    };
  } catch (error) {
    return {
      host,
      path: check.path,
      expected_status: check.expectedStatus,
      observed_status: null,
      duration_ms: Date.now() - started,
      pass: false,
      error_class: error instanceof Error ? error.name : "UnknownError",
    };
  }
}

async function pingHeartbeat(fetchImpl, url, failed) {
  if (!url) throw new Error("HEALTHCHECKS_PING_URL is not configured");
  const target = failed ? `${url.replace(/\/$/, "")}/fail` : url;
  const response = await fetchImpl(target, { method: "POST", body: failed ? "probe failed" : "ok" });
  if (!response.ok) throw new Error(`heartbeat delivery failed with ${response.status}`);
}

// The existing monitor owns this read-only probe; no extra worker or timer.
export async function probeAbuse(env,fetchImpl,now) {
  const fail=(reason)=>({host:'api.festapp.net',path:'/rest/v1/rpc/get_abuse_monitor_v1',pass:false,reason});
  if(!env.ABUSE_MONITOR_TOKEN||!env.SUPABASE_ANON_KEY)return fail('monitor_not_configured');
  try {
    const response=await fetchImpl('https://api.festapp.net/rest/v1/rpc/get_abuse_monitor_v1',{
      method:'POST',redirect:'error',signal:AbortSignal.timeout(10_000),
      headers:{apikey:env.SUPABASE_ANON_KEY,'Content-Type':'application/json'},
      body:JSON.stringify({p_token:env.ABUSE_MONITOR_TOKEN}),
    });
    if(!response.ok)return fail('monitor_unavailable');
    const state=await response.json();
    const reasons=[];
    const age=(value)=>value==null?0:(now.getTime()-Date.parse(value))/1000;
    const threshold=(key)=>{
      const value=state.thresholds?.[key];
      if(!Number.isSafeInteger(value)||value<=0)throw new Error('Invalid monitor policy');
      return value;
    };
    if(!state.queue||!state.provider||!state.policyRevision||!Number.isFinite(age(state.measuredAt)))return fail('monitor_invalid');
    for(const cls of ['auth','commitment','ordinary']) {
      if(!state.queue[cls])return fail('monitor_invalid');
      const elapsed=age(state.queue[cls].oldestCreatedAt);
      if(!Number.isFinite(elapsed)||elapsed>threshold(`monitor.${cls}.age.seconds`))reasons.push(`${cls}_backlog`);
    }
    for(const [field,key] of [['oldestExpiredUsageAt','cleanup'],['oldestGrowthEvidenceAt','growth']]) {
      const elapsed=age(state[field]);
      if(!Number.isFinite(elapsed)||elapsed>threshold(`monitor.${key}.age.seconds`))reasons.push(`${key}_stale`);
    }
    const provider=state.provider;
    if(provider.paused||provider.providerOutageStreak>0||Date.parse(provider.circuitUntil)>now.getTime())reasons.push('provider_unavailable');
    if(!provider.quotaMeasuredAt||!Number.isFinite(age(provider.quotaMeasuredAt))||age(provider.quotaMeasuredAt)>threshold('monitor.provider.quota.age.seconds'))reasons.push('provider_quota_stale');
    return {host:'api.festapp.net',path:'/rest/v1/rpc/get_abuse_monitor_v1',pass:reasons.length===0,reasons,state};
  } catch {return fail('monitor_unavailable');}
}

export async function runProbes(env, fetchImpl = fetch, now = new Date()) {
  const results = await Promise.all(TARGETS.flatMap((host) =>
    CHECKS.map((check) => probe(fetchImpl, host, check))));
  results.push(await probeAbuse(env,fetchImpl,now));
  const failed = results.some((result) => !result.pass);
  const observedAt = now.toISOString();
  const record = {
    version: 1,
    observed_at: observedAt,
    probe_location: "cloudflare-worker",
    pass: !failed,
    results,
  };
  const encoded = JSON.stringify(record);
  const key = `monitoring/${observedAt.slice(0, 10)}/${observedAt.replaceAll(":", "-")}.json`;
  await Promise.all([
    env.EVIDENCE_BUCKET.put(key, encoded, { httpMetadata: { contentType: "application/json" } }),
    env.EVIDENCE_BUCKET.put("monitoring/latest.json", encoded, { httpMetadata: { contentType: "application/json" } }),
  ]);
  await pingHeartbeat(fetchImpl, env.HEALTHCHECKS_PING_URL, failed);
  if (failed) {
    console.error(JSON.stringify({ event: "festapp_self_hosted_probe_failed", observed_at: observedAt, results }));
    throw new Error("Festapp external health probe failed");
  }
  console.log(JSON.stringify({ event: "festapp_self_hosted_probe_passed", observed_at: observedAt }));
  return record;
}

export default {
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(runProbes(env));
  },
};
