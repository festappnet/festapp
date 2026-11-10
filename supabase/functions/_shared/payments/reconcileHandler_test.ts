import { strict as assert } from "node:assert";
import { AuthError } from "../authError.ts";
import { PaymentRegistry } from "./registry.ts";
import { paymentReconcileHandler } from "./reconcileHandler.ts";
import type { HostedPaymentDependencies } from "./contracts.ts";

Deno.test("machine recovery authenticates before constructing any provider", async () => {
  let constructed = false;
  const registry = new PaymentRegistry([["other", () => { constructed = true; throw new Error("secret"); }]]);
  const response = await paymentReconcileHandler(new Request("https://test/reconcile", {method: "POST", body: "{}"}), registry,
    async () => { throw new AuthError("Denied", 403); });
  assert.equal(response.status, 403); assert(!constructed);
  assert.deepEqual(await response.json(), {error: "unauthorized"});
  assert.equal(response.headers.get("cache-control"), "no-store");
});
Deno.test("a missing credential cannot starve another registered recovery queue", async () => {
  let purged = false;
  const healthy: HostedPaymentDependencies = {
    connector: {id: "healthy", displayName: "Healthy", validateCheckoutUrl: v => v,
      createOrRecoverCheckout: () => { throw new Error("unexpected create"); },
      checkout: () => { throw new Error("unexpected checkout"); },
      recoverCheckout: () => { throw new Error("unexpected recovery"); },
      observePayment: () => { throw new Error("unexpected observation"); }},
    store: {
      purgeExpiredSources: async () => { purged = true; return 0; }, recoverableAttempts: async () => [],
      claimCheckout: () => { throw new Error("unexpected claim"); }, commitCheckout: () => { throw new Error("unexpected commit"); },
      failCheckout: async () => {}, ingest: () => { throw new Error("unexpected ingest"); }, deferRecovery: async () => {},
      readReturn: async () => ({}), readStatus: async () => ({}), readHandoff: async () => ({}), attachHandoff: async () => {},
      claimSync: () => { throw new Error("unexpected sync"); }, failSync: async () => {},
    }, livemode: false, allowedOrigins: [], routes: {payPath: "/pay", returnPath: "/return"},
    verifyPlatform: async () => {}, openSource: () => { throw new Error("unexpected source"); },
  };
  const registry = new PaymentRegistry([["broken", () => { throw new Error("private secret"); }], ["healthy", () => healthy]]);
  const response = await paymentReconcileHandler(new Request("https://test/reconcile", {method: "POST", body: '{"requestSecret":"proof"}'}), registry,
    async input => { assert.equal(input.requestSecret, "proof"); return {user: null}; });
  assert.equal(response.status, 503); assert(purged);
  const body = await response.text(); assert(!body.includes("private secret")); assert(body.includes('"healthy"'));
});
