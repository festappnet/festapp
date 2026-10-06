import { formatCurrency, formatIBAN } from "../_shared/utilities.ts";
import { generateFullOrder } from "../_shared/orderOverview.ts";
import { generateQrCode } from "../_shared/qrCodePayment.ts";
import { paymentReferenceValue } from "../_shared/paymentPresentation.ts";
import { getBaseOrderData } from "./shared.ts";
import { translations } from "../_shared/translations/translations.ts";
import type { Tone } from "../_shared/translations/translations.ts";

/**
 * Prepares the data required for the TICKET_ORDER_PAID email template.
 *
 * This is a merged handler that covers both deposit-paid and fully-paid scenarios.
 * Branches internally based on whether the order is fully paid:
 * - Fully paid: Shows "fully paid" confirmation with no remaining balance.
 * - Deposit paid: Shows deposit paid confirmation with remaining amount + QR code.
 */
export async function getTicketOrderPaidTemplate(
  reqData: any,
  authorizationHeader: string,
) {
  const { orderId, requestSecret, lang = "cs" } = reqData.data;
  const code = reqData.code;

  const tr = translations[lang as keyof typeof translations] || translations.cs;
  const attachments: any[] = [];

  // 1. Fetch and authorize base order data
  const {
    order,
    occasion,
    payment_info,
    bank_account,
    latest_history_id,
    form_data,
    reply_to,
  } = await getBaseOrderData(orderId, requestSecret, authorizationHeader);

  // 2. Get the communication tone
  const tone: Tone = (form_data?.communication_tone === "informal")
    ? "informal"
    : "formal";

  const depositAmount = Number(payment_info?.deposit_amount) || 0;
  const totalAmount = Number(payment_info?.amount) || 0;
  const amountPaid = Number(payment_info?.paid) || 0;
  const currency = order.currency_code || "CZK";

  let balanceReasoning = "";

  // Determine if fully paid — based on amount comparison
  const isFullyPaid = amountPaid >= totalAmount;

  if (isFullyPaid) {
    // Fully paid — no remaining balance shown
    balanceReasoning = tr.depositFullyPaid(
      formatCurrency(totalAmount, currency),
      tone,
    );
    // No QR code needed — fully paid
  } else {
    // Deposit paid — show remaining amount
    const remainingAmount = totalAmount - amountPaid;

    // Read deposit deadline from the deposit feature in occasion features
    const features = occasion.features || [];
    const depositFeature = features.find((f: any) => f.code === "deposit");
    let depositDeadline: string;
    const deadlineType = depositFeature?.deposit_deadline;
    const deadlineDays = depositFeature?.deposit_deadline_days;

    if (deadlineType === "on_site") {
      depositDeadline = lang === "cs" ? "na místě" : "on site";
    } else if (deadlineDays) {
      depositDeadline = lang === "cs"
        ? `${deadlineDays} dní před akcí`
        : `${deadlineDays} days before the event`;
    } else {
      depositDeadline = lang === "cs" ? "na místě" : "on site";
    }

    balanceReasoning = tr.depositPaid(
      formatCurrency(amountPaid, currency),
      formatCurrency(remainingAmount, currency),
      depositDeadline,
      tone,
    );

    // QR code for remaining amount
    try {
      const qrPaymentData = {
        amount: remainingAmount,
        currency_code: currency,
        account_number: bank_account.account_number,
        account_number_human_readable:
          bank_account.account_number_human_readable,
        variable_symbol: payment_info.variable_symbol,
        creditor_reference: payment_info.creditor_reference,
        creditor_name: bank_account.creditor_name,
      };
      const qrCodeBytes = await generateQrCode(
        qrPaymentData,
        order.data,
        occasion.title,
      );
      attachments.push({
        filename: `qr-payment-${occasion.title}.png`,
        content: qrCodeBytes,
        contentType: "image/png",
        encoding: "binary",
      });
    } catch (error: any) {
      console.error(
        `Could not generate QR code for order ${orderId}:`,
        error.message,
      );
    }
  }

  const subs = {
    occasionTitle: occasion.title,
      orderSymbol: order.order_symbol,
    fullOrder: generateFullOrder(
      order.data,
      order.data.tickets,
      occasion.features,
      lang,
        order.order_symbol,
    ),
    balanceReasoning: balanceReasoning,
    amount: formatCurrency(amountPaid, currency),
  };
  const sender = occasion.title;
  const receiver = order.data.email;
  const context = {
    occasion: occasion.id,
    organization: occasion.organization,
    unit: occasion.unit,
    orderHistoryId: latest_history_id,
    paymentInfoId: payment_info.id,
  };

  return { subs, sender, receiver, context, attachments, reply_to };
}
