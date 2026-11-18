import { emailPayloadHash, sealEmail } from "../_shared/emailPayload.ts";
import type { Contact } from "./handler.ts";

function escapeHtml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

export async function contactIntent(
  { id, email, message }: Contact,
  from: string,
) {
  const sealed = await sealEmail({
    from,
    to: "info@vstupenky.online",
    subject: "Dotaz z formuláře vstupenky.online",
    html: `<p>E-mail pro odpověď: ${escapeHtml(email)}</p><p>${
      escapeHtml(message).replace(/\r\n|\r|\n/g, "<br>")
    }</p>`,
    replyTo: email,
    attachments: [],
  });
  return {
    p_id: id,
    p_reply_to: email,
    p_sealed: sealed,
    p_content_hash: await emailPayloadHash(JSON.stringify([email, message])),
  };
}
