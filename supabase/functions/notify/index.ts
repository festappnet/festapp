import { buildNotificationPayload } from "./notificationPayload.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { loadOrganizationNotificationConfig } from "../_shared/organizationNotificationConfig.ts";
import { webhookTokenMatches } from "./webhookAuth.ts";

Deno.serve(async (req) => {
  const expectedToken = Deno.env.get("NOTIFY_WEBHOOK_TOKEN") ?? "";
  if (req.method !== "POST" || Number(req.headers.get("content-length") ?? 0) > 64 * 1024 ||
      !await webhookTokenMatches(req.headers.get("Authorization"), expectedToken)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  }
  let notificationId: unknown;
  try { notificationId = (await req.json())?.record?.id; }
  catch { return Response.json({ error: "invalid_payload" }, {status:400}); }
  if (typeof notificationId !== "string" || !/^[0-9a-f-]{36}$/i.test(notificationId)) {
    return Response.json({error:"invalid_payload"},{status:400});
  }
  const {data:record,error:admissionError}=await supabaseAdmin.rpc("admit_notification_delivery_v1",{p_notification:notificationId});
  if(admissionError || !record) return Response.json({error:"notification_unavailable"},{status:admissionError?.code==="PT429"?429:503});
  if (record.allowed !== true) return Response.json({error:"temporarily_limited"},{status:429});
  const organizationId = record.organization; // assuming `organization` is passed in `record`
  const url = "https://onesignal.com/api/v1/notifications";

  let notificationConfig;
  try {
    notificationConfig = await loadOrganizationNotificationConfig(
      supabaseAdmin,
      organizationId,
    );
  } catch {
    console.error("Required organization configuration is missing.");
    return new Response(
      JSON.stringify({ error: "Missing required organization configuration" }),
      {
        headers: { "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
  const { appId: onesignalAppId, restApiKey: onesignalRestApiKey, defaultUrl } =
    notificationConfig;
  if (!defaultUrl) {
    console.error("Required organization configuration is missing.");
    return new Response(
      JSON.stringify({ error: "Missing required organization configuration" }),
      { headers: { "Content-Type": "application/json" }, status: 400 },
    );
  }

  // Optional deep-link target path within the occasion (e.g. "cleaning").
  // Falls back to "news" so existing notifications are unaffected.
  const targetPath =
    (record.data && ["news", "cleaning"].includes(record.data.path))
      ? record.data.path
      : "news";

  const payload = buildNotificationPayload({
    appId: onesignalAppId,
    defaultUrl,
    occasionLink: record.occasion_link,
    targetPath,
    recipient: record.to,
    heading: record.heading,
    content: record.content,
  });

  // Send notification to OneSignal
  let response: Response;
  try { response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${onesignalRestApiKey}`,
    },
    body: JSON.stringify({ ...payload, idempotency_key: record.id }),
    signal: AbortSignal.timeout(10000),
  }); } catch { return Response.json({error:"notification_delivery_unavailable"},{status:503}); }

  if (!response.ok) {
    console.error("Notification delivery failed with status:", response.status);
    return new Response(
      JSON.stringify({ error: "notification_delivery_failed" }),
      {
        status: 502,
        headers: { "Content-Type": "application/json" },
      },
    );
  } else {
    return new Response(JSON.stringify({ status: "accepted" }), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  }
});
