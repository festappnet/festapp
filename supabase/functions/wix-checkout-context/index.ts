import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { wixCheckoutContext } from "./handler.ts";

Deno.serve((request) =>
  wixCheckoutContext(request, {
    async configuration() {
      const { data, error } = await supabaseAdmin.rpc(
        "get_wix_checkout_configuration_internal",
      )
        .abortSignal(AbortSignal.timeout(5000));
      if (
        error || !data || typeof data.appId !== "string" ||
        typeof data.organizationId !== "number"
      ) {
        throw new Error("WIX_NOT_CONFIGURED");
      }
      return { appId: data.appId, organizationId: data.organizationId };
    },
    async issue(args) {
      const { data, error } = await supabaseAdmin.rpc(
        "issue_wix_checkout_origin_internal",
        args,
      )
        .abortSignal(AbortSignal.timeout(5000));
      if (error) throw new Error("CHECKOUT_CONTEXT_UNAVAILABLE");
      return data;
    },
  })
);
