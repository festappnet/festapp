import { createUserClient, supabaseAdmin } from "../supabaseUtil.ts";
import { StripeProvider, StripeBoundaryError } from "./provider.ts";
import { type StripePaymentsDependencies } from "./payments.ts";
import {
  type ConnectDependencies,
  stripeAuthorizeUrl,
  StripeOAuthProvider,
} from "./connect.ts";

function stripeEnvironment() {
  const mode = Deno.env.get("STRIPE_MODE");
  if (mode !== "test" && mode !== "live") {
    throw new Error("stripe_not_configured");
  }
  const livemode = mode === "live";
  const secretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const apiVersion = Deno.env.get("STRIPE_API_VERSION") ?? "";
  const platform = Deno.env.get("STRIPE_PLATFORM_ACCOUNT_ID") ?? "";
  if (!/^acct_[A-Za-z0-9]+$/.test(platform)) {
    throw new Error("stripe_not_configured");
  }
  const allowedOrigins = JSON.parse(
    Deno.env.get("STRIPE_ALLOWED_ORIGINS") ?? "[]",
  );
  if (
    !Array.isArray(allowedOrigins) || allowedOrigins.length === 0 ||
    allowedOrigins.some((x) => typeof x !== "string")
  ) throw new Error("stripe_not_configured");
  const provider = new StripeProvider({
    secretKey,
    livemode,
    apiVersion,
    allowedReturnOrigins: allowedOrigins,
  });
  let verification: Promise<void> | undefined;
  return {
    livemode,
    allowedOrigins,
    secretKey,
    provider,
    verifyPlatform: () => verification ??= provider.verifyPlatform(platform),
  };
}
export function stripeConnectDependencies(): ConnectDependencies {
  const { livemode, allowedOrigins, secretKey, provider, verifyPlatform } =
    stripeEnvironment();
  const config = {
    livemode,
    allowedOrigins,
    clientId: Deno.env.get("STRIPE_CONNECT_CLIENT_ID") ?? "",
    callbackUrl: Deno.env.get("STRIPE_CONNECT_CALLBACK_URL") ?? "",
  };
  const oauth = new StripeOAuthProvider(secretKey, livemode);
  stripeAuthorizeUrl(config, "0".repeat(64));
  return {
    config,
    provider,
    oauth,
    verifyPlatform,
    async authenticate(authorization) {
      const { data, error } = await createUserClient(authorization).auth
        .getUser();
      return error || !data.user ? null : { id: data.user.id };
    },
    async userRpc(authorization, name, args) {
      const { data, error } = await createUserClient(authorization).rpc(
        name,
        args,
      );
      if (error) throw new Error("stripe_action_rejected");
      return data;
    },
    async serviceRpc(name, args) {
      const { data, error } = await supabaseAdmin.rpc(name, args);
      if (error) throw new Error("stripe_service_action_rejected");
      return data;
    },
  };
}

export function stripePaymentDependencies(): StripePaymentsDependencies {
  const { livemode, allowedOrigins, provider, verifyPlatform } =
    stripeEnvironment();
  const webhookSecrets = JSON.parse(
    Deno.env.get("STRIPE_WEBHOOK_SECRETS") ?? "[]",
  );
  if (
    !Array.isArray(webhookSecrets) || webhookSecrets.length > 3 ||
    webhookSecrets.some((x) =>
      typeof x !== "string" || !/^whsec_[A-Za-z0-9]+$/.test(x)
    )
  ) throw new Error("stripe_not_configured");
  return {
    livemode,
    allowedOrigins,
    provider,
    verifyPlatform,
    webhookSecrets,
    async rpc(name, args) {
      const { data, error } = await supabaseAdmin.rpc(name, args);
      if (error) {
        if(error.message==='INVALID_CAPABILITY')throw new StripeBoundaryError('invalid_capability');
        if(error.code==='PT429')throw new StripeBoundaryError('payment_rate_limited',true);
        throw new Error("stripe_action_rejected");
      }
      return data;
    },
  };
}
