import { assertEquals } from "jsr:@std/assert@1";
import { emailWorkerEnvironment } from "./emailWorkerEnvironment.ts";

Deno.test("only the queue worker receives SES credentials; producers and feedback retain their own inputs", () => {
  const environment = {
    EMAIL_SES_ACCESS_KEY_ID: "fixture-access",
    EMAIL_SES_SECRET_ACCESS_KEY: "fixture-secret",
    EMAIL_SES_SESSION_TOKEN: "fixture-session",
    EMAIL_SES_REGION: "fixture-region",
    EMAIL_PAYLOAD_KEY: "fixture-payload",
    EMAIL_SNS_TOPIC_ARN: "fixture-topic",
    AUTH_EMAIL_HOOK_SECRET: "fixture-hook",
  };
  assertEquals(
    Object.fromEntries(
      emailWorkerEnvironment("process-email-queue", environment),
    ),
    environment,
  );
  for (
    const service of [
      "send-custom-email",
      "auth-email-hook",
      "email-provider-events",
      "unknown-function",
    ]
  ) {
    assertEquals(
      Object.fromEntries(emailWorkerEnvironment(service, environment)),
      {
        EMAIL_PAYLOAD_KEY: "fixture-payload",
        EMAIL_SNS_TOPIC_ARN: "fixture-topic",
        AUTH_EMAIL_HOOK_SECRET: "fixture-hook",
      },
    );
  }
});

Deno.test("router Monitoring credentials never reach application workers", () => {
  assertEquals(emailWorkerEnvironment("process-email-queue", { FESTAPP_MONITORING_TOKEN: "private", FESTAPP_MONITORING_URL: "https://monitor.invalid", DEFAULT_EMAIL: "sender" }), [["DEFAULT_EMAIL", "sender"]]);
});

Deno.test('only the font rendering owners receive the dedicated font capability', () => {
  const environment = { TICKET_FONT_SERVICE_SECRET: 'font-fixture', DEFAULT_EMAIL: 'sender' };
  for (const service of ['download-ticket','preview-ticket-layout','process-email-queue']) {
    assertEquals(Object.fromEntries(emailWorkerEnvironment(service,environment)), environment);
  }
  for (const service of ['confirm-account-deletion','send-tickets','fetch-http-data','unknown']) {
    assertEquals(Object.fromEntries(emailWorkerEnvironment(service,environment)), {DEFAULT_EMAIL:'sender'});
  }
});

Deno.test('only account confirmation receives the dedicated asset deletion capability', () => {
  const environment = { ASSET_CLEANUP_SERVICE_SECRET: 'delete-fixture', DEFAULT_EMAIL: 'sender' };
  assertEquals(Object.fromEntries(emailWorkerEnvironment('confirm-account-deletion', environment)), environment);
  for (const service of ['request-account-deletion','process-email-queue','download-ticket','fetch-http-data','unknown']) {
    assertEquals(Object.fromEntries(emailWorkerEnvironment(service, environment)), { DEFAULT_EMAIL: 'sender' });
  }
});
