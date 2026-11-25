import { PaymentError } from "../payments/contracts.ts";
import {
  openPaymentSource,
  preparePaymentSource,
} from "../payments/paySource.ts";
import { supabaseAdmin } from "../supabaseUtil.ts";
import { goPayPaymentAdapter } from "./adapter.ts";
import { GoPaySandboxProvider } from "./provider.ts";

export function goPayPaymentDependencies() {
  if (Deno.env.get("GOPAY_SANDBOX_ENABLED") !== "true") {
    throw new PaymentError("gopay_not_configured");
  }
  const goId = Deno.env.get("GOPAY_SANDBOX_GO_ID") ?? "";
  const storefrontOrigin = Deno.env.get("GOPAY_SANDBOX_STOREFRONT_ORIGIN") ??
    "";
  const notificationUrl = Deno.env.get("GOPAY_SANDBOX_NOTIFICATION_URL") ?? "";
  return goPayPaymentAdapter({
    callbackToken: new URL(notificationUrl).searchParams.get("hook") ?? "",
    storefrontOrigin,
    provider: new GoPaySandboxProvider({
      goId,
      storefrontOrigin,
      clientId: Deno.env.get("GOPAY_SANDBOX_CLIENT_ID") ?? "",
      clientSecret: Deno.env.get("GOPAY_SANDBOX_CLIENT_SECRET") ?? "",
      notificationUrl,
    }),
    openSource: openPaymentSource,
    prepareSource: preparePaymentSource,
    async rpc(operation, args) {
      const { data, error } = await supabaseAdmin.rpc(
        "gopay_runtime_internal",
        {
          p_operation: operation,
          p_args: args,
        },
      );
      if (error?.message === "INVALID_CAPABILITY") {
        throw new PaymentError("invalid_capability");
      }
      if (error?.message === "GOPAY_LEASE_LOST") {
        throw new PaymentError("payment_lease_lost", true);
      }
      if (error) throw new PaymentError("gopay_action_rejected", true);
      if (
        data?.disposition === "dispatch" && data.snapshot?.accountId !== goId
      ) {
        throw new PaymentError("gopay_account_mismatch");
      }
      return data;
    },
  });
}
