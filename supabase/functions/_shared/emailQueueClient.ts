import { safeClickTracking } from "./emailTracking.ts";
import {
  type DeliverEmailInput,
  type EmailDeliveryResult,
  renderEmail,
} from "./emailDelivery.ts";
import { type EmailKind, kindForTemplate } from "./emailRegistry.ts";
import { sealEmail } from "./emailPayload.ts";
export async function emailRpc(
  name: string,
  args: Record<string, unknown> = {},
) {
  const { supabaseAdmin } = await import("./supabaseUtil.ts");
  const { data, error } = await supabaseAdmin.rpc(name, args);
  if (error) {
    throw Object.assign(new Error(`email_rpc_${name}`), { code: error.code });
  }
  return data;
}
export class EmailAcceptancePendingError extends Error {
  constructor(readonly messageId: string) {
    super("email_pending");
  }
}

export async function awaitEmailAccepted(
  messageId: string,
  timeoutMs = 8000,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  do {
    const state = await emailRpc("get_internal_email_state", {
      p_message: messageId,
    });
    if (state === "accepted") return;
    if (
      ["unknown", "dead", "cancelled", "expired", "suppressed"].includes(state)
    ) throw new Error(`email_${state}`);
    await new Promise((resolve) => setTimeout(resolve, 250));
  } while (Date.now() < deadline);
  throw new EmailAcceptancePendingError(messageId);
}
/** Compatibility boundary: sent/email_sent is returned only after canonical accepted. */
export async function enqueueAndAwaitEmail(
  input: DeliverEmailInput & {
    dedupeKey?: string;
    kind?: EmailKind;
    expiresAt?: string;
  },
  options: {
    enqueuePrepared?: (
      parameters: Record<string, unknown>,
    ) => Promise<{ message_id: string }>;
  } = {},
): Promise<EmailDeliveryResult> {
  const kind = input.kind ?? kindForTemplate(input.templateCode ?? "");
  await admitEmailPreparation(input);
  const prepared = await renderEmail(input);
  // Stable content digest for older clients without a request ID. Identical request retries join the same intent.
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify({ kind, input })),
  );
  const dedupe = input.dedupeKey ??
    Array.from(new Uint8Array(hash), (b) => b.toString(16).padStart(2, "0"))
      .join("");
  const contentHash = Array.from(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(JSON.stringify(prepared)),
      ),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  const sealed = await sealEmail(prepared);
  // Dedupe hash derives from the plaintext digest; random encryption nonce must not cause collision.
  const enqueue = options.enqueuePrepared ??
    ((parameters: Record<string, unknown>) =>
      emailRpc("enqueue_prepared_email", parameters));
  const message = await enqueue({
    p_kind: kind,
    p_context: { ...input.context, recipient_user: input.recipientUser },
    p_recipient: input.to,
    p_sealed: sealed,
    p_dedupe: dedupe,
    p_content_hash: contentHash,
    p_code: input.templateCode ?? "",
    p_expires: input.expiresAt ?? null,
  });
  await awaitEmailAccepted(message.message_id);
  return { templateId: input.template?.id ?? null, logged: true };
}
export async function prepareAccountEmail(input: DeliverEmailInput) {
  await admitEmailPreparation(input);
  const prepared = await renderEmail(input);
  const digest = Array.from(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(JSON.stringify(prepared)),
      ),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  return { p_sealed: await sealEmail(prepared), p_content_hash: digest };
}

async function admitEmailPreparation(input: DeliverEmailInput): Promise<void> {
  const allowed = await emailRpc("admit_email_preparation_v1", {
    p_organization: input.context.organization,
    p_occasion: input.context.occasion ?? null,
    p_unit: input.context.unit ?? null,
    p_recipient: input.to,
  });
  if (allowed !== true) throw new Error("email_preparation_deferred");
}
