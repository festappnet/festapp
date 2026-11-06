import {strict as assert} from "node:assert";
import {decodePaymentClaim, decodeCommitReceipt} from "./contracts.ts";
import {stripeClaim} from "./connectors/stripe.ts";
Deno.test("malformed RPC dispatch and false commit receipts cannot cross the adapter", () => {
  for (const value of [null, {}, {disposition: "dispatch", snapshot: {}}, {disposition: "busy"}])
    assert.throws(() => stripeClaim(value), /dispatch_invalid/);
  for (const value of [{}, {committed: true}, {committed: true, payment: {method: "foreign", status: "paid"}}])
    assert.throws(() => decodeCommitReceipt(value, "stripe"), /commit_receipt_invalid/);
  assert.throws(() => decodePaymentClaim({providerId: "foreign", disposition: "read", payment: {}}, "stripe"), /dispatch_invalid/);
});
