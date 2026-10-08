import assert from "node:assert/strict";
import test from "node:test";
import { runProbes } from "../src/index.mjs";

function environment(writes, pingUrl = "https://hc-ping.example/uuid") {
  return {
    HEALTHCHECKS_PING_URL: pingUrl,
    MONITORING_URL: "https://monitor.example/", MONITORING_TOKEN: "fixture-monitoring-token-123456789012345",
    FESTAPP_API_URL: "https://api.festapp.net", FESTAPP_ANON_KEY: "fixture-anon", FESTAPP_HEALTH_TOKEN: "fixture-health",
    EVIDENCE_BUCKET: { async put(key, value) { writes.push({ key, value: JSON.parse(value) }); } },
  };
}

test("healthy probes persist timestamped and latest evidence then deliver heartbeat", async () => {
  const writes = [];
  const requests = [];
  const fetchImpl = async (target, init) => {
    const url = String(target);
    if (url.startsWith("https://monitor.example/")) {
      const batch = JSON.parse(init.body);
      return Response.json({ results: batch.events.map(e => ({ eventId: e.event_id, recorded: true })) }, { status: 202 });
    }
    if (url.endsWith("/get_festapp_monitoring_health_v1")) return Response.json({ ok: true, alerts: [] });
    requests.push(url);
    if (url.startsWith("https://hc-ping.example/")) return new Response("", { status: 200 });
    if (url.endsWith("/storage/v1/status")) return new Response("", { status: 200 });
    return new Response("", { status: 401 });
  };
  const result = await runProbes(environment(writes), fetchImpl, new Date("2026-09-02T19:00:00Z"));
  assert.equal(result.pass, true);
  assert.equal(result.results.length, 3);
  assert.deepEqual(writes.map(({ key }) => key), [
    "monitoring/2026-09-02/2026-09-02T19-00-00.000Z.json",
    "monitoring/latest.json",
  ]);
  assert.equal(requests.at(-1), "https://hc-ping.example/uuid");
});

test("failed probe is collected centrally without duplicating application alerts at the watchdog", async () => {
  const writes = [];
  const requests = [];
  const fetchImpl = async (target, init) => {
    const url = String(target);
    if (url.startsWith("https://monitor.example/")) {
      const batch = JSON.parse(init.body);
      return Response.json({ results: batch.events.map(e => ({ eventId: e.event_id, recorded: true })) }, { status: 202 });
    }
    if (url.endsWith("/get_festapp_monitoring_health_v1")) return Response.json({ ok: true, alerts: [] });
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
  assert.equal(requests.at(-1), "https://hc-ping.example/uuid");
});

test("missing alert destination fails closed after retaining probe evidence", async () => {
  const writes = [];
  const fetchImpl = async (target, init) => {
    const url = String(target);
    if (url.startsWith("https://monitor.example/")) return Response.json({ results: JSON.parse(init.body).events.map(e => ({ eventId: e.event_id, recorded: true })) }, { status: 202 });
    if (url.endsWith("/get_festapp_monitoring_health_v1")) return Response.json({ ok: true, alerts: [] });
    return new Response("", { status: url.endsWith("/storage/v1/status") ? 200 : 401 });
  };
  await assert.rejects(runProbes(environment(writes, ""), fetchImpl), /not configured/);
  assert.equal(writes.length, 2);
});

test("unrecorded Monitoring events fail the independent watchdog", async () => {
  const writes = [], requests = [];
  await assert.rejects(runProbes(environment(writes), async (target) => {
    const url = String(target); requests.push(url);
    if (url.startsWith("https://hc-ping.example/")) return new Response("");
    if (url.startsWith("https://monitor.example/")) return Response.json({ results: [] }, { status: 202 });
    if (url.endsWith("/get_festapp_monitoring_health_v1")) return Response.json({ ok: true, alerts: [] });
    return new Response("", { status: url.endsWith("/storage/v1/status") ? 200 : 401 });
  }), /shared Monitoring collection failed/);
  assert.equal(requests.at(-1), "https://hc-ping.example/uuid/fail");
});

test("email queue health failure is reported in the same two-check SDK batch", async () => {
  const writes = []; let batch;
  await assert.rejects(runProbes(environment(writes), async (target, init) => {
    const url = String(target);
    if (url.startsWith("https://hc-ping.example/")) return new Response("");
    if (url.startsWith("https://monitor.example/")) { batch = JSON.parse(init.body); return Response.json({ results: batch.events.map(e => ({ eventId: e.event_id, recorded: true })) }, { status: 202 }); }
    if (url.endsWith("/get_festapp_monitoring_health_v1")) return Response.json({ ok: false, alerts: ["email_backlog"] });
    return new Response("", { status: url.endsWith("/storage/v1/status") ? 200 : 401 });
  }), /external health probe failed/);
  assert.equal(batch.events.length, 2);
  assert.equal(batch.events.find(e => e.check_id === "email-delivery").outcome, "failure");
});
