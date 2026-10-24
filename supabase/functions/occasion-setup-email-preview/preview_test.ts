import { previewOrder, renderDraftPreview } from "./content.ts";
import { confirmationSubstitutions } from "../_shared/confirmationContent.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";
import { previewHandler } from "./handler.ts";

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
    substitutions: confirmationSubstitutions(
      previewOrder(context.title, context.tone),
    ),
    replyTo: context.replyTo,
  }, () => Promise.resolve(resolved));
  assert(preview.html === sent.html && preview.subject === sent.subject);
  assert(preview.replyTo === sent.replyTo);
  assert(preview.html.startsWith("<main><p>Vlastní text</p>"));
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
  assert(confirmationSubstitutions(order).variableSymbol === "");
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
  assert((await handler(request({ ...valid, tone: "other" }))).status === 400);
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
  for (const [code, status] of [["42501", 403], ["40001", 409]] as const) {
    const denied = previewHandler(async () => ({
      data: null,
      error: { code },
    }));
    assert((await denied(request(valid))).status === status);
  }
});

Deno.test("ticket preview modes use the shared QR block, leave confirmation separate, and accept only explicit samples", async () => {
  for (const deliveryMode of ["inline_qr", "both", "pdf_attachment"]) {
    // No PDF resources are involved in inline mode. PDF generation is covered by ticket renderer contracts.
    if (deliveryMode !== "inline_qr") continue;
    const preview = await renderDraftPreview({
      ...context,
      messageType: "order_tickets",
      deliveryMode,
      ticketEnabled: true,
      ticketFeature: { code: "ticket", is_enabled: true },
      sampleTicketCount: 3,
    });
    assert(
      preview.inlineImages.length === 3 && preview.attachments.length === 0,
    );
    assert((preview.html.match(/<img /g) ?? []).length === 3);
    assert(
      preview.html.includes("<main>") &&
        !preview.html.includes("festapp-preview:"),
    );
  }
  const handler = previewHandler(async (_jwt, params) => {
    assert(params.p_occasion === 12 && params.p_id === null);
    assert(
      params.p_message_type === "order_tickets" &&
        params.p_delivery_mode === "inline_qr",
    );
    return {
      data: {
        ...context,
        messageType: "order_tickets",
        deliveryMode: "inline_qr",
        ticketFeature: { code: "ticket", is_enabled: true },
      },
      error: null,
    };
  });
  const response = await handler(
    request({
      occasionId: 12,
      messageType: "order_tickets",
      deliveryMode: "inline_qr",
      sampleTicketCount: 3,
    }),
  );
  assert(
    response.status === 200 &&
      (await response.json()).inlineImages.length === 3,
  );
  for (
    const input of [
      { ...valid, messageType: "other" },
      { ...valid, sampleTicketCount: 20 },
      { ...valid, deliveryMode: "bad" },
      { ...valid, occasionId: 12 },
    ]
  ) assert((await handler(request(input))).status === 400);
  const disabled = await renderDraftPreview({
    ...context,
    messageType: "order_tickets",
    deliveryMode: "inline_qr",
    ticketFeature: { is_enabled: false },
  });
  assert(
    disabled.inlineImages.length === 0 && disabled.attachments.length === 0,
  );
});
