import { verifyWebhook, WebhookVerificationError } from "npm:@festapp/banksync@0.2.2";

type Dependencies = {
  secret: string;
  instanceId: string;
  ingest: (digest: string, envelope: unknown) => Promise<unknown>;
};
const MAX_BYTES = 64 * 1024;
export async function bankSyncWebhook(req: Request, deps: Dependencies): Promise<Response> {
  const json = (body: unknown, status: number) => new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!deps.secret || !deps.instanceId) return json({ error: "receiver_not_configured" }, 503);
  if (!req.body) return json({ error: "body_required" }, 400);
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    const deadline = Date.now() + 10_000;
    while (true) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const part = await Promise.race([
        reader.read(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => reject(new Error("timeout")), Math.max(1, deadline - Date.now()));
        }),
      ]).finally(() => clearTimeout(timer));
      if (part.done) break;
      length += part.value.length;
      if (length > MAX_BYTES) {
        await reader.cancel();
        return json({ error: "body_limit" }, 413);
      }
      chunks.push(part.value);
    }
  } catch {
    await reader.cancel().catch(() => {});
    return json({ error: "body_read_failed" }, 400);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  let event;
  try {
    event = await verifyWebhook({
      secret: deps.secret,
      timestamp: req.headers.get("x-banksync-timestamp") ?? "",
      deliveryId: req.headers.get("x-banksync-delivery-id") ?? "",
      signature: req.headers.get("x-banksync-signature") ?? "",
      bodyBytes: bytes,
      eventVersion: "2",
      toleranceSeconds: 300,
    });
  } catch (error) {
    const code = error instanceof WebhookVerificationError ? error.code : "verification_failed";
    return json({ error: code }, ["signature_invalid", "timestamp_invalid", "timestamp_out_of_range"].includes(code) ? 401 : 400);
  }
  const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)))
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  try {
    const receipt = await deps.ingest(digest, event) as Record<string, unknown> | null;
    if (receipt?.ok !== true || receipt.receipt_version !== 1 || receipt.delivery_id !== event.delivery_id) {
      return json({ error: "receipt_invalid" }, 503);
    }
    return json(receipt, 200);
  } catch (error) {
    return json({ error: "ingest_failed" }, String(error).includes("BANK_SYNC_DELIVERY_CONFLICT") ? 409 : 503);
  }
}
