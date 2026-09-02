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

export async function runProbes(env, fetchImpl = fetch, now = new Date()) {
  const results = await Promise.all(TARGETS.flatMap((host) =>
    CHECKS.map((check) => probe(fetchImpl, host, check))));
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
