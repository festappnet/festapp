import { sealEmail } from "./emailPayload.ts";

export type WaitlistEmailContext = {
  orderId?: number;
  recipient: string;
  organization: number;
  occasion: number;
  unit: number;
  occasionTitle: string;
  orderSymbol?: string;
  participantCount: number;
  offeredCount?: number;
  formLink: string;
  expiresAt?: string;
};

export type WaitlistEmailSource = WaitlistEmailContext & {
  version: 1 | 2;
  templateCode: "waitlist_confirmation" | "waitlist_offer";
  token: string;
};

export async function sha256Text(value: string): Promise<string> {
  const bytes = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

/** Only the encrypted source crosses the SQL boundary. Rendering follows commit
 * so registration templates receive the actual allocated order identity. */
export async function prepareWaitlistDelivery(
  context: WaitlistEmailContext,
  templateCode: WaitlistEmailSource["templateCode"],
  seal: (source: unknown) => Promise<Record<string, string>> = sealEmail,
) {
  if (
    !context.recipient || !context.formLink || !context.organization ||
    !context.occasion || !context.unit
  ) {
    throw new Error("waitlist_email_context_invalid");
  }
  const token = Array.from(
    crypto.getRandomValues(new Uint8Array(32)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  const source: WaitlistEmailSource = {
    ...context,
    version: 2,
    templateCode,
    token,
  };
  const overview = templateCode === "waitlist_confirmation" ? await prepareOrderOverviewSource(context, seal) : null;
  return {
    ...(context.orderId ? { orderId: context.orderId } : {}),
    recipient: context.recipient,
    templateCode,
    tokenHash: await sha256Text(token),
    contentHash: await sha256Text(JSON.stringify(source)),
    sealed: await seal(source),
    ...(overview ? { overview } : {}),
  };
}

export type OrderOverviewSource = WaitlistEmailContext & {
  version: 1;
  purpose: "order_overview";
  token: string;
};

export async function prepareOrderOverviewSource(context: WaitlistEmailContext, seal = sealEmail) {
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)),
    byte => byte.toString(16).padStart(2, "0")).join("");
  const source: OrderOverviewSource = { ...context, version: 1, purpose: "order_overview", token };
  return { tokenHash: await sha256Text(token), contentHash: await sha256Text(JSON.stringify(source)), sealed: await seal(source) };
}
