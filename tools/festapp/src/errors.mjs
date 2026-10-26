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
export function safeError(error) {
    if (error?.name === 'TimeoutError' || error?.name === 'AbortError')
        return { code: 'TIMEOUT', message: 'TIMEOUT', retryable: true };
    const known = error instanceof OperationError;
    return {
        code: known ? error.code : 'UNAVAILABLE',
        message: known ? error.code : 'Operation unavailable',
        retryable: known ? error.retryable : true,
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
