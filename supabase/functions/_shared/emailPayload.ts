// Auth codes and prepared snapshots never persist as plaintext. Key only in runtime.
function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 8192) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  }
  return btoa(binary);
}
function bytes(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}
async function key(): Promise<CryptoKey> {
  const raw = bytes(Deno.env.get("EMAIL_PAYLOAD_KEY") ?? "");
  if (raw.length !== 32) throw new Error("email_payload_key_unavailable");
  return await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, [
    "encrypt",
    "decrypt",
  ]);
}
export async function sealEmail(
  value: unknown,
): Promise<Record<string, string>> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await key(),
    new TextEncoder().encode(JSON.stringify(value)),
  );
  return {
    v: "1",
    iv: base64(iv),
    ciphertext: base64(new Uint8Array(encrypted)),
  };
}
export async function openEmail<T>(value: Record<string, string>): Promise<T> {
  if (value.v !== "1") throw new Error("unsupported_email_payload");
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: bytes(value.iv) },
    await key(),
    bytes(value.ciphertext),
  );
  return JSON.parse(new TextDecoder().decode(decrypted));
}
