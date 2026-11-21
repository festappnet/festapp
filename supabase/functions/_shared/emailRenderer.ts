import { showPaymentQrInEmail } from "./qrCodePayment.ts";
import {
  measurementApprovalEmail,
  metaCapiApprovalEmail,
} from "./measurementApprovalEmail.ts";
import { renderAdminNotificationEmail } from "./adminNotificationEmail.ts";
import { providerPaymentSubstitutions } from "./orderEmailPresentation.ts";
import { paymentRegistry } from "./payments/runtime.ts";
import { renderSaleOpeningEmail } from "./saleOpeningEmail.ts";
import { overviewRequiredLinks } from "./emailActionLink.ts";
import { unitVerificationEmail } from "./unitVerificationEmail.ts";
import {
  orderEmailOverviewContext,
  overviewEmailSubstitutions,
} from "./orderEmailOverview.ts";
import { firstLoginEmail } from "./firstLoginEmail.ts";
import { type PreparedEmail, renderEmail } from "./emailDelivery.ts";
import { prepareWalletEmail } from "./ticketWalletEmail.ts";
import { prepareTicketDelivery } from "./ticketDelivery.ts";
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
  recipient_user?: string | null;
  organization: number | null;
  occasion: number;
  unit: number;
  order_id: number;
  lease_token: string;
  attempt_id: string;
  prepared: Record<string, string> | null;
};
const recoveryNoticeCopy: Record<string, [string, string]> = {
  cs: [
    "Zahájili jsme obnovu zabezpečení účtu",
    "Pokud jste o obnovu nepožádali, obraťte se na podporu Festappu.",
  ],
  sk: [
    "Začali sme obnovu zabezpečenia účtu",
    "Ak ste o obnovu nepožiadali, kontaktujte podporu Festappu.",
  ],
  en: [
    "Account security recovery has started",
    "If you did not request recovery, contact Festapp support.",
  ],
  de: [
    "Die Wiederherstellung der Kontosicherheit wurde gestartet",
    "Wenn Sie die Wiederherstellung nicht angefordert haben, wenden Sie sich an den Festapp-Support.",
  ],
  es: [
    "Se ha iniciado la recuperación de la seguridad de la cuenta",
    "Si no solicitaste la recuperación, contacta con el equipo de soporte de Festapp.",
  ],
  pl: [
    "Rozpoczęto odzyskiwanie zabezpieczeń konta",
    "Jeśli nie proszono o odzyskiwanie, skontaktuj się z pomocą Festapp.",
  ],
  uk: [
    "Розпочато відновлення безпеки облікового запису",
    "Якщо ви не запитували відновлення, зверніться до підтримки Festapp.",
  ],
};

const factorChangeNoticeCopy: Record<string, [added: string, removed: string, message: string]> = {
  cs: ["Byl přidán způsob ověření", "Ověřovací faktor byl odebrán", "Pokud jste změnu neprovedli, obraťte se na podporu Festappu."],
  sk: ["Bol pridaný spôsob overenia", "Overovací faktor bol odstránený", "Ak ste zmenu nevykonali, kontaktujte podporu Festappu."],
  en: ["A verification method was added", "A verification factor was removed", "If you did not make this change, contact Festapp support."],
  de: ["Eine Bestätigungsmethode wurde hinzugefügt", "Ein Anmeldefaktor wurde entfernt", "Wenn Sie diese Änderung nicht vorgenommen haben, wenden Sie sich an den Festapp-Support."],
  es: ["Se añadió un método de verificación", "Se eliminó un factor de verificación", "Si no hiciste este cambio, contacta con el equipo de soporte de Festapp."],
  pl: ["Dodano metodę weryfikacji", "Usunięto metodę weryfikacji", "Jeśli to nie Twoja zmiana, skontaktuj się z pomocą Festapp."],
  uk: ["Додано спосіб підтвердження", "Фактор перевірки видалено", "Якщо ви не вносили цю зміну, зверніться до підтримки Festapp."],
};

export async function renderQueuedEmail(
  input: EmailRow,
): Promise<{ prepared: PreparedEmail; postAction: Record<string, unknown> }> {
  if (input.message_kind === "admin_notification_digest") {
    if (!input.recipient_user || input.organization !== null) {
      throw new Error("notification_scope_invalid");
    }
    return await renderAdminNotificationEmail({
      ...input,
      recipient_user: input.recipient_user,
    });
  }
  if (input.organization === null) {
    throw new Error("email_tenant_scope_required");
  }
  const row = { ...input, organization: input.organization };
  if (row.message_kind === "sale_opening_opened") {
    return await renderSaleOpeningEmail(row);
  }
  if (["waitlist_confirmation", "waitlist_offer"].includes(row.message_kind)) {
    return await renderWaitlistEmail(row);
  }
  if (row.message_kind === "custom" && [
    "ACCOUNT_MFA_RECOVERY_STARTED", "ACCOUNT_MFA_FACTOR_REMOVED", "ACCOUNT_PASSKEY_REMOVED", "ACCOUNT_MFA_METHOD_ADDED",
  ].includes(row.code)) {
    const lang = String(row.data?.lang ?? "cs");
    const recovery = Object.hasOwn(recoveryNoticeCopy, lang) ? recoveryNoticeCopy[lang] : recoveryNoticeCopy.cs;
    const [added, removed, changeMessage] = Object.hasOwn(factorChangeNoticeCopy, lang) ? factorChangeNoticeCopy[lang] : factorChangeNoticeCopy.cs;
    const [subject, message] = row.code === "ACCOUNT_MFA_RECOVERY_STARTED" ? recovery
      : [row.code === "ACCOUNT_MFA_METHOD_ADDED" ? added : removed, changeMessage];
    const sender = Deno.env.get("DEFAULT_EMAIL") ?? "";
    return {
      prepared: {
        from: `Festapp <${sender}>`, to: row.recipient, replyTo: sender,
        subject, html: `<h2>${subject}</h2><p>${message}</p>`, attachments: [],
      },
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
  if (row.message_kind === "custom" && row.code === "MEASUREMENT_APPROVAL_REQUEST") {
    return {
      prepared: measurementApprovalEmail(
        row.recipient,
        row.data,
        Deno.env.get("DEFAULT_EMAIL") ?? "",
      ),
      postAction: { tracking_policy: "disabled" },
    };
  }
  if (row.message_kind === "custom" && row.code === "META_CAPI_APPROVAL_REQUEST") {
    return {
      prepared: metaCapiApprovalEmail(
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
    // Read before optional preparation; begin_email_send fences any later preference change.
    const walletSettings = result.data.wallet;
    const walletFingerprint = walletSettings.fingerprint;
    const lang = row.data?.lang ?? occasion.locale ?? "cs";
    let walletHtml = "";
    try {
      walletHtml = await prepareWalletEmail(
        { ...row, data: { ...row.data, lang } },
        delivery.tickets,
        walletSettings.feature,
        emailRpc,
      );
    } catch {
      console.warn("ticket_wallet_email_unavailable");
    }
    const method = result.data.payment_info?.payment_method;
    const payment = ticketEmailSubstitutions(
      result.data,
      lang,
      paymentRegistry.has(method)
        ? paymentRegistry.resolve(method).connector.displayName
        : String(method ?? ""),
    );
    const overviewContext = await orderEmailOverviewContext(row, emailRpc);
    const overviewUrl = overviewContext?.url ?? null;
    const overviewActions = overviewContext?.allowedActions ?? [];
    return {
      prepared: await renderEmail({
        to: row.recipient,
        templateCode: row.code,
        requiredLinks: overviewRequiredLinks(overviewUrl, lang, overviewActions),
        context: {
          organization: row.organization,
          occasion: row.occasion,
          unit: row.unit,
        },
        substitutions: {
          ...payment,
          ...overviewEmailSubstitutions(overviewUrl, lang, overviewActions),
        },
        from: `${occasion.title} | Festapp <${Deno.env.get("DEFAULT_EMAIL")}>`,
        replyTo: reply_to,
        attachments: delivery.attachments,
        ticketBlock: delivery.html + walletHtml,
      }),
      postAction: {
        ...((overviewUrl || walletHtml) ? { tracking_policy: "disabled" } : {}),
        wallet_fingerprint: walletFingerprint,
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
  const overviewContext = await orderEmailOverviewContext(row, emailRpc);
    const overviewUrl = overviewContext?.url ?? null;
    const overviewActions = overviewContext?.allowedActions ?? [];
  let formData = rendered.formData;
  if (row.message_kind !== "order_confirmation") {
    const current = await emailRpc("get_order_details_for_email", {
      p_order_id: row.order_id,
    });
    formData = current.data?.form_data;
    const payment = current.data?.payment_info;
    if (payment) {
      rendered.subs.paymentMethodName =
        paymentRegistry.has(payment.payment_method)
          ? paymentRegistry.resolve(payment.payment_method).connector
            .displayName
          : String(payment.payment_method ?? "");
      rendered.subs.paymentAction = payment.payment_method === "bank" &&
          payment.collectionAction?.allowed === true
        ? rendered.subs.paymentDetails || rendered.subs.balanceReasoning || ""
        : "";
    }
    if (payment && paymentRegistry.hasHosted(payment.payment_method)) {
      const name =
        paymentRegistry.resolve(payment.payment_method).connector.displayName;
      Object.assign(
        rendered.subs,
        providerPaymentSubstitutions(
          payment,
          name,
          row.data?.lang ?? "cs",
          overviewEmailSubstitutions(overviewUrl, row.data?.lang, overviewActions)
            .order_overview_button,
        ),
      );
    }
  }

  const prepared = await renderEmail({
    to: row.recipient,
    templateCode: row.code,
    requiredLinks: overviewRequiredLinks(overviewUrl, row.data?.lang, overviewActions),
    context: {
      organization: row.organization,
      occasion: row.occasion,
      unit: row.unit,
    },
    substitutions: {
      ...rendered.subs,
      ...overviewEmailSubstitutions(overviewUrl, row.data?.lang, overviewActions),
    },
    attachments: rendered.attachments ?? [],
    paymentQr: rendered.paymentQrPng
      ? {
        png: rendered.paymentQrPng,
        lang: row.data?.lang,
        inline: showPaymentQrInEmail(formData),
      }
      : undefined,
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
