import {
  formatCurrency,
  formatDatetime,
  formatIBAN,
} from "../_shared/utilities.ts";
import { generateFullOrder } from "../_shared/orderOverview.ts";
import { generateQrCode } from "../_shared/qrCodePayment.ts";
import { paymentReferenceValue } from "../_shared/paymentPresentation.ts";
import { getBaseOrderData } from "./shared.ts";
import { translations } from "../_shared/translations/translations.ts";
import { generateChangeOverview } from "../_shared/changeOverview.ts";
import type { Tone } from "../_shared/translations/translations.ts"; // Import the Tone type

/**
 * Prepares the data required for the TICKET_ORDER_UPDATE email template.
 */
export async function getTicketOrderUpdateTemplate(
  reqData: any,
  authorizationHeader: string,
) {
  const { orderId, requestSecret, lang: requestedLanguage = "cs" } =
    reqData.data;
  const lang = requestedLanguage in translations
    ? requestedLanguage as keyof typeof translations
    : "cs";

  // Select the correct language object (csTranslations or enTranslations)
  const tr = translations[lang] || translations.cs;
  const attachments: any[] = [];

  // 1. Fetch and authorize base order data using the shared function
  const {
    order,
    occasion,
    payment_info,
    bank_account,
    latest_history_id,
    order_changes,
    form_data,
    reply_to,
  } = await getBaseOrderData(orderId, requestSecret, authorizationHeader);

  // 2. Get the communication tone
  const tone: Tone = (form_data?.communication_tone === "informal")
    ? "informal"
    : "formal";

  // 3. Calculate balance and generate a single, consolidated reasoning string
  const orderPrice = Number(order.price) || 0;
  const amountPaid = Number(payment_info?.paid) || 0;
  const balance = orderPrice - amountPaid;
  const currency = order.currency_code || "CZK";
  let balanceReasoning = "";

  if (orderPrice === 0) {
    balanceReasoning = tr.zeroOrder(currency, tone);
  } else if (balance < 0) {
    balanceReasoning = tr.overpaid(
      formatCurrency(Math.abs(balance), currency),
      tone,
    );
  } else if (balance > 0) {
    const iban = formatIBAN(bank_account.account_number);
    if (amountPaid === 0) {
      balanceReasoning = tr.unpaid(
        formatCurrency(orderPrice, currency),
        bank_account.account_number_human_readable,
        iban,
        paymentReferenceValue(payment_info),
        formatDatetime(payment_info.deadline, lang),
        tone, // Pass tone
      );
    } else {
      balanceReasoning = tr.underpaid(
        formatCurrency(amountPaid, currency),
        formatCurrency(balance, currency),
        bank_account.account_number_human_readable,
        iban,
        paymentReferenceValue(payment_info),
        formatDatetime(payment_info.deadline, lang),
        tone, // Pass tone
      );
    }

    // 4. Generate Payment QR Code if there is a balance
    try {
      const qrPaymentData = {
        amount: balance,
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
    } catch (error) {
      console.error(
        `Could not generate QR code for order ${occasion.title}:`,
        error instanceof Error ? error.message : "unknown error",
      );
    }
  } else {
    // Pass tone to the translation function
    balanceReasoning = tr.fullyPaid(tone);
  }

  // 5. Generate Change Overview
  const changeOverviewHtml = generateChangeOverview(
    order_changes,
    lang,
  );

  // 6. Prepare final data for the email client
  const subs = {
    occasionTitle: occasion.title,
    changeOverview: changeOverviewHtml,
    fullOrder: generateFullOrder(
      order.data,
      order.data.tickets,
      occasion.features,
      lang,
    ),
    balanceReasoning: balanceReasoning,
  };
  const sender = occasion.title;
  const receiver = order.data.email;
  const context = {
    occasion: occasion.id,
    organization: occasion.organization,
    unit: occasion.unit,
    orderHistoryId: latest_history_id,
  };

  return { subs, sender, receiver, context, attachments, reply_to };
}
