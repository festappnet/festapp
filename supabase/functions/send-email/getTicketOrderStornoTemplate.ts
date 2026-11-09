import { resolveCommunicationTone } from "../_shared/communicationTone.ts";
import { orderTemplateValues, resolveEmailLanguage } from "../_shared/emailCommunication.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { formatCurrency } from "../_shared/utilities.ts";
import { authorizeRequest } from "../_shared/auth.ts";
import { getBaseOrderData } from "./shared.ts";

export async function getTicketOrderStornoTemplate(reqData: any, authorizationHeader: string) {
  const { orderId, requestSecret, lang: requestedLanguage } = reqData.data;
  const lang = resolveEmailLanguage(requestedLanguage);

  const { order, occasion, payment_info, bank_account, latest_history_id, reference_history, form_data, reply_to } = await getBaseOrderData(orderId, requestSecret, authorizationHeader);

 const tone = resolveCommunicationTone(form_data?.communication_tone);

 // Call the RPC function "get_latest_order_history" which returns the latest order history for non-zero price
 const { data: orderHistory, error: historyError } = await supabaseAdmin.rpc(
   "get_latest_order_history",
   { order_id: orderId }
 );

 if (historyError || !orderHistory) {
   console.error("No valid order history found:", historyError);
   throw new Error("Valid order history not found");
 }

 // Assuming the function returns a row with price and currency_code directly
 const { price, currency_code } = orderHistory;

  // Prepare substitutions with price and currency code
  const subs: Record<string, string> = {
    ...orderTemplateValues("TICKET_ORDER_STORNO", occasion.title, order.order_symbol, tone, lang),
    amount: formatCurrency(price, currency_code),
  };

  // Add sender and receiver information
  const sender = occasion.title;
  const receiver = order.data.email;

  // Build a context object for template selection.
  const context = {
    occasion: occasion.id,
    unit: occasion.unit,
    organization: occasion.organization,
  };

  return { subs, sender, receiver, context, reply_to };
}
