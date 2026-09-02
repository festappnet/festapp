import {
  deliverEmail,
  EmailTemplateNotFoundError,
} from "../_shared/emailDelivery.ts";
import { translatePlatformLinks } from "../_shared/translatePlatformLinks.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";

const _DEFAULT_EMAIL = Deno.env.get("DEFAULT_EMAIL")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 405,
      });
    }

    const reqData = await req.json();
    const userId = reqData.usr; // ID of the user to invite
    const occasionId = reqData.oc; // ID of the occasion
    if (
      typeof userId !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId) ||
      !Number.isSafeInteger(occasionId) || occasionId <= 0
    ) {
      return new Response(JSON.stringify({ error: "Invalid input parameters" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization")! },
        },
      },
    );

    // Generate a 6-digit sign in code.
    const code = Math.floor(100000 + Math.random() * 900000).toString();

    const { data: answer, error: passwordSetError } = await supabaseUser.rpc(
      "reset_user_password",
      {
        p_user_id: userId,
        p_password: code,
      },
    );

    if (passwordSetError || !answer) {
      console.error("Password change has failed.");
      return new Response(JSON.stringify({ error: "Password change fail" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 403,
      });
    }

    // Retrieve occasion user data.
    const occasionUser = await supabaseAdmin
      .from("occasion_users")
      .select("data")
      .eq("user", userId)
      .eq("occasion", occasionId)
      .single();

    if (!occasionUser.data) {
      console.error("User is not part of the occasion.");
      return new Response(
        JSON.stringify({ error: "User is not part of the occasion" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 404,
        },
      );
    }

    // Retrieve the occasion's organization.
    const { data: occasionData, error: occasionError } = await supabaseAdmin
      .from("occasions")
      .select("organization")
      .eq("id", occasionId)
      .single();

    if (occasionError) {
      console.error("Occasion not found.");
      return new Response(JSON.stringify({ error: "Occasion not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    const organizationId = occasionData.organization;

    // Get organization config.
    const orgData = await supabaseAdmin
      .from("organizations")
      .select("data")
      .eq("id", organizationId)
      .single();

    const orgConfig = orgData.data!.data;
    const appName = orgConfig.APP_NAME || "DefaultAppName";
    const defaultLang = orgConfig.DEFAULT_LANGUAGE || "en";
    const platforms = orgConfig.PLATFORMS || [];

    const platformLinksHtml = translatePlatformLinks(platforms, defaultLang);

    const context = { organization: organizationId, occasion: occasionId };

    const { data: userProfile, error: userProfileError } = await supabaseAdmin
      .from("user_info")
      .select("email_readonly,name,surname")
      .eq("id", userId)
      .single();

    if (userProfileError || !userProfile?.email_readonly) {
      return new Response(JSON.stringify({ error: "User profile not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      });
    }

    const subs = {
      name: userProfile.name,
      surname: userProfile.surname,
      code: code,
      email: userProfile.email_readonly,
      appName: appName,
      platformLinks: platformLinksHtml,
    };

    const { data: userEmail, error: emailError } = await supabaseAdmin.rpc(
      "get_user_delivery_email",
      { p_user: userId },
    );

    if (emailError || !userEmail) {
      console.error("Failed to get user's email:", emailError);
      return new Response(
        JSON.stringify({ error: "Failed to get user's email" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        },
      );
    }

    try {
      const delivery = await deliverEmail({
        to: userEmail,
        recipientUser: userId,
        templateCode: "SIGN_IN_CODE",
        context,
        substitutions: subs,
        from: `${appName} | Festapp <${_DEFAULT_EMAIL}>`,
      });
      if (!delivery.logged) {
        return new Response(
          JSON.stringify({
            user: userId,
            code: 202,
            status: "sent_unrecorded",
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 200,
          },
        );
      }
    } catch (error) {
      if (error instanceof EmailTemplateNotFoundError) {
        return new Response(
          JSON.stringify({ error: "Email template not found" }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 404,
          },
        );
      }
      throw error;
    }

    return new Response(
      JSON.stringify({ user: userId, code: 200, status: "sent" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
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
