import { paidEmailSubstitutions } from "../_shared/paidEmailContent.ts";
import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";

import {
  escapeTicketText,
  prepareTicketDelivery,
} from "../_shared/ticketDelivery.ts";

/** Synthetic sample only: no identity lookup, capability link, QR or invoice. */
export function previewOrder(title: string, tone: string) {
  return {
    occasion: { title, features: [] },
    order_symbol: "UKAZKA-001",
    form: { data: { communication_tone: tone } },
    payment_info: {
      amount: 1000,
      currency_code: "CZK",
      deadline: "2030-01-15T12:00:00Z",
      account_number: "CZ0000000000000000000000",
      account_number_human_readable: "000000-0000000000/0000",
      variable_symbol: "0000000000",
    },
    data: {
      tickets: [{
        ticket_symbol: "UKAZKA-001",
        products: [{
          title: "Ukázková vstupenka",
          price: 1000,
          currency_code: "CZK",
        }],
      }],
    },
  };
}

export async function renderDraftPreview(context: any) {
  const isTickets = context.messageType === "order_tickets";
  const feature = {
    ...(context.ticketFeature ?? { code: "ticket" }),
    delivery_mode: context.deliveryMode ?? "pdf_attachment",
  };
  const occasion = context.occasion ??
    { id: 0, title: context.title, data: {} };
  occasion.features = [feature];
  let delivery: Awaited<ReturnType<typeof prepareTicketDelivery>> | undefined;
  if (isTickets) {
    const samples = Array.from({
      length: context.sampleTicketCount === 3 ? 3 : 1,
    }, (_, i) => ({
      id: i + 1,
      occasion: occasion.id,
      state: "paid",
      ticket_symbol: `festapp-preview:INVALID-${i + 1}`,
    }));
    delivery = await prepareTicketDelivery(
      occasion,
      {},
      samples,
      async (occasion) => {
        // Lazy import keeps inline preview independent of fonts/backgrounds and PDF.
        const {
          loadLayoutResources,
          resolveTicketTemplate,
          generateTicketPdf,
        } = await import("../_shared/ticketGeneration.ts");
        const { sampleData, indexProductCatalog, validateProductReferences } =
          await import("../_shared/ticketRenderData.ts");
        const resources = await loadLayoutResources(occasion);
        const template = await resolveTicketTemplate(occasion, resources);
        const catalog = indexProductCatalog(
          context.sampleProducts ?? { product_types: [], products: [] },
          occasion.id,
        );
        validateProductReferences(template, catalog);
        return async (ticket) => {
          const data = sampleData("normal", occasion, catalog, template);
          for (
            const element of template.elements
          ) {
            if (element.binding === "qr") {
              data[element.id] = ticket.ticket_symbol;
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
      },
    );
  }
  const prepared = await renderEmail({
    to: "preview@example.invalid",
    context: { organization: 0 }, // Resolver below owns the already-authorized hierarchy.
    templateCode: isTickets
      ? "TICKET_ORDER_PAYMENT_DONE"
      : "TICKET_ORDER_CONFIRMATION",
    attachments: delivery?.attachments,
    ticketBlock: isTickets ? delivery?.html ?? "" : undefined,
    subjectSubstitutions: isTickets
      ? { occasionTitle: context.title, orderSymbol: "UKAZKA-001" }
      : undefined,
    substitutions: isTickets
      ? {
        ...paidEmailSubstitutions({
          order: {
            ...previewOrder(context.title, context.tone),
            price: 1000,
            currency_code: "CZK",
          },
          occasion,
          payment_info: { amount: 1000, paid: 1000 },
          form_data: { communication_tone: context.tone },
        }),
        occasionTitle: escapeTicketText(context.title),
        orderSymbol: "UKAZKA-001",
      }
      : confirmationSubstitutions(
        previewOrder(context.title, context.tone),
      ),
    replyTo: context.replyTo ?? undefined,
  }, () => Promise.resolve(context.resolved));
  return {
    attachments: prepared.attachments.filter((a) => a.disposition !== "INLINE")
      .map((a) => ({ filename: a.filename, contentType: a.contentType })),
    inlineImages: prepared.attachments.filter((a) => a.disposition === "INLINE")
      .map((a) => ({ contentId: a.contentId, content: a.content })),
    subject: prepared.subject,
    html: prepared.html,
    replyTo: prepared.replyTo,
    revision: context.revision,
    has_custom_template: context.has_custom_template,
  };
}
