import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";

/** Synthetic sample only: no identity lookup, capability link, QR or invoice. */
export function previewOrder(title: string, tone: string, configuration?: {ticketsEnabled?: boolean; sampleProducts?: any[]}) {
  const products = configuration?.sampleProducts?.filter(p => !p.is_hidden && Number.isFinite(Number(p.price))) ?? [];
  const currency = products[0]?.currency_code ?? 'CZK';
  const sampleProducts = products.filter(p => (p.currency_code ?? 'CZK') === currency);
  const amount = sampleProducts.length ? sampleProducts.reduce((sum, p) => sum + Number(p.price), 0) : 0;
  return {
    occasion: { title, features: configuration?.ticketsEnabled ? [{code:'ticket',is_enabled:true}] : [] },
    order_symbol: "UKAZKA-001",
    form: { data: { communication_tone: tone } },
    payment_info: {
      amount,
      currency_code: currency,
      deadline: "2030-01-15T12:00:00Z",
      account_number: "CZ0000000000000000000000",
      account_number_human_readable: "000000-0000000000/0000",
      variable_symbol: "0000000000",
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
  const prepared = await renderEmail({
    to: "preview@example.invalid",
    context: { organization: 0 }, // Resolver below owns the already-authorized hierarchy.
    templateCode: "TICKET_ORDER_CONFIRMATION",
    substitutions: confirmationSubstitutions(
      previewOrder(context.title, context.tone, context),
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
