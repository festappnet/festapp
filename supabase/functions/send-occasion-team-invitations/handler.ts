import { accessCommandId } from "../_shared/accessCommandId.ts";
export type InvitationRecipient = { email: string; kind: "member" | "account" | "new"; alreadyEditor?: boolean; role: "editor" | "read_only" };
export type InvitationPreview = { canManage: boolean; sendConfirmed: boolean; recipients: InvitationRecipient[];
 event: { id: number; title: string; unit: number; organization: number }; organizationData: { DEFAULT_URL: string; APP_NAME?: string } };
export interface InvitationDependencies {
 preview(authorization: string, draftId: string): Promise<InvitationPreview>;
 execute(authorization: string, commandId: string, request: Record<string, unknown>): Promise<unknown>;
}
export function createInvitationHandler(deps: InvitationDependencies) {
 return async (req: Request) => {
  const headers = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { headers, status });
  if (req.method === "OPTIONS") return json({});
  if (req.method !== "POST") return json({}, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "unauthenticated" }, 401);
  try {
   const { draftId } = await req.json();
   if (typeof draftId !== "string" || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(draftId)) return json({ error: "invalid_draft" }, 400);
   const preview = await deps.preview(authorization, draftId);
   if (!preview.canManage) return json({ error: "invitation_access_denied" }, 403);
   if (!preview.sendConfirmed || !preview.event?.id || preview.recipients.length > 20) return json({ error: "confirmation_required" }, 409);
   const results = [];
   for (const recipient of preview.recipients) {
    if (recipient.alreadyEditor) { results.push({ email: recipient.email, status: "already_editor" }); continue; }
    try {
     const result = await deps.execute(authorization, await accessCommandId(`setup:${draftId}:${recipient.email}:${recipient.role}`), {
      scope: { type: "occasion", id: preview.event.id }, operation: "send_invitation", communication: "invite_to_accept",
      email: recipient.email, sourceDraft: draftId, roles: { is_editor: recipient.role === "editor", is_editor_view: true },
     });
     results.push({ email: recipient.email, status: "queued", result });
    } catch { results.push({ email: recipient.email, status: "failed" }); }
   }
   return json({ complete: results.every(r => r.status !== "failed"), results });
  } catch { return json({ error: "invitation_access_denied" }, 403); }
 };
}
