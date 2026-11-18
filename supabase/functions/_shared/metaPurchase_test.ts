import { assertEquals } from "jsr:@std/assert@1";
import { sendMetaPurchase } from "../process-meta-purchases/metaPurchase.ts";

const purchase = {
  dataset: "123456",
  accessToken: "test-credential",
  testEventCode: "TEST4242",
  eventId: "c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44",
  eventTime: 1795000000,
  value: 100.25,
  currency: "CZK",
  emailHash: "a".repeat(64),
  sourceUrl: "https://tickets.example/form/concert",
  clientAgent: "Fixture checkout",
};

Deno.test("Meta Purchase sends the immutable settlement and recognizes a receipt", async () => {
  const result = await sendMetaPurchase(purchase, async (url, options) => {
    assertEquals(url, "https://graph.facebook.com/v25.0/123456/events");
    assertEquals(
      new Headers(options?.headers).get("Authorization"),
      "Bearer test-credential",
    );
    assertEquals(JSON.parse(String(options?.body)), {
      data: [{
        event_name: "Purchase",
        event_id: purchase.eventId,
        event_time: purchase.eventTime,
        action_source: "website",
        event_source_url: purchase.sourceUrl,
        user_data: {
          em: [purchase.emailHash],
          client_user_agent: purchase.clientAgent,
        },
        custom_data: { value: 100.25, currency: "CZK" },
      }],
      test_event_code: "TEST4242",
    });
    return Response.json({ events_received: 1 });
  });
  assertEquals(result, "sent");
});

Deno.test("Meta response determines retry, credential pause or permanent failure", async () => {
  for (
    const [status, body, expected] of [
      [200, { events_received: 0 }, "retry"],
      [400, { error: { code: 190 } }, "credentials"],
      [400, { error: { code: 10 } }, "credentials"],
      [429, {}, "retry"],
      [500, {}, "retry"],
      [400, { error: { is_transient: true } }, "retry"],
      [400, {}, "rejected"],
    ] as const
  ) {
    assertEquals(
      await sendMetaPurchase(
        purchase,
        async () => Response.json(body, { status }),
      ),
      expected,
    );
  }
  assertEquals(
    await sendMetaPurchase(purchase, async () => {
      throw new Error("timeout");
    }),
    "retry",
  );
});
