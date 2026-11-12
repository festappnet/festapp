import { waitlistEmailCopy, waitlistCountPhrase } from "../supabase/functions/_shared/waitlistEmailCopy.ts";
import { emailVariableContract } from "../supabase/functions/_shared/emailVariables.ts";
import { orderCommunication } from "../supabase/functions/_shared/emailCommunication.ts";
import { communicationTones } from "../supabase/functions/_shared/communicationTone.ts";
import { saleOpeningSubstitutions } from '../supabase/functions/_shared/saleOpeningPresentation.ts';
import { confirmationPaymentSubstitutions, providerPaymentSubstitutions, updateBalanceReasoning, paidPaymentSubstitutions, reminderBalanceReasoning } from "../supabase/functions/_shared/orderEmailPresentation.ts";
import { generateFullOrder } from "../supabase/functions/_shared/orderOverview.ts";
import { generateChangeOverview } from "../supabase/functions/_shared/changeOverview.ts";
import { csTranslations } from "../supabase/functions/_shared/translations/translations.cs.ts";
import { enTranslations } from "../supabase/functions/_shared/translations/translations.en.ts";
import {
  generatePaymentDetails,
  renderAccountNumber,
} from "../supabase/functions/_shared/translations/payment-details.helpers.ts";
import {
  escapeEmailHtml,
  overviewEmailSubstitutions,
  overviewRequiredLinks,
  waitlistActionLink,
} from "../supabase/functions/_shared/emailActionLink.ts";
import { completeEmailContent } from "../supabase/functions/_shared/emailContentCompletion.ts";
import { translatePlatformLinks } from "../supabase/functions/_shared/translatePlatformLinks.ts";
import {
  formatCurrency,
  formatDatetime,
  formatIBAN,
} from "../supabase/functions/_shared/utilities.ts";

const root = new URL("../", import.meta.url);
const read = (path: string) => Deno.readTextFile(new URL(path, root));
const fixture = JSON.parse(
  await read("automation/fixtures/email_preview/order.json"),
);
const sources = [
  "automation/generate_email_preview_examples.ts",
  "automation/fixtures/email_preview/order.json",
  "supabase/functions/send-sign-in-code/teamAccessNotice.ts",
  "supabase/functions/send-reset-password-link/index.ts",
  "supabase/functions/send-occasion-team-invitations/handler.ts",
  "packages/festapp_contracts/email-variables.json",
  "packages/festapp_contracts/waitlist-email-copy.json",
  "packages/festapp_contracts/communication-tone.json",
  ...[
    "orderOverview.ts",
    "communicationTone.ts",
    "emailCommunication.ts",
    "emailVariables.ts",
    "emailTemplateComposition.ts",
    "waitlistEmailCopy.ts",
    "orderEmailPresentation.ts",
    "paymentPresentation.ts",
    "translations/translations.ts",
    "metaSurcharge.ts",
    "utilities.ts",
    "changeOverview.ts",
    "emailActionLink.ts",
    "saleOpeningPresentation.ts",
    "emailContentCompletion.ts",
    "translatePlatformLinks.ts",
    "translations/translations.cs.ts",
    "translations/translations.en.ts",
    "translations/payment-details.helpers.ts",
  ].map((p) => `supabase/functions/_shared/${p}`),
  "database/functions/eshop_waitlist/email_render_context.sql",
  ...["Confirmation", "Paid", "Update", "Reminder", "Storno"].map((p) =>
    `supabase/functions/send-email/getTicketOrder${p}Template.ts`
  ),
];
const sourceDigest = Array.from(
  new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(
        (await Promise.all(sources.map(async (p) => `${p}\n${await read(p)}`)))
          .join("\n"),
      ),
    ),
  ),
).map((b) => b.toString(16).padStart(2, "0")).join("");
const records: Record<string, unknown>[] = [];
const scalar = {
  appName: "Festapp",
  name: "Jana",
  surname: "Nováková",
  email: fixture.orderData.email,
  resetLink: "https://example.invalid/reset?preview=1",
  confirmationUrl: "https://example.invalid/delete?preview=1",
  expiresAt: "30. 10. 2026 18:00",
  code: "123456",
  occasionTitle: fixture.occasionTitle,
  orderSymbol: fixture.orderSymbol,
  accountNumber: fixture.accountNumber,
  iban: formatIBAN(fixture.iban),
  variableSymbol: fixture.variableSymbol,
  deadline: fixture.deadline,
};
for (const locale of ["cs", "en"] as const) {
  const tr = locale === "cs" ? csTranslations : enTranslations;
  const money = (n: number) => formatCurrency(n, "CZK");
  for (const tone of communicationTones) {
    for (
      const templateCode of [
        "TICKET_ORDER_CONFIRMATION",
        "TICKET_ORDER_UPDATE",
        "TICKET_ORDER_PAYMENT_DONE",
        "TICKET_ORDER_REMINDER",
        "TICKET_ORDER_STORNO",
      ]
    ) {
      const scenarios = templateCode === "TICKET_ORDER_CONFIRMATION"
        ? ["unpaid", "deposit", "zero"]
        : templateCode === "TICKET_ORDER_UPDATE"
        ? ["unpaid", "paid", "zero"]
        : templateCode === "TICKET_ORDER_PAYMENT_DONE"
        ? ["paid", "deposit"]
        : templateCode === "TICKET_ORDER_REMINDER"
        ? ["unpaid"]
        : ["standard"];
      for (const scenario of scenarios) {
        const zero = scenario === "zero";
        const paid = scenario === "paid";
        const deposit = scenario === "deposit";
        const tickets = zero
          ? fixture.tickets.map((t: any) => ({
            ...t,
            products: t.products.map((p: any) => ({ ...p, price: 0 })),
          }))
          : fixture.tickets;
        // Fixtures select monetary facts; production presenters select the text.
        const total = zero ? 0 : 800;
        const amountPaid = paid ? total
          : templateCode === "TICKET_ORDER_PAYMENT_DONE" && deposit ? 300 : 0;
        const payment = {
          payment_method: 'bank', collectionAction: {method: 'bank', purpose: 'collect_payment', allowed: true},
          amount: total, paid: amountPaid, deposit_amount: deposit ? 300 : 0,
          currency_code: "CZK", account_number: fixture.iban,
          account_number_human_readable: fixture.accountNumber,
          variable_symbol: fixture.variableSymbol,
          deadline: "2026-10-30T12:00:00",
        };
        let balanceReasoning = "";
        let amount = money(total);
        switch (templateCode) {
          case "TICKET_ORDER_CONFIRMATION":
            ({ balanceReasoning, amount } = confirmationPaymentSubstitutions(
              payment, fixture.features, locale, tone));
            break;
          case "TICKET_ORDER_UPDATE":
            balanceReasoning = updateBalanceReasoning(
              total, amountPaid, "CZK", payment, payment, locale, tone);
            break;
          case "TICKET_ORDER_PAYMENT_DONE":
            ({ balanceReasoning, amount } = paidPaymentSubstitutions(
              total, amountPaid, "CZK", fixture.features, locale, tone));
            break;
          case "TICKET_ORDER_REMINDER":
            balanceReasoning = reminderBalanceReasoning(
              5 * 86400000, 5, total - amountPaid, amountPaid, "CZK", payment, payment, locale, tone);
            break;
        }
        records.push({
          templateCode,
          scenario,
          paymentMethod: 'bank', collectionAllowed: total > amountPaid,
          locale,
          tone,
          values: {
            ...scalar,
            accountNumber: total > amountPaid ? fixture.accountNumber : '', iban: total > amountPaid ? formatIBAN(fixture.iban) : '', variableSymbol: total > amountPaid ? fixture.variableSymbol : '',
            paymentAction: total > amountPaid ? balanceReasoning : '', paymentMethodName: locale === 'cs' ? 'Bankovní převod' : 'Bank transfer',
            orderCommunication: orderCommunication(templateCode, fixture.occasionTitle, tone, locale),
            // Delivery is optional; absent ticket content renders as an empty block.
            tickets: "",
            deadline: formatDatetime(payment.deadline, locale),
            amount,
            remainingTime: tr.days_remaining(5),
            ...overviewEmailSubstitutions(fixture.overviewUrl, locale),
            order_overview_url: fixture.overviewUrl,
            // Raw scalar URL: composer escapes once according to context.
            fullOrder: generateFullOrder(
              fixture.orderData,
              tickets,
              fixture.features,
              locale,
              fixture.orderSymbol,
            ),
            balanceReasoning,
            changeOverview: generateChangeOverview(
              zero
                ? {
                  ...fixture.changes,
                  referenceTotal: 0,
                  currentTotal: 0,
                  hasChanges: false,
                }
                : fixture.changes,
              locale,
            ),
            paymentDetails: generatePaymentDetails({
              accountNumber: fixture.accountNumber,
              iban: formatIBAN(fixture.iban),
              variableSymbol: fixture.variableSymbol,
              amount,
              lang: locale,
            }),
          },
          requiredLinks: overviewRequiredLinks(fixture.overviewUrl, locale),
        });
      }
    }
  }
  for (
    const templateCode of [
      "RESET_PASSWORD",
      "SIGN_IN_CODE",
      "APP_LINKS",
      "ACCOUNT_DELETION_CONFIRM",
      "ACCOUNT_DELETION_COMPLETE",
    ]
  ) {
    const links = translatePlatformLinks([{
      platform: "web",
      link: "https://example.invalid/app",
    }], locale);
    records.push({
      templateCode,
      scenario: "standard",
      locale,
      tone: "formal",
      values: { ...scalar, appLinks: links, platformLinks: links },
      requiredLinks: [],
    });
  }
}
// Delivery SQL and offline examples are generated from the same vocabulary.
for (const tone of communicationTones) {
  const toneValues = waitlistEmailCopy[tone];
  for (const templateCode of ["waitlist_confirmation", "waitlist_offer"]) {
    records.push({
      templateCode,
      scenario: "standard",
      locale: "cs",
      tone,
      values: {
        ...toneValues,
        orderSymbol: fixture.orderSymbol,
        occasionTitle: fixture.occasionTitle,
        participant_count: "2",
        participant_phrase: waitlistCountPhrase(2, "person"),
        offered_count: "2",
        offered_places: waitlistCountPhrase(2, "place"),
        offer_expires_at: "30. 10. 2026 18:00",
        ...overviewEmailSubstitutions(fixture.overviewUrl),
        order_overview_url: fixture.overviewUrl,
        manage_waitlist_url: fixture.manageUrl,
        manage_waitlist_button: waitlistActionLink(
          escapeEmailHtml(fixture.manageUrl),
          toneValues.waitlist_manage_button_label,
        ),
        offer_url: fixture.offerUrl,
        offer_button: waitlistActionLink(
          escapeEmailHtml(fixture.offerUrl),
          toneValues.waitlist_offer_button_multiple,
        ),
      },
      singleApplicationTemplates: {
        participant_count: "1",
        participant_phrase: waitlistCountPhrase(1, "person"),
        offered_count: "1",
        offered_places: waitlistCountPhrase(1, "place"),
        waitlist_offer_instructions: toneValues.waitlist_offer_instructions_single,
        offer_button: waitlistActionLink(
          escapeEmailHtml(fixture.offerUrl), toneValues.waitlist_offer_button_single,
        ),
      },
      requiredLinks: overviewRequiredLinks(fixture.overviewUrl),
    });
  }
}
// Build display-only binding templates with the SAME production HTML owners.
// Slots only replace fixture data; the client never recreates order/payment layout.
for (const locale of ['cs','en'] as const) {
 for (const [method,name] of [['stripe','Stripe'],['barion','Barion'],['orchard','Orchard Pay'],['unknown','Unknown provider']]) {
  for (const status of ['open','paid','partially_refunded','refunded','disputed','action_required','expired','pending']) {
   for (const templateCode of ['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_STORNO']) {
    const payment={payment_method:method,providerPayment:{status},collectionAction:{allowed:method!=='unknown'&&status==='open'}};
    const substitutions=providerPaymentSubstitutions(payment,name,locale,overviewEmailSubstitutions(fixture.overviewUrl,locale).order_overview_button);
    records.push({templateCode,scenario:method+'-'+status,locale,tone:'formal',paymentMethod:method,collectionAllowed:payment.collectionAction.allowed,
     values:{...scalar,...overviewEmailSubstitutions(fixture.overviewUrl,locale),...substitutions,amount:formatCurrency(800,'CZK'),orderCommunication:orderCommunication(templateCode,fixture.occasionTitle,'formal',locale),fullOrder:generateFullOrder(fixture.orderData,fixture.tickets,fixture.features,locale,fixture.orderSymbol)},requiredLinks:overviewRequiredLinks(fixture.overviewUrl,locale)});
   }
  }
 }
 for (const templateCode of ['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_PAYMENT_DONE']) {
  const payment={payment_method:'cash',amount:800,paid:0,currency_code:'CZK',data:{payment_policy:{cashInstructions:locale==='cs'?'U vstupu.':'At the entrance.'}},collectionAction:{allowed:true}};
  records.push({templateCode,scenario:'cash-unpaid',locale,tone:'formal',paymentMethod:'cash',collectionAllowed:true,values:{...scalar,...overviewEmailSubstitutions(fixture.overviewUrl,locale),
   ...confirmationPaymentSubstitutions(payment,[],locale,'formal'),orderCommunication:orderCommunication(templateCode,fixture.occasionTitle,'formal',locale),fullOrder:generateFullOrder(fixture.orderData,fixture.tickets,fixture.features,locale,fixture.orderSymbol),accountNumber:'',iban:'',variableSymbol:'',paymentAction:'',paymentMethodName:locale==='cs'?'Hotovost':'Cash'},requiredLinks:[]});
 }
}
const moneySlots: Record<string, string> = {
  [formatCurrency(450, "CZK")]: "{{preview_price_0}}",
  [formatCurrency(350, "CZK")]: "{{preview_price_1}}",
  [formatCurrency(800, "CZK")]: "{{preview_total}}",
  [formatCurrency(300, "CZK")]: "{{preview_deposit}}",
  [formatCurrency(500, "CZK")]: "{{preview_remaining}}",
  [formatCurrency(250, "CZK")]: "{{preview_previous_price}}",
  [formatCurrency(700, "CZK")]: "{{preview_reference_total}}",
  [formatCurrency(0, "CZK")]: "{{preview_zero}}",
};
const moneyPattern = new RegExp(
  Object.keys(moneySlots).sort((a, b) => b.length - a.length)
    .map((value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|"),
  "g",
);
for (const locale of ['cs','en','sk','de','pl','uk']) {
 for (const templateCode of ['sale_opening_opened']) {
  for (const tone of communicationTones) {
  records.push({templateCode, scenario: 'standard', locale, tone,
   values: saleOpeningSubstitutions(locale, locale === 'cs' ? 'Podzimní ples' : locale === 'sk' ? 'Jesenný ples' : locale === 'de' ? 'Herbstball' : locale === 'pl' ? 'Bal jesienny' : locale === 'uk' ? 'Осінній бал' : 'Autumn ball',
    'https://example.invalid/form/preview',
    'https://example.invalid/form/preview#sale_opening=unsubscribe&token=preview'), requiredLinks: []});
  }
 }
}
for (const tone of communicationTones) {
  const samples: Record<string,string> = {appName: 'Festapp Tickets', occasionTitle: fixture.occasionTitle,
    roleLabel: 'Editor', invitationUrl: 'https://example.invalid/team-invitation?token=preview',
    occasionAdminUrl: 'https://example.invalid/slavnost/admin'};
  for (const templateCode of ['TEAM_INVITATION', 'TEAM_ACCESS_NOTICE'] as const) {
    const values = Object.fromEntries(emailVariableContract.templates[templateCode].map(code => {
      if (!(code in samples)) throw new Error(`Missing system preview value: ${code}`);
      return [code, samples[code]];
    }));
    records.push({templateCode, scenario: 'standard', locale: 'cs', tone, values, requiredLinks: []});
  }
}

for (const record of records) {
  if (!String(record.templateCode).startsWith("TICKET")) continue;
  const zero = record.scenario === "zero";
  const tickets = fixture.tickets.map((ticket: any, index: number) => ({
    ...ticket,
    products: ticket.products.map((product: any) => ({
      ...product,
      title: `{{preview_product_${index}_title}}`,
      type_title: `{{preview_product_${index}_type}}`,
      price: zero ? 0 : product.price,
    })),
  }));
  const values = record.values as Record<string, string>;
  const changes = structuredClone(fixture.changes);
  for (const change of changes.productChanges) {
    for (const item of change.changed ?? []) {
      item.from.title = "{{preview_product_1_title}}";
      item.to.title = "{{preview_product_1_title}}";
    }
  }
  const templates: Record<string, string> = {
    orderCommunication: orderCommunication(record.templateCode, "{{preview_occasion}}", record.tone, record.locale),
    fullOrder: generateFullOrder(
      fixture.orderData,
      tickets,
      fixture.features,
      record.locale as "cs" | "en",
      fixture.orderSymbol,
    ),
    paymentAction: values.paymentAction ?? "",
    balanceReasoning: values.balanceReasoning ?? "",
    paymentDetails: values.paymentDetails ?? "",
    changeOverview: zero
      ? ""
      : generateChangeOverview(changes, record.locale as "cs" | "en"),
  };
  record.contextDefaults = {
    preview_payment_method: String(record.paymentMethod ?? ''), preview_collection_allowed: String(record.collectionAllowed === true),
    preview_occasion: fixture.occasionTitle,
    preview_product_0_title: fixture.tickets[0].products[0].title,
    preview_product_0_type: fixture.tickets[0].products[0].type_title,
    preview_product_1_title: fixture.tickets[1].products[0].title,
    preview_product_1_type: fixture.tickets[1].products[0].type_title,
    preview_price_0: formatCurrency(450),
    preview_price_1: formatCurrency(350),
    preview_total: formatCurrency(800),
    preview_deposit: formatCurrency(300),
    preview_remaining: formatCurrency(500),
    preview_previous_price: formatCurrency(250),
    preview_reference_total: formatCurrency(700),
    preview_zero: formatCurrency(0),
    preview_zero_explanation: "0 CZK",
    preview_deadline: values.deadline || fixture.deadline,
    preview_currency: "CZK",
    preview_account_number: record.paymentMethod === 'bank' && record.collectionAllowed === true ? fixture.accountNumber : '',
    preview_iban: record.paymentMethod === 'bank' && record.collectionAllowed === true ? formatIBAN(fixture.iban) : '',
  };
  const contextualize = (templates: Record<string, string>) => Object.fromEntries(
    Object.entries(templates).map((
      [code, html],
    ) => [
      code,
      html.replaceAll(renderAccountNumber(fixture.accountNumber), renderAccountNumber("{{preview_account_number}}"))
        .replaceAll(fixture.accountNumber, "{{preview_account_number}}")
        .replaceAll(formatIBAN(fixture.iban), "{{preview_iban}}")
        .replace(moneyPattern, (value) => moneySlots[value])
        .replaceAll(values.deadline || fixture.deadline, "{{preview_deadline}}")
        .replace(/0 CZK/g, "{{preview_zero_explanation}}"),
    ]),
  );
  record.contextTemplates = contextualize(templates);
  const applicationFeatures = fixture.features.map((feature: any) => feature.code === "ticket"
    ? { ...feature, is_enabled: false } : feature);
  const singleChanges = structuredClone(changes);
  for (const change of singleChanges.productChanges) {
    change.ticket_symbol = tickets[0].ticket_symbol;
    for (const item of change.changed ?? []) {
      item.from.title = "{{preview_product_0_title}}";
      item.to.title = "{{preview_product_0_title}}";
      item.to.price = zero ? 0 : 450;
    }
  }
  singleChanges.referenceTotal = zero ? 0 : 250;
  singleChanges.currentTotal = zero ? 0 : 450;
  record.singleApplicationTemplates = contextualize({
    fullOrder: generateFullOrder(fixture.orderData, tickets.slice(0, 1),
      applicationFeatures, record.locale as "cs" | "en", fixture.orderSymbol),
    changeOverview: zero ? "" : generateChangeOverview(singleChanges, record.locale as "cs" | "en"),
  });
  record.singleApplicationDefaults = {
    preview_total: formatCurrency(zero ? 0 : 450),
    preview_remaining: formatCurrency(zero ? 0 : 150),
    preview_reference_total: formatCurrency(zero ? 0 : 250),
  };
  record.applicationContextTemplates = contextualize({
    fullOrder: generateFullOrder(
      fixture.orderData,
      tickets,
      fixture.features.map((feature: any) => feature.code === "ticket"
        ? { ...feature, is_enabled: false } : feature),
      record.locale as "cs" | "en",
      fixture.orderSymbol,
    ),
  });
}

const url = "https://example.invalid/order?order_id=1&preview=1";
const requiredLinks = overviewRequiredLinks(url);
for (const record of records) {
  // Every declared slot is defined; unavailable method-specific slots stay empty.
  // This never fabricates a bank account/action for another method or closed state.
  for (const code of (emailVariableContract.templates as Record<string, readonly string[]>)[record.templateCode] ?? []) {
    if (!(code in record.values)) record.values[code] = '';
  }
  record.richCodes = Object.keys(record.values).filter((code) =>
    (emailVariableContract.variables as Record<string, { html: boolean }>)[code]?.html === true);
}
const paddedWrapper = '<html><body><table><tr><td style="padding:24px">{{content}}</td></tr></table></body></html>';
const compositionFixtures = [
  { name: "custom fragment omits overview", html: "<p>Hello</p>", requiredLinks },
  {
    name: "custom document omits overview",
    html: "<html><body><p>Hello</p></body></html>",
    requiredLinks,
  },
  {
    name: "existing link",
    html: `<a href="${escapeEmailHtml(url)}">Status</a>`,
    requiredLinks,
  },
  {
    name: "card slot",
    html: "<div><!-- customer-order-overview-link --></div><p>Signature</p>",
    requiredLinks,
  },
  {
    name: "unavailable",
    html: "<p>Hello</p><!-- customer-order-overview-link -->",
    requiredLinks: [],
  },
  {
    name: "custom full document in padded wrapper omits overview",
    html: "<html><body><p>Signature</p></body></html>",
    wrapperHtml: paddedWrapper,
    requiredLinks,
  },
  {
    name: "empty wrapper behaves as no wrapper",
    html: "<p>Signature</p>",
    wrapperHtml: "",
    requiredLinks,
  },
  {
    name: "custom cancellation in padded wrapper omits overview",
    html: "<p>Cancellation</p><p>Signature</p>",
    wrapperHtml: paddedWrapper,
    requiredLinks,
  },
  {
    name: "card before signature inside padded wrapper",
    html: "<div><!-- customer-order-overview-link --></div><p>Signature</p>",
    wrapperHtml: paddedWrapper,
    requiredLinks,
  },
  {
    name: "wrapper explicit link suppresses fallback",
    html: "<p>Signature</p>",
    wrapperHtml: `<main style="padding:24px">{{content}}<a href="${escapeEmailHtml(url)}">Status</a></main>`,
    requiredLinks,
  },
  {
    name: "wrapper first slot retains precedence",
    html: "<div><!-- customer-order-overview-link --></div><p>Signature</p>",
    wrapperHtml: '<main><!-- customer-order-overview-link --><section>{{content}}</section></main>',
    requiredLinks,
  },
  {
    name: "existing authored link inside padded wrapper",
    html: `<a href="${escapeEmailHtml(url)}">Status</a><p>Signature</p>`,
    wrapperHtml: paddedWrapper,
    requiredLinks,
  },
].map((f) => ({
  ...f,
  expected: completeEmailContent(f.html, f.requiredLinks, "wrapperHtml" in f ? f.wrapperHtml : undefined),
}));
const output = JSON.stringify(
  { version: 1, sourceDigest, sources, records, compositionFixtures },
) + "\n";
const rawReferenceHtml =
  `<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><title>Ukázky e-mailů</title><style>body{font:16px/1.5 sans-serif;margin:24px;color:#202020;background:#fff}article{max-width:720px;margin:0 auto 40px}a{pointer-events:none}h1{font-size:24px}</style><h1>Obsah e-mailu - ukázková data</h1>` +
  records.filter((r) => r.locale === "cs" && r.tone === "formal").map((r) => {
    const values = r.values as Record<string, string>;
    const content = String(r.templateCode).startsWith('sale_opening')
      ? values.sale_opening_action + values.sale_opening_unsubscribe
      : String(r.templateCode).startsWith("waitlist")
      ? [
        values.manage_waitlist_button,
        r.templateCode === "waitlist_offer" ? values.offer_button : "",
      ].join("")
      : String(r.templateCode).startsWith("TICKET")
      ? (values.balanceReasoning ?? "") + (values.fullOrder ?? "") +
        (r.templateCode === "TICKET_ORDER_UPDATE" ? values.changeOverview : "")
      : values.appLinks;
    // The reference document itself has no actionable links or remote images.
    const inert = completeEmailContent(
      content ?? "",
      r.requiredLinks as ReturnType<typeof overviewRequiredLinks>,
    ).replace(/ href="[^"]*"/g, "");
    return `<article><h2>${r.templateCode} / ${r.scenario}</h2>${inert}</article>`;
  }).join("") + "</html>\n";
const referenceHtml = rawReferenceHtml.replace(/[ \t]+$/gm, "");
const referenceDestination = new URL(
  "assets/email_templates/preview_reference.html",
  root,
);
const destination = new URL(
  "assets/email_templates/preview_examples.json",
  root,
);
const runtimeDestination = new URL('supabase/functions/_shared/emailPreviewDefaults.json', root);
const runtimeDefaults = JSON.stringify(scalar) + '\n';
const scenariosDestination = new URL('supabase/functions/_shared/emailPreviewScenarios.json', root);
const runtimeScenarios = JSON.stringify({version:1, sourceDigest, records:records.map(r => ({
  templateCode:r.templateCode, scenario:r.scenario, locale:r.locale, tone:r.tone,
  values:r.values, richCodes:r.richCodes, requiredLinks:r.requiredLinks,
}))}) + '\n';
if (Deno.args.includes("--check")) {
  if (await Deno.readTextFile(scenariosDestination) !== runtimeScenarios) throw new Error('Runtime email preview scenarios are stale');
  if (await Deno.readTextFile(runtimeDestination) !== runtimeDefaults) throw new Error('Runtime email preview defaults are stale');
  if (await Deno.readTextFile(destination) !== output) {
    throw new Error(
      "Email preview examples are stale; regenerate with documented command",
    );
  }
  if (await Deno.readTextFile(referenceDestination) !== referenceHtml) {
    throw new Error("Email preview reference is stale");
  }
  console.log(`Email preview examples fresh (${records.length} scenarios)`);
} else {
  await Deno.writeTextFile(scenariosDestination, runtimeScenarios);
  await Deno.writeTextFile(runtimeDestination, runtimeDefaults);
  await Deno.writeTextFile(destination, output);
  await Deno.writeTextFile(referenceDestination, referenceHtml);
  console.log(`Generated ${records.length} email preview scenarios`);
}
