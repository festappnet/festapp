import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "npm:jose@6.1.3";

const jwks = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"), { timeoutDuration: 5000 });
export function base64url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
export const randomSecret = () => base64url(crypto.getRandomValues(new Uint8Array(32)));
export async function hash(value: string) { return base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))); }
export function requireSecret(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(value)) throw new Error("invalid_provider_proof");
  return value;
}
export function safeReturnPath(value: unknown): string {
  if (typeof value !== "string" || !/^\/(?!\/)[A-Za-z0-9/_-]*$/.test(value) || value.includes("..")) return "/";
  return value;
}
export async function validateGoogleToken(token: string, audience: string, nonceHash: string, key: JWTVerifyGetKey = jwks) {
  const { payload } = await jwtVerify(token, key, {
    algorithms: ["RS256"], issuer: ["https://accounts.google.com", "accounts.google.com"],
    audience, requiredClaims: ["sub", "iat", "exp", "nonce", "email", "email_verified"], maxTokenAge: "10m", clockTolerance: 5,
  });
  if ((Array.isArray(payload.aud) && payload.aud.length > 1 && payload.azp !== audience) || payload.azp != null && payload.azp !== audience || typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 255 ||
      typeof payload.nonce !== "string" || await hash(payload.nonce) !== nonceHash || payload.email_verified !== true ||
      typeof payload.email !== "string" || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(payload.email)) throw new Error("invalid_provider_proof");
  const email = payload.email.toLowerCase().trim();
  return { issuer: "https://accounts.google.com", subject: payload.sub, email,
    name: typeof payload.name === "string" ? payload.name.slice(0, 160) : "",
    mailboxVerified: email.endsWith("@gmail.com") || (typeof payload.hd === "string" && payload.hd.length > 0) };
}
export async function encryptedProof(value: string, keyText: string, decrypt = false): Promise<string> {
  if (!/^[0-9a-f]{64}$/i.test(keyText)) throw new Error("provider_unavailable");
  const raw = Uint8Array.from(keyText.match(/../g)!, (v) => parseInt(v, 16));
  const key = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
  if (decrypt) {
    const bytes = Uint8Array.from(atob(value.replaceAll("-", "+").replaceAll("_", "/")), (v) => v.charCodeAt(0));
    return new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12) }, key, bytes.slice(12)));
  }
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const body = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(value)));
  return base64url(new Uint8Array([...iv, ...body]));
}
export async function mailboxHash(attempt: string, code: string, secret: string) {
  if (secret.length < 32) throw new Error("provider_unavailable");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return base64url(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${attempt}:${code}`))));
}
