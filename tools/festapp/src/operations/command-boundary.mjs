import { z } from 'zod';
import { OperationError, commandEdgeResponse } from '../errors.mjs';

// No upstream messages, values, unknown keys, tokens or schema error objects are
// logged. Codes and depths distinguish schema drift from transport failures.
// Logging is best effort: it must never replace the error being reported.
export function outputDiagnostic(operation, error, phase = 'output', projectPath) {
    try {
        const issues = error?.name === 'ZodError' && Array.isArray(error?.issues) ? error.issues : null;
        console.error(JSON.stringify({ event: 'festapp_output_failure', operation, phase,
            cause: error?.name === 'ZodError' ? 'schema_validation' :
                error instanceof OperationError ? error.code :
                ['TimeoutError', 'AbortError'].includes(error?.name) ? error.name : 'upstream_failure',
            ...(issues ? { issues: issues.slice(0, 20).map(issue => ({
                code: issue?.code, ...(projectPath ? { path: projectPath(issue?.path ?? []) } : {}), depth: Array.isArray(issue?.path) ? issue.path.length : 0,
                ...(typeof issue?.expected === 'string' ? { expected: issue.expected } : {}),
            })) } : {}),
        }));
    } catch { /* Diagnostics are optional. */ }
}

export function parseOutput(schema, value, operation, projectPath) {
    try { return schema.parse(value); }
    catch (error) { outputDiagnostic(operation, error, 'output', projectPath); throw error; }
}

// Ticket layout saves keep their own pending-intent recovery (pending/resume),
// which owns the outcome of an unvalidated receipt; a migrated intent may not
// be re-derivable from its request. They keep their existing errors.
const UNGUARDED = new Set(['ticket_layouts.save', 'ticket_layouts.resume']);

// The canonical envelope of a write that sent this command ID, or null. Edge
// responses are interpreted exactly like commandEdgeResponse: anything it
// rejects (transport/concurrency/permission failures, 410, uncommitted 5xx or a
// committed receipt for another command) is not a commit.
function committedEnvelope(method, params, response, commandId) {
    const sent = method === 'rpc' ? params[1]?.p_command_id : params[1]?.body?.commandId;
    if (!z.uuid().safeParse(sent).success || (commandId !== undefined && sent !== commandId)) return null;
    let data;
    if (method === 'invoke') {
        try { data = commandEdgeResponse(response ?? {}, sent); } catch { return null; }
    } else {
        if (response?.error) return null;
        data = response?.data;
    }
    return data?.code === 200 && ['applied', 'unchanged'].includes(data.status) &&
        data.mutation?.commandId === sent && data.mutation.receiptId === sent ? data : null;
}

// Observe the canonical transaction envelope BEFORE adapters validate/project
// its result or perform another read. Never infer a commit from a transport
// error, a 409/410/rejection, a call that did not send this command's ID (for
// example a read RPC) or a receipt belonging to another command.
// Nothing is persisted here: the canonical envelope (receiptId === commandId)
// comes from the SQL receipt owner, which replays the same committed receipt
// for the same command. A replay whose readback still fails therefore returns
// the same COMMITTED_READBACK_FAILED; SQL keeps authorization, payload
// conflicts and receipt expiry authoritative on every replay.
export async function commandBoundary(client, descriptor, args, run) {
    if (descriptor.domainReadOnly || UNGUARDED.has(descriptor.id)) return run(client);
    let receiptId, formId;
    const observe = async (target, method, params) => {
        const response = await target[method](...params);
        const envelope = committedEnvelope(method, params, response, args.commandId);
        if (envelope) receiptId = envelope.mutation.receiptId;
        return response;
    };
    const functions = client.functions && new Proxy(client.functions, { get(target, key) {
        return key === 'invoke' ? (...params) => observe(target, key, params) : Reflect.get(target, key);
    } });
    const tracked = new Proxy(client, { get(target, key) {
        if (key === 'rpc') return (...params) => observe(target, key, params);
        if (key === 'functions') return functions;
        const value = Reflect.get(target, key);
        return typeof value === 'function' ? value.bind(target) : value;
    } });
    try { return await run(tracked, id => { formId = id; }); }
    catch (error) {
        if (!receiptId) throw error;
        outputDiagnostic(descriptor.id, error, 'after_commit');
        const failure = new OperationError('COMMITTED_READBACK_FAILED', false);
        failure.cause = error;
        failure.receipt = { commandId: receiptId, receiptId, ...(formId ? { occasionId: args.occasionId, formId } : {}) };
        throw failure;
    }
}
