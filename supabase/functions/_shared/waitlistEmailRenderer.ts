import {
  type DeliverEmailInput,
  type PreparedEmail,
  renderEmail,
} from "./emailDelivery.ts";
import { openEmail } from "./emailPayload.ts";
import { emailRpc } from "./emailQueueClient.ts";
import { sha256Text, type WaitlistEmailSource } from "./waitlistEmail.ts";

export type WaitlistEmailRow = {
  message_kind: string;
  code: string;
  recipient: string;
  organization: number;
  occasion: number;
  unit: number;
  order_id: number;
  data: {
    order_id: number;
    offer_id?: string | null;
    content_hash: string;
    waitlistEnvelope: Record<string, string>;
  };
};

export type WaitlistRenderContext = {
  orderId: number;
  orderSymbol: string;
  organization: number;
  occasion: number;
  unit: number;
  formLink: string;
  webLink: string;
  replyTo?: string;
  tokenHash: string;
  participantCount?: number;
  offeredCount?: number;
  expiresAt?: string;
  manageEnvelope?: Record<string, string>;
  manageContentHash?: string;
  manageTokenHash?: string;
};

function escapeHtml(value: unknown): string {
  return String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

/** Only a trusted tenant setting supplies the base. Bearer data stays in the
 * fragment, which browsers do not send to the form host or in Referer headers. */
export function waitlistCapabilityUrl(
  context: WaitlistRenderContext,
  source: WaitlistEmailSource,
  offerId?: string | null,
): string {
  const base = new URL(context.webLink);
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname);
  if (
    (base.protocol !== "https:" && !(base.protocol === "http:" && local)) ||
    base.username || base.password || base.search || base.hash ||
    !context.formLink || /[\r\n]/.test(context.formLink)
  ) throw new Error("waitlist_email_origin_invalid");
  const url = new URL(
    `form/${encodeURIComponent(context.formLink)}`,
    `${base.href.replace(/\/$/, "")}/`,
  );
  const parameters = new URLSearchParams(
    offerId
      ? { offer_id: offerId, token: source.token }
      : { order_id: String(context.orderId), token: source.token },
  );
  url.hash = `waitlist?${parameters}`;
  return url.href;
}

type Dependencies = {
  open: (value: Record<string, string>) => Promise<WaitlistEmailSource>;
  context: (
    orderId: number,
    offerId: string | null,
    recipient: string,
  ) => Promise<WaitlistRenderContext>;
  render: (input: DeliverEmailInput) => Promise<PreparedEmail>;
  now: () => number;
};

export async function renderWaitlistEmail(
  row: WaitlistEmailRow,
  dependencies: Partial<Dependencies> = {},
): Promise<{ prepared: PreparedEmail; postAction: Record<string, unknown> }> {
  const d: Dependencies = {
    open: openEmail<WaitlistEmailSource>,
    context: (orderId, offerId, recipient) =>
      emailRpc("get_waitlist_email_render_context_v1", {
        p_order_id: orderId,
        p_offer_id: offerId,
        p_recipient: recipient,
      }),
    render: renderEmail,
    now: Date.now,
    ...dependencies,
  };
  const source = await d.open(row.data.waitlistEnvelope);
  const offer = row.code === "waitlist_offer";
  if (
    !["waitlist_confirmation", "waitlist_offer"].includes(row.code) ||
    source.version !== 1 || source.templateCode !== row.code ||
    row.message_kind !== row.code || source.recipient !== row.recipient ||
    source.organization !== row.organization ||
    source.occasion !== row.occasion ||
    source.unit !== row.unit || row.data.order_id !== row.order_id ||
    !Number.isSafeInteger(row.order_id) || row.order_id <= 0 ||
    (source.orderId !== undefined && source.orderId !== row.order_id) ||
    !/^[0-9a-f]{64}$/.test(source.token) ||
    await sha256Text(JSON.stringify(source)) !== row.data.content_hash ||
    !Number.isSafeInteger(source.participantCount) ||
    source.participantCount < 1 ||
    offer !== Boolean(row.data.offer_id)
  ) throw new Error("waitlist_email_binding_invalid");
  if (
    offer && (
      !Number.isSafeInteger(source.offeredCount) || source.offeredCount! < 1 ||
      !source.expiresAt || !Number.isFinite(Date.parse(source.expiresAt)) ||
      Date.parse(source.expiresAt) <= d.now()
    )
  ) throw new Error("waitlist_email_offer_expired");
  const context = await d.context(
    row.order_id,
    row.data.offer_id ?? null,
    row.recipient,
  );
  if (
    context.orderId !== row.order_id || !context.orderSymbol ||
    context.organization !== row.organization ||
    context.occasion !== row.occasion ||
    context.unit !== row.unit || context.formLink !== source.formLink ||
    await sha256Text(source.token) !== context.tokenHash
  ) throw new Error("waitlist_email_context_mismatch");
  if (
    offer && (
      !Number.isSafeInteger(context.offeredCount) ||
      context.offeredCount! < 1 ||
      context.offeredCount! > source.offeredCount! ||
      !Number.isSafeInteger(context.participantCount) ||
      context.participantCount! < 1 ||
      !context.expiresAt ||
      Date.parse(context.expiresAt) !== Date.parse(source.expiresAt!)
    )
  ) throw new Error("waitlist_email_offer_context_invalid");
  let manageSource = source;
  if (offer) {
    if (!context.manageEnvelope) {
      throw new Error("waitlist_manage_source_missing");
    }
    manageSource = await d.open(context.manageEnvelope);
    if (
      manageSource.version !== 1 ||
      manageSource.templateCode !== "waitlist_confirmation" ||
      manageSource.recipient !== row.recipient ||
      manageSource.organization !== row.organization ||
      manageSource.occasion !== row.occasion ||
      manageSource.unit !== row.unit ||
      manageSource.formLink !== source.formLink ||
      (manageSource.orderId !== undefined &&
        manageSource.orderId !== row.order_id) ||
      !/^[0-9a-f]{64}$/.test(manageSource.token) ||
      await sha256Text(JSON.stringify(manageSource)) !==
        context.manageContentHash ||
      await sha256Text(manageSource.token) !== context.manageTokenHash
    ) throw new Error("waitlist_manage_binding_invalid");
  }
  const url = escapeHtml(
    waitlistCapabilityUrl(context, source, row.data.offer_id),
  );
  const manageUrl = escapeHtml(waitlistCapabilityUrl(context, manageSource));
  const button = (href: string, label: string) =>
    `<a href="${href}" rel="noreferrer noopener" referrerpolicy="no-referrer" style="display:inline-block;padding:12px 20px;background:#1565c0;color:#ffffff;text-decoration:none;border-radius:6px">${label}</a>`;
  const substitutions: Record<string, string | number> = {
    order_symbol: escapeHtml(context.orderSymbol),
    occasion_title: escapeHtml(source.occasionTitle),
    participant_count: offer
      ? context.participantCount!
      : source.participantCount,
    manage_waitlist_url: manageUrl,
    manage_waitlist_button: button(manageUrl, "Spravovat čekání"),
    ...(offer
      ? {
        offered_count: context.offeredCount!,
        offer_expires_at: escapeHtml(source.expiresAt!),
        offer_url: url,
        offer_button: button(url, "Otevřít nabídku míst"),
      }
      : {}),
  };
  return {
    prepared: await d.render({
      to: row.recipient,
      templateCode: row.code,
      context: {
        organization: row.organization,
        occasion: row.occasion,
        unit: row.unit,
      },
      substitutions,
      replyTo: context.replyTo,
    }),
    postAction: {
      tracking_policy: "disabled",
      ...(offer ? { waitlist_pending_count: context.offeredCount } : {}),
    },
  };
}
