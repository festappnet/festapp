import assert from "node:assert/strict";
import { openEmail } from "./emailPayload.ts";
import {
  prepareWaitlistDelivery,
  sha256Text,
  type WaitlistEmailSource,
} from "./waitlistEmail.ts";

const context = {
  orderId: 101,
  recipient: "waitlist@example.invalid",
  organization: 1,
  occasion: 2,
  unit: 3,
  occasionTitle: "Synthetic occasion",
  participantCount: 4,
  offeredCount: 2,
  formLink: "synthetic-form",
  expiresAt: "2026-10-14T12:00:00Z",
};

Deno.test("waitlist capability crosses SQL only as hash and encrypted source", async () => {
  const previous = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set(
    "EMAIL_PAYLOAD_KEY",
    btoa(String.fromCharCode(...new Uint8Array(32).fill(17))),
  );
  try {
    const delivery = await prepareWaitlistDelivery(context, "waitlist_offer");
    const source = await openEmail<WaitlistEmailSource>(delivery.sealed);
    assert.match(source.token, /^[0-9a-f]{64}$/);
    assert.equal(delivery.tokenHash, await sha256Text(source.token));
    assert.equal(source.recipient, delivery.recipient);
    assert.equal(source.orderId, context.orderId);
    assert.equal(source.templateCode, delivery.templateCode);
    assert.equal(source.offeredCount, 2);
    assert.equal(source.expiresAt, context.expiresAt);
    assert.equal(
      delivery.contentHash,
      await sha256Text(JSON.stringify(source)),
    );
    assert.equal(JSON.stringify(delivery).includes(source.token), false);
    const second = await prepareWaitlistDelivery(context, "waitlist_offer");
    assert.notEqual(second.tokenHash, delivery.tokenHash);
  } finally {
    if (previous === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY");
    else Deno.env.set("EMAIL_PAYLOAD_KEY", previous);
  }
});

Deno.test("registration encrypted source can precede order identity allocation", async () => {
  let source: WaitlistEmailSource | undefined;
  const { orderId: _, ...registration } = context;
  const delivery = await prepareWaitlistDelivery(
    registration,
    "waitlist_confirmation",
    async (value) => {
      source = value as WaitlistEmailSource;
      return { v: "1", iv: "mock", ciphertext: "mock" };
    },
  );
  assert.equal(delivery.orderId, undefined);
  assert.equal(source?.participantCount, 4);
  assert.equal(source?.templateCode, "waitlist_confirmation");
  assert.equal("token" in delivery, false);
});

Deno.test("waitlist delivery requires server recipient and tenant context", async () => {
  await assert.rejects(
    () =>
      prepareWaitlistDelivery({ ...context, recipient: "" }, "waitlist_offer"),
    /waitlist_email_context_invalid/,
  );
  await assert.rejects(
    () =>
      prepareWaitlistDelivery(
        { ...context, organization: 0 },
        "waitlist_offer",
      ),
    /waitlist_email_context_invalid/,
  );
});
