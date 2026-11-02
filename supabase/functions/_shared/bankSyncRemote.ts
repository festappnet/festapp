export const FIO_TOKEN_ERROR = 'fio_token_invalid_or_inactive';
export const FIO_ACCOUNT_ERROR = 'fio_receiving_account_mismatch';
export class BankSyncRemoteError extends Error {
  constructor(readonly code: string, readonly retryAfterSeconds: number | null = null) { super(code); }
}

export function bankSyncErrorCode(error: unknown): string {
  return error instanceof BankSyncRemoteError ? error.code : 'bank_sync_retry_required';
}

export function bankSyncAccountError(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null;
  if (value === 'Error: missing_statement_info' || value === 'Error: invalid_statement_json') return 'fio_invalid_response';
  if (value === FIO_TOKEN_ERROR) return FIO_TOKEN_ERROR;
  if (value === FIO_ACCOUNT_ERROR || value === `Error: ${FIO_ACCOUNT_ERROR}`) return FIO_ACCOUNT_ERROR;
  // BankSync owns the Fio adapter. Decode only its known error classes here;
  // never expose an upstream message or infer an invalid token from a 5xx.
  if (typeof value === 'string' && /^(FioTransientFailure: Fio API 5[0-9]{2}$|FioRateLimited: Fio API (409|429)$|TimeoutError:|AbortError:)/.test(value)) {
    return 'fio_temporarily_unavailable';
  }
  return 'bank_sync_retry_required';
}

export async function bankSyncRemote(path: string, method = 'GET', body?: unknown, idempotency?: string) {
  const origin = Deno.env.get('BANKSYNC_API_URL');
  const key = Deno.env.get('BANKSYNC_TENANT_ADMIN_KEY');
  if (!origin?.startsWith('https://') || !key) throw new Error('management_not_configured');
  const response = await fetch(`${origin.replace(/\/$/, '')}${path}`, {
    method, redirect: 'error', signal: AbortSignal.timeout(path.endsWith('/fio-sync') ? 65_000 : 20_000),
    headers: {'x-tenant-secret':key,'content-type':'application/json',
      ...(idempotency ? {'idempotency-key':idempotency} : {})},
    ...(body === undefined ? {} : {body:JSON.stringify(body)}),
  });
  const result = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 429 && path.endsWith('/fio-sync') && result?.error === 'api_fetch_throttled') {
      const seconds = Number(result.retry_after_s);
      throw new BankSyncRemoteError('bank_sync_retry_required',
        Number.isFinite(seconds) ? Math.max(30, Math.min(300, Math.ceil(seconds))) : 30);
    }
    if (response.status === 503 && path.endsWith('/fio-sync') && result?.error === 'fio_api_transient_failure') {
      throw new BankSyncRemoteError('fio_temporarily_unavailable');
    }
    // Never pass bank payloads, token material, or arbitrary upstream strings to clients.
    throw new BankSyncRemoteError(response.status === 422 && [FIO_TOKEN_ERROR,FIO_ACCOUNT_ERROR].includes(result?.error)
      ? result.error : 'bank_sync_retry_required');
  }
  return result;
}

/** Consumer allowlist: upstream exception messages and response bodies never enter the UI. */
export function bankSyncLastFailure(remote: Record<string, unknown>): Record<string, unknown> | null {
  const value = remote.api_last_failure;
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    const code = remote.api_last_error === 'Error: missing_statement_info' ? 'missing_statement_info'
      : remote.api_last_error === 'Error: invalid_statement_json' ? 'invalid_statement_json' : null;
    // Older BankSync versions have no reliable failure timestamp or request metadata.
    return code ? {version:1,code,stage:'response_decode'} : null;
  }
  const input = value as Record<string, unknown>;
  const codes = ['missing_statement_info','invalid_statement_json','FioTokenInvalidOrInactive',
    'FioRateLimited','FioTransientFailure','FioApiError','fio_receiving_account_mismatch',
    'TimeoutError','AbortError','TypeError','bank_sync_internal_error'];
  const stages = ['response_decode','bank_http','account_identity','transport','bank_sync'];
  if (input.version !== 1 || typeof input.code !== 'string' || !codes.includes(input.code) || typeof input.stage !== 'string' || !stages.includes(input.stage)) return null;
  const result: Record<string, unknown> = {version:1,code:input.code,stage:input.stage};
  if (typeof input.id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.id)) result.id = input.id;
  if (typeof input.occurred_at === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(input.occurred_at)
    && Number.isFinite(Date.parse(input.occurred_at))) result.occurred_at = input.occurred_at;
  if (typeof input.operation === 'string' && ['transactions','periods'].includes(input.operation)) result.operation = input.operation;
  if (typeof input.transport === 'string' && ['direct','proxy'].includes(input.transport)) result.transport = input.transport;
  if (Number.isInteger(input.http_status) && Number(input.http_status) >= 100 && Number(input.http_status) <= 599) result.http_status = input.http_status;
  for (const key of ['document_shape','statement_shape','info_shape']) {
    if (typeof input[key] === 'string' && ['missing','null','array','object','string','number','boolean'].includes(input[key] as string)) result[key] = input[key];
  }
  return result;
}
