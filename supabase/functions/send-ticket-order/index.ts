import { orderEmailOverviewUrl } from '../_shared/orderEmailOverview.ts';
import { executeConfirmedWaitlistOrder } from "./confirmedWaitlistOrder.ts";
import { executeConfirmedFormOrder } from "./confirmedFormOrder.ts";
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
import {
  type HostedPaymentDependencies,
  requireHostedPayment,
} from "../_shared/payments/contracts.ts";
import { prepareOrderDelivery } from "../_shared/payments/orderDelivery.ts";
import { paymentRegistry } from "../_shared/payments/runtime.ts";
import { executeTicketOrderRpc } from "./ticketOrderRpc.ts";

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

    let payload;
    try {
      payload = await req.json();
    } catch (error) {
      if (!(error instanceof SyntaxError)) throw error;
      return Response.json({
        code: 400,
        errorCode: "INVALID_TICKET_ORDER_INTENT",
      }, { status: 400, headers: corsHeaders });
    }
    if (
      payload === null || typeof payload !== "object" || Array.isArray(payload)
    ) {
      return Response.json({
        code: 400,
        errorCode: "INVALID_TICKET_ORDER_INTENT",
      }, { status: 400, headers: corsHeaders });
    }

    const {
      orderDetails: directOrderDetails,
      replacement,
      administrativeOrder,
      waitlistAcceptance,
      commandId: requestedCommandId,
      clientId: requestedClientId,
    } = payload;
    if (
      !hasSingleTicketOrderPayload({
        orderDetails: directOrderDetails,
        replacement,
        administrativeOrder,
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
    if (
      !directOrderDetails && !replacement && !waitlistAcceptance &&
      !administrativeOrder
    ) {
      return new Response(JSON.stringify({ error: "Missing order payload" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }
    const authorizationHeader = req.headers.get("Authorization");
    if (administrativeOrder) {
      if (!authorizationHeader) {
        return Response.json({
          code: 401,
          errorCode: "AUTHENTICATION_REQUIRED",
        }, { status: 401, headers: corsHeaders });
      }
      return Response.json(
        await executeConfirmedFormOrder({
          administrativeOrder,
          commandId,
          client: createUserClient(authorizationHeader),
          serviceClient: supabaseAdmin,
          gateway: fakturoidGateway,
        }),
        { headers: corsHeaders },
      );
    }

    if (paymentRegistry.hasHosted(replacement?.inputData?.payment_method)) {
      return Response.json({ error: "STRIPE_REPLACEMENT_UNSUPPORTED" }, {
        status: 400,
        headers: corsHeaders,
      });
    }
    const preparedOrder = directOrderDetails
      ? { ...directOrderDetails }
      : directOrderDetails;
    let paymentDependencies: HostedPaymentDependencies | undefined;
    if (preparedOrder) {
      paymentRegistry.stripOrderSources(preparedOrder);
      if (paymentRegistry.hasHosted(preparedOrder.payment_method)) {
        paymentDependencies = requireHostedPayment(
          paymentRegistry.resolve(preparedOrder.payment_method),
        );
        if (!paymentDependencies.order) {
          throw new Error("payment_order_not_configured");
        }
        preparedOrder[paymentDependencies.order.sourceField] =
          await paymentDependencies.order.prepareSource();
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
    if (waitlistAcceptance?.administration) {
      if (!acceptanceActor) {
        return Response.json({
          code: 401,
          errorCode: "AUTHENTICATION_REQUIRED",
        }, { status: 401, headers: corsHeaders });
      }
      return Response.json(
        await executeConfirmedWaitlistOrder({
          administration: waitlistAcceptance.administration,
          payload: {
            offerId: waitlistAcceptance.offerId,
            ticketIds: waitlistAcceptance.ticketIds,
            orderDetails: directOrderDetails,
            approvalHash: waitlistAcceptance.approvalHash,
          },
          actor: acceptanceActor,
          commandId,
          serviceClient: supabaseAdmin,
          gateway: fakturoidGateway,
        }),
        { headers: corsHeaders },
      );
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

    const userScoped = authorizationHeader && !waitlistAcceptance;
    console.info(
      `Creating ticket order via ${
        userScoped ? "user-scoped" : "system"
      } authorization`,
    );
    const rpcResult = await executeTicketOrderRpc(
      // Caddy replaces this header from its trusted proxy resolution; the gateway and
      // the function router preserve it. Never accept an address from JSON or
      // use the untrusted CF/X-Forwarded-For alternatives here.
      userScoped
        ? createUserClient(
          authorizationHeader!,
          req.headers.get("x-festapp-client-ip"),
        )
        : supabaseAdmin,
      rpcName,
      rpcParameters,
    );
    if (rpcResult.error) {
      console.error("Ticket order RPC error:", rpcResult.error);
    }
    if (waitlistAcceptance && !rpcResult.error) {
      acceptanceEnvelope = rpcResult.envelope;
    }
    if (waitlistAcceptance && rpcResult.error) {
      return new Response(
        JSON.stringify({ error: "waitlist_command_failed" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    ticketOrderResponse = rpcResult.order;

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
    let providerResult: Record<string, unknown> | undefined;
    if (paymentRegistry.hasHosted(order?.payment_info?.payment_method)) {
      const binding = paymentDependencies ??
        requireHostedPayment(
          paymentRegistry.resolve(order.payment_info.payment_method),
        );
      if (!binding.order) throw new Error("payment_order_not_configured");
      const source = await binding.order.readSource(order.id, commandId);
      providerResult = await prepareOrderDelivery(
        source,
        order.id,
        commandId,
        preparedOrder?.payment_surface ??
          waitlistAcceptance?.orderDetails?.payment_surface,
        ticketOrder.payment,
        binding,
      );
    }
    if (
      order?.payment_info?.payment_method === "bank" &&
      Number(order?.payment_info?.amount) > 0
    ) {
      const preparation = await prepareFakturoidTicketOrder({
        client: supabaseAdmin,
        gateway: fakturoidGateway,
        order,
        commandId,
        unitName: order.occasion.title,
        replacement: !!replacement,
        durable: !!order.data?.discount,
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
    const payment = paymentInfo?.payment_method === "bank" && paymentInfo &&
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

    // The successful RPC has authorized this command (including receipt replay).
    // Reuse the existing sealed buyer source used by order email. The receipt
    // stays immutable; neither a retry nor an email rotates the capability.
    if (!replacement && !waitlistAcceptance && ticketOrder.order?.id) {
      try {
        const url = await orderEmailOverviewUrl({
          order_id: ticketOrder.order.id,
          recipient: ticketOrder.order.data?.email,
          message_id: commandId,
        }, async (name, params) => {
          const { data, error } = await supabaseAdmin.rpc(name, params);
          if (error) throw error;
          return data;
        });
        if (url) ticketOrder.orderOverviewUrl = url;
      } catch { /* A committed order remains successful; email can recover the link. */ }
    }

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
              ...providerResult,
              ...(deliveryReceipt ? { delivery_receipt: deliveryReceipt } : {}),
            },
          }
          : {
            ticketOrder,
            payment: ticketOrder.payment,
            payment_qr: paymentQr,
            code: 200,
            delivery: "queued",
            ...providerResult,
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
