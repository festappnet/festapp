import {
  fetchPublicBinary,
  parseSafeTarget,
} from "../fetch-http-data/safeFetch.ts";
import { fetchPinnedHttps } from "../fetch-http-data/pinnedHttps.ts";
import { extractPolicyId, MAX_HTML_BYTES } from "./policy.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
interface Dependencies {
  supabaseUrl: string;
  anonKey: string;
  fetch?: typeof fetch;
  websiteFetch?: typeof fetchPinnedHttps;
  resolveDns?: (query: string, recordType: "A" | "AAAA") => Promise<string[]>;
}
export async function handleProbe(
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") return reply(405, { error: "method" });
  const authorization = request.headers.get("Authorization");
  if (!authorization || !/^Bearer [^\s]+$/i.test(authorization)) {
    return reply(401, { error: "unauthorized" });
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return reply(400, { error: "invalid_request" });
  }
  if (
    !body || !Number.isSafeInteger(body.unitId) || body.unitId <= 0 ||
    typeof body.origin !== "string"
  ) return reply(400, { error: "invalid_request" });
  let target;
  try {
    target = parseSafeTarget(body.origin);
    if (target.origin !== body.origin) {
      return reply(400, { error: "invalid_origin" });
    }
  } catch {
    return reply(400, { error: "invalid_origin" });
  }
  const rpc = (name: string, params: object) =>
    (deps.fetch ?? fetch)(`${deps.supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        Authorization: authorization,
        apikey: deps.anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(params),
      signal: AbortSignal.timeout(15_000),
    });
  try {
    // This RPC requires exactly the same manager predicate as the save RPC.
    const permission = await rpc("get_unit_website_consent_bindings", {
      p_unit: body.unitId,
    });
    if (!permission.ok) {
      return reply(permission.status === 401 ? 401 : 403, {
        error: "forbidden",
      });
    }
    const scope = await permission.json();
    if (
      !Array.isArray(scope.saved_origins) ||
      !scope.saved_origins.includes(body.origin)
    ) return reply(403, { error: "origin_not_saved" });
    const { bytes } = await fetchPublicBinary(
      body.origin,
      {
        fetch: deps.websiteFetch ?? fetchPinnedHttps,
        resolveDns: deps.resolveDns ?? Deno.resolveDns,
      },
      MAX_HTML_BYTES,
      ["text/html", "application/xhtml+xml"],
      true,
    );
    const policyId = extractPolicyId(new TextDecoder().decode(bytes));
    if (!policyId) return reply(422, { error: "policy_not_found" });
    if (body.confirm === true) {
      // A changed policy needs a fresh organizer confirmation, never silent pinning.
      if (body.expectedPolicyId !== policyId) {
        return reply(409, { error: "policy_changed", policyId });
      }
      const saved = await rpc("save_unit_website_consent_binding", {
        p_unit: body.unitId,
        p_website_origin: body.origin,
        p_platform: body.platform,
        p_provider_config: { provider: "complianz", policyId },
        p_expected_version: body.version,
        p_expected_consent_revision: body.revision,
        p_confirm: true,
      });
      return reply(saved.status, await saved.json());
    }
    return reply(200, { policyId });
  } catch {
    return reply(502, { error: "detection_unavailable" });
  }
}
