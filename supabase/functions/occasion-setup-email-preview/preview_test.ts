import { previewOrder, renderDraftPreview } from "./content.ts";
import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";
import { previewHandler } from "./handler.ts";
import defaults from "../_shared/emailPreviewDefaults.json" with {type:"json"};
import { qrPng } from "../_shared/ticketDelivery.ts";
import { encodeAttachment } from "../_shared/emailDelivery.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const resolved = {
  template: {
    id: 1,
    subject: "{{occasionTitle}} {{orderSymbol}}",
    html: "<p>Vlastní text</p>{{balanceReasoning}}{{fullOrder}}",
  },
  wrapper: { html: "<main>{{content}}</main>" },
};
const context = {
  sampleProducts: [{title:"Sample",price:1000,currency_code:"CZK"}],
  revision: 3,
  title: "Ukázková událost",
  tone: "formal",
  replyTo: "support@example.invalid",
  resolved,
  has_custom_template: true,
};

Deno.test("preview and sending use identical substitutions and inherited wrapper", async () => {
  const preview = await renderDraftPreview(context);
  const sent = await renderEmail({
    context: { organization: 1 },
    to: "recipient@example.invalid",
    substitutions: {...defaults, ...confirmationSubstitutions(
      previewOrder(context.title, context.tone, context),
    )},
    replyTo: context.replyTo,
  }, () => Promise.resolve(resolved));
  assert(preview.html === sent.html && preview.subject === sent.subject);
  assert(preview.replyTo === sent.replyTo);
  assert(preview.html.includes("<main><p>Vlastní text</p>"));
  assert(!preview.html.includes("recipient@example.invalid"));
  assert(
    !preview.html.includes("href="),
    "Synthetic bank sample must have no capability links",
  );
  assert(sent.attachments.length === 0);
});

Deno.test("formal/informal only changes generated content, preserving custom static text", async () => {
  const formal = await renderDraftPreview(context);
  const informal = await renderDraftPreview({ ...context, tone: "informal" });
  assert(formal.html !== informal.html);
  assert(
    formal.html.includes("Vlastní text") &&
      informal.html.includes("Vlastní text"),
  );
});

Deno.test("pure confirmation retains zero order and deposit semantics", () => {
  const order: any = previewOrder("Test", "informal");
  order.payment_info.amount = 0;
  assert(confirmationSubstitutions(order).variableSymbol === defaults.variableSymbol);
  order.payment_info.amount = 1000;
  order.payment_info.deposit_amount = 500;
  order.occasion.features = [{ code: "deposit", deposit_deadline: "on_site" }];
  const subs = confirmationSubstitutions(order);
  assert(subs.balanceReasoning.includes("na místě"));
  assert(subs.balanceReasoning.includes("500"));
});

function request(input: unknown, authorization = "Bearer user-jwt") {
  return new Request("https://example.invalid/preview", {
    method: "POST",
    headers: { Authorization: authorization },
    body: JSON.stringify(input),
  });
}
const valid = { draftId: "00000000-0000-4000-8000-000000000001", revision: 3 };

Deno.test("endpoint rejects unauthenticated requests and arbitrary hierarchy/template inputs", async () => {
  let calls = 0;
  const handler = previewHandler(async () => {
    calls++;
    return { data: context, error: null };
  });
  assert((await handler(request(valid, ""))).status === 401);
  assert((await handler(request({ ...valid, occasion: 2 }))).status === 400);
  assert((await handler(request({ ...valid, templateId: 5 }))).status === 400);
  assert((await handler(request({ ...valid, tone: "formal" }))).status === 400);
  assert(
    (await handler(request({ ...valid, replyTo: "override@example.invalid" })))
      .status === 400,
  );
  assert((await handler(request(null))).status === 400);
  assert((await handler(request([]))).status === 400);
  assert(calls === 0);
});

Deno.test("endpoint forwards user JWT and draft revision; denied/stale requests do not render", async () => {
  const handler = previewHandler(async (jwt, params) => {
    assert(jwt === "Bearer user-jwt");
    assert(params.p_id === valid.draftId && params.p_expected_revision === 3);
    return { data: context, error: null };
  });
  const response = await handler(request(valid));
  assert(
    response.status === 200 &&
      response.headers.get("Cache-Control") === "no-store",
  );
  assert((await response.json()).revision === 3);
  for (const [code, status] of [["42501", 403], ["PT409", 409], ["40001", 409], ["22023", 400], ["XX000", 503]] as const) {
    const denied = previewHandler(async () => ({
      data: null,
      error: { code, message: code === "40001" ? "Draft revision conflict" : undefined },
    }));
    assert((await denied(request(valid))).status === status);
  }
  let calls = 0;
  const serialization = previewHandler(async () => {
    calls++;
    return {data: null, error: {code: "40001", message: "could not serialize access due to concurrent update"}};
  });
  assert((await serialization(request(valid))).status === 503);
  assert(calls === 1);
});

Deno.test("preview reflects configured ticket/product content and retains authored email CSS", async () => {
  const context = { title: "Concert", tone: "formal", ticketsEnabled: true,
    sampleProducts: [{title:"Balcony",price:250,currency_code:"CZK"}],
    resolved:{template:{id:2,subject:"{{occasionTitle}}",html:'<style>h1{color:red}</style><h1 style="font-family:serif">{{occasionTitle}}</h1>{{fullOrder}}'},wrapper:{html:'<html><body style="background:white">{{content}}</body></html>'}} };
  const result = await renderDraftPreview(context);
  const sent = await renderEmail({to:"sample@example.invalid",context:{organization:1},substitutions:{...defaults,...confirmationSubstitutions(previewOrder(context.title,context.tone,context))}},async()=>context.resolved);
  assert(result.html === sent.html);
  assert(result.html.includes('<style>h1{color:red}</style>'));
  assert(result.html.includes('font-family:serif'));
  assert(result.html.includes('Balcony'));
  assert(previewOrder(context.title,context.tone,context).payment_info.amount===250);
  assert(previewOrder(context.title,context.tone,context).occasion.features[0].code==='ticket');
});

Deno.test('shared preview defaults and configured bank details render in full', async () => {
  const sample = previewOrder('Moje akce','formal',{
    sampleProducts:[{title:'Vstupné',price:725,currency_code:'CZK'}],
    paymentInfo:{account_number:'CZ6508000000192000145399',account_number_human_readable:'19-2000145399/0800'},
    deadlineDurationSeconds:3*86400,
  },new Date('2026-10-22T12:00:00Z'));
  assert(sample.payment_info.deadline==='2026-10-25T12:00:00.000Z');
  const values=confirmationSubstitutions(sample);
  assert(values.accountNumber==='19-2000145399/0800');
  assert(values.iban==='CZ65 0800 0000 1920 0014 5399');
  assert(values.variableSymbol===defaults.variableSymbol);
  assert(sample.payment_info.amount===725);
  const result=await renderDraftPreview({...context,paymentInfo:sample.payment_info,
    resolved:{template:{subject:'{{appName}} - {{occasionTitle}}',html:'{{accountNumber}} {{iban}} {{name}}'},wrapper:{html:'{{content}}'}}});
  assert(result.subject===defaults.appName+' - '+context.title);
  assert(result.html.includes('19-2000145399/0800')&&result.html.replace(/<[^>]*>/g,'').includes('CZ65 0800 0000 1920 0014 5399'));
  assert(result.html.includes(defaults.name));
});

Deno.test("draft catalog returns the same authorized templates and preview context", async () => {
  const emailTemplates = [{code:"TICKET_ORDER_CONFIRMATION", template:resolved.template, customized:true}];
  const emailScope = {unit:{id:1},organization:{id:3}};
  const preview = await renderDraftPreview({...context,emailTemplates,emailScope});
  assert(preview.emailTemplates === emailTemplates);
  assert(preview.emailScope === emailScope);
  assert(preview.authoringContext.senderAddress === (Deno.env.get("DEFAULT_EMAIL") || ""));
  assert(preview.authoringContext.wrapperHtml === resolved.wrapper.html);
  assert(preview.previewContext.title === context.title);
  assert(preview.previewContext.products[0].price === 1000);
});

Deno.test("ticket preview preserves catalog response and uses only synthetic inline admission QR", async () => {
  const result = await renderDraftPreview({ ...context, messageType: "order_tickets", deliveryMode: "inline_qr",
    ticketsEnabled: true, ticketFeature: { code: "ticket", is_enabled: true }, sampleTicketCount: 3,
    emailTemplates: [{code:"TICKET_ORDER_CONFIRMATION"}], emailScope: {unit:{id:1}} });
  assert(result.inlineImages.length === 3 && result.attachments.length === 0);
  assert((result.html.match(/<img /g) ?? []).length === 3);
  assert(!result.html.includes("festapp-preview:") && result.emailTemplates.length === 1);
  assert(result.html.includes("Kód vstupenky:") && result.html.includes("UKAZKA-001"));
  assert(result.html.includes("U vstupu ukažte tento QR kód."));
  assert(result.inlineImages[0].content === encodeAttachment(await qrPng("festapp-preview:UKAZKA-001"), "binary"),
    "Readable sample codes must never turn preview QR into valid admission identities");
  assert(result.emailScope.unit.id === 1);
  const disabled = await renderDraftPreview({ ...context, messageType: "order_tickets", deliveryMode: "inline_qr", ticketsEnabled: false });
  assert(disabled.inlineImages.length === 0 && disabled.attachments.length === 0);
});

Deno.test("PDF ticket preview displays a friendly sample attachment name", async () => {
  const result = await renderDraftPreview({
    ...context, messageType: "order_tickets", deliveryMode: "pdf_attachment",
    ticketsEnabled: true, ticketFeature: { code: "ticket", is_enabled: true },
    sampleTicketCount: 1,
  });
  assert(result.attachments.length === 1);
  assert(result.attachments[0].filename === "vstupenka-ukazka-1.pdf");
  assert(!JSON.stringify(result.attachments).includes("INVALID"));
});
Deno.test("existing-occasion preview forwards resource scope, and validates ticket options before context lookup", async () => {
  let calls=0;
  const handler=previewHandler(async(jwt,params)=>{
    calls++; assert(jwt==="Bearer user-jwt" && params.p_id===null && params.p_occasion===12);
    assert(params.p_message_type==="order_tickets" && params.p_delivery_mode==="inline_qr");
    return {data:{...context,messageType:"order_tickets",deliveryMode:"inline_qr",ticketsEnabled:true},error:null};
  });
  const response=await handler(request({occasionId:12,messageType:"order_tickets",deliveryMode:"inline_qr",sampleTicketCount:3}));
  assert(response.status===200 && (await response.json()).inlineImages.length===3);
  for(const bad of [{...valid,occasionId:12},{...valid,messageType:"other"},{...valid,sampleTicketCount:20},{...valid,deliveryMode:"bad"}]) {
    assert((await handler(request(bad))).status===400);
  }
  assert(calls===1);
});

Deno.test("draft banner appears in the preview and authoring wrapper without changing inheritance", async () => {
  const banner = "https://img.festapp.net/images/draft-banner.webp";
  const preview = await renderDraftPreview({...context, emailBanner: banner,
    inheritedEmailBanner: "https://img.festapp.net/images/inherited.webp"});
  assert(preview.html.includes(banner));
  assert(preview.authoringContext.wrapperHtml.includes(banner));
  assert(preview.inheritedEmailBanner.endsWith("inherited.webp"));
  assert(context.resolved.wrapper.html === "<main>{{content}}</main>");
});
