import { supabaseAdmin } from "../supabaseUtil.ts";
import { PaymentError } from "../payments/contracts.ts";
import {
  openPaymentSource,
  preparePaymentSource,
} from "../payments/paySource.ts";
import { BarionSandboxProvider } from "./provider.ts";
import { barionPaymentAdapter } from "./adapter.ts";

/** A single sandbox merchant. Secrets are server configuration, never SQL,
 * browser data or a caller-selected environment name. Live support is absent.
 */
export function barionPaymentDependencies() {
  const accountId = Deno.env.get("BARION_SANDBOX_SHOP_ID") ?? "";
  const allowedOrigins: unknown = JSON.parse(
    Deno.env.get("BARION_SANDBOX_ALLOWED_ORIGINS") ?? "[]",
  );
  const enabled = Deno.env.get("BARION_SANDBOX_ENABLED") === "true";
  if (
    !enabled || !/^[a-f0-9]{32}$/.test(accountId) ||
    !Array.isArray(allowedOrigins) || allowedOrigins.length === 0 ||
    allowedOrigins.some((origin) =>
      typeof origin !== "string" || new URL(origin).origin !== origin ||
      !origin.startsWith("https://")
    )
  ) {
    throw new Error("barion_not_configured");
  }
  const provider = new BarionSandboxProvider({
    accountId,
    posKey: Deno.env.get("BARION_SANDBOX_POSKEY") ?? "",
    payee: Deno.env.get("BARION_SANDBOX_PAYEE") ?? "",
    callbackUrl: Deno.env.get("BARION_SANDBOX_CALLBACK_URL") ?? "",
    allowedReturnOrigins: allowedOrigins,
  });
  return barionPaymentAdapter({
    provider,
    allowedOrigins,
    openSource: openPaymentSource,
    prepareSource: preparePaymentSource,
    async verifyPlatform() {
      if (
        Deno.env.get("BARION_SANDBOX_ENABLED") !== "true"
      ) throw new PaymentError("barion_not_configured");
    },
    async rpc(operation, args) {
      const { data, error } = await supabaseAdmin.rpc(
        "barion_runtime_internal",
        { p_operation: operation, p_args: args },
      );
      if (error) {
        if (error.message === "INVALID_CAPABILITY") {
          throw new PaymentError("invalid_capability");
        }
        if (error.message === "BARION_LEASE_LOST") {
          throw new PaymentError("payment_lease_lost", true);
        }
        throw new PaymentError("barion_action_rejected", true);
      }
      // A deployment cannot route a saved foreign account through this key.
      if (
        data?.disposition === "dispatch" &&
        data?.snapshot?.accountId !== accountId
      ) {
        throw new PaymentError("barion_account_mismatch");
      }
      return data;
    },
  });
}
