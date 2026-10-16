/** Numeric process-wide counters from the pinned Edge Runtime main worker.
 * Uses existing logs: no endpoint, credentials, payloads or additional process.
 */
export const RESOURCE_METRICS_PREFIX = "festapp_runtime_resource_metrics ";
const FIELDS = ["activeUserWorkersCount", "retiredUserWorkersCount", "receivedRequestsCount", "handledRequestsCount"] as const;
type NativeRuntime = { getRuntimeMetrics(): Promise<Record<string, unknown>> };

export async function sampleRuntimeResources(): Promise<Record<string, number>> {
  const runtime = (globalThis as unknown as { EdgeRuntime: NativeRuntime }).EdgeRuntime;
  const metrics = await runtime.getRuntimeMetrics();
  const data: Record<string, number> = { version: 1, at: Date.now() };
  for (const field of FIELDS) {
    const value = metrics[field];
    if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) throw new Error("Invalid runtime counter");
    data[field] = value;
  }
  return data;
}

export function startRuntimeResourceMetrics(): () => void {
  let busy = false;
  const sample = async () => {
    if (busy) return;
    busy = true;
    try { console.log(RESOURCE_METRICS_PREFIX + JSON.stringify(await sampleRuntimeResources())); }
    catch { console.warn("festapp_runtime_resource_metrics_unavailable"); }
    finally { busy = false; }
  };
  void sample();
  const timer = setInterval(() => { void sample(); }, 60_000);
  return () => clearInterval(timer);
}
