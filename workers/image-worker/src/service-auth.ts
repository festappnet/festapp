/** Constant-time comparison for dedicated server capabilities, never user JWTs. */
export async function equalServiceSecret(provided: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(expected), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(provided));
  return crypto.subtle.verify('HMAC', key, signature, encoder.encode(expected));
}
