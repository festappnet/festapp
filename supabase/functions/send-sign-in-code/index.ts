// Supported participant credential producer and old HTTP acceptance contract.
// Domain intent, trusted preparation and atomic enqueue live in access management.
import { executeMemberAccess } from "../manage-member-access/handler.ts";
import { memberAccessDependencies } from "../manage-member-access/dependencies.ts";
import { accessCommandId } from "../_shared/accessCommandId.ts";
import { awaitEmailAccepted, EmailAcceptancePendingError } from "../_shared/emailQueueClient.ts";
const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("{}", { headers });
  if (req.method !== "POST") return new Response("{}", { headers, status: 405 });
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return new Response("{}", { headers, status: 401 });
  try {
    const body = await req.json();
    if (typeof body.usr !== "string" || !Number.isSafeInteger(body.oc)) return new Response("{}", { headers, status: 400 });
    const commandId = await accessCommandId(`sign-in:${body.oc}:${body.usr}:${body.requestId ?? Math.floor(Date.now() / 300000)}`);
    const request = { scope: { type: "occasion", id: body.oc }, userId: body.usr, operation: "send_invitation", communication: "notify_existing_access" };
    const preview = await memberAccessDependencies.preview(authorization, await accessCommandId(commandId + ":probe"), request);
    if (preview.replay) {
      const id = (preview.replay.data as { communication?: { messageId?: string } })?.communication?.messageId;
      if (id) await awaitEmailAccepted(id);
      return new Response(JSON.stringify({ user: body.usr, code: 200, status: "sent" }), { headers });
    }
    const member = preview.member ?? {};
    if (!member.is_manager && !member.is_editor && !member.is_editor_view) request.communication = "participant_credentials";
    // A credential retry has a different intent than the first mode probe.
    const result = await executeMemberAccess(memberAccessDependencies, authorization, commandId, request);
    const messageId = (result.data as { communication: { messageId: string } }).communication.messageId;
    await awaitEmailAccepted(messageId);
    return new Response(JSON.stringify({ user: body.usr, code: 200, status: "sent" }), { headers });
  } catch (error) {
    if (error instanceof EmailAcceptancePendingError) return new Response(JSON.stringify({ code: 202, status: "queued", messageId: error.messageId }), { headers, status: 202 });
    return new Response(JSON.stringify({ error: "invitation_failed" }), { headers, status: 403 });
  }
});
