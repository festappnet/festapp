import { reminderBalanceReasoning, depositReminderBalanceReasoning } from "../_shared/orderEmailPresentation.ts";
import { formatCurrency, formatIBAN } from "../_shared/utilities.ts";
import { generateFullOrder } from "../_shared/orderOverview.ts";
import { generateQrCode } from "../_shared/qrCodePayment.ts";
import { paymentReferenceValue } from "../_shared/paymentPresentation.ts";
import { getBaseOrderData } from "./shared.ts";
import { translations } from "../_shared/translations/translations.ts";
import type { Tone } from "../_shared/translations/translations.ts";
import { generatePaymentDetails } from "../_shared/translations/payment-details.helpers.ts";

/**
 * Prepares the data required for the TICKET_ORDER_REMINDER email template.
 *
 * This is a merged handler that covers both:
 * - Regular payment reminders (order not yet paid, deadline approaching)
 * - Deposit reminders (deposit paid, remaining balance due before event)
 *
 * The handler checks for `is_deposit_reminder` flag in the request data to
 * determine which type of reminder to send.
 */
export async function getTicketOrderReminderTemplate(
  reqData: any,
  authorizationHeader: string,
) {
  const { orderId, requestSecret, lang = "cs" } = reqData.data;
  const isDepositReminder = reqData.data?.is_deposit_reminder === true;

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

  const currency = order.currency_code || "CZK";
  const iban = formatIBAN(bank_account.account_number);

  if (isDepositReminder) {
    // --- DEPOSIT REMAINDER REMINDER ---
    const totalAmount = Number(payment_info?.amount) || 0;
    const amountPaid = Number(payment_info?.paid) || 0;
    const remainingAmount = totalAmount - amountPaid;

    if (remainingAmount <= 0) {
      throw new Error(
        `Order ${orderId} is already fully paid. No deposit reminder needed.`,
      );
    }

    const balanceReasoning = depositReminderBalanceReasoning(
      remainingAmount, currency, occasion.features || [], occasion.start_time, bank_account, payment_info, lang, tone,
    );

    // Generate Payment QR Code for remaining amount
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
        `Could not generate QR code for deposit reminder ${orderId}:`,
        error.message,
      );
    }

    const paymentDetails = generatePaymentDetails({
      accountNumber: bank_account.account_number_human_readable,
      variableSymbol: paymentReferenceValue(payment_info),
      amount: formatCurrency(remainingAmount, currency),
      iban: iban,
      lang: lang as "cs" | "en",
    });

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
      amount: formatCurrency(remainingAmount, currency),
      paymentDetails: paymentDetails,
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
  } else {
    // --- REGULAR PAYMENT REMINDER ---
    const orderPrice = Number(order.price) || 0;
    const amountPaid = Number(payment_info?.paid) || 0;
    const balance = orderPrice - amountPaid;

    if (balance <= 0) {
      throw new Error(
        `Order ${orderId} is already paid or has a zero balance. No reminder needed.`,
      );
    }

    // Generate reminder-specific text based on the deadline
    const now = new Date();
    const deadline = new Date(payment_info.deadline);
    const timeDiff = deadline.getTime() - now.getTime();
    const daysDiff = Math.ceil(Math.abs(timeDiff) / (1000 * 3600 * 24));
    const balanceReasoning = reminderBalanceReasoning(
      timeDiff, daysDiff, balance, amountPaid, currency, bank_account, payment_info, lang, tone,
    );

    // Generate Payment QR Code
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
    } catch (error: any) {
      console.error(
        `Could not generate QR code for order ${occasion.title}:`,
        error.message,
      );
    }

    // Prepare final data for the email client
    const amount = formatCurrency(balance, currency);
    const remainingTimeStr = timeDiff > 0
      ? tr.days_remaining(daysDiff)
      : tr.days_remaining(0);
    const deadlineStr = deadline.toLocaleDateString(
      lang === "cs" ? "cs-CZ" : "en-US",
    );

    const paymentDetails = generatePaymentDetails({
      accountNumber: bank_account.account_number_human_readable,
      variableSymbol: paymentReferenceValue(payment_info),
      amount: amount,
      iban: iban,
      lang: lang as "cs" | "en",
    });

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
      amount: amount,
      remainingTime: remainingTimeStr,
      deadline: deadlineStr,
      paymentDetails: paymentDetails,
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
}
