import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  type DeliverEmailInput,
  EmailTemplateNotFoundError,
  renderEmail,
} from "./emailDelivery.ts";
const input: DeliverEmailInput = {
  to: "fixture@example.invalid",
  from: "sender@example.invalid",
  replyTo: "reply@example.invalid",
  templateCode: "FIXTURE",
  context: { organization: 3, occasion: 7 },
  substitutions: { name: "Customer", code: "123456" },
};
Deno.test("canonical render uses the scoped existing template and authoritative wrapper", async () => {
  const result = await renderEmail(input, async (code, context) => {
    assertEquals(code, "FIXTURE");
    assertEquals(context, input.context);
    return {
      template: { id: 1, subject: "Hello {{name}}", html: "<p>{{code}}</p>" },
      wrapper: { html: "<main>{{content}}</main>" },
    };
  });
  assertEquals(result.subject, "Hello Customer");
  assertEquals(result.html, "<main><p>123456</p></main>");
  assertEquals(result.replyTo, input.replyTo);
  assertEquals(result.from, input.from);
});
Deno.test("editor snapshot receives the same wrapper and preserves exact links and layout", async () => {
  const html =
    '<a href="https://example.invalid/path?token=unchanged"> link </a>\n<table><tr><td>Layout</td></tr></table>';
  const result = await renderEmail(
    { ...input, template: { id: null, subject: "Editor {{name}}", html } },
    async () => ({
      template: { id: 1, subject: "Stored", html: "Stored" },
      wrapper: { html: "<main>{{content}}</main>" },
    }),
  );
  assertEquals(result.subject, "Editor Customer");
  assertEquals(result.html, `<main>${html}</main>`);
});
Deno.test("binary and base64 PDF attachments survive rendering without truncation", async () => {
  const result = await renderEmail(
    {
      ...input,
      attachments: Array.from(
        { length: 4 },
        (_, i) => ({
          filename: `ticket-${i}.pdf`,
          content: i % 2 ? "AQID" : new Uint8Array([1, 2, 3]),
          contentType: "application/pdf",
          encoding: i % 2 ? "base64" : "binary",
        }),
      ),
    },
    async () => ({ template: { id: 1, subject: "Tickets", html: "Tickets" } }),
  );
  assertEquals(result.attachments.length, 4);
  for (const attachment of result.attachments) {
    assertEquals(attachment.content, "AQID");
  }
});
Deno.test("missing or malformed template fails preparation before any transport", async () => {
  await assertRejects(
    () => renderEmail(input, async () => ({})),
    EmailTemplateNotFoundError,
  );
});

Deno.test("custom cancellation omits an overview action even inside a padded wrapper", async () => {
  const url = "https://example.invalid/order?preview=1";
  const action = `<a href="${url}">Status</a>`;
  const wrapper = '<html><body><table><tr><td style="padding:24px">{{content}}</td></tr></table></body></html>';
  const result = await renderEmail({
    ...input,
    template: { id: 1, subject: "Cancellation", html: "<p>Signature</p>" },
    requiredLinks: [{ url, html: action }],
  }, async () => ({ wrapper: { html: wrapper } }));
  assertEquals(result.html, wrapper.replace("{{content}}", "<p>Signature</p>"));
  assertEquals(Object.keys(result).includes("requiredLinks"), false);
});
Deno.test("wrapper link and order card slot determine action placement before signature", async () => {
  const url = "https://example.invalid/order?preview=1";
  const action = `<a href="${url}">Status</a>`;
  const html = '<section><!-- customer-order-overview-link --></section><p>Signature</p>';
  const render = (wrapper: string) => renderEmail({
    ...input, template: { id: 1, subject: "Order", html },
    requiredLinks: [{ url, html: action }],
  }, async () => ({ wrapper: { html: wrapper } }));
  assertEquals((await render('<main style="padding:24px">{{content}}</main>')).html,
    `<main style="padding:24px"><section>${action}</section><p>Signature</p></main>`);
  assertEquals((await render(`<main>{{content}}${action}</main>`)).html,
    `<main><section></section><p>Signature</p>${action}</main>`);
});

Deno.test("an explicitly authored overview button remains inside its wrapper", async () => {
  const url = "https://example.invalid/order?preview=1";
  const action = `<a href="${url}">Status</a>`;
  const wrapper = '<main style="padding:24px">{{content}}</main>';
  const result = await renderEmail({
    ...input, substitutions: { ...input.substitutions, order_overview_button: action },
    template: { id: 1, subject: "Cancellation", html: "<p>Signature</p>{{order_overview_button}}" },
    requiredLinks: [{ url, html: action }],
  }, async () => ({ wrapper: { html: wrapper } }));
  assertEquals(result.html, wrapper.replace("{{content}}", `<p>Signature</p>${action}`));
});
