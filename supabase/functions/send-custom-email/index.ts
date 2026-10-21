import { emailRpc } from "../_shared/emailQueueClient.ts";
import { enqueueAndAwaitEmail } from "../_shared/emailQueueClient.ts";
import {
  getSupabaseUser,
  createUserClient,
  supabaseAdmin,
  getEmailTemplateAndWrapper,
} from "../_shared/supabaseUtil.ts";
import { authoringContextResponse } from "./authoringContext.ts";
import { loadAuthoringPaymentAccounts } from "./authoringPaymentAccounts.ts";

const _DEFAULT_EMAIL = Deno.env.get("DEFAULT_EMAIL")!;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  try {
    // Handle CORS preflight
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const reqData = await req.json();

    if (reqData.action === "authoringContext") {
      if (req.method !== "POST") {
        return Response.json({ error: "Method not allowed" }, {
          status: 405,
          headers: corsHeaders,
        });
      }
      return await authoringContextResponse(
        reqData,
        req.headers.get("Authorization") || "",
        {
          senderAddress: _DEFAULT_EMAIL || "",
          catalog: async (authorization, entityType, entityId) => {
            const { data, error } = await createUserClient(authorization).rpc(
              "get_entity_email_templates",
              { p_entity_type: entityType, p_entity_id: entityId },
            );
            return error ? null : data;
          },
          resolve: getEmailTemplateAndWrapper,
          paymentAccounts: (context) => loadAuthoringPaymentAccounts(supabaseAdmin, context),
        },
        corsHeaders,
      );
    }

    // Expecting a request body with:
    // - template: a full email template model object (with html, subject, occasion, etc.)
    // - subs: a record of substitutions
    // - email: the recipient's email address
    const { template, subs, email } = reqData;

    if (!template || !subs || !email) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: template, subs, or email",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        },
      );
    }

    // Ensure that the template contains an 'occasion' (or organization) field to check editor permission.
    if (!template.occasion) {
      return new Response(
        JSON.stringify({
          error: "Template does not contain occasion information",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        },
      );
    }

    // Get the authenticated user from the Authorization header.
    const authHeader = req.headers.get("Authorization") || "";
    const user = await getSupabaseUser(authHeader);
    if (!user?.user?.id) {
      return new Response(
        JSON.stringify({ error: "Authentication required" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 401,
        },
      );
    }

    // Verify that the user is an editor for the occasion specified in the template.
    const userId = user.user.id;
    const { data: isEditor, error: permissionError } = await createUserClient(authHeader)
      .rpc("can_send_custom_email", { p_occasion: template.occasion });

    if (permissionError || isEditor !== true) {
      console.error(
        `User ${userId} is not an editor for occasion ${template.occasion}`,
      );
      return new Response(
        JSON.stringify({ error: "Forbidden: User is not an editor" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 403,
        },
      );
    }

    const occasion = await emailRpc("get_email_occasion_context", {
      p_occasion: template.occasion,
    });
    await enqueueAndAwaitEmail({
      to: email,
      kind: "custom",
      ...(reqData.requestId
        ? { dedupeKey: `custom:${userId}:${reqData.requestId}` }
        : {}),
      templateCode: template.code,
      context: {
        organization: occasion.organization,
        actor_id: userId,
        unit: occasion.unit,
        occasion: template.occasion,
      },
      substitutions: subs,
      template,
      from: `Festapp <${_DEFAULT_EMAIL}>`,
    }, {
      enqueuePrepared: (parameters) => emailRpc("enqueue_custom_email_for_actor_v1", {
        ...parameters, p_actor: userId,
      }),
    });

    return new Response(JSON.stringify({ email }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
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
