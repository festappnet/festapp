export class OperationError extends Error {
    constructor(code, retryable = false) {
        super(code);
        this.code = code;
        this.retryable = retryable;
    }
}
export function check(value, code = 'UPSTREAM_CONTRACT_FAILURE') {
    if (!value) throw new OperationError(code);
}
const permissionMessages = new Map([
    ['INSUFFICIENT_SCOPE', 'This connection is missing the required OAuth permissions. Reconnect and explicitly approve the scopes required by this tool; your account must also have permission for the action.'],
    ['ORGANIZER_CONSENT_REQUIRED', 'This connection does not include access to the whole organizer. Reconnect and explicitly select that organizer, rather than only its events. The account must also have the required organizer role; consent alone does not grant that role.'],
    ['FORBIDDEN', 'The connected account or selected connection access does not permit this action. Check the selected event or organizer and ask its administrator to verify your account permissions. Retrying unchanged will not grant access.'],
]);
const operationPermissionMessages = new Map([
    ['forms.save', 'Saving this form was denied. Your account needs form editor rights for this event or its organizer unit, and the form must belong to an event included in this connection. Ask the event organizer to verify your role and check the selected event and form. OAuth consent does not grant account permissions; reconnect only if the connection access or scopes need changing.'],
    ['units.settings.inspect', 'Reading organizer settings requires a live manager role for that organizer. Check the selected organizer and ask its administrator to verify the account role. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
    ['units.settings.save', 'Changing analytics or other organizer settings requires a live manager role for that organizer. Check the selected organizer and ask its administrator to verify the account role. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
]);
export function safeError(error, { operation } = {}) {
    if (error?.name === 'TimeoutError' || error?.name === 'AbortError')
        return { code: 'TIMEOUT', message: 'TIMEOUT', retryable: true };
    const known = error instanceof OperationError;
    const message = error?.code === 'FORBIDDEN'
        ? operationPermissionMessages.get(operation) ?? permissionMessages.get(error.code)
        : permissionMessages.get(error?.code) ?? error?.code;
    return {
        code: known ? error.code : 'UNAVAILABLE',
        message: known ? message : 'Operation unavailable',
        retryable: known ? !permissionMessages.has(error.code) && error.retryable : true,
    };
}
export function upstream(error) {
    if (!error) return;
    const status = Number(error.status);
    throw new OperationError(
        status === 401 ||
            [
                'refresh_token_not_found',
                'refresh_token_already_used',
                'session_not_found',
                'invalid_credentials',
            ].includes(error.code)
            ? 'AUTHENTICATION_REQUIRED'
            : status === 403 || error.code === '42501'
              ? 'FORBIDDEN'
              : status === 404
                ? 'NOT_FOUND_OR_INACCESSIBLE'
                : status === 429
                  ? 'TEMPORARILY_LIMITED'
                  : 'UNAVAILABLE',
        status >= 500 || status === 429 || !status,
    );
}

// A network/relay/server failure may hide a committed command. All order and
// waitlist adapters preserve the original UUID, including invoice-pending replies.
export function commandEdgeResponse({data,error},commandId){
 const status=Number(error?.status??error?.context?.status);
 if(['40001','40P01'].includes(error?.code??data?.errorCode))throw new OperationError('TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND',true);
 if(error&&![401,403].includes(status)&&(['FunctionsFetchError','FunctionsRelayError'].includes(error.name)||[408,429].includes(status)||status>=500))
  throw new OperationError('TEMPORARY_FAILURE_RETRY_SAME_COMMAND',true);
 if(data?.errorCode==='42501')throw new OperationError('FORBIDDEN');
 if(error)upstream({...error,status:error.status??error.context?.status});
 if(data?.code===503&&data.committed){
  check(data.committed.mutation?.commandId===commandId&&data.committed.mutation?.receiptId===commandId);
  return data.committed;
 }
 if(Number(data?.code)>=500)throw new OperationError('TEMPORARY_FAILURE_RETRY_SAME_COMMAND',true);
 if(data?.code===410)throw new OperationError('COMMAND_EXPIRED_DO_NOT_REPLAY');
 return data;
}
