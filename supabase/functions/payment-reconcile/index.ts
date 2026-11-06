import { paymentReconcileHandler } from "../_shared/payments/reconcileHandler.ts";
import { paymentRegistry } from "../_shared/payments/runtime.ts";
Deno.serve(request => paymentReconcileHandler(request, paymentRegistry));
