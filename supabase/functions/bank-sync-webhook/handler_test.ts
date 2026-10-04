import { buildWebhookEnvelope, signWebhook, type WebhookEnvelope, type Transaction } from "npm:@festapp/banksync@0.2.2";
import { bankSyncWebhook } from "./handler.ts";
const secret = "synthetic-test-secret";
const transaction: Transaction = {
  id: 1, bank_account_id: 42, amount_cents: 1007, currency: "EUR",
  counter_account: null, bank_code: null, bank_name: null, vs: null, ks: null, ss: null,
  message: null, sender_name: null, user_identification: null, transaction_type: null,
  performed_by: null, comment: null, command_id: "777", source: "fio_api",
  date: "2026-10-04T12:00:00Z", date_offset_min: null, transaction_id: "990001", external_id: null,
  raw_vs: null, payer_reference: "RF471234567890", direction: "incoming", identity_kind: "movement", identity_provenance: "fio_api_column22",
};
const event = buildWebhookEnvelope({ delivery_id: "01K00000000000000000000001", pairing_code: "0123456789", transaction, event_version: "2" });
function assert(value: unknown, message = "assertion failed"): asserts value { if (!value) throw new Error(message); }
async function request(envelope = event, timestamp?: number): Promise<Request> {
  const signed = await signWebhook({ secret, envelope, ...(timestamp === undefined ? {} : { timestamp }) });
  return new Request("https://api.festapp.net/functions/v1/bank-sync-webhook", { method: "POST", headers: signed.headers, body: new Uint8Array(signed.bodyBytes) });
}
const receipt = { ok: true, receipt_version: 1, delivery_id: event.delivery_id, outcome: "paired" };
Deno.test("durable receipt, raw hash and lost HTTP response retry", async () => {
  let digest: string | undefined;
  let commits = 0;
  const deps = { secret, instanceId: "test", ingest: (hash: string, envelope: unknown) => {
    assert((envelope as WebhookEnvelope).event_version === "2");
    if (digest === undefined) { digest = hash; commits++; } else assert(digest === hash);
    return Promise.resolve(receipt);
  } };
  const first = await bankSyncWebhook(await request(), deps);
  const retry = await bankSyncWebhook(await request(), deps);
  assert(first.status === 200 && retry.status === 200 && commits === 1);
  assert(JSON.stringify(await first.json()) === JSON.stringify(await retry.json()));
});
Deno.test("bad HMAC, stale timestamp and v1 never reach SQL", async () => {
  let calls = 0;
  const deps = { secret, instanceId: "test", ingest: () => { calls++; return Promise.resolve(receipt); } };
  const bad = await request(); bad.headers.set("x-banksync-signature", `sha256=${"0".repeat(64)}`);
  assert((await bankSyncWebhook(bad, deps)).status === 401);
  assert((await bankSyncWebhook(await request(event, Math.floor(Date.now()/1000)-301), deps)).status === 401);
  assert((await bankSyncWebhook(await request({ ...event, event_version: "1" }), deps)).status === 400);
  assert(calls === 0);
});
Deno.test("bounded body and valid signed contract", async () => {
  const deps = { secret, instanceId: "test", ingest: () => Promise.resolve(receipt) };
  assert((await bankSyncWebhook(new Request("https://example.com", { method: "POST", body: "x".repeat(65537) }), deps)).status === 413);
  for (const data of [{ ...transaction, date: "broken" }, { ...transaction, direction: "outgoing" }, { ...transaction, currency: "BTC" }]) {
    assert((await bankSyncWebhook(await request({ ...event, data } as WebhookEnvelope), deps)).status === 400);
  }
});
Deno.test("database failure and invalid receipt return retryable 503", async () => {
  assert((await bankSyncWebhook(await request(), { secret, instanceId: "test", ingest: () => Promise.reject(new Error("database_timeout")) })).status === 503);
  assert((await bankSyncWebhook(await request(), { secret, instanceId: "test", ingest: () => Promise.resolve({ success: true }) })).status === 503);
  assert((await bankSyncWebhook(await request(), { secret, instanceId: "test", ingest: () => Promise.reject(new Error("BANK_SYNC_DELIVERY_CONFLICT")) })).status === 409);
});
