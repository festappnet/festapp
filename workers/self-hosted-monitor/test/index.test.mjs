import assert from "node:assert/strict";
import test from "node:test";
import { runProbes } from "../src/index.mjs";

function environment(writes, pingUrl = "https://hc-ping.example/uuid") {
  return {
    HEALTHCHECKS_PING_URL: pingUrl,
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
  const result = await runProbes(environment(writes), fetchImpl, new Date("2026-09-02T19:00:00Z"));
  assert.equal(result.pass, true);
  assert.equal(result.results.length, 6);
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
