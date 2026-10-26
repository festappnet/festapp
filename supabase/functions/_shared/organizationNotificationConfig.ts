type RpcClient = {
  rpc: (
    functionName: string,
    parameters: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>;
};

export type OrganizationNotificationConfig = {
  appId: string;
  restApiKey: string;
  defaultUrl: string | null;
};

export async function loadOrganizationNotificationConfig(
  client: RpcClient,
  organizationId: number,
): Promise<OrganizationNotificationConfig> {
  if (!Number.isSafeInteger(organizationId) || organizationId <= 0) {
    throw new Error("notification_configuration");
  }

  const { data, error } = await client.rpc(
    "get_organization_notification_delivery_config",
    { p_organization_id: organizationId },
  );
  if (error || data == null || typeof data !== "object") {
    throw new Error("notification_configuration");
  }

  const value = data as Record<string, unknown>;
  const appId = value.onesignal_app_id;
  const restApiKey = value.onesignal_rest_api_key;
  const defaultUrl = value.default_url;
  if (
    typeof appId !== "string" || appId.length === 0 ||
    typeof restApiKey !== "string" || restApiKey.length === 0 ||
    (defaultUrl !== null && typeof defaultUrl !== "string")
  ) {
    throw new Error("notification_configuration");
  }

  return { appId, restApiKey, defaultUrl };
}
