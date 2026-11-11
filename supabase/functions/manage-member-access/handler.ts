import type { RegisteredEmailValues } from "../_shared/emailVariables.ts";
import { generateSignInCode } from "../_shared/signInCode.ts";
import { translatePlatformLinks } from "../_shared/translatePlatformLinks.ts";

export type AccessPreview = {
  replay?: Record<string, unknown>; existingInvitation?: { invitationId: string; messageId: string } | null;
  actor: string; intentHash: string; previewHash: string;
  scope: { type: string; id: number }; unit: number; occasion: number | null; organization: number;
  profile?: Record<string, unknown>; userId?: string; email: string; recipient: string; member?: Record<string, unknown>;
  roles: Record<string, unknown>; title: string; destination: string;
  communication: string;
  organizationData: { DEFAULT_URL: string; APP_NAME?: string; DEFAULT_LANGUAGE?: string; PLATFORMS?: { platform: string; link: string }[] };
};
export interface AccessDependencies {
  preview(authorization: string, commandId: string, request: Record<string, unknown>): Promise<AccessPreview>;
  prepare(input: Record<string, unknown>): Promise<Record<string, unknown>>;
  stage(args: Record<string, unknown>): Promise<string | null>;
  commit(authorization: string, commandId: string, request: Record<string, unknown>, preparation: string | null): Promise<Record<string, unknown>>;
  token(): string;
}
const escape = (value: unknown) => String(value ?? "");
const roleLabels: Record<string, Record<string, string>> = {
  cs: { is_manager: "Správce", is_editor: "Editor", is_editor_view: "Pouze pro čtení", is_editor_order: "Správa objednávek", is_editor_order_view: "Čtení objednávek", is_receptionist: "Recepce", is_approver: "Schvalování", is_cleaning_crew: "Úklid", is_cleaning_blocked: "Blokace úklidu" },
  en: { is_manager: "Manager", is_editor: "Editor", is_editor_view: "Read only", is_editor_order: "Order management", is_editor_order_view: "Order viewer", is_receptionist: "Reception", is_approver: "Approver", is_cleaning_crew: "Cleaning", is_cleaning_blocked: "Cleaning blocked" },
};
export async function hashAccessToken(token: string) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)))].map(b => b.toString(16).padStart(2, "0")).join("");
}
export async function executeMemberAccess(deps: AccessDependencies, authorization: string, commandId: string, request: Record<string, unknown>) {
  const preview = await deps.preview(authorization, commandId, request);
  if (preview.replay) return preview.replay;
  if (preview.existingInvitation) return await deps.commit(authorization, commandId, request, null);
  if (preview.communication === "none") return await deps.commit(authorization, commandId, request, null);
  const base = new URL(preview.organizationData.DEFAULT_URL);
  if (!["https:", "http:"].includes(base.protocol) || base.protocol === "http:" && !["localhost", "127.0.0.1"].includes(base.hostname)
    || base.username || base.password || base.search || base.hash) throw new Error("invalid_organization_origin");
  const token = preview.communication === "invite_to_accept" ? deps.token() : null;
  const password = preview.communication === "participant_credentials" ? generateSignInCode() : null;
  const url = new URL(token ? "/team-invitation" : preview.destination, base);
  if (token) url.searchParams.set("token", token);
  const labels = roleLabels[preview.organizationData.DEFAULT_LANGUAGE ?? "en"] ?? roleLabels.en;
  const labelsText = Object.entries(preview.roles).filter(([key, value]) => value === true && labels[key]).map(([key]) => labels[key]).join(", ");
  const substitutions: RegisteredEmailValues = password ? {
      code: password, email: escape(preview.email), name: escape(preview.profile?.name),
      surname: escape(preview.profile?.surname),
      appName: escape(preview.organizationData.APP_NAME ?? "Festapp"),
      platformLinks: translatePlatformLinks(preview.organizationData.PLATFORMS ?? [], preview.organizationData.DEFAULT_LANGUAGE ?? "en"),
    } : { appName: escape(preview.organizationData.APP_NAME ?? "Festapp"), occasionTitle: escape(preview.title),
      roleLabel: escape(labelsText), occasionAdminUrl: escape(url), invitationUrl: escape(url) };
  const input = {
    to: preview.recipient, recipientUser: preview.communication === "invite_to_accept" ? undefined : preview.userId,
    templateCode: token ? "TEAM_INVITATION" : password ? "SIGN_IN_CODE" : "TEAM_ACCESS_NOTICE",
    context: { organization: preview.organization, unit: preview.unit, occasion: preview.occasion },
    substitutions,
  };
  const prepared = await deps.prepare(input);
  const preparation = await deps.stage({ p_actor: preview.actor, p_command_id: commandId,
    p_intent_hash: preview.intentHash, p_preview_hash: preview.previewHash, p_prepared: prepared,
    p_token_hash: token ? await hashAccessToken(token) : null, p_password: password });
  return await deps.commit(authorization, commandId, request, preparation);
}
const safeReasons = new Set(["already_member", "invalid_email", "scope_denied", "credential_operation_denied", "version_conflict", "command_payload_conflict", "preparation_deferred", "invitation_expired", "invitation_revoked", "wrong_identity", "upgrade_required", "dispatch_unresolved", "invalid_intent", "membership_required", "roles_required", "invitation_pending"]);
export function createMemberAccessHandler(deps: AccessDependencies) {
  return async (req: Request) => {
    const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
    const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { headers, status });
    if (req.method === "OPTIONS") return json({});
    if (req.method !== "POST") return json({ reasonCode: "method_not_allowed" }, 405);
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ reasonCode: "unauthenticated" }, 401);
    try {
      const body = await req.json();
      if (typeof body.commandId !== "string" || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.commandId)
        || !body.request || typeof body.request !== "object" || Array.isArray(body.request)) return json({ reasonCode: "invalid_intent" }, 400);
      return json(await executeMemberAccess(deps, authorization, body.commandId, body.request));
    } catch (error) {
      const correlationId = crypto.randomUUID();
      const reason = error instanceof Error && safeReasons.has(error.message) ? error.message
        : error instanceof Error && error.message === "email_preparation_deferred" ? "preparation_deferred" : "access_operation_failed";
      // No SQL detail, recipient, token or credential in customer errors/logs.
      console.error(JSON.stringify({ correlationId, reason }));
      return json({ status: "rejected", code: reason === "scope_denied" || reason === "credential_operation_denied" ? 403 : 409, reasonCode: reason, correlationId },
        reason === "scope_denied" || reason === "credential_operation_denied" ? 403 : 409);
    }
  };
}
