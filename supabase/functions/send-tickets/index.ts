import { prepareTicketRenderer } from '../_shared/ticketGeneration.ts';
import { deliverEmail, EmailTemplateNotFoundError } from "../_shared/emailDelivery.ts";
import { supabaseAdmin, createUserClient } from "../_shared/supabaseUtil.ts";
import { authorizeRequest, AuthError } from "../_shared/auth.ts";

const _DEFAULT_EMAIL = Deno.env.get("DEFAULT_EMAIL")!;

// CORS Headers.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/**
 * Main function served by Deno. Orchestrates fetching tickets and sending emails.
 * Supports a request secret that, if provided and valid, skips the editor check.
 */
Deno.serve(async (req) => {
  try {
    // Handle CORS preflight request.
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const reqData = await req.json();
    const { requestSecret, orderId, email } = reqData;

    // Validate input parameters first.
    if (typeof orderId !== "number" || typeof email !== "string") {
      return new Response(JSON.stringify({ error: "Invalid input parameters" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // etch Order Details (Admin level access required to get initial data)
    const { data: orderDetailsResponse, error: rpcError } = await supabaseAdmin.rpc('get_order_details_for_email', { p_order_id: orderId });

    if (rpcError || orderDetailsResponse.code !== 200) {
        console.error("Error fetching order details:", rpcError || orderDetailsResponse.message);
        throw new Error("Failed to fetch order details.");
    }

    const { order, occasion, payment_info, bank_account, latest_history_id, reference_history, form_data, reply_to } = orderDetailsResponse.data;

    const authorizationHeader = req.headers.get("Authorization");

    // Perform authorization. Returns the user object if authorized via Token, or null if via Secret.
    const { user } = await authorizeRequest({ requestSecret, authorizationHeader, occasionId: occasion.id });

    const occasionTitle = occasion.title;
    const features = occasion.features;
    const ticketFeature = features?.find((feature: any) => feature.code === "ticket");
    const isTicketEnabled = ticketFeature?.is_enabled ?? false;

    // Fetch tickets only if the ticket feature is enabled.
    let tickets: any[] = [];
    const { data: fetchedTickets, error: ticketsError } = await supabaseAdmin.rpc("get_tickets_with_details", { order_id: orderId });
    if (ticketsError || !fetchedTickets) {
            console.error("Error fetching tickets:", ticketsError);
            return new Response(JSON.stringify({ error: "Error fetching tickets" }), {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
              status: 500,
            });
        }
        tickets = fetchedTickets.filter((t: any) => t.state !== "storno");
        if (!tickets.length) {
            return new Response(JSON.stringify({ error: "No valid tickets" }), {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
              status: 400,
            });
    }

    const organizationId = occasion.organization;
    const context = { organization: organizationId, occasion: occasion.id, unit: occasion.unit};

    let attachments: Array<{
      filename: string;
      content: Uint8Array;
      contentType: string;
      encoding: "binary" | "base64";
    }> = [];

    if (isTicketEnabled) {
      const renderTicket = await prepareTicketRenderer(occasion, tickets[0], order.data);
      for (const ticket of tickets) {
        try {
          const { bytes: pdfBytes } = await renderTicket(ticket);
          attachments.push({
            filename: `ticket_${ticket.ticket_symbol}.pdf`,
            content: pdfBytes,
            contentType: "application/pdf",
            encoding: "binary",
          });
        } catch (error) {
          throw error; // Abort the batch; never send a partial set after a render failure.
        }
      }
      if (!attachments.length) {
        return new Response(JSON.stringify({ error: "Failed to generate any ticket PDFs" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        });
      }
    }

    try {
      await deliverEmail({
        to: email,
        templateCode: "TICKET_ORDER_PAYMENT_DONE",
        context,
        substitutions: { occasionTitle },
        from: `${occasionTitle} | Festapp <${_DEFAULT_EMAIL}>`,
        attachments,
        replyTo: reply_to,
      });
    } catch (error) {
      if (error instanceof EmailTemplateNotFoundError) {
        return new Response(JSON.stringify({ error: "Email template not found" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 404,
        });
      }
      throw error;
    }

    const ticketIds = tickets.map((ticket) => ticket.id);
    let updateError = null;

    // Update Status Logic
    // If we have an authenticated user (from authorizeRequest), use the User-scoped client and _ws RPC
    if (user && authorizationHeader) {
        const userClient = createUserClient(authorizationHeader);
        const { error } = await userClient.rpc("update_order_and_tickets_to_sent_ws", { order_id: orderId, ticket_ids: ticketIds });
        updateError = error;
    } else {
        // Fallback to Admin client for Secret/System requests
        const { error } = await supabaseAdmin.rpc("update_order_and_tickets_to_sent", { order_id: orderId, ticket_ids: ticketIds });
        updateError = error;
    }

    if (updateError) {
      console.error("Failed to update order and tickets to sent:", updateError);
      return new Response(JSON.stringify({ error: "Failed to update order/tickets to sent" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      });
    }

    return new Response(JSON.stringify({ message: "Tickets sent successfully", code: 200 }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    // Handle both custom AuthError and any other unexpected errors.
    const isAuthError = error instanceof AuthError;
    const status = isAuthError ? error.status : 500;
    const message = error instanceof Error
      ? error.message
      : "Unexpected error occurred";

    console.error(`Error [${status}]: ${message}`, isAuthError ? '' : error);

    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: status,
    });
  }
});
