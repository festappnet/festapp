import { Webhook } from "npm:standardwebhooks@1.0.0";
import type { prepareAccountEmail } from "../_shared/emailQueueClient.ts";
import { authEmailContent, authEmailRecipients } from "./content.ts";
async function intentHash(value: string) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
export function authEmailHandler(
  d: {
    secret: string;
    publicAuthUrl: string;
    rpc: (name: string, args: Record<string, unknown>) => Promise<any>;
    prepare: typeof prepareAccountEmail;
  },
) {
  return async (req: Request) => {
    if (req.method !== "POST") return new Response(null, { status: 405 });
    const secret = d.secret;
    if (!secret) return new Response(null, { status: 503 });
    try {
      const body = await req.text();
      if (body.length > 64000) return new Response(null, { status: 413 });
      const payload = new Webhook(secret.replace(/^v1,/, "")).verify(
        body,
        Object.fromEntries(req.headers),
      ) as any;
      const data = payload.email_data;
      if (!req.headers.get("webhook-id")) {
        return new Response(null, { status: 400 });
      }
      const context = await d.rpc("get_auth_email_context", {
        p_user: payload.user?.id,
      });
      if (!context) throw new Error("auth_email_scope_unavailable");
      // No tracking/rewrite and no side effect on GET: the existing Auth verification flow owns the proof.
      for (const recipient of authEmailRecipients(payload.user, data)) {
        const template = authEmailContent(recipient.data, d.publicAuthUrl);
        const snapshot = await d.prepare({
          to: recipient.to,
          recipientUser: payload.user.id,
          context: { organization: context.organization },
          template,
          substitutions: {},
        });
        await d.rpc("enqueue_prepared_email", {
          p_kind: "gotrue",
          p_context: {
            organization: context.organization,
            recipient_user: payload.user.id,
          },
          p_recipient: recipient.to,
          ...snapshot,
          p_content_hash: await intentHash(
            JSON.stringify({
              user: payload.user.id,
              recipient: recipient.to,
              data: recipient.data,
            }),
          ),
          p_dedupe: `auth-hook:${
            req.headers.get("webhook-id")
          }:${recipient.suffix}`,
          p_code: "",
          p_expires: new Date(Date.now() + 600000).toISOString(),
        });
      }
      return Response.json({}); // Durable acknowledgment, not a claim of delivery.
    } catch {
      return Response.json({
        error: {
          http_code: 503,
          message: "Email intent could not be recorded",
        },
      }, { status: 503 });
    }
  };
}
