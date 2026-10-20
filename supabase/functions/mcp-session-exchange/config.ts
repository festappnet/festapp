export type McpTenant = { tenantId: string; tenantOrigin: string; issuer: string; brokerSecret: string; organizationId: number };

/** Explicit first-party registry. Request bodies can never choose a tenant,
 * issuer, organization or broker credential. Future hosts reuse this handler. */
export function parseMcpTenants(raw: string): McpTenant[] {
  const values: unknown = JSON.parse(raw);
  if (!Array.isArray(values) || !values.length || values.length > 100) throw new Error("invalid_mcp_tenants");
  const origins = new Set<string>();
  return values.map(value => {
    const tenant = value as McpTenant;
    for (const origin of [tenant.tenantOrigin, tenant.issuer]) {
      const url = new URL(origin);
      if (url.protocol !== "https:" || url.origin !== origin) throw new Error("invalid_mcp_origin");
    }
    if (!/^[a-z0-9][a-z0-9-]{0,99}$/.test(tenant.tenantId) ||
        !Number.isSafeInteger(tenant.organizationId) || tenant.organizationId <= 0 ||
        !/^[A-Za-z0-9_-]{43}$/.test(tenant.brokerSecret) || origins.has(tenant.tenantOrigin)) throw new Error("invalid_mcp_tenant");
    origins.add(tenant.tenantOrigin);
    return Object.freeze({ tenantId: tenant.tenantId, tenantOrigin: tenant.tenantOrigin,
      issuer: tenant.issuer, brokerSecret: tenant.brokerSecret, organizationId: tenant.organizationId });
  });
}
