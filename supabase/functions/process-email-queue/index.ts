import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { emailRpc } from "../_shared/emailQueueClient.ts";
import { renderQueuedEmail } from "../_shared/emailRenderer.ts";
import { sealEmail } from "../_shared/emailPayload.ts";
import { drainEmails } from "../_shared/emailDispatcher.ts";
import { createEmailSender } from "../_shared/emailSender.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  try {
    const body = await req.json();
    if (!body.requestSecret) {
      throw new AuthError("System authorization required", 401);
    }
    await authorizeRequest({ requestSecret: body.requestSecret });
    const sender = createEmailSender();
    const work = (async () => {
      await sender.refreshQuota();
      return await drainEmails({
        rpc: emailRpc,
        prepare: renderQueuedEmail,
        seal: sealEmail,
        now: Date.now,
        send: sender.send,
      });
    })();
    // pg_net may close its HTTP connection before preparation/send completes.
    const runtime = (globalThis as typeof globalThis & {
      EdgeRuntime?: { waitUntil(promise: Promise<unknown>): void };
    }).EdgeRuntime;
    runtime?.waitUntil(work);
    const result = await work;
    return new Response(JSON.stringify(result), { headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: "email_worker_failed" }), {
      status: e instanceof AuthError ? e.status : 500,
      headers,
    });
  }
});
