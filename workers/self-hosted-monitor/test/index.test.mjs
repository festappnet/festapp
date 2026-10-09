import assert from "node:assert/strict";
import test from "node:test";
import { runProbes } from "../src/index.mjs";

function environment(writes) {
  return {
    MONITORING_URL: "https://monitor.example/", MONITORING_TOKEN: "fixture-monitoring-token-123456789012345",
    FESTAPP_API_URL: "https://api.festapp.net", FESTAPP_ANON_KEY: "fixture-anon", FESTAPP_HEALTH_TOKEN: "fixture-health",
    EVIDENCE_BUCKET: { async put(key, value) { writes.push({ key, value: JSON.parse(value) }); } },
  };
}
function transport({ requests, batches, backendFailed = false, emailFailed = false, unrecorded = false }) {
  return async (target, init) => {
    const url = String(target); requests.push(url);
    if (url.startsWith("https://monitor.example/")) {
      const batch = JSON.parse(init.body); batches.push(batch);
      return Response.json({ results: unrecorded ? [] : batch.events.map(e => ({ eventId: e.event_id, recorded: true })) }, { status: 202 });
    }
    assert.equal(new URL(url).hostname, "api.festapp.net", "no external heartbeat destination is contacted");
    if (url.endsWith("/get_festapp_monitoring_health_v1")) return Response.json({ ok: !emailFailed, alerts: emailFailed ? ["email_backlog"] : [] });
    return new Response("", { status: backendFailed ? 503 : url.endsWith("/storage/v1/status") ? 200 : 401 });
  };
}

test("healthy probes retain evidence and report only through Monitoring without Healthchecks configuration", async () => {
  const writes = [], requests = [], batches = [];
  const result = await runProbes(environment(writes), transport({ requests, batches }), new Date("2026-09-02T19:00:00Z"));
  assert.equal(result.pass, true);
  assert.equal(result.results.length, 3);
  assert.deepEqual(writes.map(({ key }) => key), ["monitoring/2026-09-02/2026-09-02T19-00-00.000Z.json", "monitoring/latest.json"]);
  assert.equal(batches.length, 1);
  assert.equal(batches[0].events.length, 2);
  assert.equal(requests.at(-1), "https://monitor.example/v1/observations");
});

test("failed backend probes are persisted and sent to Monitoring", async () => {
  const writes = [], requests = [], batches = [];
  await assert.rejects(runProbes(environment(writes), transport({ requests, batches, backendFailed: true })), /external health probe failed/);
  assert.equal(writes[0].value.pass, false);
  assert.equal(batches[0].events.find(e => e.check_id === "canonical-backend").outcome, "failure");
});

test("unrecorded observations fail collection without an external fallback", async () => {
  const writes = [], requests = [], batches = [];
  await assert.rejects(runProbes(environment(writes), transport({ requests, batches, unrecorded: true })), /shared Monitoring collection failed/);
  assert.equal(writes.length, 2);
  assert.equal(requests.at(-1), "https://monitor.example/v1/observations");
});

test("email queue health failure shares the same SDK batch", async () => {
  const writes = [], requests = [], batches = [];
  await assert.rejects(runProbes(environment(writes), transport({ requests, batches, emailFailed: true })), /external health probe failed/);
  assert.equal(batches.length, 1);
  assert.equal(batches[0].events.length, 2);
  assert.equal(batches[0].events.find(e => e.check_id === "email-delivery").outcome, "failure");
});
