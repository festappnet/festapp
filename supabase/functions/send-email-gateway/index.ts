import { emailRpc } from "../_shared/emailQueueClient.ts";
import { openEmail } from "../_shared/emailPayload.ts";
import {
  sendSes,
  type SesConfig,
  sesRequest,
  verifySesAccount,
  verifySesConfiguration,
} from "../_shared/sesProvider.ts";
import { gatewayAttempt } from "./gateway.ts";
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
Deno.serve(async (req) => {
  const token = Deno.env.get("EMAIL_GATEWAY_TOKEN");
  if (
    req.method !== "POST" || !token ||
    req.headers.get("Authorization") !== `Bearer ${token}`
  ) return new Response(null, { status: 401 });
  try {
    const body = await req.json();
    if (body.refreshQuota === true) {
      try {
        if (await emailRpc("reserve_email_quota_refresh")) {
          const actualAccount = await verifySesAccount(
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
          ) throw new Error("ses_account_not_ready");
          await emailRpc("refresh_email_quota", {
            p_account: actualAccount,
            p_region: config.region,
            p_rate: account.SendQuota?.MaxSendRate,
            p_daily: account.SendQuota?.Max24HourSend,
            p_used: account.SendQuota?.SentLast24Hours,
          });
        }
        return Response.json({ quota: "checked" });
      } catch (error) {
        await emailRpc("invalidate_email_quota", {
          p_reason: "ses_preflight_failed",
        });
        throw error;
      }
    }
    if (
      !/^[0-9a-f-]{36}$/i.test(body.attemptId ?? "") ||
      !/^[0-9a-f-]{36}$/i.test(body.leaseToken ?? "")
    ) return new Response(null, { status: 400 });
    const result = await gatewayAttempt(body.attemptId, body.leaseToken, {
      rpc: emailRpc,
      open: openEmail,
      send: (message, tags, sensitive, engagement) =>
        sendSes(message, config, tags, sensitive, fetch, engagement),
      config,
    });
    return Response.json(result, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return Response.json({ error: "gateway_state_unconfirmed" }, {
      status: 503,
    });
  }
});
