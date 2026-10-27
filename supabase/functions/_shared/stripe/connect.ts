import {
  type AccountReadiness,
  record,
  StripeBoundaryError,
  type StripeProvider,
} from "./provider.ts";

export class StripeOAuthProvider {
  constructor(
    private readonly secret: string,
    private readonly livemode: boolean,
    private readonly fetcher: typeof fetch = fetch,
  ) {
    if (
      !new RegExp(`^sk_${livemode ? "live" : "test"}_[A-Za-z0-9]+$`).test(
        secret,
      )
    ) throw new StripeBoundaryError("stripe_configuration_invalid");
  }
  async exchange(code: string): Promise<string> {
    if (!/^[A-Za-z0-9_-]{8,512}$/.test(code)) {
      throw new StripeBoundaryError("stripe_oauth_code_invalid");
    }
    let response: Response;
    try {
      response = await this.fetcher("https://connect.stripe.com/oauth/token", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.secret}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({ grant_type: "authorization_code", code }),
        signal: AbortSignal.timeout(15_000),
        redirect: "error",
      });
    } catch {
      throw new StripeBoundaryError("stripe_connection_status_uncertain", true);
    }
    if (!response.ok) throw new StripeBoundaryError("stripe_oauth_rejected");
    let value: Record<string, unknown>;
    try {
      value = record(await response.json());
    } catch {
      throw new StripeBoundaryError("stripe_connection_status_uncertain", true);
    }
    if (
      value.livemode !== this.livemode || value.scope !== "read_write" ||
      typeof value.stripe_user_id !== "string" ||
      !/^acct_[A-Za-z0-9]+$/.test(value.stripe_user_id)
    ) throw new StripeBoundaryError("stripe_oauth_response_invalid");
    // Platform key + connected account scope is the only payment credential.
    // OAuth access/refresh tokens and raw authorization codes are not persisted.
    return value.stripe_user_id;
  }
  async deauthorize(accountId: string, clientId: string): Promise<void> {
    if (
      !/^acct_[A-Za-z0-9]+$/.test(accountId) ||
      !/^ca_[A-Za-z0-9]+$/.test(clientId)
    ) throw new StripeBoundaryError("stripe_disconnect_invalid");
    let response: Response;
    try {
      response = await this.fetcher(
        "https://connect.stripe.com/oauth/deauthorize",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${this.secret}`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: new URLSearchParams({
            stripe_user_id: accountId,
            client_id: clientId,
          }),
          signal: AbortSignal.timeout(15_000),
          redirect: "error",
        },
      );
    } catch {
      throw new StripeBoundaryError("stripe_disconnect_uncertain", true);
    }
    if (!response.ok) {
      throw new StripeBoundaryError("stripe_disconnect_uncertain", true);
    }
    let result: Record<string, unknown>;
    try {
      result = record(await response.json());
    } catch {
      throw new StripeBoundaryError("stripe_disconnect_uncertain", true);
    }
    if (result.stripe_user_id !== accountId) {
      throw new StripeBoundaryError("stripe_disconnect_uncertain", true);
    }
  }
}
export type StripeConnectConfig = {
  livemode: boolean;
  clientId: string;
  callbackUrl: string;
  allowedOrigins: readonly string[];
};
export function stripeAuthorizeUrl(
  config: StripeConnectConfig,
  state: string,
): string {
  if (
    !/^ca_[A-Za-z0-9]+$/.test(config.clientId) || !/^[a-f0-9]{64}$/.test(state)
  ) throw new StripeBoundaryError("stripe_configuration_invalid");
  const redirect = new URL(config.callbackUrl);
  const local = !config.livemode && redirect.protocol === "http:" &&
    ["127.0.0.1", "localhost", "[::1]"].includes(redirect.hostname);
  if (
    (redirect.protocol !== "https:" && !local) ||
    !config.allowedOrigins.includes(redirect.origin) || redirect.username ||
    redirect.password || redirect.search || redirect.hash
  ) throw new StripeBoundaryError("stripe_configuration_invalid");
  const url = new URL("https://connect.stripe.com/oauth/authorize");
  url.search = new URLSearchParams({
    response_type: "code",
    scope: "read_write",
    client_id: config.clientId,
    redirect_uri: redirect.href,
    state,
    stripe_landing: "login",
  }).toString();
  return url.href;
}
export type ConnectDependencies = {
  config: StripeConnectConfig;
  authenticate: (authorization: string) => Promise<{ id: string } | null>;
  userRpc: (
    authorization: string,
    name: string,
    args: Record<string, unknown>,
  ) => Promise<unknown>;
  serviceRpc: (name: string, args: Record<string, unknown>) => Promise<unknown>;
  oauth: Pick<StripeOAuthProvider, "exchange" | "deauthorize">;
  provider: Pick<StripeProvider, "account">;
  verifyPlatform: () => Promise<void>;
};
const baseHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
async function body(req: Request): Promise<Record<string, unknown>> {
  const reader = req.body?.getReader();
  if (!reader) throw new Error("invalid_body");
  let size = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.byteLength;
      if (size > 8192) {
        await reader.cancel();
        throw new Error("body_limit");
      }
      chunks.push(next.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, at);
    at += chunk.length;
  }
  const parsed = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("invalid_body");
  }
  return parsed;
}
export async function stripeConnectHandler(
  req: Request,
  deps: ConnectDependencies,
  callback = false,
): Promise<Response> {
  const origin = req.headers.get("origin");
  const headers = {
    ...baseHeaders,
    ...(origin && deps.config.allowedOrigins.includes(origin)
      ? {
        "Access-Control-Allow-Origin": origin,
        "Vary": "Origin",
        "Access-Control-Allow-Headers":
          "authorization,apikey,content-type,x-client-info",
        "Access-Control-Allow-Methods": "POST,OPTIONS",
      }
      : {}),
  };
  const json = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), { status, headers });
  if (origin && !deps.config.allowedOrigins.includes(origin)) {
    return json({ error: "stripe_origin_not_allowed" }, 403);
  }
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("authorization");
  if (!authorization) return json({ error: "unauthorized" }, 401);
  let actor: { id: string } | null;
  try {
    actor = await deps.authenticate(authorization);
  } catch {
    return json({ error: "unauthorized" }, 401);
  }
  if (!actor) return json({ error: "unauthorized" }, 401);
  let input: Record<string, unknown>;
  try {
    input = await body(req);
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!callback) {
    if (!Number.isSafeInteger(input.unitId) || (input.unitId as number) <= 0) {
      return json({ error: "stripe_unit_required" }, 400);
    }
    if(input.commandId!==undefined&&(typeof input.commandId!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(input.commandId)))return json({error:'invalid_request'},400);
    const args = { p_unit: input.unitId, p_livemode: deps.config.livemode };
    try {
      switch (input.action) {
        case "disconnect-impact":
          return json(
            await deps.userRpc(
              authorization,
              "get_stripe_disconnect_impact",
              args,
            ),
          );
        case "disconnect": {
          if (
            typeof input.connectionId !== "string" ||
            !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/
              .test(input.connectionId)
          ) return json({ error: "invalid_request" }, 400);
          const accepted = record(await deps.userRpc(authorization,
            input.commandId ? 'begin_stripe_disconnect_client_sync_v1' : 'begin_stripe_disconnect', {
              ...args,p_expected_connection:input.connectionId,
              ...(input.commandId ? {p_command_id:input.commandId} : {}),
            }));
          if(input.commandId && accepted.code!==200)return json(accepted);
          const intent = input.commandId ? record(accepted.data) : accepted;
          const resultBody=(result:unknown)=>input.commandId ? {...accepted,data:{...intent,result}} : result;
          await deps.verifyPlatform();
          const claim = record(
            await deps.serviceRpc("claim_stripe_disconnect_internal", {
              p_intent: intent.intentId,
              p_actor: actor.id,
              p_livemode: deps.config.livemode,
            }),
          );
          if (claim.disposition === "replay") return json(resultBody(claim.result));
          if (claim.disposition !== "dispatch") {
            return json(resultBody({ disconnected: false, uncertain: true }), 202);
          }
          try {
            await deps.oauth.deauthorize(
              String(claim.accountId),
              deps.config.clientId,
            );
            return json(
              resultBody(await deps.serviceRpc("finish_stripe_disconnect_internal", {
                p_intent: intent.intentId,
                p_success: true,
              })),
            );
          } catch {
            await deps.serviceRpc("finish_stripe_disconnect_internal", {
              p_intent: intent.intentId,
              p_success: false,
            }).catch(() => {});
            return json(resultBody({ disconnected: false, uncertain: true }), 202);
          }
        }
        case "form-options":
          if (
            !Number.isSafeInteger(input.occasionId) ||
            (input.occasionId as number) <= 0
          ) return json({ error: "invalid_request" }, 400);
          return json(
            await deps.userRpc(authorization, "get_form_stripe_recipient", {
              ...args,
              p_occasion: input.occasionId,
            }),
          );
        case "status":
          return json(
            await deps.userRpc(
              authorization,
              "get_stripe_unit_connection",
              args,
            ),
          );
        case "pause":
        case "resume":
          if(input.commandId)return json(await deps.userRpc(authorization,'set_stripe_unit_paused_client_sync_v1',{
            ...args,p_paused:input.action==='pause',p_command_id:input.commandId,
          }));
          await deps.userRpc(authorization, "set_stripe_unit_paused", {
            ...args,
            p_paused: input.action === "pause",
          });
          return json(
            await deps.userRpc(
              authorization,
              "get_stripe_unit_connection",
              args,
            ),
          );
        case "start":
        case "replace": {
          // Validate callback configuration before persisting a flow.
          stripeAuthorizeUrl(deps.config, "0".repeat(64));
          const started = record(
            await deps.userRpc(
              authorization,
              "begin_stripe_connection_flow",
              args,
            ),
          );
          await deps.verifyPlatform();
          return json({
            flowId: started.flowId,
            expiresAt: started.expiresAt,
            url: stripeAuthorizeUrl(deps.config, String(started.state)),
          });
        }
        default:
          return json({ error: "stripe_action_not_supported" }, 400);
      }
    } catch {
      return json({ error: "stripe_connection_action_rejected" }, 403);
    }
  }
  if (
    typeof input.state !== "string" || !/^[a-f0-9]{64}$/.test(input.state) ||
    (input.error !== "access_denied" &&
      (typeof input.code !== "string" ||
        !/^[A-Za-z0-9_-]{8,512}$/.test(input.code)))
  ) return json({ error: "stripe_connection_flow_invalid" }, 400);
  let claim: Record<string, unknown>;
  try {
    claim = record(
      await deps.serviceRpc("claim_stripe_connection_flow_internal", {
        p_state: input.state,
        p_actor: actor.id,
        p_livemode: deps.config.livemode,
      }),
    );
  } catch {
    return json({ error: "stripe_connection_flow_invalid" }, 403);
  }
  if (claim.disposition === "replay") {
    const result = record(claim.result);
    return result.connected === true && Number.isSafeInteger(result.unitId) &&
        typeof result.connectionId === "string"
      ? json(result)
      : json({ error: "stripe_connection_status_uncertain" }, 503);
  }
  if (claim.disposition !== "claimed") {
    return json({ error: "stripe_connection_status_uncertain" }, 409);
  }
  const finishArgs = { p_flow: claim.flowId, p_lease: claim.lease };
  try {
    if (input.error === "access_denied") {
      await deps.serviceRpc("finish_stripe_connection_flow_error_internal", {
        ...finishArgs,
        p_denied: true,
      });
      return json({ status: "cancelled", unitId: claim.unitId });
    }
    await deps.verifyPlatform();
    const accountId = await deps.oauth.exchange(input.code as string);
    const account: AccountReadiness = await deps.provider.account(accountId);
    if (!account.modelVerified) {
      throw new StripeBoundaryError("stripe_account_model_unverified");
    }
    const result = record(
      await deps.serviceRpc("complete_stripe_connection_flow_internal", {
        ...finishArgs,
        p_account: account,
      }),
    );
    if (result.connected !== true || result.unitId !== claim.unitId) {
      throw new Error("invalid_receipt");
    }
    return json(result);
  } catch {
    try {
      await deps.serviceRpc("finish_stripe_connection_flow_error_internal", {
        ...finishArgs,
        p_denied: false,
      });
    } catch {
      /* A completed SQL result is recovered by replay, never by another code exchange. */
    }
    return json({
      error: "stripe_connection_status_uncertain",
      unitId: claim.unitId,
    }, 503);
  }
}
