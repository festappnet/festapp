import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";
import defaults from "../_shared/emailPreviewDefaults.json" with {type:"json"};

/** Synthetic sample only: no identity lookup, capability link, QR or invoice. */
export function previewOrder(title: string, tone: string, configuration?: {ticketsEnabled?: boolean; sampleProducts?: any[]; paymentInfo?: any; deadlineDurationSeconds?: number}, now = new Date()) {
  const products = configuration?.sampleProducts?.filter(p => !p.is_hidden && Number.isFinite(Number(p.price))) ?? [];
  const currency = products[0]?.currency_code ?? 'CZK';
  const sampleProducts = products.filter(p => (p.currency_code ?? 'CZK') === currency);
  const amount = sampleProducts.length ? sampleProducts.reduce((sum, p) => sum + Number(p.price), 0) : 0;
  const dateParts = defaults.deadline.match(/(\d+)[.]\s*(\d+)[.]\s*(\d+)/)!;
  const deadline = configuration?.deadlineDurationSeconds != null && Number.isFinite(configuration.deadlineDurationSeconds) && configuration.deadlineDurationSeconds >= 0
    ? new Date(now.getTime() + configuration.deadlineDurationSeconds * 1000).toISOString()
    : new Date(Date.UTC(Number(dateParts[3]), Number(dateParts[2])-1, Number(dateParts[1]), 12)).toISOString();
  return {
    occasion: { title, features: configuration?.ticketsEnabled ? [{code:'ticket',is_enabled:true}] : [] },
    order_symbol: defaults.orderSymbol,
    form: { data: { communication_tone: tone } },
    payment_info: {
      amount,
      currency_code: currency,
      deadline,
      account_number: configuration?.paymentInfo?.account_number || defaults.iban,
      account_number_human_readable: configuration?.paymentInfo?.account_number_human_readable || configuration?.paymentInfo?.account_number || defaults.accountNumber,
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
  const prepared = await renderEmail({
    to: "preview@example.invalid",
    context: { organization: 0 }, // Resolver below owns the already-authorized hierarchy.
    templateCode: "TICKET_ORDER_CONFIRMATION",
    substitutions: {...defaults, ...confirmationSubstitutions(
      order,
    )},
    replyTo: context.replyTo ?? undefined,
  }, () => Promise.resolve(context.resolved));
  return {
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
      paymentAccounts: context.paymentInfo ? [{
        accountNumber: context.paymentInfo.account_number_human_readable || context.paymentInfo.account_number,
        iban: context.paymentInfo.account_number,
        currencies: [context.sampleProducts?.[0]?.currency_code ?? 'CZK'],
      }] : [],
    },
    previewContext: {
      title: context.title,
      deadline: order.payment_info.deadline,
      products: context.sampleProducts ?? [],
      ticketsEnabled: context.ticketsEnabled,
    },
  };
}
