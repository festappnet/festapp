import { synchronizeCanonicalBankConnections } from "../_shared/bankSyncClient.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { authorizeRequest, AuthError } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  try {
    // Handle CORS preflight requests
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const requestData = await req.json();
    const { occasionLink } = requestData;

    if (!occasionLink) {
      return new Response(JSON.stringify({ error: "Missing occasion link" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // 1. Fetch the occasion and its associated unit ID
    const { data: occasionData, error: occasionError } = await supabaseAdmin
      .from("occasions")
      .select("id, unit")
      .eq("link", occasionLink)
      .single();

    if (occasionError || !occasionData) {
      console.error("Occasion not found:", occasionError);
      return new Response(JSON.stringify({ error: "Occasion not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    const occasionId = occasionData.id;
    const unitId = occasionData.unit;

    // 2. Authorize the user as an editor for the occasion
    await authorizeRequest({
      authorizationHeader: req.headers.get("Authorization"),
      occasionId: occasionId,
    });

    const results = await synchronizeCanonicalBankConnections(unitId);
    return new Response(JSON.stringify({ results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error) {
    // Handle both custom AuthError and any other unexpected errors.
    const isAuthError = error instanceof AuthError;
    const status = isAuthError ? error.status : 500;
    const message = error instanceof Error
      ? error.message
      : "An unexpected error occurred";

    console.error(`Error [${status}]: ${message}`, isAuthError ? '' : error);

    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: status,
    });
  }
});
