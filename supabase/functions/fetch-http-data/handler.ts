import { encode as base64Encode } from "https://deno.land/std@0.170.0/encoding/base64.ts";
import { fetchPublicImage, UnsafeTargetError } from "./safeFetch.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Dependencies {
  supabaseUrl: string;
  anonKey: string;
  fetch?: typeof globalThis.fetch;
  resolveDns?: (query: string, recordType: "A" | "AAAA") => Promise<string[]>;
}

function reply(status: number, body: object): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

/** Authorize with the caller's JWT through the same RPC as image upload. */
export async function handleFetchHttpData(
  request: Request,
  dependencies: Dependencies,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return reply(405, { error: "Method not allowed" });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return reply(400, { error: "Invalid request" });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return reply(400, { error: "Invalid request" });
  }
  const { targetUrl, occasionId, unitId } = body as Record<string, unknown>;
  const hasOccasion = occasionId !== undefined;
  const hasUnit = unitId !== undefined;
  const owner = hasOccasion ? occasionId : unitId;
  if (hasOccasion === hasUnit || typeof owner !== "number" ||
    !Number.isSafeInteger(owner) || owner <= 0 ||
    typeof targetUrl !== "string" || !targetUrl) {
    return reply(400, { error: "Invalid request" });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization || !/^Bearer [^\s]+$/i.test(authorization)) {
    return reply(401, { error: "Unauthorized" });
  }
  // No request-secret or service-role path. PostgREST validates the caller JWT
  // and the RPC evaluates auth.uid(), using only the public anon API key.
  const send = dependencies.fetch ?? globalThis.fetch;
  try {
    if (!dependencies.supabaseUrl || !dependencies.anonKey) {
      throw new Error("Missing backend configuration");
    }
    const permission = await send(
      `${dependencies.supabaseUrl}/rest/v1/rpc/check_upload_permission`,
      {
        method: "POST",
        headers: {
          apikey: dependencies.anonKey,
          Authorization: authorization,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(hasOccasion
          ? { p_occasion_id: owner }
          : { p_unit_id: owner }),
        signal: AbortSignal.timeout(15_000),
      },
    );
    if (permission.status === 401) return reply(401, { error: "Unauthorized" });
    if (permission.status === 403) return reply(403, { error: "Forbidden" });
    if (!permission.ok) throw new Error("Permission check failed");
    if (await permission.json() !== true) return reply(403, { error: "Forbidden" });

    // Only safeFetch talks to the external host; it never receives user headers.
    const image = await fetchPublicImage(targetUrl, {
      fetch: (url, init) => send(url, init),
      resolveDns: dependencies.resolveDns ?? Deno.resolveDns,
    });
    return reply(200, {
      data: base64Encode(Uint8Array.from(image.bytes).buffer),
      contentType: image.contentType,
    });
  } catch (error) {
    const status = error instanceof UnsafeTargetError ? 400 : 500;
    console.error("fetch_http_data_failed", { status });
    return reply(status, {
      error: status === 500 ? "Unexpected error occurred" : "Request rejected",
    });
  }
}
