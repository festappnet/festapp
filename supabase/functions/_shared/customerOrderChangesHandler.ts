import {
  customerChangeHeaders as headers,
  openCustomerChangeSource,
  prepareCustomerChangeDelivery,
  readCustomerChangeInput,
} from "./customerOrderChanges.ts";
export type CustomerChangeRpc = (
  params: Record<string, unknown>,
) => Promise<any>;
const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });
/** HTTP boundary; the injected RPC is the one scoped SQL gateway, not a domain mock. */
export function createCustomerOrderChangesHandler(rpc: CustomerChangeRpc) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return new Response("ok", { headers });
    if (request.method !== "POST") return respond({ code: 405 }, 405);
    let action = "";
    try {
      const input = await readCustomerChangeInput(request);
      action = input.action;
      const params = {
        p_token: input.token,
        p_order: input.orderId ?? null,
        p_operation: input.operation ?? null,
        p_payload: input.payload ?? {},
        p_command: input.commandId ?? null,
        p_fingerprint: input.fingerprint ?? null,
      };
      if (action === "challenge") {
        const context = await rpc({ ...params, p_action: "challenge_context" });
        const delivery = await prepareCustomerChangeDelivery(
          context,
          input.token,
          input.operation!,
          input.payload ?? {},
        );
        // The canonical gateway supplies this header. Browser input never supplies IP.
        const ip = request.headers.get("cf-connecting-ip") ??
          request.headers.get("x-real-ip") ?? "unavailable";
        const key = await crypto.subtle.importKey(
          "raw",
          new TextEncoder().encode(Deno.env.get("EMAIL_PAYLOAD_KEY") ?? ""),
          { name: "HMAC", hash: "SHA-256" },
          false,
          ["sign"],
        );
        const digest = await crypto.subtle.sign(
          "HMAC",
          key,
          new TextEncoder().encode(ip),
        );
        const ipHash = Array.from(
          new Uint8Array(digest),
          (b) => b.toString(16).padStart(2, "0"),
        ).join("");
        await rpc({
          ...params,
          p_action: "challenge",
          p_delivery: delivery,
          p_ip_hash: ipHash,
        });
        return respond({ code: 202 }, 202);
      }
      const data = await rpc({ ...params, p_action: action });
      if (action === "resolve") {
        return respond({
          code: 200,
          ...await openCustomerChangeSource(
            data.source,
            input.token,
            data.orderId,
          ),
        });
      }
      return respond(data);
    } catch (error) {
      if (action === "challenge") return respond({ code: 202 }, 202);
      const code = (error as { code?: string })?.code;
      const status = ["40001", "40P01", "55P03"].includes(code ?? "")
        ? 409
        : code === "22023"
        ? 422
        : 403;
      return respond({
        code: status,
        errorCode: status === 409
          ? "CUSTOMER_CHANGE_CONFLICT"
          : status === 422
          ? "CUSTOMER_FIELDS_INVALID"
          : "CUSTOMER_CHANGE_UNAVAILABLE",
      }, status);
    }
  };
}
