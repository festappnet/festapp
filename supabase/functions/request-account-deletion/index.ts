import {
  awaitEmailAccepted,
  emailRpc,
  prepareAccountEmail,
} from "../_shared/emailQueueClient.ts";
import {
  accountDeletionCors,
  createOpaqueToken,
  jsonResponse,
  maskEmail,
  sha256,
} from "../_shared/accountDeletion.ts";
import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { parseOrganizationBranding } from "../_shared/organizationBranding.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: accountDeletionCors });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthenticated" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    const text = await request.text();
    body = text ? JSON.parse(text) : {};
  } catch {
    return jsonResponse({ error: "invalid_request" }, 400);
  }
  if (!body || Array.isArray(body) || Object.keys(body).length !== 0) {
    return jsonResponse(
      { error: "authoritative_identity_fields_forbidden" },
      400,
    );
  }

  const { data: authData, error: authError } = await createUserClient(
    authorization,
  ).auth.getUser();
  const user = authData.user;
  if (authError || !user?.id || !user.email) {
    return jsonResponse({ error: "unauthenticated" }, 401);
  }

  const { data: profile } = await supabaseAdmin.from("user_info")
    .select("organization").eq("id", user.id).maybeSingle();
  const organizationId = Number(profile?.organization);
  if (
    !profile || !Number.isSafeInteger(organizationId) || organizationId <= 0
  ) {
    return jsonResponse({ error: "account_unavailable" }, 403);
  }
  const { data: organizationRow, error: organizationError } =
    await supabaseAdmin
      .from("organizations").select("data").eq("id", organizationId).single();
  let branding;
  try {
    if (organizationError) throw organizationError;
    branding = parseOrganizationBranding(organizationRow?.data);
  } catch {
    return jsonResponse({ error: "configuration_unavailable" }, 503);
  }
  const { data: deliveryEmail, error: deliveryEmailError } = await supabaseAdmin
    .rpc("get_user_delivery_email", { p_user: user.id });
  if (deliveryEmailError || !deliveryEmail) {
    return jsonResponse({ error: "account_unavailable" }, 403);
  }

  const token = createOpaqueToken();
  const tokenHash = await sha256(token);
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const maskedEmail = maskEmail(deliveryEmail);
  try {
    const emailInput = {
      to: deliveryEmail,
      recipientUser: user.id,
      templateCode: "ACCOUNT_DELETION_CONFIRM",
      context: { organization: organizationId },
      substitutions: {
        confirmationUrl: `${branding.defaultUrl}/delete-account?token=${
          encodeURIComponent(token)
        }`,
        expiresAt,
        appName: branding.appName,
      },
      from: `${branding.appName} | Festapp <${
        Deno.env.get("DEFAULT_EMAIL") || ""
      }>`,
    };

    const snapshot = await prepareAccountEmail(emailInput);
    const created = await emailRpc("enqueue_account_email", {
      p_operation: "deletion_confirm",
      p_domain: {
        user_id: user.id,
        token_hash: tokenHash,
        masked_email: maskedEmail,
      },
      p_context: emailInput.context,
      p_recipient: deliveryEmail,
      ...snapshot,
      p_dedupe: `deletion:${user.id}:${Math.floor(Date.now() / 300000)}`,
      p_code: "ACCOUNT_DELETION_CONFIRM",
      p_expires: expiresAt,
    });
    await awaitEmailAccepted(created.message_id);
  } catch {
    return jsonResponse({ error: "delivery_failed" }, 503);
  }

  return jsonResponse({ status: "email_sent", maskedEmail, expiresAt }, 202);
});
