import { emailRpc, prepareAccountEmail } from "../_shared/emailQueueClient.ts";
import { authEmailHandler } from "./handler.ts";
Deno.serve(
  authEmailHandler({
    secret: Deno.env.get("AUTH_EMAIL_HOOK_SECRET") ?? "",
    publicAuthUrl: Deno.env.get("AUTH_EMAIL_PUBLIC_URL") ?? "",
    rpc: emailRpc,
    prepare: prepareAccountEmail,
  }),
);
