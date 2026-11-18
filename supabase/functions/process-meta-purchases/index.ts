import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { sendMetaPurchase } from "../_shared/metaPurchase.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";

Deno.serve(async (request) => {
  const respond = (body: unknown, status = 200) =>
    Response.json(body, {
      status,
      headers: { "Cache-Control": "no-store" },
    });
  if (request.method !== "POST") {
    return respond({ error: "method_not_allowed" }, 405);
  }
  try {
    const { requestSecret } = await request.json();
    await authorizeRequest({ requestSecret });
    const claims = await supabaseAdmin.rpc("claim_meta_purchase_deliveries", {
      p_limit: 8,
    });
    if (claims.error) return respond({ error: "claim_failed" }, 503);
    // Prepare each delivery immediately before sending and keep the batch
    // comfortably inside the two-minute SQL lease, even on network timeout.
    let faults = 0;
    for (const claim of claims.data ?? []) {
      const args = { p_order_id: claim.order_id, p_lease: claim.lease };
      const prepared = await supabaseAdmin.rpc(
        "prepare_meta_purchase_delivery",
        args,
      );
      if (prepared.error) {
        faults++;
        continue;
      }
      if (!prepared.data) continue;
      const finished = await supabaseAdmin.rpc(
        "finish_meta_purchase_delivery",
        {
          ...args,
          p_result: await sendMetaPurchase(prepared.data),
        },
      );
      if (finished.error) faults++;
    }
    return respond(
      { claimed: claims.data?.length ?? 0, faults },
      faults ? 503 : 200,
    );
  } catch (error) {
    return respond(
      { error: "delivery_unavailable" },
      error instanceof AuthError ? error.status : 503,
    );
  }
});
