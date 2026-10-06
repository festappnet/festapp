import type { DeliverEmailInput } from "../_shared/emailDelivery.ts";

export function configuredAppLinksOrganization() {
  const value = Number(Deno.env.get("APP_LINKS_ORGANIZATION_ID"));
  return Number.isSafeInteger(value) && value > 0 ? value : null;
}

export function isCsmOrganization(organizationId: unknown) {
  return organizationId === configuredAppLinksOrganization();
}

export type AppLinksDeliveryInput = {
  userId: string;
  occasionId: number;
  unitId: number | null;
  organizationId: number;
  deliveryEmail: string;
  appName: string;
  appLinks: string;
  fromEmail: string;
};

export type AppLinksDeliveryDependencies = {
  deliverEmail(input: DeliverEmailInput): Promise<unknown>;
};

export async function deliverAppLinks(
  input: AppLinksDeliveryInput,
  dependencies: AppLinksDeliveryDependencies,
) {
  await dependencies.deliverEmail({
    to: input.deliveryEmail,
    recipientUser: input.userId,
    templateCode: "APP_LINKS",
    context: {
      organization: input.organizationId,
      occasion: input.occasionId,
      unit: input.unitId,
    },
    substitutions: { appLinks: input.appLinks, appName: input.appName },
    from: `${input.appName} | Festapp <${input.fromEmail}>`,
  });
  // Acceptance and the app_links_sent projection are owned by canonical SQL.
}
