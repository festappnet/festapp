import { generateSignInCode } from "../_shared/signInCode.ts";
import {
  awaitEmailAccepted,
  emailRpc,
  prepareAccountEmail,
} from "../_shared/emailQueueClient.ts";
import { EmailTemplateNotFoundError } from "../_shared/emailDelivery.ts";
import { translatePlatformLinks } from "../_shared/translatePlatformLinks.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { finishRegistration } from "./registrationFlow.ts";

const _DEFAULT_EMAIL = Deno.env.get("DEFAULT_EMAIL")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const reqData = await req.json();
    const userEmail = reqData.email.trim();
    const organizationId = reqData.organization;

    const orgData = await supabaseAdmin
      .from("organizations")
      .select("data")
      .eq("id", organizationId)
      .single();

    if (orgData.error || !orgData.data) {
      console.error("Organization data not found.");
      return new Response(
        JSON.stringify({ error: "Organization data not found" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 404,
        },
      );
    }

    const orgConfig = orgData.data.data;
    const appName = orgConfig.APP_NAME;
    const defaultUrl = orgConfig.DEFAULT_URL;

    if (!appName || !defaultUrl) {
      console.error("Required configuration is missing.");
      return new Response(
        JSON.stringify({ error: "Missing required configuration" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        },
      );
    }

    const userData = await supabaseAdmin
      .from("user_info")
      .select()
      .eq("email_readonly", userEmail)
      .eq("organization", organizationId)
      .maybeSingle();

    if (userData.data != null) {
      return new Response(
        JSON.stringify({ email: userEmail, code: 409 }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    const defaultLang = orgConfig.DEFAULT_LANGUAGE || "en";
    const userLang = reqData.lang || defaultLang || "cs";
    const unitTitle = userLang === "cs" ? "Moje akce" : "My events";

    const code = generateSignInCode();

    const platforms = orgConfig.PLATFORMS || [];
    const platformLinksHtml = translatePlatformLinks(platforms, defaultLang);
    const snapshot = await prepareAccountEmail({
      to: userEmail,
      templateCode: "SIGN_IN_CODE",
      context: { organization: organizationId },
      substitutions: {
        code,
        email: userEmail,
        platformLinks: platformLinksHtml,
        appName,
      },
      from: `${appName} | Festapp <${_DEFAULT_EMAIL}>`,
    });
    const queued = await emailRpc("enqueue_account_email", {
      p_operation: "register",
      p_domain: {
        ...(reqData.signInCodeVersion === 2
          ? { invitation_code: code }
          : { password: code }),
        data: reqData,
        unit_title: unitTitle,
      },
      p_context: { organization: organizationId },
      p_recipient: userEmail,
      ...snapshot,
      p_dedupe: `register:${userEmail.toLowerCase()}`,
      p_code: "SIGN_IN_CODE",
      p_expires: new Date(Date.now() + 600000).toISOString(),
    });
    const createResult = { data: queued.domain, error: null };
    try {
      const result = await finishRegistration({
        creationResult: createResult,
        userEmail,
        organizationId,
        appName,
        code,
        platformLinksHtml,
        defaultEmail: _DEFAULT_EMAIL,
      }, () => awaitEmailAccepted(queued.message_id));
      return new Response(
        JSON.stringify(result.body),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: result.status,
        },
      );
    } catch (error) {
      if (error instanceof EmailTemplateNotFoundError) {
        return new Response(
          JSON.stringify({ error: "Template not found" }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 404,
          },
        );
      }
      throw error;
    }
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({ error: "Unexpected error occurred" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      },
    );
  }
});
