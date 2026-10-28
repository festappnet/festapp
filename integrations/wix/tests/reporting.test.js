import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, writeFileSync, rmSync, mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {prepareReporting} from '../reporting/prepare.mjs';

const instance = '01234567-1234-4234-8234-123456789abc';
function fixture() {
  return {schemaVersion: 2, period: '2026-10', agreement: {reference: 'approved-amendment',
    attributionPolicyReference: 'approved-attribution', refundPolicyReference: 'approved-refunds',
    serviceFeeOnly: true, grossTicketValueExcluded: true, externalTicketCheckoutApproved: true,
    partnerBillingApproved: true, refundTreatmentConfirmed: true, refundConversion: 'original-charge'}, receipts: [{
    id: 'fee-1', kind: 'charge', refundSequence: '0', sourceReference: 'canonical-fee-settlement-1',
    productName: 'Ticketing service fee', instanceId: instance,
    instanceVerificationReference: 'server-verified-installation-1',
    occurredAt: '2026-10-01T12:00:00.000Z', currency: 'CZK',
    amountBasis: 'settled-service-fee-excluding-tax', feeMinor: '5000',
    agreedExpensesMinor: '0', wixShareBps: 2000,
    organizerAgreementReference:'organizer-contract-1',organizerFeeRateBps:500,
    customerOrigin:'wix',customerOriginEvidenceReference:'verified-organizer-acquisition-1',
    fx: {usdMinorNumerator: '1', sourceMinorDenominator: '25', reference: 'accounted-fx-1'},
  }]};
}
function refund(input, id, amount, time = '2026-10-02T12:00:00.000Z') {
  const r = {...input.receipts[0], id, kind: 'refund', refundSequence: String(input.receipts.length), chargeReceiptId: 'fee-1', feeMinor: amount, occurredAt: time};
  // A refund uses the stored original conversion/share, never today's values.
  delete r.fx; delete r.wixShareBps;
  input.receipts.push(r);
  return r;
}

test('CSV and API use the same service-fee-only USD projection without mutating the source', () => {
  const input = fixture(), before = JSON.stringify(input), report = prepareReporting(input);
  assert.equal(JSON.stringify(input), before);
  const event = report.events[0].requestBody.event;
  assert.deepEqual(event, {createdDate: '2026-10-01T12:00:00.000Z', billingType: 'CHARGE',
    grossRevenue: '2.00', netRevenue: '2.00', wixShare: '0.40'});
  assert.match(report.csv, /"2.00","2.00"/);
  assert.match(report.csv, /"0.40"\r\n$/);
  assert.equal(report.events[0].instanceId, instance);
  assert.deepEqual(report.events[0].basis.fx, input.receipts[0].fx);
  assert.equal('instanceId' in event, false); // instance-scoped auth, no browser attribution in the body
  assert.equal(prepareReporting(input).digest, report.digest);
});

test('unapproved terms, ticket proceeds and missing attribution evidence fail closed', () => {
  for (const field of ['serviceFeeOnly', 'grossTicketValueExcluded', 'externalTicketCheckoutApproved', 'partnerBillingApproved', 'refundTreatmentConfirmed']) {
    const input = fixture(); input.agreement[field] = false;
    assert.throws(() => prepareReporting(input), /UNAPPROVED_COMMERCIAL_BASIS/);
  }
  const input = fixture(); input.receipts[0].amountBasis = 'ticket-face-value';
  assert.throws(() => prepareReporting(input), /TICKET_PROCEEDS/);
  input.receipts[0].amountBasis = 'settled-service-fee-excluding-tax';
  delete input.receipts[0].instanceVerificationReference;
  assert.throws(() => prepareReporting(input), /MISSING_VERIFIED_APP_INSTANCE/);
});

test('split refunds reverse the exact original USD fee and share after cumulative rounding', () => {
  const input = fixture(); Object.assign(input.receipts[0], {feeMinor: '3', wixShareBps: 5000,
    fx: {usdMinorNumerator: '1', sourceMinorDenominator: '3', reference: 'accounted-fx'}});
  for (let n = 1; n <= 3; n++) refund(input, `refund-${n}`, '1', `2026-10-0${n + 1}T12:00:00.000Z`);
  const events = prepareReporting(input).events.map(r => r.requestBody.event);
  const cents = value => Math.round(Number(value) * 100);
  for (const field of ['grossRevenue', 'netRevenue', 'wixShare']) {
    assert.equal(events.reduce((sum, r) => sum + cents(r[field]), 0), 0, field);
  }
  assert.deepEqual(events.slice(1).map(r => r.grossRevenue), ['0.00', '-0.01', '0.00']);
});

test('later-period refunds retain the original rate and earlier refund balances', () => {
  const input = fixture(); refund(input, 'partial', '1000');
  refund(input, 'remaining', '4000', '2026-11-01T12:00:00.000Z');
  input.period = '2026-11';
  const report = prepareReporting(input);
  assert.equal(report.events.length, 1);
  assert.equal(report.events[0].requestBody.event.grossRevenue, '-1.60');
  assert.equal(report.events[0].requestBody.event.wixShare, '-0.32');
  assert.equal(report.events[0].basis.chargeReceiptId, 'fee-1');
  assert.equal(report.csv.split('\r\n').length, 3);
});

test('duplicate facts, cross-instance refunds and excess refunds cannot be exported', () => {
  let input = fixture(); input.receipts.push({...input.receipts[0]});
  assert.throws(() => prepareReporting(input), /DUPLICATE/);
  input = fixture(); refund(input, 'r', '5001');
  assert.throws(() => prepareReporting(input), /REFUND_EXCEEDS/);
  input = fixture(); refund(input, 'r', '1').instanceId = '11234567-1234-4234-8234-123456789abc';
  assert.throws(() => prepareReporting(input), /REFUND_CHARGE_SCOPE_MISMATCH/);
});

test('only approved expenses are deducted and zero first-year share is explicit', () => {
  const input = fixture(); input.receipts[0].agreedExpensesMinor = '1000';
  assert.throws(() => prepareReporting(input), /UNAPPROVED_EXPENSES/);
  Object.assign(input.receipts[0], {expenseApprovalReference: 'approved-deduction', wixShareBps: 0});
  const event = prepareReporting(input).events[0].requestBody.event;
  assert.equal(event.netRevenue, '1.60');
  assert.equal(event.wixShare, '0.00');
});

test('organizer rates are individual evidence and pre-existing non-Wix customers cannot enter the report',()=>{
  const input=fixture();delete input.receipts[0].organizerAgreementReference;
  assert.throws(()=>prepareReporting(input),/MISSING_ORGANIZER_FEE_AGREEMENT/);
  input.receipts[0].organizerAgreementReference='individual-contract';
  input.receipts[0].organizerFeeRateBps=null;
  assert.throws(()=>prepareReporting(input),/MISSING_ORGANIZER_FEE_AGREEMENT/);
  input.receipts[0].organizerFeeRateBps=250;
  input.receipts[0].customerOrigin='pre-existing-non-wix';
  assert.throws(()=>prepareReporting(input),/NON_WIX_CUSTOMER_REVENUE/);
  input.receipts[0].customerOrigin='wix';
  const report=prepareReporting(input);
  assert.equal(report.events[0].basis.organizerFeeRateBps,250);
  assert.equal(report.events[0].basis.organizerAgreementReference,'individual-contract');
});

test('money, FX and dates reject unsafe or imprecise input', () => {
  for (const value of [5000, '50.00', '-1', '9007199254740992.1', '0']) {
    const input = fixture(); input.receipts[0].feeMinor = value;
    assert.throws(() => prepareReporting(input), /INVALID_MINOR_AMOUNT/);
  }
  const input = fixture(); input.receipts[0].fx.sourceMinorDenominator = '0';
  assert.throws(() => prepareReporting(input), /INVALID_MINOR_AMOUNT/);
  input.receipts[0].fx.sourceMinorDenominator = '25';
  input.receipts[0].occurredAt = '2026-02-30T12:00:00.000Z';
  assert.throws(() => prepareReporting(input), /INVALID_TRANSACTION_INSTANT/);
});

test('CLI emits private CSV/API files as one batch and refuses overwrite', () => {
  const root = fileURLToPath(new URL('..', import.meta.url));
  mkdirSync(`${root}/.private`, {recursive: true});
  const temp = mkdtempSync(`${root}/.private/report-test-`);
  try {
    const source = `${temp}/input.json`, output = `${temp}/batch`;
    writeFileSync(source, JSON.stringify(fixture()));
    const run = () => spawnSync(process.execPath, ['scripts/prepare-billing.mjs', source, output], {cwd: root, encoding: 'utf8'});
    assert.equal(run().status, 0);
    const manifest = JSON.parse(readFileSync(`${output}/manifest.json`, 'utf8'));
    const events = JSON.parse(readFileSync(`${output}/events.json`, 'utf8'));
    assert.equal(manifest.status, 'prepared-not-submitted');
    assert.equal(manifest.eventCount, events.length);
    assert.match(readFileSync(`${output}/report.csv`, 'utf8'), /"0.40"/);
    assert.notEqual(run().status, 0);
    assert.deepEqual(JSON.parse(readFileSync(`${output}/manifest.json`, 'utf8')), manifest);
  } finally { rmSync(temp, {recursive: true, force: true}); }
});

test('late refunds append to immutable rounding order without changing earlier payloads', () => {
  const input = fixture(); Object.assign(input.receipts[0], {feeMinor:'3',wixShareBps:5000,
    fx:{usdMinorNumerator:'1',sourceMinorDenominator:'2',reference:'accounted-fx'}});
  refund(input,'already-reported','1','2026-10-03T12:00:00.000Z');
  const before=prepareReporting(input).events.find(e=>e.receiptId==='already-reported');
  refund(input,'late-fact','1','2026-10-02T12:00:00.000Z');
  const after=prepareReporting(input).events.find(e=>e.receiptId==='already-reported');
  assert.deepEqual(after,before);
  assert.equal(after.requestBody.event.grossRevenue,'-0.01');
  assert.equal(prepareReporting(input).events.find(e=>e.receiptId==='late-fact').requestBody.event.grossRevenue,'0.00');
  refund(input,'final','1','2026-11-01T12:00:00.000Z');
  const all=prepareReporting(input).events;
  input.period='2026-11';
  const final=prepareReporting(input).events[0].requestBody.event;
  for(const field of ['grossRevenue','netRevenue','wixShare']) {
    assert.equal([...all.map(e=>e.requestBody.event),final].reduce((sum,e)=>sum+Math.round(Number(e[field])*100),0),0);
  }
});

test('old reporting formats, duplicate and missing source refund sequences fail closed',()=>{
  const input=fixture();input.schemaVersion=1;
  assert.throws(()=>prepareReporting(input),/INVALID_REPORT_INPUT/);
  input.schemaVersion=2;refund(input,'r1','1');refund(input,'r2','1');
  delete input.receipts[1].refundSequence;assert.throws(()=>prepareReporting(input),/INVALID_REFUND_SEQUENCE/);
  input.receipts[1].refundSequence='2';assert.throws(()=>prepareReporting(input),/DUPLICATE_REFUND_SEQUENCE/);
  input.receipts[1].refundSequence='1';input.receipts[2].refundSequence='3';
  assert.throws(()=>prepareReporting(input),/INCOMPLETE_OR_DUPLICATE_REFUND_SEQUENCE/);
});
