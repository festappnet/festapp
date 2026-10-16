import { sampleRuntimeResources } from "./runtime_resource_metrics.ts";
const counters = { activeUserWorkersCount: 2, retiredUserWorkersCount: 4, receivedRequestsCount: 19, handledRequestsCount: 17 };
Deno.test("native metrics expose numeric allowlist only and reject invalid counters", async () => {
  const original = (globalThis as unknown as Record<string, unknown>).EdgeRuntime;
  try {
    Object.assign(globalThis, { EdgeRuntime: { getRuntimeMetrics: async () => ({ ...counters, secret: "fixture-never-serialize", heap: { customer: "fixture" } }) } });
    const data = await sampleRuntimeResources();
    if (JSON.stringify(data).includes("fixture") || Object.keys(data).length !== 6 || data.activeUserWorkersCount !== 2) throw new Error("Metrics allowlist failed");
    Object.assign(globalThis, { EdgeRuntime: { getRuntimeMetrics: async () => ({ ...counters, activeUserWorkersCount: "secret" }) } });
    let failed = false;
    try { await sampleRuntimeResources(); } catch { failed = true; }
    if (!failed) throw new Error("Invalid observation accepted");
  } finally { Object.assign(globalThis, { EdgeRuntime: original }); }
});
