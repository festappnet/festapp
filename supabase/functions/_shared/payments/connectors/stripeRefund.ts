import { type RefundCapability } from "../contracts.ts";
import type { StripeProvider } from "../../stripe/provider.ts";

/** A distinct typed capability on the existing connector, not another registry. */
export function stripeRefundCapability(deps: {
  verifyPlatform(): Promise<void>;
  provider: Partial<Pick<StripeProvider, "requestRefund" | "recoverRefund">>;
}): RefundCapability | undefined {
  if (!deps.provider.requestRefund || !deps.provider.recoverRefund) return undefined;
  return {
    confirmation: "verified_provider_observation",
    currencies: ["CZK", "EUR", "PLN", "USD", "GBP"],
    async requestRefund(snapshot) {
      await deps.verifyPlatform();
      return await deps.provider.requestRefund!(snapshot);
    },
    async recoverRefund(snapshot, state) {
      await deps.verifyPlatform();
      return await deps.provider.recoverRefund!(snapshot, state);
    },
  };
}
