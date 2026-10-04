import { sesBody, type SesConfig, SesFailure } from "../_shared/sesProvider.ts";
import type { PreparedEmail } from "../_shared/emailDelivery.ts";
export type GatewayDependencies = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<any>;
  open: (value: any) => Promise<PreparedEmail>;
  send: (
    message: PreparedEmail,
    tags: Record<string, string>,
    sensitive: boolean,
    engagement: boolean,
  ) => Promise<string>;
  config: SesConfig;
};
export async function gatewayAttempt(
  attemptId: string,
  token: string,
  d: GatewayDependencies,
) {
  // Atomic begin, validation and permit. No HTTP replay can cross this boundary twice.
  const begin = await d.rpc("begin_email_send", {
    p_attempt: attemptId,
    p_token: token,
  });
  if (begin.disposition !== "send") return begin;
  const row = begin.message;
  let providerId: string;
  let providerStarted = false;
  try {
    const message = await d.open(row.prepared);
    if (message.to !== row.recipient) {
      throw new Error("prepared_recipient_mismatch");
    }
    const sensitive = row.tracking_policy === "disabled";
    sesBody(
      message,
      d.config,
      {
        message_id: row.message_id,
        attempt_id: attemptId,
        message_kind: row.message_kind,
      },
      sensitive,
      row.tracking_policy === "engagement",
    );
    providerStarted = true;
    providerId = await d.send(
      message,
      {
        message_id: row.message_id,
        attempt_id: attemptId,
        message_kind: row.message_kind,
        organization_id: String(row.organization),
      },
      sensitive,
      row.tracking_policy === "engagement",
    );
  } catch (e) {
    const outcome = !providerStarted
      ? "dead"
      : e instanceof SesFailure
      ? e.outcome
      : "unknown";
    await d.rpc("finish_email_attempt", {
      p_attempt: attemptId,
      p_token: token,
      p_outcome: outcome,
      p_error: !providerStarted
        ? "prepared_payload_invalid"
        : e instanceof SesFailure
        ? e.code
        : "gateway_ambiguous",
    });
    return { disposition: outcome };
  }
  // Persistence failure after acceptance must never pass through a send-retry catch.
  await d.rpc("finish_email_attempt", {
    p_attempt: attemptId,
    p_token: token,
    p_outcome: "accepted",
    p_provider_id: providerId,
  });
  return { disposition: "accepted" };
}
