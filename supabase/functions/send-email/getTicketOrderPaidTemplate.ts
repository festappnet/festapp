import { bankCollectionAllowed } from "../_shared/orderEmailPresentation.ts";
import { orderTemplateValues, resolveEmailLanguage } from "../_shared/emailCommunication.ts";
import { resolveCommunicationTone } from "../_shared/communicationTone.ts";
import { isBankPaymentInfo } from "../_shared/paymentPresentation.ts";
import { confirmedNetPayment, paidPaymentSubstitutions } from "../_shared/orderEmailPresentation.ts";
import { generateFullOrder } from "../_shared/orderOverview.ts";
import { generateQrCode } from "../_shared/qrCodePayment.ts";
import { getBaseOrderData } from "./shared.ts";


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
  const { orderId, requestSecret, lang: requestedLanguage } = reqData.data;
  const lang = resolveEmailLanguage(requestedLanguage);
  const code = reqData.code;

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
  const tone = resolveCommunicationTone(form_data?.communication_tone);

  const totalAmount = Number(payment_info?.amount) || 0;
  const amountPaid = confirmedNetPayment(payment_info);
  const currency = order.currency_code || "CZK";

  const paymentPresentation = paidPaymentSubstitutions(
    totalAmount, amountPaid, currency, occasion.features || [], lang, tone, payment_info,
  );

  if (bankCollectionAllowed(payment_info) && ['CZK','EUR'].includes(payment_info.currency_code) && !(amountPaid >= totalAmount)) {
    const remainingAmount = totalAmount - amountPaid;
    // QR code for remaining amount
    try {
      const qrPaymentData = {
        payment_method: payment_info.payment_method, collectionAction: payment_info.collectionAction,
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
    ...orderTemplateValues("TICKET_ORDER_PAYMENT_DONE", occasion.title, order.order_symbol, tone, lang),
    fullOrder: generateFullOrder(
      order.data,
      order.data.tickets,
      occasion.features,
      lang,
        order.order_symbol,
    ),
    balanceReasoning: paymentPresentation.balanceReasoning,
    amount: paymentPresentation.amount,
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
