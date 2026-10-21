import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";

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
  const prepared = await renderEmail({
    to: "preview@example.invalid",
    context: { organization: 0 }, // Resolver below owns the already-authorized hierarchy.
    templateCode: "TICKET_ORDER_CONFIRMATION",
    substitutions: confirmationSubstitutions(
      previewOrder(context.title, context.tone),
    ),
    replyTo: context.replyTo ?? undefined,
  }, () => Promise.resolve(context.resolved));
  return {
    subject: prepared.subject,
    html: prepared.html,
    replyTo: prepared.replyTo,
    revision: context.revision,
    has_custom_template: context.has_custom_template,
  };
}
