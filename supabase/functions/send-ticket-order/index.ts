import { withOrderIdentity } from "../_shared/orderOverview.ts";
import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { presentPayment } from "../_shared/paymentPresentation.ts";
import {
  hasSingleTicketOrderPayload,
  resolveTicketOrderCommandIdentity,
} from "./commandIdentity.ts";
import { executeConfirmedSeatOrder } from "./confirmedReplacement.ts";
import { prepareFakturoidTicketOrder } from "./fakturoidPreparation.ts";
import { fakturoidGateway } from "./fakturoid.ts";
import { prepareStripePaySource } from "../_shared/stripe/paySource.ts";
import { prepareStripeOrderDelivery } from "../_shared/stripe/orderDelivery.ts";
import { stripePaymentDependencies } from "../_shared/stripe/environment.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const {
      orderDetails: directOrderDetails,
      replacement,
      waitlistAcceptance,
      commandId: requestedCommandId,
      clientId: requestedClientId,
    } = await req.json();
    if (
      !hasSingleTicketOrderPayload({
        orderDetails: directOrderDetails,
        replacement,
        waitlistAcceptance,
      })
    ) {
      return Response.json({
        code: 400,
        errorCode: "INVALID_TICKET_ORDER_INTENT",
      }, { status: 400, headers: corsHeaders });
    }
    if (waitlistAcceptance && (!requestedCommandId || !requestedClientId)) {
      return new Response(
        JSON.stringify({ error: "Missing command identity" }),
        { status: 400, headers: corsHeaders },
      );
    }
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
    if (!directOrderDetails && !replacement && !waitlistAcceptance) {
      return new Response(JSON.stringify({ error: "Missing order payload" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }
    const authorizationHeader = req.headers.get("Authorization");
    if (replacement?.inputData?.payment_method === "stripe") {
      return Response.json({ error: "STRIPE_REPLACEMENT_UNSUPPORTED" }, {
        status: 400,
        headers: corsHeaders,
      });
    }
    const preparedOrder = directOrderDetails
      ? { ...directOrderDetails }
      : directOrderDetails;
    let stripeDependencies:
      | ReturnType<typeof stripePaymentDependencies>
      | undefined;
    if (preparedOrder) {
      delete preparedOrder.stripePaymentSource;
      if (preparedOrder.payment_method === "stripe") {
        stripeDependencies = stripePaymentDependencies();
        preparedOrder.stripePaymentSource = await prepareStripePaySource();
      }
    }
    if (replacement && !authorizationHeader) {
      return new Response(
        JSON.stringify({ error: "Replacement requires authentication" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 401,
        },
      );
    }
    if (replacement?.confirmation != null) {
      const result = await executeConfirmedSeatOrder({
        replacement,
        commandId,
        client: createUserClient(authorizationHeader!),
        serviceClient: supabaseAdmin,
        gateway: fakturoidGateway,
      });
      return Response.json(result, { headers: corsHeaders, status: 200 });
    }
    const rpcName = waitlistAcceptance
      ? "execute_waitlist_command_client_sync_v1"
      : replacement
      ? "replace_blueprint_order_client_sync_v1"
      : "create_ticket_order_client_sync_v1";
    let acceptanceActor: string | null = null;
    if (
      waitlistAcceptance && authorizationHeader &&
      authorizationHeader !== `Bearer ${Deno.env.get("SUPABASE_ANON_KEY")}`
    ) {
      const { data, error } = await createUserClient(authorizationHeader).auth
        .getUser();
      if (error || !data.user) {
        return new Response(
          JSON.stringify({ error: "Invalid authorization" }),
          { status: 401, headers: corsHeaders },
        );
      }
      acceptanceActor = data.user.id;
    }
    const rpcParameters = waitlistAcceptance
      ? {
        p_operation: "accept",
        p_payload: { ...waitlistAcceptance, orderDetails: preparedOrder },
        p_command_id: commandId,
        p_client_id: clientId,
        p_actor: acceptanceActor,
        p_deliveries: [],
      }
      : replacement
      ? {
        p_spot_ids: replacement.spotIds,
        p_input_data: replacement.inputData,
        p_command_id: commandId,
      }
      : {
        p_order: preparedOrder,
        p_command_id: commandId,
        p_client_id: clientId,
      };
    let ticketOrderResponse: any;
    let acceptanceEnvelope: any;
    const acceptanceFailure = (message: string) => ({
      ...acceptanceEnvelope,
      status: "rejected",
      code: 503,
      data: { code: 503, errorCode: "PAYMENT_PREPARATION_FAILED", message },
      sync: { replacements: [] },
    });

    if (authorizationHeader && !waitlistAcceptance) {
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
      if (waitlistAcceptance && !error) acceptanceEnvelope = data;
      if (waitlistAcceptance && error) {
        return new Response(
          JSON.stringify({ error: "waitlist_command_failed" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      ticketOrderResponse = error
        ? {
          code: error.code === "PT429" ? 429 : 500,
          errorCode: error.code === "PT429"
            ? "ABUSE_LIMIT_EXCEEDED"
            : undefined,
          message: error.message,
        }
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
      return new Response(
        JSON.stringify(waitlistAcceptance ? acceptanceEnvelope : ticketOrder),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    ticketOrder.order = await withOrderIdentity(
      ticketOrder.order,
      async (params) => {
        const { data, error } = await supabaseAdmin.rpc(
          "read_order_identity",
          params,
        );
        if (error) throw error;
        return data;
      },
    );
    const order = ticketOrder.order;
    let stripeResult: Record<string, unknown> | undefined;
    if (order?.payment_info?.payment_method === "stripe") {
      const { data: source, error: sourceError } = await supabaseAdmin.rpc(
        "get_stripe_order_pay_source_internal",
        {
          p_order: order.id,
          p_command: commandId,
        },
      );
      if (sourceError) throw new Error("stripe_payment_source_unavailable");
      stripeResult = await prepareStripeOrderDelivery(
        source,
        order.id,
        commandId,
        preparedOrder?.payment_surface ??
          waitlistAcceptance?.orderDetails?.payment_surface,
        ticketOrder.payment,
        stripeDependencies ?? stripePaymentDependencies(),
      );
    }
    if (
      order?.payment_info?.payment_method !== "stripe" &&
      Number(order?.payment_info?.amount) > 0
    ) {
      const preparation = await prepareFakturoidTicketOrder({
        client: supabaseAdmin,
        gateway: fakturoidGateway,
        order,
        commandId,
        unitName: order.occasion.title,
        replacement: !!replacement,
      });
      if (!preparation.ok) {
        return Response.json(
          waitlistAcceptance
            ? acceptanceFailure("Fakturoid could not complete this order")
            : {
              code: 503,
              errorCode: preparation.reason,
              message: "Fakturoid could not complete this order",
            },
          { headers: corsHeaders, status: 200 },
        );
      }
    }

    const paymentInfo = ticketOrder.order?.payment_info;
    const payment = paymentInfo?.payment_method !== "stripe" && paymentInfo &&
        Number(paymentInfo.amount) > 0
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

    // Capability creation is an additive read feature; failure must not fail a committed order.
    let deliveryReceipt: string | undefined;
    try {
      const capability = Array.from(
        crypto.getRandomValues(new Uint8Array(32)),
        (b) => b.toString(16).padStart(2, "0"),
      ).join("");
      const hash = Array.from(
        new Uint8Array(
          await crypto.subtle.digest(
            "SHA-256",
            new TextEncoder().encode(capability),
          ),
        ),
        (b) => b.toString(16).padStart(2, "0"),
      ).join("");
      const { data, error } = await supabaseAdmin.rpc(
        "create_email_confirmation_receipt",
        { p_command: commandId, p_order: ticketOrder.order.id, p_hash: hash },
      );
      if (!error && data === true) deliveryReceipt = capability;
    } catch { /* success and QR remain authoritative */ }
    return new Response(
      JSON.stringify(
        waitlistAcceptance
          ? {
            ...acceptanceEnvelope,
            data: {
              ...ticketOrder,
              payment_qr: paymentQr,
              delivery: "queued",
              ...stripeResult,
              ...(deliveryReceipt ? { delivery_receipt: deliveryReceipt } : {}),
            },
          }
          : {
            ticketOrder,
            payment_qr: paymentQr,
            code: 200,
            delivery: "queued",
            ...stripeResult,
            ...(deliveryReceipt ? { delivery_receipt: deliveryReceipt } : {}),
          },
      ),
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
