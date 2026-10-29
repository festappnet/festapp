import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, writeFile, rm, stat} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import {qualificationTarget, inspectQualification, sendQualification} from '../billing/qualification.mjs';

const date = '2026-10-29T10:00:00.000Z';
const approval = {schemaVersion: 1, ...qualificationTarget, zeroValueChargeApproved: true,
  wixApprovalMessageId: '0123456789abcdef'}; // fake provider only
async function fixture(t) {
  const dir = await mkdtemp(join(tmpdir(), 'wix-bi-qualification-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  return join(dir, 'attempt.jsonl');
}
function provider(overrides = {}) {
  return {authorize: async instance => {assert.equal(instance, qualificationTarget.instanceId); return 'never-persist-token';},
    send: async (token, event) => new Response(JSON.stringify({event: {...event, ...qualificationTarget}}), {status: 200}),
    ...overrides};
}
const send = (stateFile, extra = {}) => sendQualification({stateFile, approval, provider: provider(), now: () => date, ...extra});

test('missing vendor approval and different app/installation fail before any attempt or I/O', async t => {
  const stateFile = await fixture(t);
  for (const change of [{zeroValueChargeApproved: false}, {appId: 'other'}, {instanceId: 'other'},
    {wixApprovalMessageId: ''}, {schemaVersion: 2}]) {
    await assert.rejects(send(stateFile, {approval: {...approval, ...change}}), /APPROVAL_REQUIRED/);
  }
  assert.deepEqual(await inspectQualification(stateFile), {state: 'not-attempted'});
});

test('sends only zero CHARGE using real executor and durable private scope-bound journal', async t => {
  const stateFile = await fixture(t);
  const result = await send(stateFile, {provider: provider({send: async (token, event) => {
    assert.equal(token, 'never-persist-token');
    assert.deepEqual(event, {createdDate: date, billingType: 'CHARGE', grossRevenue: '0', netRevenue: '0', wixShare: '0'});
    const pending = JSON.parse((await readFile(stateFile, 'utf8')).trim());
    assert.equal(pending.state, 'sending');
    assert.deepEqual(pending.payload.requestBody.event, event);
    assert.equal((await stat(stateFile)).mode & 0o777, 0o600);
    return new Response(JSON.stringify({event: {...event, ...qualificationTarget}}), {status: 200});
  }})});
  assert.equal(result.state, 'confirmed');
  const saved = await inspectQualification(stateFile);
  assert.equal(saved.state, 'confirmed'); assert.equal(saved.httpStatus, 200);
  assert.equal(saved.approvalMessageId, approval.wixApprovalMessageId);
  assert.equal((await readFile(stateFile, 'utf8')).includes('never-persist-token'), false);
});

test('parallel callers and later restarts cannot authorize or send another event', async t => {
  const stateFile = await fixture(t);
  let ready, release, calls = 0;
  const entered = new Promise(resolve => {ready = resolve;});
  const gate = new Promise(resolve => {release = resolve;});
  const first = send(stateFile, {provider: provider({authorize: async () => {calls++; ready(); await gate; return 'token';}})});
  await entered;
  assert.equal((await send(stateFile)).state, 'existing-attempt');
  release(); assert.equal((await first).state, 'confirmed');
  assert.equal((await send(stateFile)).state, 'existing-attempt');
  assert.equal(calls, 1);
});

test('lost response is unknown and never automatically retried', async t => {
  const stateFile = await fixture(t);
  const result = await send(stateFile, {provider: provider({send: async () => {throw Error('private provider failure');}})});
  assert.equal(result.state, 'unknown');
  assert.equal((await send(stateFile)).state, 'existing-attempt');
  assert.equal((await inspectQualification(stateFile)).state, 'unknown');
  assert.equal((await readFile(stateFile, 'utf8')).includes('private provider failure'), false);
});

test('provider rejects precondition; the rejected attempt still prevents replay', async t => {
  const stateFile = await fixture(t);
  assert.equal((await send(stateFile, {provider: provider({send: async () => new Response('{}', {status: 428})})})).state, 'rejected');
  assert.equal((await inspectQualification(stateFile)).httpStatus, 428);
  assert.equal((await send(stateFile)).state, 'existing-attempt');
});

test('nonzero or wrong-installation success is unknown instead of confirmed', async t => {
  for (const changed of [{grossRevenue: '1'}, {instanceId: 'other'}]) {
    const stateFile = await fixture(t);
    const result = await send(stateFile, {provider: provider({send: async (token, event) =>
      new Response(JSON.stringify({event: {...event, ...qualificationTarget, ...changed}}), {status: 200})})});
    assert.equal(result.state, 'unknown');
    assert.equal((await send(stateFile)).state, 'existing-attempt');
  }
});

test('process death after durable claim is unknown on restart and cannot replay', async t => {
  const stateFile = await fixture(t);
  const module = new URL('../billing/qualification.mjs', import.meta.url).href;
  const code = `import {sendQualification} from ${JSON.stringify(module)};
    await sendQualification({stateFile:${JSON.stringify(stateFile)},approval:${JSON.stringify(approval)},
      provider:{authorize:async()=>process.exit(23),send:async()=>process.exit(99)}});`;
  const child = spawnSync(process.execPath, ['--input-type=module', '--eval', code], {encoding: 'utf8'});
  assert.equal(child.status, 23, child.stderr);
  assert.equal((await inspectQualification(stateFile)).state, 'unknown');
  assert.equal((await send(stateFile)).state, 'existing-attempt');
});

test('existing partial or corrupt attempt files fail closed', async t => {
  for (const content of ['', '{partial', '{}\n']) {
    const stateFile = await fixture(t);
    await writeFile(stateFile, content, {mode: 0o600});
    assert.deepEqual(await inspectQualification(stateFile), {state: 'unknown'});
    assert.equal((await send(stateFile)).state, 'existing-attempt');
  }
});

test('authorization rejection is recorded without a billing POST and cannot retry', async t => {
  const stateFile = await fixture(t);
  const result = await send(stateFile, {provider: provider({authorize: async () => {throw Error('secret');},
    send: async () => assert.fail('billing POST must not run')})});
  assert.equal(result.state, 'rejected');
  assert.equal((await send(stateFile)).state, 'existing-attempt');
});
