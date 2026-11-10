import { strict as assert } from "node:assert";
import { PaymentRegistry } from "./registry.ts";
import { reconcilePaymentRefunds } from "./refunds.ts";
import { builtinPaymentBinding } from "./connectors/builtin.ts";
import { requireHostedPayment, type RefundSnapshot, type RefundCapability } from "./contracts.ts";
import { StripeProvider } from "../stripe/provider.ts";
import { stripeRefundCapability } from "./connectors/stripeRefund.ts";

const requestId = 'a1234567-1234-4234-8234-123456789012';
const snapshot: RefundSnapshot & {attemptId: string} = {requestId, providerId: 'stripe',
  attemptId: 'attempt_original', accountId: 'acct_original', livemode: false, paymentId: 'pi_original',
  amountMinor: 30000, currency: 'CZK', createdAt: 1000, idempotencyKey: 'festapp:refund:' + requestId};
function provider(fetcher: typeof fetch, now = 1100) {
  return new StripeProvider({secretKey: 'sk_test_fixture', livemode: false, apiVersion: '2026-10-28.endive',
    allowedReturnOrigins: [], now: () => now, fetch: fetcher});
}
function payment() { return {object: 'payment_intent', id: 'pi_original', livemode: false,
  amount_received: 100000, currency: 'czk', status: 'succeeded', metadata: {festapp_attempt: snapshot.attemptId}}; }
function refund(status = 'succeeded') { return {object: 'refund', id: 're_original', payment_intent: 'pi_original',
  amount: 30000, currency: 'czk', status, metadata: {festapp_refund: requestId}}; }
Deno.test('builtin methods share registry without fake hosted checkout dependencies', async () => {
  let calls = 0;
  const registry = new PaymentRegistry(['bank', 'cash'].map(id => [id, () => builtinPaymentBinding(id as 'bank'|'cash', async (name, args, authorization) => {
    assert.equal(name, 'command_payment_operation'); assert.equal(authorization, 'Bearer fixture');
    assert.equal(args.p_command_id, requestId); calls++; return {request: {status: 'pending'}};
  })] as const));
  const bank = registry.resolve('bank');
  assert.equal(bank.hostedCheckout, undefined);
  assert.equal(bank.operation?.confirmation, 'bank_event');
  assert.throws(() => requireHostedPayment(bank), /hosted_checkout_unavailable/);
  const result = await bank.operation!.execute({method: 'bank', operation: 'prepare_refund'}, requestId, 'Bearer fixture');
  assert.equal(result.kind, 'show_bank_instructions'); assert.equal(calls, 1);
});
Deno.test('Stripe refund transport preserves account, original payment, exact amount and idempotency identity', async () => {
  let writes = 0;
  const p = provider(async (url, init) => {
    assert.equal(new Headers(init?.headers).get('Stripe-Account'), snapshot.accountId);
    if (String(url).endsWith('/payment_intents/pi_original')) return Response.json(payment());
    assert.equal(String(url), 'https://api.stripe.com/v1/refunds');
    assert.equal(init?.method, 'POST'); writes++;
    assert.equal(new Headers(init?.headers).get('Idempotency-Key'), snapshot.idempotencyKey);
    const body = init?.body as URLSearchParams;
    assert.equal(body.get('payment_intent'), snapshot.paymentId); assert.equal(body.get('amount'), '30000');
    assert.equal(body.get('metadata[festapp_refund]'), requestId);
    return Response.json(refund('pending'));
  });
  assert.equal((await p.requestRefund(snapshot)).status, 'pending'); assert.equal(writes, 1);
  await assert.rejects(() => p.requestRefund({...snapshot, livemode: true}), /binding_invalid/);
});
Deno.test('Stripe refund normalization includes action, failure, cancellation and successful observations', async () => {
  for (const [raw, expected] of [['requires_action','action_required'],['failed','failed'],['canceled','cancelled'],['succeeded','succeeded']]) {
    const p = provider(async url => Response.json(String(url).includes('/payment_intents/') ? payment() : refund(raw)));
    assert.equal((await p.recoverRefund(snapshot, {refundId: 're_original'})).status, expected);
  }
});
Deno.test('refund recovery beyond retention is read-only and an empty list remains unknown', async () => {
  let writes = 0;
  const p = provider(async (url, init) => {
    if (init?.method === 'POST') writes++;
    return Response.json(String(url).includes('/payment_intents/') ? payment() : {data: [], has_more: false});
  }, 1000 + 48 * 3600);
  await assert.rejects(() => p.requestRefund(snapshot), /requires_reconciliation/);
  assert.equal((await p.recoverRefund(snapshot, {})).status, 'unknown'); assert.equal(writes, 0);
});
Deno.test('a timeout after Stripe dispatch recovers through the shared worker without a second write', async () => {
  let writes = 0, dispatched = false;
  const p = provider(async (url, init) => {
    if (String(url).includes('/payment_intents/')) return Response.json(payment());
    if (init?.method === 'POST') {writes++; throw new Error('response lost');}
    return Response.json({data: [refund()], has_more: false});
  });
  const registry = new PaymentRegistry([['stripe', () => ({connector: {id: 'stripe', displayName: 'Stripe'},
    refund: stripeRefundCapability({provider: p, verifyPlatform: async () => {}})})]]);
  const rpc = async (name: string, args: Record<string, unknown>) => {
    if (name === 'get_recoverable_payment_refunds') return [{requestId, providerId: 'stripe'}];
    if (name === 'claim_payment_refund') {const prior = dispatched; dispatched = true;
      return {requestId, providerId: 'stripe', lease: 'lease', priorDispatched: prior, connectorState: {}, snapshot};}
    assert.equal(name, 'complete_payment_refund'); return args.p_result;
  };
  assert.equal((await reconcilePaymentRefunds(registry, rpc))[0].state, 'uncertain');
  assert.equal((await reconcilePaymentRefunds(registry, rpc))[0].state, 'completed'); assert.equal(writes, 1);
});
Deno.test('two distinct external protocols use the same refund executor and reservation receipt', async () => {
  for (const id of ['protocol_a', 'protocol_b']) {
    let invoked = 0;
    const capability: RefundCapability = {confirmation: 'verified_provider_observation', currencies: ['CZK'],
      requestRefund: async s => {assert.equal(s.providerId, id); invoked++; return {status: 'pending', dispatchUncertain: false};},
      recoverRefund: async () => ({status: 'unknown', dispatchUncertain: true})};
    const registry = new PaymentRegistry([[id, () => ({connector: {id, displayName: id}, refund: capability})]]);
    const results = await reconcilePaymentRefunds(registry, async name => {
      if (name === 'get_recoverable_payment_refunds') return [{requestId, providerId: id}];
      if (name === 'claim_payment_refund') return {requestId, providerId: id, lease: 'lease', priorDispatched: false,
        connectorState: {}, snapshot: {...snapshot, providerId: id}};
      return {};
    });
    assert.equal(invoked, 1); assert.equal(results[0].state, 'completed');
  }
});
Deno.test('dispatch success reaches the original provider ingestion without manufacturing a bank movement', async () => {
  const {stripePaymentAdapter} = await import('./connectors/stripe.ts');
  const {hostedPaymentBinding} = await import('./contracts.ts');
  let ingested = false;
  const p = provider(async (url, init) => {
    const path = String(url);
    if (path.includes('/payment_intents/')) return Response.json(payment());
    if (path.includes('/checkout/sessions/')) return Response.json({object: 'checkout.session', id: 'cs_test_original',
      status: 'complete', livemode: false, amount_total: 100000, currency: 'czk', mode: 'payment',
      client_reference_id: snapshot.attemptId, expires_at: 2800, payment_method_types: ['card'], payment_status: 'paid',
      payment_intent: {...payment(), amount: 100000, latest_charge: {created: 1050}}});
    if (path.includes('/disputes?')) return Response.json({data: [], has_more: false});
    if (init?.method === 'POST') return Response.json({...refund(), created: 1100});
    return Response.json({data: [{...refund(), created: 1100}], has_more: false});
  });
  const deps = stripePaymentAdapter({provider: p, verifyPlatform: async () => {}, livemode: false,
    allowedOrigins: [], webhookSecrets: [], rpc: async (name, args) => {
      if (name === 'claim_stripe_sync_internal') return {providerId: 'stripe', disposition: 'dispatch', lease: 'sync_lease',
        snapshot: {...snapshot, amountMinor: 100000, orderReference: 'Original order', expiresAt: 2800, sessionId: 'cs_test_original', returnBaseUrl: 'https://test/stripe/return'},
        source: null};
      assert.equal(name, 'ingest_stripe_payment_internal');
      const facts = args.p_facts as {movements: {kind: string; providerId: string}[]};
      assert(facts.movements.some(m => m.kind === 'refund' && m.providerId === 're_original'));
      assert(facts.movements.some(m => m.kind === 'payment' && m.providerId === 'pi_original')); ingested = true;
      return {data: {committed: true, payment: {method: 'stripe', status: 'partially_refunded'}}};
    }});
  const registry = new PaymentRegistry([['stripe', () => hostedPaymentBinding(deps,
    stripeRefundCapability({provider: p, verifyPlatform: async () => {}}))]]);
  const result = await reconcilePaymentRefunds(registry, async (name, args) => {
    if (name === 'get_recoverable_payment_refunds') return [{requestId, providerId: 'stripe'}];
    if (name === 'claim_payment_refund') return {requestId, providerId: 'stripe', lease: 'lease', priorDispatched: false,
      connectorState: {}, snapshot};
    assert.equal(name, 'complete_payment_refund'); assert(ingested); return args.p_result;
  });
  assert.equal(result[0].state, 'completed'); assert(ingested);
});
