import { buildEpcSctPayload, buildSpdPayload, isValidIban } from "../paymentPresentation.ts";
import { record, PaymentError } from "./contracts.ts";
import { paymentHeaders, readPaymentBytes } from "./http.ts";

const headers = {...paymentHeaders, 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,x-client-info,content-type',
  'Access-Control-Allow-Methods': 'POST,OPTIONS'};
export function presentRefundInstructions(value: unknown): Record<string, unknown> {
  const instructions = record(value);
  if (!Object.keys(instructions).length) return instructions;
  const {recipientIban, recipientName, amount, currency, reference} = instructions;
  if (!isValidIban(recipientIban) || typeof amount !== 'string' || !/^[0-9]{1,8}(?:\.[0-9]{1,2})?$/.test(amount) || Number(amount) <= 0)
    throw new PaymentError('payment_refund_instructions_invalid');
  const payment = {account_number: recipientIban, creditor_name: recipientName, amount,
    currency_code: currency, variable_symbol: reference, creditor_reference: reference};
  if (currency === 'CZK') return {...instructions, format: 'SPD', payload: buildSpdPayload(payment)};
  if (currency === 'EUR') return {...instructions, format: 'EPC_SCT', payload: buildEpcSctPayload(payment)};
  // No pretend SPD in other currencies: actual bank-event support remains SQL policy.
  return {...instructions, format: null, payload: null};
}
export function decoratePaymentOperation(value: unknown): Record<string, unknown> {
  const result = {...record(value)};
  if (result.instructions) result.instructions = presentRefundInstructions(result.instructions);
  if (record(result.request).instructions) {
    result.request = {...record(result.request), instructions: presentRefundInstructions(record(result.request).instructions)};
  }
  if (Array.isArray(result.requests)) result.requests = result.requests.map(request => {
    const r = record(request);
    return {...r, ...(r.instructions ? {instructions: presentRefundInstructions(r.instructions)} : {})};
  });
  if (result.context) result.context = decoratePaymentOperation(result.context);
  // SQL client-sync envelope contains the same operation body as its data.
  if (result.data) result.data = decoratePaymentOperation(result.data);
  return result;
}
export async function paymentOperationHandler(request: Request, deps: {
  authenticate(authorization: string): Promise<boolean>;
  rpc(authorization: string, name: string, args: Record<string, unknown>): Promise<unknown>;
}): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers});
  if (request.method !== 'POST') return Response.json({error: 'method_not_allowed'}, {status: 405, headers});
  let rpcStarted = false, rpcCompleted = false;
  try {
    const authorization = request.headers.get('authorization') ?? '';
    if (!authorization || !await deps.authenticate(authorization)) return Response.json({error: 'unauthorized', mutationNotApplied: true}, {status: 401, headers});
    const body = record(JSON.parse(new TextDecoder().decode(await readPaymentBytes(request, 8192))));
    const input = record(body.input_data ?? body.input ?? body);
    const orderId = input.orderId ?? input.order_id;
    if (!Number.isSafeInteger(orderId) || Number(orderId) <= 0) throw new PaymentError('payment_order_invalid');
    rpcStarted = true;
    const value = input.operation === 'read'
      ? await deps.rpc(authorization, 'get_payment_operation_context', {p_order_id: orderId})
      : input.operation === 'preview'
      ? await deps.rpc(authorization, 'preview_payment_operation', {input_data: input})
      : input.operation === 'bank_instructions'
      ? await deps.rpc(authorization, 'get_bank_refund_instructions', {input_data: input})
      : await deps.rpc(authorization, 'command_payment_operation', {input_data: input, p_command_id: body.p_command_id ?? body.commandId});
    rpcCompleted = true;
    return Response.json(decoratePaymentOperation(value), {headers});
  } catch (error) {
    // SQL error codes are stable UI feedback; never return arbitrary provider bodies.
    const code = error instanceof PaymentError ? error.code : /^([A-Z][A-Z0-9_]+)$/.test(String(record(error).message))
      ? String(record(error).message) : 'payment_operation_unavailable';
    const sqlState = String(record(error).code ?? '');
    // Only an explicit server transaction error proves rollback. A lost RPC
    // response or an encoder failure after commit must retain the same intent.
    const mutationNotApplied = !rpcStarted || (!rpcCompleted && /^(P0|22|23|40|42|55)[A-Z0-9]{3}$/.test(sqlState));
    return Response.json({error: code, mutationNotApplied}, {status: 409, headers});
  }
}
