import { overviewRequiredLinks } from "./emailActionLink.ts";
import { unitVerificationEmail } from "./unitVerificationEmail.ts";
import {
  orderEmailOverviewUrl,
  overviewEmailSubstitutions,
} from "./orderEmailOverview.ts";
import { bankSyncWarningEmail } from "./bankSyncWarningEmail.ts";
import { firstLoginEmail } from "./firstLoginEmail.ts";
import { type PreparedEmail, renderEmail } from "./emailDelivery.ts";
import { escapeTicketText, prepareTicketDelivery } from "./ticketDelivery.ts";
import { ticketEmailSubstitutions } from "./ticketEmail.ts";
import { getTicketOrderConfirmationTemplate } from "../send-email/getTicketOrderConfirmationTemplate.ts";
import { getTicketOrderReminderTemplate } from "../send-email/getTicketOrderReminderTemplate.ts";
import { getTicketOrderPaidTemplate } from "../send-email/getTicketOrderPaidTemplate.ts";
import { getTicketOrderUpdateTemplate } from "../send-email/getTicketOrderUpdateTemplate.ts";
import { getTicketOrderStornoTemplate } from "../send-email/getTicketOrderStornoTemplate.ts";
import { safeClickTracking } from "./emailTracking.ts";
import { emailRpc } from "./emailQueueClient.ts";
import { renderWaitlistEmail } from "./waitlistEmailRenderer.ts";
export type EmailRow = {
  message_id: string;
  message_kind: string;
  code: string;
  data: any;
  recipient: string;
  organization: number;
  occasion: number;
  unit: number;
  order_id: number;
  lease_token: string;
  attempt_id: string;
  prepared: Record<string, string> | null;
};
export async function renderQueuedEmail(
  row: EmailRow,
): Promise<{ prepared: PreparedEmail; postAction: Record<string, unknown> }> {
  if (["waitlist_confirmation", "waitlist_offer"].includes(row.message_kind)) {
    return await renderWaitlistEmail(row);
  }
  if (row.message_kind === "custom" && row.code === "BANK_SYNC_WARNING") {
    return {
      prepared: bankSyncWarningEmail(
        row.recipient,
        row.data,
        Deno.env.get("DEFAULT_EMAIL") ?? "",
      ),
      postAction: { tracking_policy: "disabled" },
    };
  }
  if (row.message_kind === "custom" && row.code === "NEW_USER_FIRST_LOGIN") {
    return {
      prepared: firstLoginEmail(
        row.recipient,
        row.data,
        Deno.env.get("DEFAULT_EMAIL") ?? "",
      ),
      postAction: { tracking_policy: "disabled" },
    };
  }
  if (
    row.message_kind === "custom" && row.code === "UNIT_VERIFICATION_REQUEST"
  ) {
    return {
      prepared: unitVerificationEmail(
        row.recipient,
        row.data,
        Deno.env.get("DEFAULT_EMAIL") ?? "",
      ),
      postAction: { tracking_policy: "disabled" },
    };
  }
  if (row.message_kind === "order_tickets") {
    const result = await emailRpc("get_order_details_for_email", {
      p_order_id: row.order_id,
    });
    if (result.code !== 200) throw new Error("ticket_order_unavailable");
    const { order, occasion, reply_to } = result.data;
    const delivery = await prepareTicketDelivery(
      occasion,
      order.data,
      await emailRpc("get_tickets_with_details", { order_id: row.order_id }),
      async (...args) => {
        const { prepareTicketRenderer } = await import("./ticketGeneration.ts");
        return await prepareTicketRenderer(...args);
      },
    );
    const lang = row.data?.lang ?? "cs";
    const payment = ticketEmailSubstitutions(result.data, lang);
    const overviewUrl = await orderEmailOverviewUrl(row, emailRpc);
    return {
      prepared: await renderEmail({
        to: row.recipient,
        templateCode: row.code,
        requiredLinks: overviewRequiredLinks(overviewUrl, row.data?.lang),
        context: {
          organization: row.organization,
          occasion: row.occasion,
          unit: row.unit,
        },
        subjectSubstitutions: {
          ...payment,
          ...overviewEmailSubstitutions(overviewUrl, lang),
        },
        substitutions: {
          ...payment,
          occasionTitle: escapeTicketText(occasion.title),
          orderSymbol: escapeTicketText(order.order_symbol),
          ...overviewEmailSubstitutions(overviewUrl, lang),
        },
        from: `${occasion.title} | Festapp <${Deno.env.get("DEFAULT_EMAIL")}>`,
        replyTo: reply_to,
        attachments: delivery.attachments,
        ticketBlock: delivery.html,
      }),
      postAction: {
        ...(overviewUrl ? { tracking_policy: "disabled" } : {}),
        ticket_ids: delivery.tickets.map((t: any) => t.id),
      },
    };
  }
  const handlers: Record<string, any> = {
    order_confirmation: getTicketOrderConfirmationTemplate,
    order_reminder: getTicketOrderReminderTemplate,
    order_payment_notice: getTicketOrderPaidTemplate,
    order_update: getTicketOrderUpdateTemplate,
    order_storno: getTicketOrderStornoTemplate,
  };
  const handler = handlers[row.message_kind];
  if (!handler) throw new Error("email_renderer_missing");
  const secret = await emailRpc("generate_request_secret", {
    p_ttl_seconds: 120,
  });
  const rendered = await handler({
    ...row,
    data: { ...row.data, orderId: row.order_id, requestSecret: secret },
  }, null);
  // Server context and snapshotted recipient are authoritative, never live replacement recipient.
  const overviewUrl = await orderEmailOverviewUrl(row, emailRpc);
  const prepared = await renderEmail({
    to: row.recipient,
    templateCode: row.code,
    requiredLinks: overviewRequiredLinks(overviewUrl, row.data?.lang),
    context: {
      organization: row.organization,
      occasion: row.occasion,
      unit: row.unit,
    },
    substitutions: {
      ...rendered.subs,
      ...overviewEmailSubstitutions(overviewUrl, row.data?.lang),
    },
    attachments: rendered.attachments ?? [],
    replyTo: rendered.reply_to,
    from: `${rendered.sender || "Festapp"} | Festapp <${
      Deno.env.get("DEFAULT_EMAIL")
    }>`,
  });
  return {
    prepared,
    postAction: {
      tracking_policy: overviewUrl ? "disabled" : safeClickTracking(
          prepared.html,
          (Deno.env.get("EMAIL_SAFE_CLICK_ORIGINS") ?? "").split(",").filter(
            Boolean,
          ),
        )
        ? "engagement"
        : "open",
      ...(rendered.context.orderHistoryId
        ? { history_id: rendered.context.orderHistoryId }
        : {}),
      ...(rendered.context.paymentInfoId
        ? { payment_info_id: rendered.context.paymentInfoId }
        : {}),
    },
  };
}
