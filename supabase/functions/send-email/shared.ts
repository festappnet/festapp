import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { normalizeEpcCreditorName } from "../_shared/paymentPresentation.ts";

/**
 * Fetches comprehensive order details from Supabase and performs authorization.
 * This is a shared utility for templates that need full order context.
 * @param orderId The ID of the order to fetch.
 * @param requestSecret A secret for authorizing against the occasion.
 * @param authorizationHeader The standard JWT authorization header.
 * @returns An object containing all relevant order data.
 */
export async function getBaseOrderData(
  orderId: string,
  requestSecret: string,
  authorizationHeader: string,
) {
  // 1. Fetch comprehensive order details from the database
  const { data: orderDetailsResponse, error: rpcError } = await supabaseAdmin
    .rpc("get_order_details_for_email", { p_order_id: orderId });

  if (rpcError || orderDetailsResponse.code !== 200) {
    console.error(
      "Error fetching order details:",
      rpcError || orderDetailsResponse.message,
    );
    throw new Error("Failed to fetch order details.");
  }

  const {
    order,
    occasion,
    payment_info,
    bank_account,
    latest_history_id,
    reference_history,
    form_data,
    reply_to,
  } = orderDetailsResponse.data;

  // 2. Perform authorization to ensure the request is legitimate
  await authorizeRequest({
    requestSecret,
    authorizationHeader,
    occasionId: occasion.id,
  });

  // Older EUR accounts may have no account-specific payee. Use the same
  // organization fallback as the order-creation response for later emails.
  if (order.currency_code === "EUR" && !bank_account?.creditor_name?.trim()) {
    const { data: organization, error: organizationError } = await supabaseAdmin
      .from("organizations")
      .select("title")
      .eq("id", occasion.organization)
      .single();
    if (organizationError) throw organizationError;
    bank_account.creditor_name = Array.from(
      normalizeEpcCreditorName(organization.title),
    ).slice(0, 70).join("");
  }

  // 3. Return the consolidated data
  return {
    order,
    occasion,
    payment_info,
    bank_account,
    latest_history_id,
    reference_history,
    form_data,
    reply_to,
  };
}
