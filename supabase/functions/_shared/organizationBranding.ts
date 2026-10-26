export type OrganizationBranding = {
  appName: string;
  defaultUrl: string;
};

export function parseOrganizationBranding(data: unknown): OrganizationBranding {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("organization_branding_missing");
  }
  const value = data as Record<string, unknown>;
  const appName = typeof value.APP_NAME === "string" ? value.APP_NAME.trim() : "";
  const defaultUrl = typeof value.DEFAULT_URL === "string"
    ? value.DEFAULT_URL.trim().replace(/\/+$/, "")
    : "";
  if (!appName || !defaultUrl) throw new Error("organization_branding_missing");
  const parsed = new URL(defaultUrl);
  if (!/^https?:$/.test(parsed.protocol)) throw new Error("organization_branding_invalid_url");
  return { appName, defaultUrl };
}
