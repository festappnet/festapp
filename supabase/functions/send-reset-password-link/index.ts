import { emailRpc, prepareAccountEmail } from "../_shared/emailQueueClient.ts";
import { EmailTemplateNotFoundError } from "../_shared/emailDelivery.ts";
import { translatePlatformLinks } from "../_shared/translatePlatformLinks.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
const _DEFAULT_EMAIL = Deno.env.get("DEFAULT_EMAIL")!;
const _ALLOWED_ORIGINS = new Set(
  (Deno.env.get("FESTAPP_ALLOWED_WEB_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean),
);

const corsHeaders = (origin: string | null) => ({
  ...(origin && _ALLOWED_ORIGINS.has(origin)
    ? { "Access-Control-Allow-Origin": origin }
    : {}),
  "Vary": "Origin",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
});

const json = (origin: string | null, status = 200) =>
  new Response(
    JSON.stringify({ accepted: true }),
    {
      status,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    },
  );

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function consumeLimit(key: string, limit: number): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "consume_password_reset_rate_limit_v1",
    {
      p_key_hash: await sha256(key),
      p_limit: limit,
      p_window_seconds: 900,
    },
  );
  if (error || typeof data !== "boolean") {
    throw error ?? new Error("rate_limit_unavailable");
  }
  return data;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  if (origin && !_ALLOWED_ORIGINS.has(origin)) return json(null, 403);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") return json(origin, 405);

  let reqData: Record<string, unknown>;
  try {
    reqData = await req.json();
  } catch {
    return json(origin, 400);
  }
  const userEmail = typeof reqData.email === "string"
    ? reqData.email.trim().toLowerCase()
    : "";
  const organizationId = Number(reqData.organization);
  if (
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(userEmail) ||
    !Number.isSafeInteger(organizationId) || organizationId <= 0
  ) return json(origin);

  const sourceAddress = req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    req.headers.get("x-real-ip") ?? "unknown";
  try {
    const sourceAllowed = await consumeLimit(`source:${sourceAddress}`, 20);
    if (!sourceAllowed) return json(origin);
    const accountAllowed = await consumeLimit(
      `account:${organizationId}:${userEmail}`,
      3,
    );
    if (!accountAllowed) return json(origin);
  } catch (error) {
    console.error("Password reset rate limiter unavailable", error);
    return json(origin, 503);
  }

  const orgData = await supabaseAdmin
    .from("organizations")
    .select("data")
    .eq("id", organizationId)
    .single();

  if (orgData.error || !orgData.data) {
    console.error("Organization data not found.");
    return json(origin);
  }

  const orgConfig = orgData.data.data;
  const appName = orgConfig.APP_NAME || "DefaultAppName";
  const defaultUrl = orgConfig.DEFAULT_URL;
  const platforms = orgConfig.PLATFORMS || [];
  const defaultLang = orgConfig.DEFAULT_LANGUAGE || "en";
  try {
    const parsedDefaultUrl = new URL(defaultUrl);
    if (
      parsedDefaultUrl.protocol !== "https:" || parsedDefaultUrl.username ||
      parsedDefaultUrl.password
    ) {
      throw new Error("invalid reset origin");
    }
  } catch (error) {
    console.error("Organization password reset origin is invalid", error);
    return json(origin);
  }

  // Generate platform links HTML
  const platformLinksHtml = translatePlatformLinks(platforms, defaultLang);

  const userData = await supabaseAdmin
    .from("user_info")
    .select("id,email_readonly")
    .eq("organization", organizationId)
    .ilike("email_readonly", userEmail)
    .maybeSingle();

  if (userData.data == null) {
    return json(origin);
  }

  const userId = userData.data.id;
  const { data: deliveryEmail, error: deliveryEmailError } = await supabaseAdmin
    .rpc("get_user_delivery_email", { p_user: userId });
  if (deliveryEmailError || !deliveryEmail) {
    console.error(
      "Password reset delivery address unavailable",
      deliveryEmailError,
    );
    return json(origin);
  }
  const token = crypto.randomUUID();

  const context = { organization: organizationId };

  const resetPasswordLink = `${defaultUrl}/resetPassword?token=${token}`;

  // Prepare substitutions
  const subs = {
    email: userData.data.email_readonly,
    resetPasswordLink: resetPasswordLink,
    platformLinks: platformLinksHtml,
    appName: appName,
  };

  try {
    const emailInput = {
      to: deliveryEmail,
      recipientUser: userId,
      templateCode: "RESET_PASSWORD",
      context,
      substitutions: subs,
      from: `${appName} | Festapp <${_DEFAULT_EMAIL}>`,
    };
    const snapshot = await prepareAccountEmail(emailInput);
    await emailRpc("enqueue_account_email", {
      p_operation: "reset_token",
      p_domain: { user_id: userId, token },
      p_context: context,
      p_recipient: deliveryEmail,
      ...snapshot,
      p_dedupe: `reset:${userId}:${
        reqData.requestId ?? Math.floor(Date.now() / 300000)
      }`,
      p_code: "RESET_PASSWORD",
      p_expires: new Date(Date.now() + 3600000).toISOString(),
    });
  } catch (error) {
    if (error instanceof EmailTemplateNotFoundError) {
      console.error("Password reset template not found");
      return json(origin);
    }
    console.error("Password reset delivery failed", error);
    return json(origin);
  }

  return json(origin);
});
