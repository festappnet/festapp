import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { presentPayment } from "../_shared/paymentPresentation.ts";
import { resolveTicketOrderCommandIdentity } from "./commandIdentity.ts";
import { useFakturoid } from "./fakturoid.ts";

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

    const {
      orderDetails: directOrderDetails,
      replacement,
      commandId: requestedCommandId,
      clientId: requestedClientId,
    } = await req.json();
    const identity = resolveTicketOrderCommandIdentity(
      requestedCommandId,
      requestedClientId,
      replacement,
    );
    if (!identity) {
      return new Response(
        JSON.stringify({ error: "Missing command identity" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        },
      );
    }
    const { commandId, clientId } = identity;
    if (!directOrderDetails && !replacement) {
      return new Response(JSON.stringify({ error: "Missing order payload" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }
    const authorizationHeader = req.headers.get("Authorization");
    if (replacement && !authorizationHeader) {
      return new Response(
        JSON.stringify({ error: "Replacement requires authentication" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 401,
        },
      );
    }
    const rpcName = replacement
      ? "replace_blueprint_order_client_sync_v1"
      : "create_ticket_order_client_sync_v1";
    const rpcParameters = replacement
      ? {
        p_spot_ids: replacement.spotIds,
        p_input_data: replacement.inputData,
        p_command_id: commandId,
      }
      : {
        p_order: directOrderDetails,
        p_command_id: commandId,
        p_client_id: clientId,
      };
    let ticketOrderResponse: any;

    if (authorizationHeader) {
      console.info("Creating ticket order via user-scoped authorization");
      const userClient = createUserClient(authorizationHeader);

      const { data, error } = await userClient.rpc(
        rpcName,
        rpcParameters,
      );
      if (error) {
        console.error("RPC Error (User Context):", error);
        ticketOrderResponse = { code: 500, message: error.message };
      } else {
        ticketOrderResponse = data?.data ?? data;
      }
    } else {
      console.info("Creating ticket order via system authorization");
      const { data, error } = await supabaseAdmin.rpc(
        rpcName,
        rpcParameters,
      );
      ticketOrderResponse = error
        ? { code: 500, message: error.message }
        : data?.data ?? data;
    }

    // Safety check if response is null/undefined
    if (!ticketOrderResponse) {
      console.error("Ticket order response is null/undefined");
      return new Response(
        JSON.stringify({
          error: "Failed to create ticket order (empty response)",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        },
      );
    }

    const ticketOrder = ticketOrderResponse;

    if (ticketOrder.code !== 200) {
      console.error("Ticket order error:", ticketOrder);
      return new Response(JSON.stringify(ticketOrder), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    const order = ticketOrder.order;
    if (Number(order?.payment_info?.amount) > 0) {
      const { data: services, error: servicesError } = await supabaseAdmin.rpc(
        "get_external_services",
        { p_order_id: order.id },
      );
      if (servicesError) throw servicesError;
      const fakturoid = services?.find((service: any) =>
        service.type === "FAKTUROID"
      );
      if (fakturoid) {
        const config = fakturoid.data;
        const variableSymbol = await useFakturoid(
          {
            client_id: config.client_id,
            client_secret: config.client_secret,
            slug: config.slug,
            subject_id: config.subject_id,
            note: config.note,
          },
          order,
          order.occasion.title,
          commandId,
          [],
          "prepare",
        );
        if (String(order.payment_info.currency_code).toUpperCase() === "CZK") {
          const { error: updateError } = await supabaseAdmin.rpc(
            "update_payment_info_variable_symbol",
            {
              p_payment_info_id: order.payment_info.id,
              p_variable_symbol: Number(variableSymbol),
            },
          );
          if (updateError) throw updateError;
        }
      }
    }

    const paymentInfo = ticketOrder.order?.payment_info;
    const payment = paymentInfo && Number(paymentInfo.amount) > 0
      ? presentPayment(paymentInfo)
      : null;
    const paymentQr = payment
      ? {
        format: payment.qrFormat,
        payload: payment.qrPayload,
        reference_kind: payment.referenceKind,
        reference: payment.referenceDisplay,
        account_number: paymentInfo.account_number,
        account_number_human_readable:
          paymentInfo.account_number_human_readable,
        amount: payment.amount,
        currency_code: payment.currency,
      }
      : null;

    return new Response(
      JSON.stringify({
        ticketOrder,
        payment_qr: paymentQr,
        code: 200,
        delivery: "queued",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(
      JSON.stringify({ error: "Unexpected error occurred" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      },
    );
  }
});
