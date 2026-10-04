import {
  SnsVerificationError,
  trustedSnsUrl,
  verifySnsEnvelope,
} from "../_shared/snsVerification.ts";
import { normalizeSesEvents } from "./events.ts";
export function feedbackHandler(
  d: {
    topic: string;
    rpc: (name: string, args: Record<string, unknown>) => Promise<unknown>;
    verify?: typeof verifySnsEnvelope;
    fetch?: typeof fetch;
  },
) {
  return async (req: Request) => {
    if (req.method !== "POST") return new Response(null, { status: 405 });
    if (!d.topic) return new Response(null, { status: 503 });
    try {
      const text = await req.text();
      if (text.length > 256000) return new Response(null, { status: 413 });
      const envelope = JSON.parse(text);
      await (d.verify ?? verifySnsEnvelope)(envelope, req.headers, d.topic);
      if (envelope.Type === "SubscriptionConfirmation") {
        const response = await (d.fetch ?? fetch)(
          trustedSnsUrl(envelope.SubscribeURL, d.topic, true),
          { redirect: "error", signal: AbortSignal.timeout(10_000) },
        );
        if (!response.ok) return new Response(null, { status: 503 });
      } else {
        const events = normalizeSesEvents(
          JSON.parse(envelope.Message),
          d.topic,
          envelope.MessageId,
        );
        await d.rpc("record_email_events", { p_events: events });
      }
      return new Response(null, { status: 204 });
    } catch (e) {
      return new Response(null, {
        status: e instanceof SnsVerificationError ? 403 : 503,
      });
    }
  };
}
