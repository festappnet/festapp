export const FIO_TOKEN_ERROR = 'fio_token_invalid_or_inactive';
export class BankSyncRemoteError extends Error {
  constructor(readonly code: string) { super(code); }
}

export function bankSyncErrorCode(error: unknown): string {
  return error instanceof BankSyncRemoteError ? error.code : 'bank_sync_retry_required';
}

export function bankSyncAccountError(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null;
  return value === FIO_TOKEN_ERROR ? FIO_TOKEN_ERROR : 'bank_sync_retry_required';
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
    // Never pass bank payloads, token material, or arbitrary upstream strings to clients.
    throw new BankSyncRemoteError(response.status === 422 && result?.error === FIO_TOKEN_ERROR
      ? FIO_TOKEN_ERROR : 'bank_sync_retry_required');
  }
  return result;
}
