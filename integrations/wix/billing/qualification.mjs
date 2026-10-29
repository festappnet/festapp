// One zero-value QA event only. This is not a service-fee source or an activation path.
import {open, readFile} from 'node:fs/promises';
import {dirname, isAbsolute} from 'node:path';
import {randomUUID} from 'node:crypto';
import registration from '../wix-app.json' with {type: 'json'};
import {dispatchBillingReceipt} from './dispatcher.mjs';

export const qualificationTarget = Object.freeze({appId: registration.appId,
  instanceId: '5ebf65f5-1d62-43a1-a7f6-f04b06f22354'});
const purpose = 'wix-zero-only-bi-qualification';
const fail = code => {throw Error(code);};
const zeroEvent = createdDate => ({createdDate, billingType: 'CHARGE',
  grossRevenue: '0', netRevenue: '0', wixShare: '0'});

function validateApproval(approval) {
  if (approval?.schemaVersion !== 1 || approval.appId !== qualificationTarget.appId ||
    approval.instanceId !== qualificationTarget.instanceId || approval.zeroValueChargeApproved !== true ||
    !/^[0-9a-f]{16}$/.test(approval.wixApprovalMessageId || '')) fail('WIX_QUALIFICATION_APPROVAL_REQUIRED');
}

// Missing, partial or corrupt outcomes never grant another attempt.
export async function inspectQualification(stateFile) {
  let raw;
  try {raw = await readFile(stateFile, 'utf8');}
  catch (error) {if (error.code === 'ENOENT') return {state: 'not-attempted'}; throw error;}
  try {
    if (raw.length > 65536 || !raw.endsWith('\n')) fail('INVALID_JOURNAL');
    const records = raw.trim().split('\n').map(line => JSON.parse(line));
    const first = records[0], last = records[1];
    if (first.purpose !== purpose || first.appId !== qualificationTarget.appId ||
      first.instanceId !== qualificationTarget.instanceId || first.state !== 'sending' ||
      records.length > 2) fail('INVALID_JOURNAL');
    validateApproval(first.approval);
    const date = first.payload?.requestBody?.event?.createdDate;
    if (typeof date !== 'string' || new Date(date).toISOString() !== date ||
      JSON.stringify(first.payload.requestBody.event) !== JSON.stringify(zeroEvent(date))) fail('INVALID_JOURNAL');
    const validFinish = last?.attemptId === first.attemptId &&
      ['confirmed', 'rejected', 'unknown'].includes(last.state);
    return {state: validFinish ? last.state : 'unknown', attemptId: first.attemptId,
      appId: first.appId, instanceId: first.instanceId, approvalMessageId: first.approval.wixApprovalMessageId,
      event: zeroEvent(date), ...(validFinish && Number.isInteger(last.httpStatus) ? {httpStatus: last.httpStatus} : {})};
  } catch {return {state: 'unknown'};}
}

export async function sendQualification({stateFile, approval, provider, now = () => new Date()}) {
  // A reference is an operator-reviewed approval receipt, not automatic proof of vendor consent.
  validateApproval(approval);
  if (!isAbsolute(stateFile)) fail('WIX_QUALIFICATION_ABSOLUTE_STATE_PATH_REQUIRED');
  const event = zeroEvent(new Date(now()).toISOString()), attemptId = randomUUID();
  const receiptId = attemptId;
  let handle;
  const journal = {
    async claim(app, receipt, kind) {
      if (app !== qualificationTarget.appId || receipt !== receiptId || kind !== 'CHARGE') fail('INVALID_QUALIFICATION_SCOPE');
      try {handle = await open(stateFile, 'wx', 0o600);}
      catch (error) {if (error.code === 'EEXIST') return {state: 'existing-attempt'}; throw error;}
      const payload = {requestBody: {event}};
      await handle.writeFile(JSON.stringify({schemaVersion: 1, purpose, state: 'sending',
        ...qualificationTarget, receiptId, attemptId,
        approval: {schemaVersion: 1, ...qualificationTarget, zeroValueChargeApproved: true,
          wixApprovalMessageId: approval.wixApprovalMessageId}, payload}) + '\n');
      await handle.sync();
      // The parent already exists (git common directory); persist the exclusive filename before I/O.
      const directory = await open(dirname(stateFile), 'r');
      try {await directory.sync();} finally {await directory.close();}
      return {state: 'claimed', instanceId: qualificationTarget.instanceId, attemptId, payload};
    },
    async finish(app, receipt, kind, attempt, outcome, evidence) {
      if (app !== qualificationTarget.appId || receipt !== receiptId || kind !== 'CHARGE' ||
        attempt !== attemptId || !['confirmed', 'rejected', 'unknown'].includes(outcome)) fail('INVALID_QUALIFICATION_FINISH');
      // Persist only bounded classification, never tokens, arbitrary provider errors or raw bodies.
      const finish = {attemptId, state: outcome,
        ...(Number.isInteger(evidence.httpStatus) ? {httpStatus: evidence.httpStatus} : {})};
      await handle.writeFile(JSON.stringify(finish) + '\n');
      await handle.sync();
    },
  };
  try {
    return await dispatchBillingReceipt({journal, provider, receiptId, kind: 'CHARGE'});
  } finally {await handle?.close();}
}
