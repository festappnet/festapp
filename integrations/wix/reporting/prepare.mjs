import {createHash} from 'node:crypto';
import registration from '../wix-app.json' with {type:'json'};
import {billingApprovalBlockers} from '../billing/approval.mjs';

// Presentation adapter over settled service-fee receipts. This module neither
// calculates organizer charges from ticket payments nor collects any money.
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fail = code => { throw new Error(code); };
const required = value => typeof value === 'string' && value.trim() && value.length <= 1000 && !/[\u0000-\u001f]/.test(value);
function positive(value) {
  if (typeof value !== 'string' || !/^[1-9]\d{0,29}$/.test(value)) fail('INVALID_MINOR_AMOUNT_OR_FX_RATIO');
  return BigInt(value);
}
function nonnegative(value) {
  if (value === '0') return 0n;
  return positive(value);
}
function rate(value) {
  if (!Number.isInteger(value) || value < 0 || value > 10000) fail('INVALID_SHARE_RATE');
  return BigInt(value);
}
const rounded = (numerator, denominator) => (numerator * 2n + denominator) / (denominator * 2n);
const money = minor => `${minor / 100n}.${String(minor % 100n).padStart(2, '0')}`;
function date(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) ||
      !Number.isFinite(Date.parse(value)) || new Date(value).toISOString() !== value) fail('INVALID_TRANSACTION_INSTANT');
  return value;
}
const csvCell = value => `"${String(value).replaceAll('"', '""')}"`;
export const columns = ['App ID', 'Instance ID', 'Transaction Date (dd/mm/yyyy)', 'Product Name',
  'Gross Revenue, Without Sales Tax (USD)', 'Net App Revenue (USD)',
  'How did you calculate your Net App Revenue', 'Revenue Share Calculation', 'Owed (USD)'];

/** Input is an operator-controlled export from the authoritative fee ledger,
 * never checkout JSON, query parameters, browser claims or a second ledger.
 * Agreement and verification references must identify real external evidence.
 * All referenced charge receipts must be present, even for a later-period refund.
 */
export function prepareReporting(input) {
  if (!input || input.schemaVersion !== 2 || !Array.isArray(input.receipts) || !input.receipts.length) fail('INVALID_REPORT_INPUT');
  const a = input.agreement;
  if (billingApprovalBlockers(a).length || a.refundConversion !== 'original-charge') fail('UNAPPROVED_COMMERCIAL_BASIS');
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(input.period || '')) fail('INVALID_MONTHLY_PERIOD');
  const byId = new Map();
  const receipts = input.receipts.map(r => {
    if (!r || !required(r.id) || byId.has(r.id)) fail('DUPLICATE_OR_MISSING_RECEIPT_ID');
    if (!required(r.sourceReference) || !required(r.productName) || /^[=+\-@\t\r]/.test(r.productName)) fail('MISSING_OR_UNSAFE_SOURCE_FIELDS');
    if (!uuid.test(r.instanceId || '') || !required(r.instanceVerificationReference)) fail('MISSING_VERIFIED_APP_INSTANCE');
    if (!['charge', 'refund'].includes(r.kind) || !/^[A-Z]{3}$/.test(r.currency || '')) fail('INVALID_FEE_RECEIPT');
    if (r.amountBasis !== 'settled-service-fee-excluding-tax') fail('TICKET_PROCEEDS_ARE_NOT_APP_REVENUE');
    if (typeof r.refundSequence !== 'string' || !/^(0|[1-9]\d{0,18})$/.test(r.refundSequence) ||
        (r.kind === 'charge' ? r.refundSequence !== '0' : r.refundSequence === '0')) fail('INVALID_REFUND_SEQUENCE');
    const result = {...r, sequence: BigInt(r.refundSequence), occurredAt: date(r.occurredAt), fee: positive(r.feeMinor), expenses: nonnegative(r.agreedExpensesMinor)};
    if (result.expenses > result.fee || (result.expenses && !required(r.expenseApprovalReference))) fail('UNAPPROVED_EXPENSES');
    byId.set(r.id, result);
    return result;
  });
  for (const r of receipts.filter(r => r.kind === 'charge')) {
    if (!required(r.organizerAgreementReference) || !Number.isInteger(r.organizerFeeRateBps) ||
        r.organizerFeeRateBps <= 0 || r.organizerFeeRateBps > 10000) fail('MISSING_ORGANIZER_FEE_AGREEMENT');
    if (r.customerOrigin !== 'wix' || !required(r.customerOriginEvidenceReference)) fail('NON_WIX_CUSTOMER_REVENUE');
    if (!required(r.fx?.reference)) fail('MISSING_FX_EVIDENCE');
    r.fxNumerator = positive(r.fx.usdMinorNumerator);
    r.fxDenominator = positive(r.fx.sourceMinorDenominator);
    if (r.currency === 'USD' && r.fxNumerator !== r.fxDenominator) fail('INVALID_USD_CONVERSION');
    r.share = rate(r.wixShareBps);
    r.refunds = [];
  }
  const compare = (left, right) => left < right ? -1 : left > right ? 1 : 0;
  for (const r of receipts.filter(r => r.kind === 'refund')) {
    const charge = byId.get(r.chargeReceiptId);
    if (!charge || charge.kind !== 'charge' || charge.instanceId !== r.instanceId || charge.currency !== r.currency ||
        charge.occurredAt > r.occurredAt || charge.productName !== r.productName) fail('REFUND_CHARGE_SCOPE_MISMATCH');
    charge.refunds.push(r);
  }
  // The source's committed per-charge sequence owns rounding. Provider dates
  // remain truthful presentation fields, even when facts arrive out of order.
  const amounts = new Map();
  for (const charge of receipts.filter(r => r.kind === 'charge')) {
    const converted = (fee, expenses) => {
      const gross = rounded(fee * charge.fxNumerator, charge.fxDenominator);
      const net = rounded((fee - expenses) * charge.fxNumerator, charge.fxDenominator);
      return {gross, net, owed: rounded(net * charge.share, 10000n)};
    };
    amounts.set(charge.id, converted(charge.fee, charge.expenses));
    let refunded = 0n, refundedExpenses = 0n, sequence = 1n;
    for (const r of charge.refunds.sort((left, right) => compare(left.sequence, right.sequence))) {
      if (r.sequence !== sequence++) fail('INCOMPLETE_OR_DUPLICATE_REFUND_SEQUENCE');
      const before = converted(refunded, refundedExpenses);
      refunded += r.fee; refundedExpenses += r.expenses;
      if (refunded > charge.fee || refundedExpenses > charge.expenses ||
          refunded - refundedExpenses > charge.fee - charge.expenses) fail('REFUND_EXCEEDS_ORIGINAL_FEE');
      const after = converted(refunded, refundedExpenses);
      const amount = {gross: after.gross - before.gross, net: after.net - before.net, owed: after.owed - before.owed};
      if (Object.values(amount).some(value => value < 0n)) fail('INVALID_REFUND_EXPENSE_ALLOCATION');
      amounts.set(r.id, amount);
    }
  }
  const rows = receipts.sort((left, right) => compare(left.occurredAt, right.occurredAt) || compare(left.id, right.id)).map(r => {
    const charge = r.kind === 'charge' ? r : byId.get(r.chargeReceiptId);
    const amount = amounts.get(r.id);
    const sign = r.kind === 'refund' ? '-' : '';
    const decimal = value => value ? sign + money(value) : '0.00';
    const event = {createdDate: r.occurredAt, billingType: r.kind.toUpperCase(), grossRevenue: decimal(amount.gross),
      netRevenue: decimal(amount.net), wixShare: decimal(amount.owed)};
    const [year, month, day] = r.occurredAt.slice(0, 10).split('-');
    return {receiptId: r.id, sourceReference: r.sourceReference, instanceId: r.instanceId,
      instanceVerificationReference: r.instanceVerificationReference, agreementReference: a.reference,
      attributionPolicyReference: a.attributionPolicyReference, refundPolicyReference: a.refundPolicyReference,
      basis: {refundSequence: r.refundSequence, amountBasis: r.amountBasis, sourceCurrency: r.currency, serviceFeeMinor: r.feeMinor,
        organizerAgreementReference: charge.organizerAgreementReference, organizerFeeRateBps: charge.organizerFeeRateBps,
        customerOrigin: charge.customerOrigin, customerOriginEvidenceReference: charge.customerOriginEvidenceReference,
        agreedExpensesMinor: r.agreedExpensesMinor, expenseApprovalReference: r.expenseApprovalReference || null,
        chargeReceiptId: charge.id, chargeSourceReference: charge.sourceReference,
        fx: {usdMinorNumerator: charge.fx.usdMinorNumerator, sourceMinorDenominator: charge.fx.sourceMinorDenominator,
          reference: charge.fx.reference}, wixShareBps: charge.wixShareBps},
      requestBody: {event},
      csv: [registration.appId, r.instanceId, `${day}/${month}/${year}`, r.productName,
        event.grossRevenue, event.netRevenue, 'Settled service fee excluding tax, less approved expenses; organizer ticket proceeds excluded.',
        `${charge.wixShareBps} basis points of net service revenue; agreement ${a.reference}`, event.wixShare]};
  }).filter(row => row.requestBody.event.createdDate.startsWith(input.period + '-'));
  if (!rows.length) fail('NO_FEE_RECEIPTS_IN_PERIOD');
  const csv = [columns, ...rows.map(row => row.csv)].map(row => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
  const events = rows.map(({csv, ...row}) => row);
  return {schemaVersion: 2, period: input.period, appId: registration.appId, events, csv,
    digest: createHash('sha256').update(JSON.stringify(events)).update(csv).digest('hex')};
}
