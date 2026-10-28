// Server-only transport. The canonical SQL journal fences every attempt. There
// is no timer, automatic retry, browser entrypoint or alternate money projection.
import registration from '../wix-app.json' with {type: 'json'};
import {prepareReporting} from '../reporting/prepare.mjs';

const appId = registration.appId;
const fail = code => { throw new Error(code); };
const fields = {createdDate: 'created_date', billingType: 'billing_type', grossRevenue: 'gross_revenue',
  netRevenue: 'net_revenue', wixShare: 'wix_share', appId: 'app_id', instanceId: 'instance_id'};
const value = (object, key) => {
  const wire = fields[key];
  if (object?.[key] !== undefined && object?.[wire] !== undefined && object[key] !== object[wire]) fail('CONFLICTING_WIX_RESPONSE');
  return object?.[key] ?? object?.[wire];
};
const cents = amount => {
  if (typeof amount !== 'string' || !/^-?\d+(\.\d{1,10})?$/.test(amount)) fail('INVALID_WIX_MONEY');
  const negative = amount.startsWith('-'), [whole, fraction = ''] = amount.replace(/^-/, '').split('.');
  return (negative ? -1n : 1n) * BigInt(whole + fraction.padEnd(10, '0'));
};
async function json(response) {
  const text = await response.text();
  if (text.length > 65536) fail('WIX_RESPONSE_TOO_LARGE');
  return JSON.parse(text);
}

export function wixBillingProvider({appSecret, fetcher = fetch, now = () => Date.now()}) {
  const post = (path, body, token) => fetcher(`https://www.wixapis.com/${path}`, {
    method: 'POST', headers: {'Content-Type': 'application/json', ...(token ? {Authorization: token} : {})},
    body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(10000),
  });
  return {
    async authorize(instanceId) {
      if (typeof appSecret !== 'string' || !appSecret.trim()) fail('WIX_APP_SECRET_REQUIRED');
      const response = await post('oauth2/token', {grant_type: 'client_credentials', client_id: appId,
        client_secret: appSecret, instance_id: instanceId});
      if (!response.ok) fail('WIX_OAUTH_REJECTED');
      const data = await json(response), token = data.access_token;
      if (typeof token !== 'string' || !token || token.length > 16384 || /[^\x21-\x7e]/.test(token) ||
        data.token_type !== 'Bearer' || !Number.isInteger(data.expires_in) || data.expires_in <= 0) fail('INVALID_WIX_OAUTH_RESPONSE');
      const infoResponse = await post('oauth2/token-info', {token});
      if (!infoResponse.ok) fail('WIX_TOKEN_SCOPE_UNVERIFIED');
      const info = await json(infoResponse);
      if (!info || ![true, 'true'].includes(info.active) || info.clientId?.toLowerCase() !== appId ||
        info.instanceId?.toLowerCase() !== instanceId.toLowerCase() || info.subjectType !== 'APP' ||
        !/^\d{1,12}$/.test(String(info.exp)) || Number(info.exp) <= Math.floor(now() / 1000)) fail('WIX_TOKEN_SCOPE_MISMATCH');
      return token; // retained only within this attempt, never persisted
    },
    async send(token, event) {
      const wire = Object.fromEntries(Object.entries(event).map(([key, item]) => [fields[key], item]));
      return post('apps/v1/billing-event', {event: wire}, token);
    },
  };
}

export async function stageBillingReport(input, journal) {
  const report = prepareReporting(input); // only owner of money/FX/refund arithmetic
  for (const event of report.events) await journal.stage(appId, event);
  return {period: report.period, digest: report.digest, count: report.events.length};
}

export async function dispatchBillingReceipt({journal, provider, receiptId, kind}) {
  const claim = await journal.claim(appId, receiptId, kind);
  if (claim.state !== 'claimed') return {state: claim.state};
  let outcome = 'rejected', evidence = {reason: 'authorization-not-completed'};
  // Failure here proves no billing POST was attempted. No provider errors or
  // tokens are copied to the journal or console.
  let token;
  try { token = await provider.authorize(claim.instanceId); }
  catch {
    await journal.finish(appId, receiptId, kind, claim.attemptId, outcome, evidence);
    return {state: outcome};
  }
  outcome = 'unknown'; evidence = {reason: 'transport-or-response-unknown'};
  try {
    const response = await provider.send(token, claim.payload.requestBody.event);
    evidence = {httpStatus: response.status, reason: 'provider-outcome-unknown'};
    // Explicit validation/auth/precondition rejections only. 408, 409, 429,
    // redirects, 5xx and undecodable/mismatched successes require reconciliation.
    if ([400, 401, 403, 404, 422, 428].includes(response.status)) {
      outcome = 'rejected'; evidence.reason = 'provider-rejected';
    } else if (response.ok) {
      const data = await json(response), event = data.event, expected = claim.payload.requestBody.event;
      if (value(event, 'appId')?.toLowerCase() !== appId || value(event, 'instanceId')?.toLowerCase() !== claim.instanceId ||
        value(event, 'billingType') !== kind || typeof value(event, 'createdDate') !== 'string' ||
        new Date(value(event, 'createdDate')).toISOString() !== expected.createdDate ||
        ['grossRevenue', 'netRevenue', 'wixShare'].some(key => cents(value(event, key)) !== cents(expected[key]))) fail('WIX_RECEIPT_MISMATCH');
      outcome = 'confirmed'; evidence = {httpStatus: response.status, event: {...expected, appId, instanceId: claim.instanceId}};
    }
  } catch { /* No blind retry: the provider may have committed before failure. */ }
  // A lost journal response leaves a fenced sending attempt. On lease expiry
  // inspect/claim records unknown; neither path grants another send.
  await journal.finish(appId, receiptId, kind, claim.attemptId, outcome, evidence);
  return {state: outcome};
}

export function rpcBillingJournal(rpc) {
  return {
    stage: (app, event) => rpc('stage_wix_billing_delivery', {p_app: app, p_event: event}),
    claim: (app, receipt, kind) => rpc('claim_wix_billing_delivery', {p_app: app, p_receipt: receipt, p_kind: kind}),
    finish: (app, receipt, kind, attempt, outcome, evidence) => rpc('finish_wix_billing_delivery', {
      p_app: app, p_receipt: receipt, p_kind: kind, p_attempt: attempt, p_outcome: outcome, p_evidence: evidence}),
  };
}
