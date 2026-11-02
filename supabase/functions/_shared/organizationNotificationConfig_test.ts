import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loadOrganizationNotificationConfig } from "./organizationNotificationConfig.ts";
import { buildNotificationPayload } from "../notify/notificationPayload.ts";

Deno.test("Slunovrat broadcast reaches its dedicated app without CSM tags", async () => {
  const client = {
    rpc() {
      return Promise.resolve({
        data: {
          onesignal_app_id: "4c5b7280-510f-4628-8fb8-b4bdd4fed1b2",
          onesignal_rest_api_key: "synthetic-only",
          default_url: "https://slunovrat.festapp.net",
        },
        error: null,
      });
    },
  };
  const config = await loadOrganizationNotificationConfig(client, 19);
  if (!config.defaultUrl) throw new Error("Fixture URL missing");
  const input = {
    ...config,
    defaultUrl: config.defaultUrl,
    occasionLink: "2025we-copy-5e6268f4",
    targetPath: "news",
    heading: "Koncert",
    content: "Změna programu",
  };
  const broadcast = buildNotificationPayload(input);
  assertEquals(
    "included_segments" in broadcast ? broadcast.included_segments : null,
    ["All"],
  );
  assertEquals("filters" in broadcast, false);
  const self = buildNotificationPayload({
    ...input,
    recipient: ["synthetic-editor"],
  });
  assertEquals("include_aliases" in self ? self.include_aliases : null, {
    external_id: ["synthetic-editor"],
  });
  assertEquals("included_segments" in self, false);
  assertEquals(
    (await loadOrganizationNotificationConfig(client, 1)).broadcastAudience,
    "generation",
  );
  assertEquals(
    (await loadOrganizationNotificationConfig({
      rpc() {
        return Promise.resolve({
          data: {
            onesignal_app_id: "different-app",
            onesignal_rest_api_key: "synthetic-only",
            default_url: "https://example.test",
          },
          error: null,
        });
      },
    }, 19)).broadcastAudience,
    "generation",
  );
});

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
