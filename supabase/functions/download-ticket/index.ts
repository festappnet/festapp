import { documentLimits, boundDocumentInput, boundDocumentOutput } from '../_shared/documentLimits.ts';
import { storedBatchTicketPdf } from '../_shared/ticketBatchStorage.ts';
import { prepareTicketRenderer } from '../_shared/ticketGeneration.ts';
import { supabaseAdmin, createUserClient } from "../_shared/supabaseUtil.ts";
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

    const authorizationHeader = req.headers.get("Authorization");
    let client;
    if (requestSecret) {
      await authorizeRequest({ requestSecret });
      client = supabaseAdmin;
    } else if (authorizationHeader) client = createUserClient(authorizationHeader);
    else throw new AuthError("Unauthorized", 401);
    const { data: result, error: rpcError } = await client.rpc('get_ticket_document_data_v1', { p_ticket: ticketId });
    if (rpcError) throw new AuthError("Ticket document temporarily unavailable", rpcError.code === 'PT429' ? 429 : 403);
    if (!result) throw new Error("Ticket document unavailable");
    const limits=documentLimits(result);
    boundDocumentInput(result,limits.inputBytes);
    const { ticket, occasion } = result;

    let pdfBytes:Uint8Array;
    if(ticket.batch_id) {
      const stored=await storedBatchTicketPdf(ticketId,client);
      if(!stored)throw new Error('batch_document_missing');
      pdfBytes=stored;
    } else {
      const render = await prepareTicketRenderer(occasion, ticket, result.order_data);
      pdfBytes=(await render(ticket)).bytes;
    }

    boundDocumentOutput(pdfBytes,1,limits);
    // Encode only after enforcing the output cap.
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