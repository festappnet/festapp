import { strict as assert } from "node:assert";
import { verifyWixIdentity, WixIdentityError } from "./identity.ts";
const app = "9c099206-ce3d-43de-bd9d-deb96bb4f51e";
const now = 1793190000;
const valid = {
  active: true,
  clientId: app,
  instanceId: "01234567-1234-4234-8234-123456789abc",
  siteId: "11234567-1234-4234-8234-123456789abc",
  subjectType: "VISITOR",
  iat: now - 10,
  exp: now + 3600,
};
const reply = (value: unknown): typeof fetch => async () =>
  Response.json(value);

Deno.test("Wix identity is verified by the fixed authoritative token-info endpoint", async () => {
  let calls = 0;
  const fetcher: typeof fetch = async (url, init) => {
    calls++;
    assert.equal(url, "https://www.wixapis.com/oauth2/token-info");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(String(init?.body)), { token: "qa-token" });
    return Response.json({
      ...valid,
      active: "true",
      iat: String(valid.iat),
      exp: String(valid.exp),
    });
  };
  assert.deepEqual(
    await verifyWixIdentity("Bearer qa-token", app, fetcher, now),
    {
      instanceId: valid.instanceId,
      siteId: valid.siteId,
      expiresAt: valid.exp,
    },
  );
  assert.equal(calls, 1);
});

Deno.test("inactive, wrong-app, expired, future-issued and missing instance/site claims fail closed", async () => {
  for (
    const changed of [
      { active: false },
      { active: "false" },
      { clientId: valid.siteId },
      { exp: now },
      { iat: now + 61 },
      { instanceId: null },
      { siteId: "not-a-site" },
      { subjectType: "UNKNOWN" },
      { exp: "not-a-time" },
      { iat: valid.exp },
    ]
  ) {
    await assert.rejects(
      () =>
        verifyWixIdentity(
          "qa-token",
          app,
          reply({ ...valid, ...changed }),
          now,
        ),
      WixIdentityError,
    );
  }
  await assert.rejects(
    () => verifyWixIdentity(null, app, reply(valid), now),
    /WIX_AUTHENTICATION_REQUIRED/,
  );
});

Deno.test("provider errors and malformed successful replies never become a local identity", async () => {
  const unavailable: typeof fetch = async () => {
    throw new Error("must not expose provider details");
  };
  await assert.rejects(
    () => verifyWixIdentity("qa-token", app, unavailable, now),
    /WIX_VERIFICATION_UNAVAILABLE/,
  );
  await assert.rejects(
    () =>
      verifyWixIdentity(
        "qa-token",
        app,
        async () => new Response("bad", { status: 503 }),
        now,
      ),
    /WIX_VERIFICATION_UNAVAILABLE/,
  );
  await assert.rejects(
    () =>
      verifyWixIdentity(
        "qa-token",
        app,
        async () => new Response("not-json"),
        now,
      ),
    /WIX_VERIFICATION_UNAVAILABLE/,
  );
});
