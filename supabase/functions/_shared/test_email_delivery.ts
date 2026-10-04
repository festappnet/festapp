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
