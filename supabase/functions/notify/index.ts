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
  const { record } = await req.json();
  if (!record || typeof record !== "object" || !Number.isSafeInteger(record.organization) ||
      !Number.isSafeInteger(record.occasion)) {
    return new Response(JSON.stringify({ error: "invalid_payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
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

  // Fetch the link for the current occasion
  const currentLink = await supabaseAdmin
    .from("occasions")
    .select("link")
    .eq("id", record.occasion)
    .single();

  if (currentLink.error || !currentLink.data) {
    console.error("Occasion link not found.");
    return new Response(JSON.stringify({ error: "Occasion link not found" }), {
      headers: { "Content-Type": "application/json" },
      status: 404,
    });
  }

  // Optional deep-link target path within the occasion (e.g. "cleaning").
  // Falls back to "news" so existing notifications are unaffected.
  const targetPath =
    (record.data && typeof record.data.path === "string" && record.data.path)
      ? record.data.path
      : "news";

  const payload = buildNotificationPayload({
    appId: onesignalAppId,
    defaultUrl,
    occasionLink: currentLink.data.link,
    targetPath,
    recipient: record.to,
    heading: record.heading,
    content: record.content,
  });

  // Send notification to OneSignal
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${onesignalRestApiKey}`,
    },
    body: JSON.stringify(payload),
  });

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
