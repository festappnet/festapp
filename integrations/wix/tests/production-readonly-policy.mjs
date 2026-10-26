// Production diagnostics permit one public SELECT RPC, never a checkout command.
export const PUBLIC_FORM = 'country_bal_vetrkovice';
export const PUBLIC_RPC = 'https://api.festapp.net/rest/v1/rpc/get_form_by_link';
export function permitsProductionRead(request) {
  if (request.url !== PUBLIC_RPC || new Headers(request.headers).get('origin') !== 'https://vstupenky.online') return false;
  if (request.method === 'OPTIONS') return true;
  if (request.method !== 'POST') return false;
  try {
    const body = JSON.parse(request.postData);
    if (!body || Array.isArray(body) || Object.keys(body).length !== 1 || body.form_link !== PUBLIC_FORM) return false;
    const headers = new Headers(request.headers);
    const key = headers.get('apikey');
    if (!key || headers.get('authorization') !== `Bearer ${key}` || headers.has('cookie')) return false;
    return JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role === 'anon';
  } catch { return false; }
}
