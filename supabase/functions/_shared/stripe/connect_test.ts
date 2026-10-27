import { strict as assert } from "node:assert";
import { stripeAuthorizeUrl, StripeOAuthProvider } from "./connect.ts";
import { StripeBoundaryError } from "./provider.ts";
Deno.test("OAuth revocation binds the verified account and client and requires a matching provider receipt", async () => {
  let calls = 0;
  const p = new StripeOAuthProvider(
    "sk_test_fixtureOnly",
    false,
    async (url, init) => {
      calls++;
      assert.equal(String(url), "https://connect.stripe.com/oauth/deauthorize");
      const body = new URLSearchParams(String(init?.body));
      assert.equal(body.get("stripe_user_id"), "acct_fixture");
      assert.equal(body.get("client_id"), "ca_fixture");
      assert.equal(new Headers(init?.headers).get("Idempotency-Key"), null);
      return Response.json({ stripe_user_id: "acct_fixture" });
    },
  );
  await p.deauthorize("acct_fixture", "ca_fixture");
  assert.equal(calls, 1);
  await assert.rejects(
    () => p.deauthorize("wrong", "ca_fixture"),
    StripeBoundaryError,
  );
  assert.equal(calls, 1);
  const uncertain = new StripeOAuthProvider(
    "sk_test_fixtureOnly",
    false,
    async () => Response.json({ stripe_user_id: "acct_wrong" }),
  );
  await assert.rejects(
    () => uncertain.deauthorize("acct_fixture", "ca_fixture"),
    (error: unknown) =>
      error instanceof StripeBoundaryError &&
      error.code === "stripe_disconnect_uncertain",
  );
});
Deno.test("OAuth transport verifies test mode and write scope and never returns provider tokens", async () => {
  const provider = new StripeOAuthProvider(
    "sk_test_fixtureOnly",
    false,
    async (url, init) => {
      assert.equal(String(url), "https://connect.stripe.com/oauth/token");
      assert.equal(
        new URLSearchParams(String(init?.body)).get("grant_type"),
        "authorization_code",
      );
      return Response.json({
        stripe_user_id: "acct_fixture",
        scope: "read_write",
        livemode: false,
        access_token: "do-not-return",
        refresh_token: "do-not-store",
      });
    },
  );
  assert.equal(await provider.exchange("ac_fixture"), "acct_fixture");
  for (
    const patch of [{ livemode: true }, { scope: "read_only" }, {
      stripe_user_id: "unverified",
    }]
  ) {
    const bad = new StripeOAuthProvider(
      "sk_test_fixtureOnly",
      false,
      async () =>
        Response.json({
          stripe_user_id: "acct_fixture",
          scope: "read_write",
          livemode: false,
          ...patch,
        }),
    );
    await assert.rejects(() => bad.exchange("ac_fixture"), StripeBoundaryError);
  }
});
Deno.test("OAuth configuration cannot redirect to another origin or encode a long-lived capability", () => {
  const config = {
    livemode: false,
    clientId: "ca_fixture",
    callbackUrl: "https://tickets.example/callback",
    allowedOrigins: ["https://tickets.example"],
  };
  for (
    const callbackUrl of [
      "https://evil.example/callback",
      "https://tickets.example/callback#secret",
      "https://tickets.example/callback?token=secret",
      "http://tickets.example/callback",
    ]
  ) {
    assert.throws(
      () => stripeAuthorizeUrl({ ...config, callbackUrl }, "a".repeat(64)),
      StripeBoundaryError,
    );
  }
});

Deno.test('receipted card commands use the ordinary immutable owner and keep provider uncertainty separate',async()=>{
 const {stripeConnectHandler}=await import('./connect.ts');
 const command='00000000-0000-4000-8000-000000000021';const calls:string[]=[];
 const accepted={code:200,status:'applied',mutation:{commandId:command},data:{intentId:'intent-fixture'}};
 const deps={config:{livemode:false,clientId:'ca_fixture',callbackUrl:'https://tickets.example/callback',allowedOrigins:['https://tickets.example']},authenticate:async()=>({id:'actor-fixture'}),
  userRpc:async(_auth:string,name:string,args:Record<string,unknown>)=>{calls.push(name);assert.equal(args.p_command_id,command);assert.equal(args.p_livemode,false);return accepted;},
  serviceRpc:async(name:string)=>{calls.push(name);return{disposition:'uncertain'};},verifyPlatform:async()=>{},
  oauth:{exchange:async()=>{throw Error('unexpected exchange');},deauthorize:async()=>{throw Error('unexpected provider dispatch');}},provider:{account:async()=>{throw Error('unexpected account read');}}};
 const request=(action:string)=>new Request('https://api.festapp.net/functions/v1/stripe-connect',{method:'POST',headers:{Authorization:'Bearer fixture-user'},body:JSON.stringify({unitId:8,action,commandId:command,...(action==='disconnect'?{connectionId:command}:{})})});
 const paused=await stripeConnectHandler(request('pause'),deps);assert.equal(paused.status,200);assert.deepEqual(await paused.json(),accepted);assert.deepEqual(calls,['set_stripe_unit_paused_client_sync_v1']);
 calls.length=0;const disconnected=await stripeConnectHandler(request('disconnect'),deps);assert.equal(disconnected.status,202);const pending=await disconnected.json();assert.equal(pending.mutation.commandId,command);assert.equal(pending.data.result.uncertain,true);assert.deepEqual(calls,['begin_stripe_disconnect_client_sync_v1','claim_stripe_disconnect_internal']);
});
