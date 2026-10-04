const encoder = new TextEncoder();
export async function bankSyncHash(value: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))))
    .map(byte => byte.toString(16).padStart(2, '0')).join('');
}
async function key(version: string) {
  const raw = Deno.env.get(`BANKSYNC_CONTROL_KEY_${version}`);
  if (!/^[1-9][0-9]*$/.test(version) || !raw) throw new Error('control_key_unavailable');
  const bytes = Uint8Array.from(atob(raw), char => char.charCodeAt(0));
  if (bytes.length !== 32) throw new Error('control_key_invalid');
  return crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
function base64(bytes: Uint8Array) { return btoa(String.fromCharCode(...bytes)); }
export async function sealBankSyncToken(token: string, operationId: string, hash: string) {
  const version = Deno.env.get('BANKSYNC_CONTROL_KEY_VERSION') ?? '';
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv,
    additionalData: encoder.encode(`${operationId}:${hash}`) }, await key(version), encoder.encode(token));
  return { version, iv: base64(iv), ciphertext: base64(new Uint8Array(encrypted)) };
}
export async function openBankSyncToken(cipher: {version:string;iv:string;ciphertext:string}, operationId:string, hash:string) {
  const bytes = (value:string) => Uint8Array.from(atob(value), char => char.charCodeAt(0));
  const decrypted = await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes(cipher.iv),
    additionalData:encoder.encode(`${operationId}:${hash}`)}, await key(cipher.version),bytes(cipher.ciphertext));
  return new TextDecoder().decode(decrypted);
}
