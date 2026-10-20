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
