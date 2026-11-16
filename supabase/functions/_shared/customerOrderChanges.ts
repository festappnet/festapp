import { openEmail, sealEmail } from "./emailPayload.ts";
import { sha256Text } from "./waitlistEmail.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";
export const customerChangeHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
export type ChangeInput = {
  action: "challenge" | "resolve" | "preview" | "command";
  token: string;
  orderId?: number;
  operation?: string;
  payload?: Record<string, unknown>;
  commandId?: string;
  fingerprint?: string;
};
export async function readCustomerChangeInput(
  request: Request,
): Promise<ChangeInput> {
  if (!request.body) throw new Error("INVALID_INPUT");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 49152) throw new Error("BODY_LIMIT");
      chunks.push(value);
    }
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  const data = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  if (
    !data || Array.isArray(data) || typeof data !== "object" ||
    Object.keys(data).some((k) =>
      ![
        "action",
        "token",
        "orderId",
        "operation",
        "payload",
        "commandId",
        "fingerprint",
      ].includes(k)
    ) ||
    !["challenge", "resolve", "preview", "command"].includes(data.action) ||
    typeof data.token !== "string" || !/^[a-f0-9]{64}$/.test(data.token) ||
    (data.orderId !== undefined &&
      (!Number.isSafeInteger(data.orderId) || data.orderId <= 0)) ||
    (data.operation !== undefined &&
      !["edit", "cancel", "withdraw"].includes(data.operation)) ||
    (data.payload !== undefined &&
      (!data.payload || Array.isArray(data.payload) ||
        typeof data.payload !== "object")) ||
    (data.commandId !== undefined &&
      (typeof data.commandId !== "string" ||
        !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(
          data.commandId,
        ))) ||
    (data.fingerprint !== undefined &&
      (typeof data.fingerprint !== "string" ||
        !/^[a-f0-9]{64}$/.test(data.fingerprint)))
  ) throw new Error("INVALID_INPUT");
  return data;
}
export async function prepareCustomerChangeDelivery(
  context: {
    webLink: string;
    orderId: number;
    recipient: string;
    locale: string;
  },
  readToken: string,
  operation: string,
  payload: Record<string, unknown>,
) {
  if (
    !Number.isSafeInteger(context.orderId) || context.orderId <= 0 ||
    typeof context.recipient !== "string" || context.recipient.length > 320 ||
    !context.recipient.includes("@")
  ) throw new Error("INVALID_CONTEXT");
  const token = Array.from(
    crypto.getRandomValues(new Uint8Array(32)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  const base = new URL(context.webLink);
  if (
    base.protocol !== "https:" &&
    !(base.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname))
  ) throw new Error("INVALID_ORIGIN");
  if (base.username || base.password || base.hash || base.search) {
    throw new Error("INVALID_ORIGIN");
  }
  const url = new URL("order", base.href.replace(/\/$/, "") + "/");
  url.search = new URLSearchParams({
    order_id: String(context.orderId),
    token: readToken,
  }).toString();
  url.hash = new URLSearchParams({ change: token }).toString();
  const english = context.locale === "en";
  const label = english
    ? "Review requested change"
    : "Zkontrolovat požadovanou změnu";
  const subject = english
    ? "Confirm your order change"
    : "Potvrzení změny objednávky";
  const description = english
    ? "This link is valid for 10 minutes. Opening it does not change your order. Review the details and confirm the change in the order overview. If you did not request this change, ignore this email."
    : "Odkaz platí 10 minut. Jeho otevřením se objednávka nezmění. V přehledu si zkontrolujte důsledky a změnu výslovně potvrďte. Pokud jste o změnu nežádali, tento e-mail ignorujte.";
  const source = {
    version: 1,
    purpose: "customer_order_change",
    token,
    readToken,
    orderId: context.orderId,
    operation,
    payload,
  };
  const from = Deno.env.get("DEFAULT_EMAIL") ?? "";
  const prepared = {
    from,
    to: context.recipient,
    replyTo: from,
    subject,
    html: `<p>${description}</p><p><a href="${
      escapeEmailHtml(url.href)
    }" rel="noreferrer noopener" referrerpolicy="no-referrer">${label}</a></p>`,
    attachments: [],
  };
  return {
    tokenHash: await sha256Text(token),
    contentHash: await sha256Text(JSON.stringify(source)),
    source: await sealEmail(source),
    email: await sealEmail(prepared),
  };
}
export async function openCustomerChangeSource(
  sealed: Record<string, string>,
  token: string,
  orderId: number,
) {
  const source = await openEmail<
    {
      version: number;
      purpose: string;
      token: string;
      readToken: string;
      orderId: number;
      operation: string;
      payload: Record<string, unknown>;
    }
  >(sealed);
  if (
    source.version !== 1 || source.purpose !== "customer_order_change" ||
    source.token !== token || source.orderId !== orderId ||
    !/^[a-f0-9]{64}$/.test(source.readToken) ||
    !["edit", "cancel", "withdraw"].includes(source.operation)
  ) throw new Error("INVALID_CAPABILITY");
  return { orderId, operation: source.operation, payload: source.payload };
}
