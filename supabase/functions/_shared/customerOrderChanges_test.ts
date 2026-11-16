import assert from "node:assert/strict";
import {
  openCustomerChangeSource,
  prepareCustomerChangeDelivery,
  readCustomerChangeInput,
} from "./customerOrderChanges.ts";
import { createCustomerOrderChangesHandler } from "./customerOrderChangesHandler.ts";
import { openEmail } from "./emailPayload.ts";
import { sha256Text } from "./waitlistEmail.ts";
const context = {
  orderId: 42,
  webLink: "https://tickets.example.test",
  recipient: "buyer@example.test",
  locale: "cs",
};
const readToken = "a".repeat(64);
const request = (body: unknown) =>
  new Request("https://api.example.test/functions/v1/customer-order-changes", {
    method: "POST",
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
  });
async function withKey(run: () => Promise<void>) {
  const old = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set("EMAIL_PAYLOAD_KEY", btoa("x".repeat(32)));
  try {
    await run();
  } finally {
    if (old === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY");
    else Deno.env.set("EMAIL_PAYLOAD_KEY", old);
  }
}
Deno.test("challenge uses the existing overview URL, one fragment credential and sealed sources", () =>
  withKey(async () => {
    const delivery = await prepareCustomerChangeDelivery(
      context,
      readToken,
      "cancel",
      { reason: "Cannot attend" },
    );
    const source = await openEmail<any>(delivery.source);
    const email = await openEmail<any>(delivery.email);
    assert.equal(email.to, context.recipient);
    assert.equal((email.html.match(/<a /g) || []).length, 1);
    const url = new URL(
      email.html.match(/href="([^"]+)"/)[1].replaceAll("&amp;", "&"),
    );
    assert.equal(url.pathname, "/order");
    assert.equal(url.searchParams.get("token"), readToken);
    assert.equal(url.searchParams.get("order_id"), "42");
    assert.equal(
      new URLSearchParams(url.hash.slice(1)).get("change"),
      source.token,
    );
    assert.equal(await sha256Text(source.token), delivery.tokenHash);
    assert.equal(JSON.stringify(delivery).includes(source.token), false);
    assert.deepEqual(
      await openCustomerChangeSource(delivery.source, source.token, 42),
      {
        orderId: 42,
        operation: "cancel",
        payload: { reason: "Cannot attend" },
      },
    );
    await assert.rejects(() =>
      openCustomerChangeSource(delivery.source, "b".repeat(64), 42)
    );
    await assert.rejects(() =>
      openCustomerChangeSource(delivery.source, source.token, 43)
    );
    await assert.rejects(() =>
      prepareCustomerChangeDelivery(
        { ...context, webLink: "https://evil@example.test" },
        readToken,
        "cancel",
        {},
      )
    );
  }));
Deno.test("bounded request parser rejects extra recipient/scope fields and streamed oversized input", async () => {
  for (
    const body of [
      {
        action: "challenge",
        token: readToken,
        recipient: "attacker@example.test",
      },
      { action: "command", token: readToken, operation: "refund" },
      { action: "command", token: "bad" },
      { action: "preview", token: readToken, payload: [] },
    ]
  ) await assert.rejects(() => readCustomerChangeInput(request(body)));
  await assert.rejects(() =>
    readCustomerChangeInput(
      request({
        action: "preview",
        token: readToken,
        payload: { x: "x".repeat(50000) },
      }),
    )
  );
});
Deno.test("GET/scanners never reach SQL; challenge failures are indistinguishable and token-free", () =>
  withKey(async () => {
    let calls = 0;
    const handler = createCustomerOrderChangesHandler(async () => {
      calls++;
      throw Object.assign(new Error("secret database details"), {
        code: "42501",
      });
    });
    assert.equal(
      (await handler(new Request("https://example.test/?token=" + readToken)))
        .status,
      405,
    );
    assert.equal(calls, 0);
    const result = await handler(
      request({
        action: "challenge",
        token: readToken,
        orderId: 42,
        operation: "cancel",
        payload: {},
      }),
    );
    assert.equal(result.status, 202);
    assert.deepEqual(await result.json(), { code: 202 });
  }));
Deno.test("HTTP conflicts preserve explicit recovery and never claim success from transport errors", async () => {
  for (const code of ["40001", "40P01", "55P03"]) {
    const handler = createCustomerOrderChangesHandler(async () => {
      throw { code, message: readToken };
    });
    const result = await handler(
      request({
        action: "command",
        token: readToken,
        operation: "cancel",
        payload: {},
        commandId: crypto.randomUUID(),
        fingerprint: "c".repeat(64),
      }),
    );
    assert.equal(result.status, 409);
    const body = await result.text();
    assert.ok(!body.includes(readToken));
    assert.match(body, /CUSTOMER_CHANGE_CONFLICT/);
  }
});

Deno.test("retired term-moving requests are rejected at the public transport boundary", async () => {
  for (const action of ["challenge", "preview", "command"]) {
    await assert.rejects(() => readCustomerChangeInput(request({
      action, token: readToken, orderId: 42, operation: "move", payload: { targetFormId: 2 },
      commandId: "12345678-1234-4234-8234-123456789012",
    })));
  }
});
