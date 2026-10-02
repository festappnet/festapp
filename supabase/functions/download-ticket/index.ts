import { prepareTicketRenderer } from '../_shared/ticketGeneration.ts';
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { authorizeRequest, AuthError } from "../_shared/auth.ts";
// Import Buffer for easy Base64 encoding (Supabase Deno supports Node polyfills)
import { Buffer } from "node:buffer";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const reqData = await req.json();
    const { requestSecret, ticketId } = reqData;

    if (typeof ticketId !== "number") {
      return new Response(JSON.stringify({ error: "Invalid input parameters" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    const { data: result, error: rpcError } = await supabaseAdmin.rpc('get_ticket_details_for_generating', {
      ticket_id_input: ticketId
    });

    if (rpcError || !result) {
      throw new Error("Failed to fetch ticket details.");
    }

    const { ticket, occasion } = result;

    const authorizationHeader = req.headers.get("Authorization");
    await authorizeRequest({ requestSecret, authorizationHeader, occasionId: occasion.id });

    const render = await prepareTicketRenderer(occasion, ticket, result.order_data);
    const { bytes: pdfBytes } = await render(ticket);

    // --- CHANGED HERE: Encode to Base64 ---
    const base64Pdf = Buffer.from(pdfBytes).toString('base64');

    // Return JSON with the Base64 string
    return new Response(JSON.stringify({ file: base64Pdf, filename: `ticket_${ticket.ticket_symbol}.pdf` }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error) {
    const isAuthError = error instanceof AuthError;
    const status = isAuthError ? error.status : 500;
    const message = error.message || "Unexpected error occurred";
    console.error(`Error: ${message}`);

    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: status,
    });
  }
});