import {
  sendSes,
  sesBody,
  type SesConfig,
  SesFailure,
  sesRequest,
  verifySesAccount,
  verifySesConfiguration,
} from "./sesProvider.ts";
import type { PreparedEmail } from "./emailDelivery.ts";
import { emailRpc } from "./emailQueueClient.ts";
import { openEmail } from "./emailPayload.ts";
export type EmailSenderDependencies = {
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
export async function sendEmailAttempt(
  attemptId: string,
  token: string,
  d: EmailSenderDependencies,
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
        : "sender_ambiguous",
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

/** Used only inside process-email-queue after its machine proof is verified. */
export function createEmailSender() {
  const config: SesConfig = {
    region: Deno.env.get("EMAIL_SES_REGION") ?? "",
    accessKey: Deno.env.get("EMAIL_SES_ACCESS_KEY_ID") ?? "",
    secretKey: Deno.env.get("EMAIL_SES_SECRET_ACCESS_KEY") ?? "",
    sessionToken: Deno.env.get("EMAIL_SES_SESSION_TOKEN"),
    sender: Deno.env.get("DEFAULT_EMAIL") ?? "",
    transactionalSet: Deno.env.get("EMAIL_SES_TRANSACTIONAL_SET") ?? "",
    securitySet: Deno.env.get("EMAIL_SES_SECURITY_SET") ?? "",
    engagementSet: Deno.env.get("EMAIL_SES_ENGAGEMENT_SET"),
    maxBytes: Number(Deno.env.get("EMAIL_MAX_BYTES") ?? "30000000"),
  };
  return {
    async refreshQuota() {
      try {
        if (!await emailRpc("reserve_email_quota_refresh")) return;
        const accountId = await verifySesAccount(
          config,
          Deno.env.get("EMAIL_SES_ACCOUNT_ID") ?? "",
        );
        await verifySesConfiguration(
          config,
          Deno.env.get("EMAIL_SNS_TOPIC_ARN") ?? "",
        );
        const account = await sesRequest(
          config,
          "GET",
          "/v2/email/account",
          null,
        );
        if (
          account.SendingEnabled !== true ||
          account.ProductionAccessEnabled !== true
        ) {
          throw new Error("ses_account_not_ready");
        }
        await emailRpc("refresh_email_quota", {
          p_account: accountId,
          p_region: config.region,
          p_rate: account.SendQuota?.MaxSendRate,
          p_daily: account.SendQuota?.Max24HourSend,
          p_used: account.SendQuota?.SentLast24Hours,
        });
      } catch (error) {
        await emailRpc("invalidate_email_quota", {
          p_reason: "ses_preflight_failed",
        });
        throw error;
      }
    },
    async send(row: { attempt_id: string; lease_token: string }) {
      await sendEmailAttempt(row.attempt_id, row.lease_token, {
        rpc: emailRpc,
        open: openEmail,
        config,
        send: (message, tags, sensitive, engagement) =>
          sendSes(message, config, tags, sensitive, fetch, engagement),
      });
    },
  };
}
