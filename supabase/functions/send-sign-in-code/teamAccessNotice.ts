import type { DeliverEmailInput } from "../_shared/emailDelivery.ts";

export type TeamAccess = {
  is_editor?: boolean;
  is_editor_view?: boolean;
  is_manager?: boolean;
};
export function hasTeamAccess(access: TeamAccess): boolean {
  return access.is_editor === true || access.is_editor_view === true ||
    access.is_manager === true;
}
function escape(value: string) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(
    ">",
    "&gt;",
  )
    .replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

/** A pre-existing team membership needs a notice, never a credential reset. */
export async function sendTeamAccessNotice(input: {
  access: TeamAccess;
  occasion: {
    id: number;
    organization: number;
    unit: number;
    link: string;
    title: string;
  };
  user: string;
  email: string;
  defaultUrl: string;
  appName: string;
  requestId: string;
}, deps: {
  authorize(): Promise<unknown>;
  deliver(input: DeliverEmailInput & { dedupeKey: string }): Promise<unknown>;
}): Promise<void> {
  if (!hasTeamAccess(input.access)) throw new Error("not_a_team_member");
  await deps.authorize();
  const base = new URL(input.defaultUrl);
  if (
    base.protocol !== "https:" || base.username || base.password ||
    base.search || base.hash
  ) {
    throw new Error("invalid_organization_origin");
  }
  const eventUrl = new URL(
    `/${encodeURIComponent(input.occasion.link)}/admin`,
    base,
  );
  await deps.deliver({
    to: input.email,
    recipientUser: input.user,
    templateCode: "TEAM_ACCESS_NOTICE",
    context: {
      organization: input.occasion.organization,
      occasion: input.occasion.id,
      unit: input.occasion.unit,
    },
    substitutions: {
      appName: escape(input.appName),
      eventTitle: escape(input.occasion.title),
      eventUrl: escape(eventUrl.toString()),
      roleLabel: input.access.is_manager
        ? "Správce"
        : input.access.is_editor
        ? "Editor"
        : "Pouze pro čtení",
    },
    dedupeKey:
      `team-access:${input.occasion.id}:${input.user}:${input.requestId}`,
  });
}
