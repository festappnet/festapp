import { generateFullOrder } from "../_shared/orderOverview.ts";
import { generateQrCode } from "../_shared/qrCodePayment.ts";
import { paymentReferenceValue } from "../_shared/paymentPresentation.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import {
  formatCurrency,
  formatDatetime,
  formatIBAN,
} from "../_shared/utilities.ts";
import { translations } from "../_shared/translations/translations.ts";
import type { Tone } from "../_shared/translations/translations.ts";
import { useFakturoid } from "../send-ticket-order/fakturoid.ts";

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
      `contract-${paymentReferenceValue(ticketOrder.order.payment_info)}.pdf`,
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
  const tr = translations[lang];
  const order = ticketOrder.order;
  const occasion = order.occasion;
  const paymentInfo = order.payment_info;
  const attachments: Attachment[] = [];

  const { data: externalServices, error } = await supabaseAdmin.rpc(
    "get_external_services",
    { p_order_id: order.id },
  );
  if (error) throw error;
  const fakturoid = externalServices?.find((service: any) =>
    service.type === "FAKTUROID"
  );
  if (fakturoid) {
    await useFakturoid(
      {
        client_id: fakturoid.data.client_id,
        client_secret: fakturoid.data.client_secret,
        slug: fakturoid.data.slug,
        subject_id: fakturoid.data.subject_id,
        note: fakturoid.data.note,
      },
      order,
      occasion.title,
      String(task.data.command_id),
      attachments,
    );
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
    ticketOrder,
    attachments,
  );

  const tone: Tone = order.form?.data?.communication_tone === "informal"
    ? "informal"
    : "formal";
  let balanceReasoning: string;
  if (paymentInfo.amount <= 0) {
    balanceReasoning = tr.zeroOrder(paymentInfo.currency_code, tone);
  } else if (
    paymentInfo.deposit_amount &&
    paymentInfo.deposit_amount < paymentInfo.amount
  ) {
    const deposit = Number(paymentInfo.deposit_amount);
    const remaining = paymentInfo.amount - deposit;
    const feature = (occasion.features ?? []).find((item: any) =>
      item.code === "deposit"
    );
    const deadline = feature?.deposit_deadline === "on_site"
      ? (lang === "cs" ? "na místě" : "on site")
      : feature?.deposit_deadline_days
      ? `${feature.deposit_deadline_days} ${
        lang === "cs" ? "dní před akcí" : "days before the event"
      }`
      : (lang === "cs" ? "na místě" : "on site");
    balanceReasoning = tr.depositRequired(
      formatCurrency(deposit, paymentInfo.currency_code),
      formatCurrency(remaining, paymentInfo.currency_code),
      deadline,
      paymentInfo.account_number_human_readable,
      formatIBAN(paymentInfo.account_number),
      paymentReferenceValue(paymentInfo),
      tone,
    );
  } else {
    balanceReasoning = tr.unpaid(
      formatCurrency(paymentInfo.amount, paymentInfo.currency_code),
      paymentInfo.account_number_human_readable,
      formatIBAN(paymentInfo.account_number),
      paymentReferenceValue(paymentInfo),
      formatDatetime(paymentInfo.deadline, lang) ?? "",
      tone,
    );
  }

  return {
    subs: {
      occasionTitle: occasion.title,
      balanceReasoning,
      price: paymentInfo.amount,
      currencyCode: paymentInfo.currency_code,
      amount: formatCurrency(paymentInfo.amount, paymentInfo.currency_code),
      accountNumber: paymentInfo.account_number_human_readable,
      iban: formatIBAN(paymentInfo.account_number),
      variableSymbol: paymentReferenceValue(paymentInfo),
      deadline: formatDatetime(paymentInfo.deadline, lang),
      fullOrder: generateFullOrder(
        order.data,
        order.data.tickets,
        occasion.features,
        lang,
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
