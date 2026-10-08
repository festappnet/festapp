import { createMonitoring } from "@festapp/monitoring";

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

export async function probeEmailHealth(env, fetchImpl = fetch) {
  try {
    const response = await fetchImpl(new URL('/rest/v1/rpc/get_festapp_monitoring_health_v1', env.FESTAPP_API_URL), {
      method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(10000),
      headers: { 'content-type': 'application/json', apikey: env.FESTAPP_ANON_KEY, Authorization: `Bearer ${env.FESTAPP_ANON_KEY}` },
      body: JSON.stringify({ p_token: env.FESTAPP_HEALTH_TOKEN }),
    });
    if (!response.ok) return { pass: false, reason: 'health_rpc_unavailable', http_status: response.status };
    const data = await response.json();
    if (typeof data.ok !== 'boolean' || !Array.isArray(data.alerts)) return { pass: false, reason: 'health_rpc_invalid' };
    return { pass: data.ok, reason: data.ok ? 'ok' : 'email_health_failed', count: data.alerts.length };
  } catch { return { pass: false, reason: 'health_rpc_unavailable' }; }
}

export async function runProbes(env, fetchImpl = fetch, now = new Date()) {
  const results = await Promise.all(TARGETS.flatMap((host) =>
    CHECKS.map((check) => probe(fetchImpl, host, check))));
  const email = await probeEmailHealth(env, fetchImpl);
  const failed = results.some((result) => !result.pass) || !email.pass;
  const observedAt = now.toISOString();
  const record = {
    version: 1,
    observed_at: observedAt,
    probe_location: "cloudflare-worker",
    pass: !failed,
    results,
    email,
  };
  const encoded = JSON.stringify(record);
  const key = `monitoring/${observedAt.slice(0, 10)}/${observedAt.replaceAll(":", "-")}.json`;
  await Promise.all([
    env.EVIDENCE_BUCKET.put(key, encoded, { httpMetadata: { contentType: "application/json" } }),
    env.EVIDENCE_BUCKET.put("monitoring/latest.json", encoded, { httpMetadata: { contentType: "application/json" } }),
  ]);
  // A single SDK batch reports all three checks. The old independent watchdog
  // now measures successful collection, not duplicate application incidents.
  try {
    const monitor = createMonitoring({
      baseUrl: env.MONITORING_URL, token: env.MONITORING_TOKEN,
      service: 'festapp-probes', release: env.MONITORING_RELEASE ?? 'v1',
      fetch: env.MONITORING_SERVICE?.fetch.bind(env.MONITORING_SERVICE) ?? fetchImpl,
    });
    for (const [index, host] of TARGETS.entries()) {
      const checks = results.filter((result) => result.host === host);
      monitor.heartbeat(index === 0 ? 'canonical-backend' : 'rehearsal-backend', {
        status: checks.every((check) => check.pass) ? 'ok' : 'failed',
        code: 'backend_health', context: { count: checks.filter((check) => !check.pass).length },
      });
    }
    monitor.heartbeat('email-delivery', {
      status: email.pass ? 'ok' : 'failed', code: 'email_health',
      context: { reason: email.reason, count: email.count ?? 0 },
    });
    const receipt = await monitor.close({ timeoutMs: 1000 });
    if (receipt.status !== 'flushed' || receipt.receipts.length !== 3 || receipt.dropped) throw new Error('monitoring_collection_failed');
  } catch {
    await pingHeartbeat(fetchImpl, env.HEALTHCHECKS_PING_URL, true);
    throw new Error('Festapp shared Monitoring collection failed');
  }
  await pingHeartbeat(fetchImpl, env.HEALTHCHECKS_PING_URL, false);
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
