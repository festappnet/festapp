import { strict as assert } from "node:assert";
import { wixCheckoutContext, type WixContextDependencies } from "./handler.ts";
const app = "9c099206-ce3d-43de-bd9d-deb96bb4f51e";
const instance = "01234567-1234-4234-8234-123456789abc";
const site = "11234567-1234-4234-8234-123456789abc";
const context = "cHJvdmVuYW5jZQ." + "a".repeat(64);
function deps(): WixContextDependencies {
  const now = Math.floor(Date.now() / 1000);
  return {
    configuration: async () => ({ appId: app, organizationId: 3 }),
    fetcher: async () =>
      Response.json({
        active: true,
        clientId: app,
        instanceId: instance,
        siteId: site,
        subjectType: "VISITOR",
        iat: now - 5,
        exp: now + 3600,
      }),
    issue: async () => ({ context, expiresAt: now + 86400 }),
  };
}
const request = (
  body: unknown = { formLink: "ples-2027", instanceId: "untrusted-browser-id" },
) =>
  new Request("https://api.festapp.net/functions/v1/wix-checkout-context", {
    method: "POST",
    headers: { authorization: "qa-token" },
    body: JSON.stringify(body),
  });

Deno.test("context issuance uses verified Wix claims and configured tenant, ignoring browser instance IDs", async () => {
  const d = deps();
  let calls = 0;
  d.issue = async (args) => {
    calls++;
    assert.deepEqual(args, {
      p_form_link: "ples-2027",
      p_instance: instance,
      p_site: site,
      p_organization: 3,
      p_app: app,
    });
    return {
      context,
      expiresAt: Math.floor(Date.now() / 1000) + 86400,
      secret: "must-not-leak",
    };
  };
  const response = await wixCheckoutContext(request(), d);
  assert.equal(response.status, 200);
  assert.equal(calls, 1);
  const value = await response.json();
  assert.equal(value.context, context);
  assert.equal("secret" in value, false);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});

Deno.test("wrong-app tokens cannot issue contexts or call the database", async () => {
  const d = deps();
  d.fetcher = async () => Response.json({ active: true, clientId: site });
  d.issue = () => {
    throw new Error("must not call");
  };
  assert.equal((await wixCheckoutContext(request(), d)).status, 401);
});

Deno.test("malformed and oversized streamed input is rejected before token verification", async () => {
  const d = deps();
  d.fetcher = () => {
    throw new Error("must not call");
  };
  for (
    const body of [
      { formLink: "../admin" },
      { formLink: "https://other.test" },
      null,
    ]
  ) {
    assert.equal((await wixCheckoutContext(request(body), d)).status, 400);
  }
  assert.equal(
    (await wixCheckoutContext(request({ formLink: "a".repeat(2000) }), d))
      .status,
    400,
  );
});

Deno.test("database failures return a bounded non-sensitive failure and OPTIONS has no side effects", async () => {
  const d = deps();
  d.issue = async () => {
    throw new Error("sensitive DB details");
  };
  const response = await wixCheckoutContext(request(), d);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    error: "CHECKOUT_CONTEXT_UNAVAILABLE",
  });
  assert.equal(
    (await wixCheckoutContext(
      new Request("https://api.festapp.net", { method: "OPTIONS" }),
      d,
    )).status,
    200,
  );
});

Deno.test("real Wix SDK language header is permitted by the context preflight", async () => {
  const response = await wixCheckoutContext(new Request("https://api.festapp.net/functions/v1/wix-checkout-context", {
    method: "OPTIONS",
    headers: {origin: "https://info9468674.wixsite.com", "access-control-request-method": "POST",
      "access-control-request-headers": "authorization,content-type,x-wix-linguist"},
  }), {configuration: () => {throw new Error("preflight must not access the backend");},
    issue: () => {throw new Error("preflight must not issue a proof");}});
  assert.equal(response.status, 200);
  const allowed = response.headers.get("Access-Control-Allow-Headers")!.split(",").map(value => value.trim());
  for (const header of ["authorization", "content-type", "x-wix-linguist"]) assert.ok(allowed.includes(header));
});
