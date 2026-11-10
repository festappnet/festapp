import { createUserClient } from "../_shared/supabaseUtil.ts";
import { paymentOperationHandler } from "../_shared/payments/operationHandler.ts";

Deno.serve(request => paymentOperationHandler(request, {
  async authenticate(authorization) {
    const {data, error} = await createUserClient(authorization).auth.getUser();
    return !error && data.user != null;
  },
  async rpc(authorization, name, args) {
    const {data, error} = await createUserClient(authorization).rpc(name, args);
    if (error) throw error;
    return data;
  },
}));
