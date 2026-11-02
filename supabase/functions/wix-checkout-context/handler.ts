import {
  verifyWixIdentity,
  WixIdentityError,
} from "../_shared/wix/identity.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, content-type, apikey, x-client-info, x-wix-linguist",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
export type WixContextDependencies = {
  configuration(): Promise<{ appId: string; organizationId: number }>;
  fetcher?: typeof fetch;
  issue(
    args: {
      p_form_link: string;
      p_instance: string;
      p_site: string;
      p_organization: number;
      p_app: string;
    },
  ): Promise<unknown>;
};
async function boundedBody(request: Request): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) return "";
  let size = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1024) {
        await reader.cancel();
        throw new WixIdentityError("INVALID_FORM_LINK", 400);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const joined = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder().decode(joined);
}
export async function wixCheckoutContext(
  request: Request,
  deps: WixContextDependencies,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers });
  }
  if (request.method !== "POST") {
    return Response.json({ error: "METHOD_NOT_ALLOWED" }, {
      status: 405,
      headers,
    });
  }
  try {
    const body = await boundedBody(request);
    let input;
    try {
      input = JSON.parse(body);
    } catch {
      throw new WixIdentityError("INVALID_FORM_LINK", 400);
    }
    if (
      !input || typeof input.formLink !== "string" ||
      input.formLink.length > 200 ||
      !/^[\p{L}\p{N}_-]+$/u.test(input.formLink)
    ) throw new WixIdentityError("INVALID_FORM_LINK", 400);
    const configuration = await deps.configuration();
    if (
      !Number.isSafeInteger(configuration.organizationId) ||
      configuration.organizationId <= 0
    ) {
      throw new WixIdentityError("WIX_NOT_CONFIGURED", 503);
    }
    const identity = await verifyWixIdentity(
      request.headers.get("authorization"),
      configuration.appId,
      deps.fetcher,
    );
    let result;
    try {
      result = await deps.issue({
        p_form_link: input.formLink,
        p_instance: identity.instanceId,
        p_site: identity.siteId,
        p_organization: configuration.organizationId,
        p_app: configuration.appId,
      });
    } catch (error) {
      // Missing, closed and demo forms are expected business rejections.
      // Preserve real database/configuration failures as server incidents.
      if (
        error && typeof error === "object" &&
        "code" in error && error.code === "22023" &&
        "message" in error && error.message === "FORM_UNAVAILABLE"
      ) throw new WixIdentityError("FORM_UNAVAILABLE", 404);
      throw new WixIdentityError("CHECKOUT_CONTEXT_UNAVAILABLE", 503);
    }
    if (
      !result || typeof result !== "object" || !("context" in result) ||
      typeof result.context !== "string" ||
      !/^[A-Za-z0-9_-]+\.[0-9a-f]{64}$/.test(result.context) ||
      !("expiresAt" in result) || typeof result.expiresAt !== "number" ||
      !Number.isSafeInteger(result.expiresAt)
    ) {
      throw new WixIdentityError("CHECKOUT_CONTEXT_UNAVAILABLE", 503);
    }
    return Response.json({
      context: result.context,
      expiresAt: result.expiresAt,
    }, { headers });
  } catch (error) {
    const failure = error instanceof WixIdentityError
      ? error
      : new WixIdentityError("CHECKOUT_CONTEXT_UNAVAILABLE", 503);
    return Response.json({ error: failure.code }, {
      status: failure.status,
      headers,
    });
  }
}
