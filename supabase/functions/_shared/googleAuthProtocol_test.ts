import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { generateKeyPair, SignJWT } from "npm:jose@6.1.3";
import { encryptedProof, hash, safeReturnPath, validateGoogleToken, mailboxHash } from "./googleAuthProtocol.ts";
const keys = await generateKeyPair("RS256");
const nonce = "provider-nonce";
const claims = { nonce, email: "Person@Example.com", email_verified: true, name: "Person" };
async function token(changes: Record<string, unknown> = {}) {
  return await new SignJWT({ ...claims, ...changes }).setProtectedHeader({ alg: "RS256" }).setIssuer("https://accounts.google.com").setSubject("subject-123").setAudience("fixture-client").setIssuedAt().setExpirationTime("5m").sign(keys.privateKey);
}
Deno.test("Google proof verifies a signature, preserves sub and treats external mailbox as unproven", async () => {
  const result = await validateGoogleToken(await token(), "fixture-client", await hash(nonce), () => keys.publicKey);
  assertEquals(result.subject, "subject-123");
  assertEquals(result.email, "person@example.com");
  assertEquals(result.mailboxVerified, false);
  const gmail = await validateGoogleToken(await token({ email: "person@gmail.com" }), "fixture-client", await hash(nonce), () => keys.publicKey);
  assertEquals(gmail.mailboxVerified, true);
});
Deno.test("bad nonce, audience, issuer, signature, azp, verification and expiry reject", async () => {
  for (const changes of [{ nonce: "wrong" }, { aud: "other" }, { iss: "https://evil.invalid" }, { azp: "other" }, { email_verified: false }, { exp: 1 }, { sub: "" }, { iat: Math.floor(Date.now()/1000)+60 }]) {
    // Registered claims are set after payload construction by token(); override them explicitly here.
    const signed = await new SignJWT({ ...claims, sub: "subject-123", aud: "fixture-client", iss: "https://accounts.google.com", iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+300, ...changes }).setProtectedHeader({ alg: "RS256" }).sign(keys.privateKey);
    await assertRejects(() => validateGoogleToken(signed, "fixture-client", hashPromise, () => keys.publicKey));
  }
  const other = await generateKeyPair("RS256");
  await assertRejects(() => validateGoogleToken(tokenText, "fixture-client", hashPromise, () => other.publicKey));
});
const hashPromise = await hash(nonce);
const tokenText = await token();
Deno.test("encrypted provider verifier authenticates ciphertext and uses random IV", async () => {
  const key = "ab".repeat(32), plain = JSON.stringify({ verifier: "secret" });
  const one = await encryptedProof(plain,key), two = await encryptedProof(plain,key);
  assertEquals(one===two,false);
  assertEquals(await encryptedProof(one,key,true),plain);
  await assertRejects(() => encryptedProof(one,"cd".repeat(32),true));
});
Deno.test("route restoration rejects redirects and encoded bypasses", () => {
  for(const value of ["//evil.invalid","https://evil.invalid","/%2f%2fevil.invalid","/../secret","/\\evil.invalid"]) assertEquals(safeReturnPath(value),"/");
  assertEquals(safeReturnPath("/event-2026/form"),"/event-2026/form");
});
Deno.test("mailbox HMAC binds code to attempt", async () => {
  assertEquals(await mailboxHash("a","123456","secret".repeat(8)) === await mailboxHash("b","123456","secret".repeat(8)),false);
});
