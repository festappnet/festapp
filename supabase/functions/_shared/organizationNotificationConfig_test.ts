import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loadOrganizationNotificationConfig } from "./organizationNotificationConfig.ts";

Deno.test("loads notification credentials only through the server RPC", async () => {
  let observedName = "";
  let observedOrganization = 0;
  const value = await loadOrganizationNotificationConfig({
    rpc(name, parameters) {
      observedName = name;
      observedOrganization = parameters.p_organization_id as number;
      return Promise.resolve({
        data: {
          onesignal_app_id: "app-id",
          onesignal_rest_api_key: "server-only-value",
          default_url: "https://example.test",
        },
        error: null,
      });
    },
  }, 12);

  assertEquals(observedName, "get_organization_notification_delivery_config");
  assertEquals(observedOrganization, 12);
  assertEquals(value.appId, "app-id");
  assertEquals(value.defaultUrl, "https://example.test");
});

Deno.test("fails closed for missing notification credentials", async () => {
  await assertRejects(
    () =>
      loadOrganizationNotificationConfig({
        rpc() {
          return Promise.resolve({ data: null, error: { code: "denied" } });
        },
      }, 12),
    Error,
    "notification_configuration",
  );
});
