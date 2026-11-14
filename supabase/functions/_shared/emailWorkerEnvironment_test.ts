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

Deno.test('only the first-party MCP broker receives the protected tenant registry', () => {
  const environment = { FESTAPP_MCP_TENANTS_JSON: 'secret registry', DEFAULT_EMAIL: 'sender' };
  assertEquals(Object.fromEntries(emailWorkerEnvironment('mcp-session-exchange', environment)), environment);
  for (const service of ['process-email-queue', 'google-auth-start', 'fetch-http-data', 'unknown']) {
    assertEquals(Object.fromEntries(emailWorkerEnvironment(service, environment)), { DEFAULT_EMAIL: 'sender' });
  }
});

Deno.test('only the subscription boundary receives Turnstile configuration', () => {
  const environment = {SALE_OPENING_TURNSTILE_SITE_KEY:'public',SALE_OPENING_TURNSTILE_SECRET_KEY:'private',SALE_OPENING_TURNSTILE_HOSTNAMES:'vstupenky.online',DEFAULT_EMAIL:'sender'};
  assertEquals(Object.fromEntries(emailWorkerEnvironment('sale-opening-notifications',environment)),environment);
  for (const service of ['process-email-queue','auth-email-hook','unknown-function']) {
    assertEquals(Object.fromEntries(emailWorkerEnvironment(service,environment)),{DEFAULT_EMAIL:'sender'});
  }
});

Deno.test('only Wallet owners receive signing credentials and only its public handler receives the origin allowlist', () => {
  const environment={GOOGLE_WALLET_SERVICE_ACCOUNT:'private-fixture',GOOGLE_WALLET_ALLOWED_ORIGINS:'https://tenant.invalid',DEFAULT_EMAIL:'sender'};
  assertEquals(Object.fromEntries(emailWorkerEnvironment('ticket-wallet',environment)),environment);
  assertEquals(Object.fromEntries(emailWorkerEnvironment('sync-ticket-wallet',environment)),{GOOGLE_WALLET_SERVICE_ACCOUNT:'private-fixture',DEFAULT_EMAIL:'sender'});
  for(const service of ['payment-operation','process-email-queue','send-custom-email','fetch-http-data','unknown'])
    assertEquals(Object.fromEntries(emailWorkerEnvironment(service,environment)),{DEFAULT_EMAIL:'sender'});
});

Deno.test('Apple signing inputs only reach Wallet adapters, never email or other provider workers',()=>{
 const environment={APPLE_WALLET_CREDENTIALS:'protected',APPLE_WALLET_WEB_SERVICE_URL:'https://api.festapp.net/functions/v1/apple-wallet',TICKET_WALLET_ALLOWED_ORIGINS:'https://vstupenky.online',DEFAULT_EMAIL:'sender'};
 assertEquals(Object.fromEntries(emailWorkerEnvironment('ticket-wallet',environment)),environment);
 for(const service of ['sync-ticket-wallet','apple-wallet'])assertEquals(Object.fromEntries(emailWorkerEnvironment(service,environment)),{APPLE_WALLET_CREDENTIALS:'protected',APPLE_WALLET_WEB_SERVICE_URL:environment.APPLE_WALLET_WEB_SERVICE_URL,DEFAULT_EMAIL:'sender'});
 for(const service of ['process-email-queue','send-custom-email','fetch-http-data','payment-operation','unknown'])assertEquals(Object.fromEntries(emailWorkerEnvironment(service,environment)),{DEFAULT_EMAIL:'sender'});
});
