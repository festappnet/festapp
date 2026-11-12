import { strict as assert } from 'node:assert';
import { decoratePaymentOperation, paymentOperationHandler, presentRefundInstructions } from './operationHandler.ts';
const instruction = {recipientIban: 'CZ6508000000192000145399', recipientName: 'Jana Nováková',
  sourceAccount: 'CZ5855000000001265098001', amount: '300.25', currency: 'CZK', reference: '12345'};
const requestSource = {method:'bank',verification:'bank_event',purpose:'bank_refund_instruction',instructionAllowed:true,status:'pending',sourceMethod:'bank',sourceOrderId:42,sourcePaymentId:55};
const readonlySource = {method:'bank',verification:'bank_event',purpose:'bank_refund_instruction',allowed:true,sourceMethod:'bank',sourceOrderId:42,sourcePaymentId:55};
Deno.test('refund SPD targets recipient and retains original VS; reopen uses identical payload', () => {
  const a = presentRefundInstructions(instruction);
  assert(String(a.payload).includes('ACC:'+instruction.recipientIban));
  assert(String(a.payload).includes('X-VS:12345')); assert(!String(a.payload).includes(instruction.sourceAccount));
  const reopened = decoratePaymentOperation({sourceOrderId:42, requests: [{...requestSource,instructions: instruction}]});
  assert.equal((reopened.requests as {instructions: {payload: string}}[])[0].instructions.payload, a.payload);
});
Deno.test('refund EUR uses existing RF and validates recipient, unsupported codec has no pretend QR', () => {
  const a = presentRefundInstructions({...instruction, currency: 'EUR', reference: 'RF18539007547034'});
  assert.equal(a.format, 'EPC_SCT'); assert(String(a.payload).includes('\nRF18539007547034\n'));
  assert.throws(() => presentRefundInstructions({...instruction, recipientIban: 'invalid'}), /instructions_invalid/);
  assert.equal(presentRefundInstructions({...instruction, currency: 'USD'}).payload, null);
});
Deno.test('operation authentication precedes context or commands', async () => {
  let called = false;
  const response = await paymentOperationHandler(new Request('https://test', {method: 'POST', headers: {authorization: 'Bearer invalid'}, body: '{}'}), {
    authenticate: async () => false, rpc: async () => {called = true; return {};},
  });
  assert.equal(response.status, 401); assert.equal(called, false);
});
Deno.test('amount preview delegates exact input to its SQL owner and never executes a command', async () => {
  const input = {operation: 'preview', orderId: 42, method: 'cash', amount: '300.25'};
  const response = await paymentOperationHandler(new Request('https://test', {method: 'POST', headers: {authorization: 'Bearer fixture'},
    body: JSON.stringify({input_data: input})}), {authenticate: async () => true, rpc: async (_, name, args) => {
      assert.equal(name, 'preview_payment_operation'); assert.deepEqual(args, {input_data: input});
      return {code: 200, preview: {netAfter: '699.75', currency: 'CZK'}};
    }});
  assert.equal(response.status, 200); assert.equal((await response.json()).preview.netAfter, '699.75');
});
Deno.test('only proven SQL rollback releases the command; transport loss and post-commit rendering stay uncertain', async () => {
  const request = () => new Request('https://test', {method: 'POST',headers: {authorization: 'Bearer fixture'},
    body: JSON.stringify({input_data: {operation: 'prepare_refund',orderId: 42},p_command_id: 'fixture'})});
  const sql = await paymentOperationHandler(request(), {authenticate: async () => true,rpc: async () => {throw {code: 'P0001',message: 'REFUND_AVAILABLE_EXCEEDED'};}});
  assert.equal((await sql.json()).mutationNotApplied,true);
  const lost = await paymentOperationHandler(request(), {authenticate: async () => true,rpc: async () => {throw new TypeError('network unavailable');}});
  assert.equal((await lost.json()).mutationNotApplied,false);
  const committed = await paymentOperationHandler(request(), {authenticate: async () => true,rpc: async () => ({code:200,request: {...requestSource,instructions: {...instruction,recipientIban:'invalid'}}})});
  assert.equal(committed.status,409);assert.equal((await committed.json()).mutationNotApplied,false);
});
Deno.test('bank QR uses a read-only RPC without command identity or refund writes', async () => {
  const input = {operation: 'bank_instructions', orderId: 42, amount: '300.25', currency: 'CZK',
    recipientIban: instruction.recipientIban, recipientName: instruction.recipientName};
  let calls = 0;
  const response = await paymentOperationHandler(new Request('https://test', {method: 'POST', headers: {authorization: 'Bearer fixture'},
    body: JSON.stringify({input_data: input})}), {authenticate: async () => true, rpc: async (_, name, args) => {
      calls++;
      assert.equal(name, 'get_bank_refund_instructions');
      assert.deepEqual(args, {input_data: input});
      return {code: 200, instructions: {...instruction,...readonlySource}};
    }});
  assert.equal(calls, 1); assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.request, undefined);
  assert(String(result.instructions.payload).includes('ACC:'+instruction.recipientIban));
  assert(String(result.instructions.payload).includes('X-VS:12345'));
});

Deno.test('unattested, disabled and cross-source instruction projections cannot render QR', () => {
 for (const invalid of [instruction, {...instruction,...readonlySource,allowed:false}, {...instruction,...readonlySource,sourceMethod:'stripe'}, {...instruction,...readonlySource,sourceOrderId:43}]) {
  assert.equal(decoratePaymentOperation({instructions:invalid},42).instructions,undefined);
 }
 for (const invalid of [{...requestSource,instructionAllowed:false},{...requestSource,sourceMethod:'orchard'},{...requestSource,sourceOrderId:43},{...requestSource,status:'cancelled'}]) {
  assert.equal((decoratePaymentOperation({request:{...invalid,instructions:instruction}},42).request as Record<string,unknown>).instructions,undefined);
 }
});
