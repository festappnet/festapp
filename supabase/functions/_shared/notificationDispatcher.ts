import { AuthError } from "./authError.ts";

type Rpc = (name: string, args?: Record<string, unknown>) => Promise<unknown>;
/** Each HTTP RPC commits independently; no transaction spans the drain loop. */
export function notificationRpc(
  url: string,
  key: string,
  transport: typeof fetch = fetch,
): Rpc {
  return async (name, args = {}) => {
    const response = await transport(
      `${url.replace(/\/$/, "")}/rest/v1/rpc/${name}`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${key}`,
          apikey: key,
          "content-type": "application/json",
        },
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(3000),
      },
    );
    if (!response.ok) throw new Error("notification_rpc_failed");
    return await response.json();
  };
}
export async function drainNotifications(
  rpc: Rpc,
  { now = Date.now, milliseconds = 10000, maxCalls = 200 } = {},
) {
  const started = now();
  let calls = 0, delivered = 0, prepared = 0, views = 0, idle = false;
  while (calls < maxCalls && now() - started < milliseconds) {
    const counts: number[] = [];
    for (
      const [name, limit] of [["project_notification_center", 500], [
        "prepare_notification_center",
        100,
      ], ["prepare_notification_center_views", 100]] as const
    ) {
      const count = await rpc(name, { p_limit: limit });
      if (
        typeof count !== "number" || !Number.isSafeInteger(count) ||
        count < 0 || count > limit
      ) throw new Error("notification_invalid_work_receipt");
      counts.push(count);
    }
    delivered += counts[0];
    prepared += counts[1];
    views += counts[2];
    calls++;
    // No work in this pass does not certify an empty queue: deferred, backing-off
    // and quarantined records remain durable and visible in SQL diagnostics.
    if (counts.every((count) => count === 0)) {
      idle = true;
      break;
    }
  }
  if (!idle) await rpc("wake_notification_center");
  return {
    delivered,
    prepared,
    views,
    calls,
    idle,
    elapsedMs: now() - started,
  };
}
export function notificationHandler(dependencies: {
  authorize(secret: string): Promise<unknown>;
  rpc: Rpc;
  waitUntil?: (work: Promise<unknown>) => void;
}) {
  const headers = {
    "content-type": "application/json",
    "cache-control": "no-store",
  };
  return async (request: Request) => {
    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "method_not_allowed" }), {
        status: 405,
        headers,
      });
    }
    let body: { requestSecret?: unknown };
    try {
      body = await request.json();
    } catch {
      return new Response(JSON.stringify({ error: "invalid_request" }), {
        status: 400,
        headers,
      });
    }
    try {
      if (
        !body || typeof body.requestSecret !== "string" ||
        !body.requestSecret || body.requestSecret.length > 4096
      ) throw new AuthError("System authorization required", 401);
      await dependencies.authorize(body.requestSecret);
      const work = drainNotifications(dependencies.rpc);
      dependencies.waitUntil?.(work);
      return new Response(JSON.stringify(await work), { headers });
    } catch (error) {
      return new Response(
        JSON.stringify({ error: "notification_worker_failed" }),
        { status: error instanceof AuthError ? error.status : 500, headers },
      );
    }
  };
}
