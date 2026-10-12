import { createMonitoring } from "./monitoring-sdk/index.js";

/** Router-level reporting covers handled 5xx responses and uncaught worker errors.
 * Bodies, URLs, identities and credentials never enter Monitoring.
 */
export async function monitorEdgeRequest(
  service: string,
  request: Request,
  handle: (request: Request) => Promise<Response>,
  environment: Record<string, string>,
  defer?: (work: Promise<unknown>) => void,
): Promise<Response> {
  let failure: unknown;
  let status = 500;
  try {
    const response = await handle(request);
    status = response.status;
    return response;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    if (status >= 500 && environment.FESTAPP_MONITORING_TOKEN) {
      const work = reportFailure(service, status, failure, environment);
      if (defer) {
        try { defer(work); } catch { await work; }
      } else await work;
    }
  }
}

async function reportFailure(service: string, status: number, error: unknown, env: Record<string, string>) {
  try {
    const monitor = createMonitoring({
      baseUrl: env.FESTAPP_MONITORING_URL,
      token: env.FESTAPP_MONITORING_TOKEN,
      service: "festapp-edge",
      release: env.FESTAPP_MONITORING_RELEASE ?? "v1",
      diagnostic: (code: string) => console.warn(`festapp_monitoring_${code}`),
    });
    monitor.reportError(error ?? new Error("edge_response_failed"), {
      code: "edge_request_failed",
      operation: service,
      context: { http_status: status },
    });
    const result = await monitor.close({ timeoutMs: 1000 });
    if (result.status !== "flushed") console.warn("festapp_monitoring_not_recorded");
  } catch { console.warn("festapp_monitoring_unavailable"); }
}
