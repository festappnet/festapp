import { openEmail } from "./emailPayload.ts";
import { type OrderOverviewSource, sha256Text } from "./waitlistEmail.ts";

type Context = {
  orderId: number; organization: number; occasion: number; unit: number;
  formLink: string; webLink: string; recipient?: string;
};
export async function openOrderOverviewUrl(context: Context, source: {
  sealed: Record<string, string>; contentHash: string; tokenHash: string;
}) {
  const plain = await openEmail<OrderOverviewSource>(source.sealed);
  if (plain.version !== 1 || plain.purpose !== "order_overview" ||
    plain.organization !== context.organization || plain.occasion !== context.occasion ||
    (context.recipient !== undefined && plain.recipient !== context.recipient) ||
    plain.unit !== context.unit ||
    (plain.orderId !== undefined && plain.orderId !== context.orderId) ||
    !/^[a-f0-9]{64}$/.test(plain.token) ||
    await sha256Text(plain.token) !== source.tokenHash ||
    await sha256Text(JSON.stringify(plain)) !== source.contentHash) {
    throw new Error("INVALID_OVERVIEW_SOURCE");
  }
  const base = new URL(context.webLink);
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname);
  if ((base.protocol !== "https:" && !(base.protocol === "http:" && local)) ||
    base.username || base.password || base.search || base.hash) throw new Error("INVALID_OVERVIEW_ORIGIN");
  const url = new URL("order", `${base.href.replace(/\/$/, "")}/`);
  url.search = new URLSearchParams({ order_id: String(context.orderId), token: plain.token }).toString();
  return url.href;
}
