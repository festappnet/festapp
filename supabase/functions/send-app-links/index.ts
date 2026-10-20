import { enqueueAndAwaitEmail } from "../_shared/emailQueueClient.ts";
import { EmailTemplateNotFoundError } from "../_shared/emailDelivery.ts";
import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { translatePlatformLinks } from "../_shared/translatePlatformLinks.ts";
import { deliverAppLinks, isCsmOrganization } from "./appLinksDelivery.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthenticated" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_request" }, 400);
  }

  const occasionId = Number(body.oc);
  const targetUserId = body.usr;
  if (
    !Number.isSafeInteger(occasionId) || occasionId <= 0 ||
    !isUuid(targetUserId)
  ) {
    return jsonResponse({ error: "invalid_request" }, 400);
  }

  try {
    await authorizeRequest({
      authorizationHeader: authorization,
      occasionId,
      permission: "manageUsers",
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({
        error: error.status === 403 ? "forbidden" : "unauthenticated",
      }, error.status);
    }
    return jsonResponse({ error: "unauthenticated" }, 401);
  }

  const { data: occasion, error: occasionError } = await supabaseAdmin
    .from("occasions")
    .select("organization,unit")
    .eq("id", occasionId)
    .maybeSingle();
  if (occasionError || !occasion) {
    return jsonResponse({ error: "occasion_not_found" }, 404);
  }
  if (!isCsmOrganization(occasion.organization)) {
    return jsonResponse({ error: "feature_unavailable" }, 403);
  }

  const { data: membership, error: membershipError } = await supabaseAdmin
    .from("occasion_users")
    .select("user")
    .eq("occasion", occasionId)
    .eq("user", targetUserId)
    .maybeSingle();
  if (membershipError || !membership) {
    return jsonResponse({ error: "occasion_user_not_found" }, 404);
  }

  const { data: organization, error: organizationError } = await supabaseAdmin
    .from("organizations")
    .select("data")
    .eq("id", occasion.organization)
    .maybeSingle();
  if (organizationError || !organization) {
    return jsonResponse({ error: "organization_not_found" }, 404);
  }

  const { data: deliveryEmail, error: deliveryEmailError } = await supabaseAdmin
    .rpc("get_user_delivery_email", {
      p_user: targetUserId,
    });
  if (deliveryEmailError || !deliveryEmail) {
    return jsonResponse({ error: "delivery_email_unavailable" }, 422);
  }

  const config = organization.data ?? {};
  const appName = typeof config.APP_NAME === "string"
    ? config.APP_NAME
    : "Festapp";
  const language = typeof config.DEFAULT_LANGUAGE === "string"
    ? config.DEFAULT_LANGUAGE
    : "en";
  const platforms = Array.isArray(config.PLATFORMS) ? config.PLATFORMS : [];
  const appLinks = translatePlatformLinks(platforms, language);
  if (!appLinks) {
    return jsonResponse({ error: "application_links_unavailable" }, 422);
  }

  try {
    await deliverAppLinks({
      userId: targetUserId,
      occasionId,
      unitId: occasion.unit,
      organizationId: occasion.organization,
      deliveryEmail,
      appName,
      appLinks,
      fromEmail: Deno.env.get("DEFAULT_EMAIL") || "",
    }, {
      deliverEmail: enqueueAndAwaitEmail,
    });
  } catch (error) {
    if (error instanceof EmailTemplateNotFoundError) {
      return jsonResponse({ error: "email_template_not_found" }, 404);
    }
    return jsonResponse({ error: "application_links_delivery_failed" }, 502);
  }

  return jsonResponse({ status: "sent" }, 200);
});
