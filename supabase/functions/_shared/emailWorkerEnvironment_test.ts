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
