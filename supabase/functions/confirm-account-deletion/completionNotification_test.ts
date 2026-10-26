import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { sendCompletionNotification } from "./completionNotification.ts";

Deno.test("completed deletion sends to the delivery email captured by the claim", async () => {
  const sent: Array<Record<string, unknown>> = [];
  const delivered = await sendCompletionNotification({
    completionEmail: "delivery@example.test",
    organization: 9,
    appName: "Tenant App",
  }, async (message) => {
    sent.push(message);
  });

  assertEquals(delivered, true);
  assertEquals(sent, [{
    to: "delivery@example.test",
    templateCode: "ACCOUNT_DELETION_COMPLETE",
    context: { organization: 9 },
    substitutions: { appName: "Tenant App" },
  }]);
});

Deno.test("completed deletion without a captured address stays best-effort", async () => {
  const sent: Array<Record<string, unknown>> = [];
  const delivered = await sendCompletionNotification({
    organization: 9,
    appName: "Tenant App",
  }, async (message) => {
    sent.push(message);
  });

  assertEquals(delivered, false);
  assertEquals(sent, []);
});
