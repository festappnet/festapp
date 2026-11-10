/** Compatibility endpoint for the installed machine caller. */
import { paymentReconcileHandler } from "../_shared/payments/reconcileHandler.ts";
import { paymentRegistry, paymentRefundRpc } from "../_shared/payments/runtime.ts";
Deno.serve(request => paymentReconcileHandler(request, paymentRegistry, undefined, paymentRefundRpc));
