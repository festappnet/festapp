import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { createCustomerOrderChangesHandler } from "../_shared/customerOrderChangesHandler.ts";
Deno.serve(createCustomerOrderChangesHandler(async (params) => {
  const { data, error } = await supabaseAdmin.rpc(
    "customer_order_change_gateway",
    params,
  );
  if (error) {
    throw Object.assign(new Error("CUSTOMER_CHANGE_FAILED"), {
      code: error.code,
    });
  }
  return data;
}));
