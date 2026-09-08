import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.mjs";

test("fails closed for every canonical Function route", async () => {
  for (const path of [
    "/functions/v1/instance-install",
    "/functions/v1/bank-mail-parser",
    "/functions/v1/notify",
  ]) {
    const response = await worker.fetch(new Request(`https://api.festapp.net${path}`));
    assert.equal(response.status, 503);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(response.headers.get("retry-after"), "300");
    assert.deepEqual(await response.json(), { error: "canonical_functions_not_activated" });
  }
});

test("does not become a general proxy or alternate public route", async () => {
  const wrongHost = await worker.fetch(new Request("https://example.com/functions/v1/notify"));
  const wrongPath = await worker.fetch(new Request("https://api.festapp.net/rest/v1/"));
  assert.equal(wrongHost.status, 404);
  assert.equal(wrongPath.status, 404);
});
