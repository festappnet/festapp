import { withOrderIdentity } from "../_shared/orderOverview.ts";
import { generateFullOrder } from "../_shared/orderOverview.ts";
import { generateQrCode } from "../_shared/qrCodePayment.ts";
import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { formatCurrency, formatDatetime } from "../_shared/utilities.ts";
import { translations } from "../_shared/translations/translations.ts";
import { fakturoidGateway } from "../send-ticket-order/fakturoid.ts";
import { openStripePaySource } from "../_shared/stripe/paySource.ts";
import { stripeConfirmationBalance } from "../_shared/stripe/email.ts";

type Attachment = {
  filename: string;
  content: Uint8Array;
  contentType: string;
  encoding: "binary";
};

async function addExternalAttachment(
  service: any,
  ticketOrder: any,
  attachments: Attachment[],
) {
  const url = service?.data?.url;
  if (!url) return;
  const { data: requestSecret, error } = await supabaseAdmin.rpc(
    "generate_request_secret",
    { p_ttl_seconds: 300 },
  );
  if (error || !requestSecret) {
    throw error ?? new Error("Request secret unavailable");
  }
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ orderId: ticketOrder.order.id, requestSecret }),
  });
  if (!response.ok) {
    throw new Error(`Attachment service failed: ${response.status}`);
  }
  const result = await response.json();
  if (!result.file) throw new Error("Attachment service returned no file");
  const bytes = Uint8Array.from(
    atob(result.file),
    (character) => character.charCodeAt(0),
  );
  attachments.push({
    filename: result.filename ??
      `contract-${ticketOrder.order.order_symbol}.pdf`,
    content: bytes,
    contentType: "application/pdf",
    encoding: "binary",
  });
}

/** Builds the confirmation effect from the immutable payload queued by the DB command. */
export async function getTicketOrderConfirmationTemplate(task: any) {
  const ticketOrder = task.data.ticket_order;
  if (!ticketOrder?.order) {
    throw new Error("Queued ticket order payload is missing");
  }
  const requestedLanguage = String(task.data.lang ?? "cs");
  const lang = requestedLanguage in translations
    ? requestedLanguage as keyof typeof translations
    : "cs";
  const order = await withOrderIdentity(ticketOrder.order, async (params) => {
    const { data, error } = await supabaseAdmin.rpc(
      "read_order_identity",
      params,
    );
    if (error) throw error;
    return data;
  }, { id: task.occasion, organization: task.organization });
  const occasion = order.occasion;
  const paymentInfo = order.payment_info;
  const attachments: Attachment[] = [];
  if (paymentInfo.payment_method === "stripe") {
    const { data: source, error } = await supabaseAdmin.rpc(
      "get_stripe_order_pay_source_internal",
      { p_order: order.id, p_command: task.data.command_id },
    );
    if (error) throw new Error("stripe_email_source_unavailable");
    const payable = ["open", "preparing"].includes(source?.payment?.status);
    const secrets = payable ? await openStripePaySource(source) : undefined;
    return {
      subs: {
        occasionTitle: occasion.title,
        orderSymbol: order.order_symbol,
        balanceReasoning: stripeConfirmationBalance(
          source,
          secrets,
          lang,
          formatCurrency(paymentInfo.amount, paymentInfo.currency_code, 2),
          formatDatetime(paymentInfo.deadline, lang) ?? "",
          JSON.parse(Deno.env.get("STRIPE_ALLOWED_ORIGINS") ?? "[]"),
        ),
        price: paymentInfo.amount,
        currencyCode: paymentInfo.currency_code,
        amount: formatCurrency(
          paymentInfo.amount,
          paymentInfo.currency_code,
          2,
        ),
        accountNumber: "",
        iban: "",
        variableSymbol: "",
        deadline: formatDatetime(paymentInfo.deadline, lang),
        fullOrder: generateFullOrder(
          order.data,
          order.data.tickets,
          occasion.features,
          lang,
          order.order_symbol,
          2,
        ),
      },
      sender: occasion.title,
      receiver: order.data.email,
      context: {
        organization: occasion.organization,
        unit: occasion.unit,
        occasion: occasion.id,
      },
      attachments,
      reply_to: order.reply_to,
    };
  }

  const { data: externalServices, error } = await supabaseAdmin.rpc(
    "get_external_services",
    { p_order_id: order.id },
  );
  if (error) throw error;
  const fakturoid = externalServices?.find((service: any) =>
    service.type === "FAKTUROID"
  );
  if (fakturoid) {
    const invoice = await fakturoidGateway.getEmailAttachment({
      config: {
        client_id: fakturoid.data.client_id,
        client_secret: fakturoid.data.client_secret,
        slug: fakturoid.data.slug,
        subject_id: fakturoid.data.subject_id,
        note: fakturoid.data.note,
      },
      order,
      commandId: String(task.data.command_id),
    });
    if (invoice.attachment) attachments.push(invoice.attachment);
  } else if (paymentInfo.amount > 0) {
    const qrPaymentInfo = paymentInfo.deposit_amount &&
        paymentInfo.deposit_amount < paymentInfo.amount
      ? { ...paymentInfo, amount: Number(paymentInfo.deposit_amount) }
      : paymentInfo;
    attachments.push({
      filename: `qr-payment.${occasion.title}.png`,
      content: await generateQrCode(qrPaymentInfo, order, occasion.title),
      contentType: "image/png",
      encoding: "binary",
    });
  }
  await addExternalAttachment(
    externalServices?.find((service: any) =>
      service.type === "SUPABASE_FUNCTION"
    ),
    { ...ticketOrder, order },
    attachments,
  );

  return {
    subs: confirmationSubstitutions(order, lang),
    sender: occasion.title,
    receiver: order.data.email,
    context: {
      organization: occasion.organization,
      unit: occasion.unit,
      occasion: occasion.id,
    },
    attachments,
    reply_to: order.reply_to,
  };
}
