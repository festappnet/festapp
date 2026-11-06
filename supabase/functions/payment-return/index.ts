import { registeredPaymentHandler } from "../_shared/payments/registry.ts";
import { paymentRegistry } from "../_shared/payments/runtime.ts";
Deno.serve((request) =>
  registeredPaymentHandler(request, paymentRegistry, "return")
);
