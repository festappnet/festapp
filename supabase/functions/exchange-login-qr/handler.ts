import { parseLoginQr, parseManualLoginCode } from "./qr.ts";

type Admission = { allowed: boolean; maxBodyBytes?: number };
export type QrDependencies = {
  admit: (occasion: number | null) => Promise<Admission>;
  exchange: (body: unknown) => Promise<unknown>;
};
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const reject = (status: number) => Response.json({ error: "invalid_credential" }, {
  status, headers: { ...headers, ...(status === 429 ? { "Retry-After": "60" } : {}) },
});

export async function handleQrExchange(req: Request, deps: QrDependencies): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reject(405);
  try {
    // No forwarded header is an identity. The durable global gate also bounds
    // random-input cardinality; the event gate covers changed manual-code guesses.
    const admission = await deps.admit(null);
    if (!admission.allowed) return reject(429);
    const cap = admission.maxBodyBytes;
    if (!Number.isSafeInteger(cap) || cap! <= 0) return reject(503);
    const reader = req.body?.getReader();
    if (!reader) return reject(401);
    let total = 0;
    const chunks: Uint8Array[] = [];
    let expired = false;
    const timeout = setTimeout(() => { expired = true; void reader.cancel(); }, 5000);
    let complete = false;
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) { complete = true; break; }
        total += value.byteLength;
        if (total > cap!) { await reader.cancel(); return reject(413); }
        chunks.push(value);
      }
    } finally { clearTimeout(timeout); reader.releaseLock(); }
    // A cancelled stream is not a complete request, even if its prefix is JSON.
    if (!complete || expired || req.signal.aborted) return reject(401);
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    let body;
    try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { return reject(401); }
    if (!body || typeof body !== "object" || Array.isArray(body)) return reject(401);
    const credential = body.payload != null ? parseLoginQr(body.payload)
      : parseManualLoginCode(body.occasion, body.manualCode);
    if (!credential) return reject(401);
    if (!(await deps.admit(credential.occasion)).allowed) return reject(429);
    const session = await deps.exchange(body);
    return session ? Response.json(session, { headers }) : reject(401);
  } catch { return reject(503); }
}
