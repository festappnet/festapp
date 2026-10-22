import { strict as assert } from "node:assert";
import {
  type ConnectDependencies,
  stripeConnectHandler,
} from "../_shared/stripe/connect.ts";
const actor = "00000000-0000-4000-8000-000000000001";
const config = {
  livemode: false,
  clientId: "ca_fixture",
  callbackUrl: "https://tickets.example/stripe/connect/callback",
  allowedOrigins: ["https://tickets.example"],
};
const result = {
  connected: true,
  unitId: 12,
  connectionId: "00000000-0000-4000-8000-000000000002",
};
function fixture() {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  let exchanges = 0;
  let provider = 0;
  const deps: ConnectDependencies = {
    config,
    authenticate: async () => ({ id: actor }),
    userRpc: async () => {
      throw new Error("not used");
    },
    serviceRpc: async (name, args) => {
      calls.push({ name, args });
      return name === "claim_stripe_connection_flow_internal"
        ? { disposition: "claimed", flowId: "flow", lease: "lease", unitId: 12 }
        : result;
    },
    oauth: {
      deauthorize: async () => {
        throw new Error("not used");
      },
      exchange: async () => {
        exchanges++;
        return "acct_verified";
      },
    },
    provider: {
      account: async (id) => {
        provider++;
        return {
          accountId: id,
          businessName: "Fixture",
          country: "CZ",
          modelVerified: true,
          chargesEnabled: true,
          payoutsEnabled: false,
          cardPaymentsActive: true,
          ready: true,
        };
      },
    },
    verifyPlatform: async () => {},
  };
  return { deps, calls, exchanges: () => exchanges, provider: () => provider };
}
const request = (patch: Record<string, unknown> = {}) =>
  new Request("https://api.example/stripe-connect-callback", {
    method: "POST",
    headers: {
      authorization: "Bearer valid",
      origin: "https://tickets.example",
    },
    body: JSON.stringify({
      state: "a".repeat(64),
      code: "ac_fixture",
      ...patch,
    }),
  });
Deno.test("A02/A07 callback binds current actor and uses provider identity, not client unit/account", async () => {
  const f = fixture();
  const r = await stripeConnectHandler(
    request({ accountId: "acct_attacker", unitId: 99 }),
    f.deps,
    true,
  );
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), result);
  assert.equal(f.calls[0].args.p_actor, actor);
  assert.equal(f.calls[0].args.p_livemode, false);
  const saved = f.calls.find((x) =>
    x.name === "complete_stripe_connection_flow_internal"
  )!;
  assert.equal(
    (saved.args.p_account as Record<string, unknown>).accountId,
    "acct_verified",
  );
  assert.equal(f.exchanges(), 1);
  assert.equal(f.provider(), 1);
});
Deno.test("A02 consumed callback replays SQL receipt without re-exchanging a one-use code", async () => {
  const f = fixture();
  f.deps.serviceRpc = async () => ({ disposition: "replay", result });
  const r = await stripeConnectHandler(request(), f.deps, true);
  assert.equal(r.status, 200);
  assert.equal(f.exchanges(), 0);
  assert.equal(f.provider(), 0);
});
Deno.test("A02 wrong actor/state, expiration and concurrent claim reject before provider", async () => {
  for (const mode of ["denied", "uncertain"]) {
    const f = fixture();
    f.deps.serviceRpc = async () => {
      if (mode === "denied") throw new Error("foreign details");
      return { disposition: "uncertain" };
    };
    const r = await stripeConnectHandler(request(), f.deps, true);
    assert(r.status >= 400);
    assert.equal(f.exchanges(), 0);
    assert.equal(f.provider(), 0);
    assert(!(await r.text()).includes("foreign"));
  }
});
Deno.test("A02 user cancels normally without exchanging code or changing an account", async () => {
  const f = fixture();
  const r = await stripeConnectHandler(
    request({ code: undefined, error: "access_denied" }),
    f.deps,
    true,
  );
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { status: "cancelled", unitId: 12 });
  assert.equal(f.exchanges(), 0);
  assert.equal(f.calls.at(-1)?.args.p_denied, true);
});
Deno.test("A07 provider timeout or SQL receipt failure stays uncertain and preserves the previous recipient", async () => {
  for (const failure of ["timeout", "model", "sql"]) {
    const f = fixture();
    if (failure === "timeout") {
      f.deps.oauth.exchange = async () => {
        throw new Error("secret provider body");
      };
    }
    if (failure === "model") {
      f.deps.provider.account = async () => ({
        accountId: "acct_foreign",
        businessName: null,
        country: "CZ",
        modelVerified: false,
        chargesEnabled: true,
        payoutsEnabled: true,
        cardPaymentsActive: true,
        ready: false,
      });
    }
    if (failure === "sql") {
      const original = f.deps.serviceRpc;
      f.deps.serviceRpc = async (name, args) =>
        name === "complete_stripe_connection_flow_internal"
          ? { connected: false }
          : original(name, args);
    }
    const r = await stripeConnectHandler(request(), f.deps, true);
    assert.equal(r.status, 503);
    assert(!(await r.text()).includes("secret"));
    assert.equal(
      f.calls.at(-1)?.name,
      "finish_stripe_connection_flow_error_internal",
    );
    assert.equal(f.calls.at(-1)?.args.p_denied, false);
  }
});
