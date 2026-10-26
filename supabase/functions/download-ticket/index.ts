import { documentLimits, boundDocumentInput, boundDocumentOutput } from '../_shared/documentLimits.ts';
import { authorizeCustomerTicket } from './customerAccess.ts';
import { prepareTicketRenderer } from '../_shared/ticketGeneration.ts';
import { supabaseAdmin, createUserClient } from "../_shared/supabaseUtil.ts";
import { authorizeRequest, AuthError } from "../_shared/auth.ts";
// Import Buffer for easy Base64 encoding (Supabase Deno supports Node polyfills)
import { Buffer } from "node:buffer";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const reqData = await req.json();
    const { requestSecret, ticketId } = reqData;
    const customer = Object.hasOwn(reqData, "token") || Object.hasOwn(reqData, "orderId");

    if (!Number.isSafeInteger(ticketId) || ticketId <= 0) {
      return new Response(JSON.stringify({ error: "Invalid input parameters" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    if (!customer && !requestSecret && !req.headers.get("Authorization")) {
      throw new AuthError("Unauthorized", 401);
    }

    if (customer && !await authorizeCustomerTicket(reqData, async (token, orderId) =>
      await supabaseAdmin.rpc('get_customer_order_overview', { p_token: token, p_order_id: orderId }))) {
      throw new AuthError("Ticket is not available", 403);
    }

    const authorizationHeader=req.headers.get('Authorization');
    let client;
    if(customer)client=supabaseAdmin; // Capability was checked before any ticket read above.
    else if(requestSecret){await authorizeRequest({requestSecret});client=supabaseAdmin;}
    else client=createUserClient(authorizationHeader!);
    const {data:result,error:rpcError}=await client.rpc('get_ticket_document_data_v1',{p_ticket:ticketId});
    if(rpcError)throw new AuthError('Ticket document temporarily unavailable',rpcError.code==='PT429'?429:403);
    if(!result)throw new AuthError('Ticket is not available',403);
    const limits=documentLimits(result);boundDocumentInput(result,limits.inputBytes);
    const {ticket,occasion}=result;
    if(customer&&!['paid','sent','used'].includes(ticket.state))throw new AuthError('Ticket is not available',403);

    const render = await prepareTicketRenderer(occasion, ticket, result.order_data);
    const { bytes: pdfBytes } = await render(ticket);

    boundDocumentOutput(pdfBytes,1,limits);
    // Encode only the bounded output.
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