import { type PaymentDependencies, PaymentError } from "./contracts.ts";
import { paymentHandler, paymentHeaders, readPaymentBytes } from "./http.ts";

/** An explicit allowlist, never a module path or environment name from a client.
 * No default provider: unknown or mismatched bindings fail closed.
 */
export class PaymentRegistry {
  private readonly factories: Map<string, () => PaymentDependencies>;
  private readonly sourceFields: readonly string[];
  constructor(
    entries: readonly (readonly [string, () => PaymentDependencies, string?])[],
  ) {
    this.factories = new Map();
    this.sourceFields = entries.flatMap((entry) => entry[2] ? [entry[2]] : []);
    for (const [id, factory] of entries) {
      if (!/^[a-z][a-z0-9_-]{0,31}$/.test(id) || this.factories.has(id)) {
        throw new PaymentError("payment_connector_registration_invalid");
      }
      this.factories.set(id, factory);
    }
  }
  has(id: unknown): id is string {
    return typeof id === "string" && this.factories.has(id);
  }
  ids(): readonly string[] {
    return [...this.factories.keys()];
  }
  stripOrderSources(order: Record<string, unknown>) {
    for (const field of this.sourceFields) delete order[field];
  }
  resolve(id: unknown): PaymentDependencies {
    if (!this.has(id)) throw new PaymentError("payment_connector_unavailable");
    const binding = this.factories.get(id)!();
    if (binding.connector.id !== id) {
      throw new PaymentError("payment_connector_identity_mismatch");
    }
    return binding;
  }
}

export async function registeredPaymentHandler(
  request: Request,
  registry: PaymentRegistry,
  action: "checkout" | "return" | "connect" = "checkout",
): Promise<Response> {
  if (request.method !== "POST") {
    return new Response(null, {
      status: request.method === "OPTIONS" ? 204 : 405,
      headers: {
        ...paymentHeaders,
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "content-type,authorization,apikey,x-client-info",
        "Access-Control-Allow-Methods": "POST,OPTIONS",
      },
    });
  }
  try {
    const body = JSON.parse(
      new TextDecoder().decode(await readPaymentBytes(request.clone(), 4096)),
    );
    if (!registry.has(body?.provider)) {
      return Response.json({ error: "payment_connector_unavailable" }, {
        status: 400,
        headers: paymentHeaders,
      });
    }
    let binding: PaymentDependencies;
    try {
      binding = registry.resolve(body.provider);
    } catch (error) {
      if (!(error instanceof Error) || error.message !== `${body.provider}_not_configured`) throw error;
      return Response.json({ error: error.message }, {
        status: 503,
        headers: { ...paymentHeaders, "Access-Control-Allow-Origin": "*" },
      });
    }
    if (action === "connect") {
      if (!binding.connection) {
        throw new PaymentError("payment_connection_unavailable");
      }
      const { provider: _, ...input } = body;
      const headers = new Headers(request.headers);
      headers.delete("Content-Length");
      return await binding.connection.handle(
        new Request(request, { headers, body: JSON.stringify(input) }),
      );
    }
    return await paymentHandler(request, binding, action === "return");
  } catch {
    return Response.json({ error: "payment_temporarily_unavailable" }, {
      status: 503,
      headers: paymentHeaders,
    });
  }
}
