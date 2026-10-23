import { ticketEmailSubstitutions } from "../_shared/ticketEmail.ts";
import {
  escapeTicketText,
  prepareTicketDelivery,
} from "../_shared/ticketDelivery.ts";
import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";
import defaults from "../_shared/emailPreviewDefaults.json" with {
  type: "json",
};

/** Synthetic sample only: no identity lookup, capability link, QR or invoice. */
export function previewOrder(
  title: string,
  tone: string,
  configuration?: {
    ticketsEnabled?: boolean;
    sampleProducts?: any[];
    paymentInfo?: any;
    deadlineDurationSeconds?: number;
  },
  now = new Date(),
) {
  const products =
    configuration?.sampleProducts?.filter((p) =>
      !p.is_hidden && Number.isFinite(Number(p.price))
    ) ?? [];
  const currency = products[0]?.currency_code ?? "CZK";
  const sampleProducts = products.filter((p) =>
    (p.currency_code ?? "CZK") === currency
  );
  const amount = sampleProducts.length
    ? sampleProducts.reduce((sum, p) => sum + Number(p.price), 0)
    : 0;
  const dateParts = defaults.deadline.match(/(\d+)[.]\s*(\d+)[.]\s*(\d+)/)!;
  const deadline = configuration?.deadlineDurationSeconds != null &&
      Number.isFinite(configuration.deadlineDurationSeconds) &&
      configuration.deadlineDurationSeconds >= 0
    ? new Date(now.getTime() + configuration.deadlineDurationSeconds * 1000)
      .toISOString()
    : new Date(
      Date.UTC(
        Number(dateParts[3]),
        Number(dateParts[2]) - 1,
        Number(dateParts[1]),
        12,
      ),
    ).toISOString();
  return {
    occasion: {
      title,
      features: configuration?.ticketsEnabled
        ? [{ code: "ticket", is_enabled: true }]
        : [],
    },
    order_symbol: defaults.orderSymbol,
    form: { data: { communication_tone: tone } },
    payment_info: {
      amount,
      currency_code: currency,
      deadline,
      account_number: configuration?.paymentInfo?.account_number ||
        defaults.iban,
      account_number_human_readable:
        configuration?.paymentInfo?.account_number_human_readable ||
        configuration?.paymentInfo?.account_number || defaults.accountNumber,
      variable_symbol: defaults.variableSymbol,
      creditor_reference: "RF18539007547034",
    },
    data: {
      tickets: [{
        ticket_symbol: "UKAZKA-001",
        products: sampleProducts,
      }],
    },
  };
}

export async function renderDraftPreview(context: any) {
  const order = previewOrder(context.title, context.tone, context);
  const isTickets = context.messageType === "order_tickets";
  let delivery: Awaited<ReturnType<typeof prepareTicketDelivery>> | undefined;
  if (isTickets) {
    const feature = {
      ...context.ticketFeature,
      code: "ticket",
      is_enabled: context.ticketsEnabled === true,
      delivery_mode: context.deliveryMode ?? "pdf_attachment",
    };
    const occasion = {
      ...(context.occasion ?? { id: 0, title: context.title, data: {} }),
      features: [feature],
    };
    const tickets = Array.from(
      { length: context.sampleTicketCount === 3 ? 3 : 1 },
      (_, i) => ({
        id: i + 1,
        occasion: occasion.id,
        state: "paid",
        ticket_symbol: `festapp-preview:UKAZKA-${
          String(i + 1).padStart(3, "0")
        }`,
      }),
    );
    delivery = await prepareTicketDelivery(occasion, {}, tickets, async () => {
      const { loadLayoutResources, resolveTicketTemplate, generateTicketPdf } =
        await import("../_shared/ticketGeneration.ts");
      const { sampleData, indexProductCatalog, validateProductReferences } =
        await import("../_shared/ticketRenderData.ts");
      const resources = await loadLayoutResources(occasion);
      const template = await resolveTicketTemplate(occasion, resources);
      const catalog = indexProductCatalog(
        context.ticketCatalog ?? { product_types: [], products: [] },
        occasion.id,
      );
      validateProductReferences(template, catalog);
      return async (ticket) => {
        const data = sampleData("normal", occasion, catalog, template);
        for (const element of template.elements) {
          if (element.binding === "qr") {
            data[element.id] = ticket.ticket_symbol;
          } else if (element.binding === "ticketSymbol") {
            data[element.id] = ticket.ticket_symbol.slice(
              "festapp-preview:".length,
            );
          }
        }
        return await generateTicketPdf(
          data,
          resources,
          template,
          undefined,
          true,
        );
      };
    });
    // Admission QR stays deliberately invalid; only its human-readable sample
    // code is shown. Production delivery continues to show the real symbol.
    delivery.html = delivery.html.replaceAll("festapp-preview:", "");
  }
  const ticketSubs = ticketEmailSubstitutions({
    order: {
      ...order,
      price: order.payment_info.amount,
      currency_code: order.payment_info.currency_code,
    },
    occasion: order.occasion,
    payment_info: { ...order.payment_info, paid: order.payment_info.amount },
    form_data: { communication_tone: context.tone },
  });
  const prepared = await renderEmail({
    to: "preview@example.invalid",
    context: { organization: 0 }, // Resolver below owns the already-authorized hierarchy.
    templateCode: isTickets
      ? "TICKET_ORDER_PAYMENT_DONE"
      : "TICKET_ORDER_CONFIRMATION",
    attachments: delivery?.attachments,
    ticketBlock: isTickets ? delivery?.html ?? "" : undefined,
    subjectSubstitutions: isTickets ? ticketSubs : undefined,
    substitutions: isTickets
      ? {
        ...ticketSubs,
        occasionTitle: escapeTicketText(context.title),
        orderSymbol: escapeTicketText(order.order_symbol),
      }
      : {
        ...defaults,
        ...confirmationSubstitutions(
          order,
        ),
      },
    replyTo: context.replyTo ?? undefined,
  }, () => Promise.resolve(context.resolved));
  return {
    attachments: prepared.attachments.filter((a) => a.disposition !== "INLINE")
      .map((a, i) => ({
        filename: isTickets ? `vstupenka-ukazka-${i + 1}.pdf` : a.filename,
        contentType: a.contentType,
      })),
    inlineImages: prepared.attachments.filter((a) => a.disposition === "INLINE")
      .map((a) => ({ contentId: a.contentId, content: a.content })),
    subject: prepared.subject,
    html: prepared.html,
    replyTo: prepared.replyTo,
    revision: context.revision,
    has_custom_template: context.has_custom_template,
    emailTemplates: context.emailTemplates,
    emailScope: context.emailScope,
    authoringContext: {
      senderAddress: prepared.from,
      wrapperHtml: context.resolved?.wrapper?.html,
      paymentAccounts: context.paymentInfo
        ? [{
          accountNumber: context.paymentInfo.account_number_human_readable ||
            context.paymentInfo.account_number,
          iban: context.paymentInfo.account_number,
          currencies: [context.sampleProducts?.[0]?.currency_code ?? "CZK"],
        }]
        : [],
    },
    previewContext: {
      title: context.title,
      deadline: order.payment_info.deadline,
      products: context.sampleProducts ?? [],
      ticketsEnabled: context.ticketsEnabled,
    },
  };
}
