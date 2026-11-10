import { reconcilePaymentRefunds, type RefundRpc } from "./refunds.ts";
import { AuthError } from "../authError.ts";
import { paymentHeaders, readPaymentBytes } from "./http.ts";
import { PaymentRegistry } from "./registry.ts";
import { reconcilePayments } from "./reconcile.ts";

/** Machine authorization precedes provider construction, credentials and I/O. */
export async function paymentReconcileHandler(request: Request, registry: PaymentRegistry,
  authorize: (input: {requestSecret?: string}) => Promise<unknown> = async input => (await import("../auth.ts")).authorizeRequest(input),
  refundRpc?: RefundRpc) {
  if (request.method !== "POST") return Response.json({error: "method_not_allowed"}, {status: 405, headers: paymentHeaders});
  try {
    const body = JSON.parse(new TextDecoder().decode(await readPaymentBytes(request, 1024)));
    await authorize({requestSecret: typeof body?.requestSecret === "string" ? body.requestSecret : undefined});
    // Independent bounded queues: a broken provider cannot consume another's budget.
    const results = await Promise.all(registry.ids().map(async provider => {
      const correlationId = crypto.randomUUID();
      try { const binding = registry.resolve(provider);
        return {provider, results: binding.hostedCheckout ? await reconcilePayments(binding.hostedCheckout) : []}; }
      catch {
        console.error(JSON.stringify({provider, operation: "reconcile", retryClass: "uncertain", correlationId}));
        return {provider, results: [{state: "uncertain"}]};
      }
    }));
    if (refundRpc) {
      try { results.push({provider: 'refund_operations', results: await reconcilePaymentRefunds(registry, refundRpc)}); }
      catch { results.push({provider: 'refund_operations', results: [{state: 'uncertain'}]}); }
    }
    return Response.json({results}, {status: results.some(r => r.results.some(v => v.state === "uncertain")) ? 503 : 200, headers: paymentHeaders});
  } catch (error) {
    return Response.json({error: error instanceof AuthError ? "unauthorized" : "payment_recovery_unavailable"},
      {status: error instanceof AuthError ? error.status : 503, headers: paymentHeaders});
  }
}
