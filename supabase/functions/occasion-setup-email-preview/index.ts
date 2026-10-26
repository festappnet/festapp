import { createUserClient } from "../_shared/supabaseUtil.ts";
import { previewHandler } from "./handler.ts";

Deno.serve(previewHandler(async (authorization, params) => {
  // Forward the user JWT. A service role must never authorize draft previews.
  const { data, error } = await createUserClient(authorization)
    .rpc("get_occasion_setup_email_preview", params);
  return { data, error };
}));
