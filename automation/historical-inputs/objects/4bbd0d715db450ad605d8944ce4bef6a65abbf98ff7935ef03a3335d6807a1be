import { strict as assert } from "node:assert";
import {
  openStripePaySource,
  prepareStripePaySource,
  stripeHandoffToken,
  stripePrivateHandoffUrl,
} from "./paySource.ts";
Deno.test("A08 sealed source persists hashes only; replay opens original independent scopes", async () => {
  let plaintext: unknown;
  const source = await prepareStripePaySource(async (value) => {
    plaintext = value;
    return { v: "1", iv: "fixture", ciphertext: "opaque" };
  });
  const secrets = await openStripePaySource(
    source,
    async () => plaintext as never,
  );
  assert.notEqual(secrets.payToken, secrets.returnHandle);
  assert(!JSON.stringify(source).includes(secrets.payToken));
  assert(!JSON.stringify(source).includes(secrets.returnHandle));
  await assert.rejects(() =>
    openStripePaySource(
      { ...source, contentHash: "0".repeat(64) },
      async () => plaintext as never,
    )
  );
  await assert.rejects(() =>
    openStripePaySource(
      source,
      async () => ({ ...secrets, payToken: secrets.returnHandle }) as never,
    )
  );
});

Deno.test("A08/A20 handoff derivation is replay-stable, independent and only an origin-bound fragment", async () => {
  const secrets = { payToken: "a".repeat(64), returnHandle: "b".repeat(64) },
    command = "12345678-1234-4234-8234-123456789abc";
  const token = await stripeHandoffToken(secrets, 1, command);
  assert.equal(await stripeHandoffToken(secrets, 1, command), token);
  assert.notEqual(await stripeHandoffToken(secrets, 2, command), token);
  assert.notEqual(token, secrets.payToken);
  assert.notEqual(token, secrets.returnHandle);
  const url = stripePrivateHandoffUrl(
    { payBaseUrl: "https://tickets.example/stripe/pay" },
    token,
    ["https://tickets.example"],
  );
  assert.equal(new URL(url).hash, "#handoff=" + token);
  assert.equal(new URL(url).search, "");
});
