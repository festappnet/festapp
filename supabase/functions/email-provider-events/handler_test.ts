import { assertEquals } from "jsr:@std/assert@1";
import { feedbackHandler } from "./handler.ts";
import { SnsVerificationError } from "../_shared/snsVerification.ts";
const root = {
  eventType: "Delivery",
  mail: {
    messageId: "fixture-provider",
    timestamp: "2026-10-03T10:00:00Z",
    destination: ["fixture@example.invalid"],
  },
  delivery: { timestamp: "2026-10-03T10:01:00Z" },
};
const request = (id = "original") =>
  new Request("https://example.invalid", {
    method: "POST",
    body: JSON.stringify({
      Type: "Notification",
      MessageId: id,
      Message: JSON.stringify(root),
    }),
  });
Deno.test("feedback outage does not acknowledge; replay has one stable redacted event identity", async () => {
  let available = false;
  const journal = new Set<string>();
  const handler = feedbackHandler({
    topic: "fixture-topic",
    verify: async () => {},
    rpc: async (name, args) => {
      assertEquals(name, "record_email_events");
      if (!available) throw new Error("DB down");
      for (const e of args.p_events as any[]) journal.add(e.key);
    },
  });
  assertEquals((await handler(request())).status, 503);
  assertEquals(journal.size, 0);
  available = true;
  assertEquals((await handler(request())).status, 204);
  assertEquals((await handler(request("replayed-sns-id"))).status, 204);
  assertEquals(journal.size, 1);
});
Deno.test("forged SNS never reaches persistence", async () => {
  let calls = 0;
  const handler = feedbackHandler({
    topic: "fixture-topic",
    verify: async () => {
      throw new SnsVerificationError("invalid_signature");
    },
    rpc: async () => {
      calls++;
    },
  });
  assertEquals((await handler(request())).status, 403);
  assertEquals(calls, 0);
});
