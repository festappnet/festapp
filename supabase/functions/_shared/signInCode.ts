/** Unbiased cryptographic six-digit code; database enforces expiry and attempts. */
export function generateSignInCode(): string {
  const sample = new Uint32Array(1);
  do {
    crypto.getRandomValues(sample);
  } while (sample[0] >= 4294000000);
  return (sample[0] % 1000000).toString().padStart(6, "0");
}
