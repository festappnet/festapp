/** Local integration adapter: actual renderer, encryption, send fence and sender.
 * Only the final provider send is fake. No network access outside loopback. */
import { renderQueuedEmail } from "../../../supabase/functions/_shared/emailRenderer.ts";
import { emailRpc } from "../../../supabase/functions/_shared/emailQueueClient.ts";
import {
  openEmail,
  sealEmail,
} from "../../../supabase/functions/_shared/emailPayload.ts";
import { sendEmailAttempt } from "../../../supabase/functions/_shared/emailSender.ts";
const target = new URL(Deno.env.get("SUPABASE_URL") ?? "invalid:");
if (target.hostname !== "127.0.0.1" || target.port !== "56521") {
  throw Error("isolated recovery backend required");
}
Deno.env.set("EMAIL_PAYLOAD_KEY", btoa("r".repeat(32)));
Deno.env.set("DEFAULT_EMAIL", "sender@example.invalid");
const input = JSON.parse(await new Response(Deno.stdin.readable).text());
const row = await emailRpc("claim_email");
if (row?.message_id !== input.messageId) {
  throw Error("unexpected claimed message");
}
const rendered = await renderQueuedEmail(row);
await emailRpc("prepare_email", {
  p_message: row.message_id,
  p_token: row.lease_token,
  p_prepared: await sealEmail(rendered.prepared),
  p_post_action: rendered.postAction,
});
let sends = 0;
const sender = {
  rpc: emailRpc,
  open: openEmail,
  config: {
    sender: "sender@example.invalid",
    region: "eu-central-1",
    accessKey: "fake",
    secretKey: "fake",
    transactionalSet: "test",
    securitySet: "test",
    maxBytes: 30_000_000,
  },
  send: async (message: any, tags: Record<string, string>) => {
    sends++;
    if (message.to !== row.recipient || tags.message_id !== row.message_id) {
      throw Error("recipient/provenance mismatch");
    }
    if (input.ambiguous) {
      throw Error("fake transport disconnected after request");
    }
    return "fake-recovery-" + row.message_id;
  },
};
const outcome = await sendEmailAttempt(row.attempt_id, row.lease_token, sender);
await sendEmailAttempt(row.attempt_id, row.lease_token, sender);
if (sends !== 1) throw Error("send permit was replayed");
if (input.deliver && outcome.disposition === "accepted") {
  const event = {
    key: "delivery:" + row.message_id,
    provider_id: "fake-recovery-" + row.message_id,
    attempt_id: row.attempt_id,
    recipient: row.recipient,
    type: "delivery",
    time: new Date().toISOString(),
  };
  await emailRpc("record_email_events", { p_events: [event, event] });
}
console.log(
  JSON.stringify({
    outcome: outcome.disposition,
    sends,
    messageId: row.message_id,
  }),
);
