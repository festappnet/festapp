export type InvitationRecipient = {
  email: string;
  kind: "member" | "account" | "new";
  alreadyEditor?: boolean;
  role: "editor" | "read_only";
};
export type InvitationPreview = {
  canManage: boolean;
  sendConfirmed: boolean;
  recipients: InvitationRecipient[];
  event: { id: number; title: string; unit: number; organization: number };
  organizationData: { DEFAULT_URL: string; APP_NAME?: string };
};
export interface InvitationDependencies {
  preview(authorization: string, draftId: string): Promise<InvitationPreview>;
  prepare(input: {
    to: string;
    templateCode: string;
    context: { organization: number; occasion: number; unit: number };
    substitutions: Record<string, string>;
  }): Promise<{ p_sealed: unknown; p_content_hash: string }>;
  enqueue(
    authorization: string,
    args: Record<string, unknown>,
  ): Promise<Record<string, unknown>>;
  token(): string;
}

export function htmlEscape(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

export async function invitationTokenHash(token: string): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)),
    ),
  ]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function createInvitationHandler(deps: InvitationDependencies) {
  return async (request: Request): Promise<Response> => {
    const headers = {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    };
    const json = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), { status, headers });
    if (request.method === "OPTIONS") return new Response("ok", { headers });
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json({ error: "unauthenticated" }, 401);
    }
    let draftId: string;
    try {
      const body = await request.json();
      draftId = body.draftId;
      if (
        typeof draftId !== "string" ||
        !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(draftId)
      ) {
        return json({ error: "invalid_draft" }, 400);
      }
    } catch {
      return json({ error: "invalid_request" }, 400);
    }
    let preview: InvitationPreview;
    try {
      preview = await deps.preview(authorization, draftId);
    } catch {
      return json({ error: "invitation_access_denied" }, 403);
    }
    if (!preview.canManage) {
      return json({ error: "invitation_access_denied" }, 403);
    }
    if (!preview.sendConfirmed) {
      return json({ error: "confirmation_required" }, 409);
    }
    if (!preview.event?.id || preview.recipients.length > 20) {
      return json({ error: "event_not_ready" }, 409);
    }
    let base: URL;
    try {
      base = new URL(preview.organizationData.DEFAULT_URL);
      if (
        base.protocol !== "https:" || base.username || base.password ||
        base.search || base.hash
      ) throw new Error();
    } catch {
      return json({ error: "invitation_origin_unavailable" }, 422);
    }
    const results: Array<{ email: string; status: string }> = [];
    for (const recipient of preview.recipients) {
      if (recipient.alreadyEditor) {
        results.push({ email: recipient.email, status: "already_editor" });
        continue;
      }
      try {
        const token = deps.token();
        const url = new URL("/team-invitation", base);
        url.searchParams.set("token", token);
        const prepared = await deps.prepare({
          to: recipient.email,
          templateCode: "TEAM_INVITATION",
          context: {
            organization: preview.event.organization,
            occasion: preview.event.id,
            unit: preview.event.unit,
          },
          substitutions: {
            eventTitle: htmlEscape(preview.event.title),
            roleLabel: recipient.role === "read_only"
              ? "Pouze pro čtení"
              : "Editor",
            appName: htmlEscape(preview.organizationData.APP_NAME ?? "Festapp"),
            invitationUrl: htmlEscape(url.toString()),
          },
        });
        const queued = await deps.enqueue(authorization, {
          p_id: draftId,
          p_email: recipient.email,
          p_token_hash: await invitationTokenHash(token),
          p_role: recipient.role,
          ...prepared,
        });
        if (
          queued.status !== "already_editor" &&
          typeof queued.message_id !== "string"
        ) throw new Error();
        results.push({
          email: recipient.email,
          status: queued.status === "already_editor"
            ? "already_editor"
            : "queued",
        });
      } catch {
        results.push({ email: recipient.email, status: "failed" });
      }
    }
    return json({
      complete: results.every((result) => result.status !== "failed"),
      results,
    });
  };
}
