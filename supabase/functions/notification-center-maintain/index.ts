import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { AuthError, authorizeRequest } from "../_shared/auth.ts";
Deno.serve(async (req) => {
  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: {
        "content-type": "application/json",
        "cache-control": "no-store",
      },
    });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const body = await req.text();
    if (body.length > 4096) return json({ error: "body_limit" }, 413);
    const { requestSecret } = JSON.parse(body);
    await authorizeRequest({ requestSecret });
    const rpc = (name: string, args: Record<string, unknown>) =>
      supabaseAdmin.rpc(name, args);
    const result = await rpc("maintain_notification_center", { p_limit: 100 });
    if (result.error) throw Error("notification_maintenance_failed");
    return json({ result: result.data });
  } catch (error) {
    return json({
      error: error instanceof AuthError
        ? error.message
        : "notification_maintenance_failed",
    }, error instanceof AuthError ? error.status : 503);
  }
});
