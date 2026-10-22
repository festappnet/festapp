import { strict as assert } from "node:assert";
import {
  type ConnectDependencies,
  stripeConnectHandler,
} from "../_shared/stripe/connect.ts";
const config = {
  livemode: false,
  clientId: "ca_fixture",
  callbackUrl: "https://tickets.example/stripe/connect/callback",
  allowedOrigins: ["https://tickets.example"],
};
const actor = "00000000-0000-4000-8000-000000000001";
function fixture() {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  let providerCalls = 0;
  const deps: ConnectDependencies = {
    config,
    authenticate: async (token) =>
      token === "Bearer valid" ? { id: actor } : null,
    userRpc: async (_auth, name, args) => {
      calls.push({ name, args });
      return name === "begin_stripe_connection_flow"
        ? { flowId: "flow", state: "a".repeat(64), expiresAt: "2026-10-21" }
        : { chargesEnabled: true, payoutsEnabled: false };
    },
    serviceRpc: async () => {
      throw new Error("not used");
    },
    oauth: {
      deauthorize: async () => {
        throw new Error("not used");
      },
      exchange: async () => {
        throw new Error("not used");
      },
    },
    provider: {
      account: async () => {
        throw new Error("not used");
      },
    },
    verifyPlatform: async () => {
      providerCalls++;
    },
  };
  return { deps, calls, providerCalls: () => providerCalls };
}
const request = (body: unknown, patch: RequestInit = {}) =>
  new Request("https://api.example/functions/v1/stripe-connect", {
    method: "POST",
    headers: {
      authorization: "Bearer valid",
      origin: "https://tickets.example",
    },
    body: JSON.stringify(body),
    ...patch,
  });
Deno.test("A25 disconnect is receipted once; timeout retry never repeats revocation", async () => {
  const f = fixture();
  let posts = 0, state = "pending";
  const connection = "00000000-0000-4000-8000-000000000002";
  f.deps.userRpc = async (_auth, name, args) => {
    assert.equal(name, "begin_stripe_disconnect");
    assert.equal(args.p_expected_connection, connection);
    return { intentId: "intent" };
  };
  f.deps.serviceRpc = async (name, args) => {
    if (name === "claim_stripe_disconnect_internal") {
      assert.equal(args.p_actor, actor);
      assert.equal(args.p_livemode, false);
      if (state !== "pending") return { disposition: "uncertain" };
      state = "claimed";
      return { disposition: "dispatch", accountId: "acct_verified" };
    }
    assert.equal(name, "finish_stripe_disconnect_internal");
    assert.equal(args.p_success, false);
    state = "uncertain";
    return { uncertain: true };
  };
  f.deps.oauth.deauthorize = async (account, client) => {
    posts++;
    assert.equal(account, "acct_verified");
    assert.equal(client, "ca_fixture");
    throw new Error("private timeout");
  };
  const body = {
    unitId: 7,
    action: "disconnect",
    connectionId: connection,
    accountId: "acct_attacker",
  };
  assert.equal((await stripeConnectHandler(request(body), f.deps)).status, 202);
  assert.equal((await stripeConnectHandler(request(body), f.deps)).status, 202);
  assert.equal(posts, 1);
});
Deno.test("A25 disconnect cannot reach Stripe without manager-authorized SQL intent", async () => {
  const f = fixture();
  f.deps.userRpc = async () => {
    throw new Error("forbidden");
  };
  assert.equal(
    (await stripeConnectHandler(
      request({
        unitId: 7,
        action: "disconnect",
        connectionId: "00000000-0000-4000-8000-000000000002",
      }),
      f.deps,
    )).status,
    403,
  );
  assert.equal(f.providerCalls(), 0);
});
Deno.test("A03 form editor options use separate scoped read rights and the server environment", async () => {
  const f = fixture();
  const response = await stripeConnectHandler(
    request({
      action: "form-options",
      unitId: 7,
      occasionId: 11,
      livemode: true,
    }),
    f.deps,
  );
  assert.equal(response.status, 200);
  assert.deepEqual(f.calls, [{
    name: "get_form_stripe_recipient",
    args: { p_unit: 7, p_livemode: false, p_occasion: 11 },
  }]);
  assert.equal(f.providerCalls(), 0);
});
Deno.test("A03 start uses authenticated SQL rights and server mode, never client account ID", async () => {
  const f = fixture();
  const r = await stripeConnectHandler(
    request({
      unitId: 12,
      action: "start",
      accountId: "acct_attacker",
      livemode: true,
      redirect: "https://evil.example",
    }),
    f.deps,
  );
  assert.equal(r.status, 200);
  const data = await r.json();
  const url = new URL(data.url);
  assert.equal(url.origin, "https://connect.stripe.com");
  assert.equal(url.searchParams.get("redirect_uri"), config.callbackUrl);
  assert.equal(url.searchParams.get("scope"), "read_write");
  assert.equal(url.searchParams.get("stripe_landing"), "login");
  assert.deepEqual(f.calls[0].args, { p_unit: 12, p_livemode: false });
  assert.equal(f.providerCalls(), 1);
  assert.equal(r.headers.get("referrer-policy"), "no-referrer");
  assert.equal(
    r.headers.get("access-control-allow-origin"),
    "https://tickets.example",
  );
});
Deno.test("A03 denied unit rights and unauthenticated requests never reach provider", async () => {
  const f = fixture();
  f.deps.userRpc = async () => {
    throw new Error("foreign organizer details");
  };
  const denied = await stripeConnectHandler(
    request({ unitId: 12, action: "start" }),
    f.deps,
  );
  assert.equal(denied.status, 403);
  assert(!(await denied.text()).includes("foreign"));
  const anon = await stripeConnectHandler(
    request({ unitId: 12, action: "start" }, {
      headers: {
        authorization: "Bearer invalid",
        origin: "https://tickets.example",
      },
    }),
    f.deps,
  );
  assert.equal(anon.status, 401);
  assert.equal(f.providerCalls(), 0);
});
Deno.test("A04/A25 status is SQL read-only, separates charges/payouts and never polls Stripe", async () => {
  const f = fixture();
  const r = await stripeConnectHandler(
    request({ unitId: 12, action: "status" }),
    f.deps,
  );
  const data = await r.json();
  assert.equal(data.chargesEnabled, true);
  assert.equal(data.payoutsEnabled, false);
  assert.equal(f.providerCalls(), 0);
  assert.equal(f.calls[0].name, "get_stripe_unit_connection");
});
Deno.test("A25 pause/resume preserve connection and use the authenticated owner", async () => {
  const f = fixture();
  await stripeConnectHandler(request({ unitId: 12, action: "pause" }), f.deps);
  assert.deepEqual(f.calls[0], {
    name: "set_stripe_unit_paused",
    args: { p_unit: 12, p_livemode: false, p_paused: true },
  });
  assert.equal(f.providerCalls(), 0);
});
Deno.test("A02 callback origin allowlist and bounded JSON apply before any writes", async () => {
  const f = fixture();
  const origin = await stripeConnectHandler(
    request({ unitId: 12, action: "start" }, {
      headers: {
        authorization: "Bearer valid",
        origin: "https://evil.example",
      },
    }),
    f.deps,
  );
  assert.equal(origin.status, 403);
  assert.equal(origin.headers.get("access-control-allow-origin"), null);
  const body = await stripeConnectHandler(
    request({ unitId: 12, action: "start", extra: "x".repeat(9000) }),
    f.deps,
  );
  assert.equal(body.status, 400);
  assert.equal(f.calls.length, 0);
  assert.equal(f.providerCalls(), 0);
});
