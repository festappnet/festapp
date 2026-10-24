import { paidEmailSubstitutions } from "../../supabase/functions/_shared/paidEmailContent.ts";
/** Private stdin/stdout adapter for the disposable SQL rehearsal, never an Edge endpoint. */
import {
  escapeTicketText,
  prepareTicketDelivery,
} from "../../supabase/functions/_shared/ticketDelivery.ts";
import {
  type PreparedEmail,
  renderEmail,
} from "../../supabase/functions/_shared/emailDelivery.ts";
import {
  openEmail,
  sealEmail,
} from "../../supabase/functions/_shared/emailPayload.ts";
import {
  sendSes,
  type SesConfig,
} from "../../supabase/functions/_shared/sesProvider.ts";
const input = JSON.parse(await new Response(Deno.stdin.readable).text());
const config: SesConfig = {
  sender: "sender@example.invalid",
  region: "eu-central-1",
  accessKey: "stub",
  secretKey: "stub",
  transactionalSet: "test",
  securitySet: "test",
  maxBytes: 30_000_000,
};
Deno.env.set("EMAIL_PAYLOAD_KEY", btoa("t".repeat(32)));
if (input.action === "prepare") {
  const { order, occasion, reply_to } = input.details.data;
  const delivery = await prepareTicketDelivery(
    occasion,
    order.data,
    input.tickets,
    async (...args) => {
      const { prepareTicketRenderer, loadLayoutResources } = await import(
        "../../supabase/functions/_shared/ticketGeneration.ts"
      );
      return await prepareTicketRenderer(...args, {
        load: loadLayoutResources,
        products: async () => input.products,
      });
    },
  );
  const prepared = await renderEmail({
    from: config.sender,
    to: input.recipient,
    replyTo: reply_to ?? config.sender,
    context: {
      organization: occasion.organization,
      occasion: occasion.id,
      unit: occasion.unit,
    },
    templateCode: "TICKET_ORDER_PAYMENT_DONE",
    attachments: delivery.attachments,
    ticketBlock: delivery.html,
    substitutions: {
      ...paidEmailSubstitutions(input.details.data),
      occasionTitle: escapeTicketText(occasion.title),
      orderSymbol: escapeTicketText(order.order_symbol),
    },
    subjectSubstitutions: {
      occasionTitle: occasion.title,
      orderSymbol: order.order_symbol,
    },
  }, async () => input.resolved);
  const snapshot = await sealEmail(prepared);
  console.log(
    JSON.stringify({
      snapshot,
      postAction: { ticket_ids: delivery.tickets.map((t) => t.id) },
    }),
  );
} else if (input.action === "send") {
  const prepared = await openEmail<PreparedEmail>(input.snapshot);
  let calls = 0;
  const provider = await sendSes(
    prepared,
    config,
    {},
    false,
    async (_url, init) => {
      calls++;
      const message = JSON.parse(String(init?.body)).Content.Simple;
      const pngs = message.Attachments.filter((a: any) =>
        a.ContentDisposition === "INLINE"
      );
      const pdfs = message.Attachments.filter((a: any) =>
        a.ContentType === "application/pdf"
      );
      if (
        pngs.length !== (input.mode === "pdf_attachment" ? 0 : 2) ||
        pdfs.length !== (input.mode === "inline_qr" ? 0 : 2)
      ) {
        throw new Error("rehearsal_attachment_mismatch");
      }
      for (
        const png of pngs
      ) {
        if (!prepared.html.includes(`cid:${png.ContentId}`)) {
          throw new Error("rehearsal_cid_mismatch");
        }
      }
      return Response.json({ MessageId: `stub-${crypto.randomUUID()}` });
    },
  );
  let html = prepared.html;
  for (const a of prepared.attachments) {
    if (a.disposition === "INLINE") {
      html = html.replaceAll(
        `cid:${a.contentId}`,
        `data:image/png;base64,${a.content}`,
      );
    }
  }
  console.log(
    JSON.stringify({
      provider,
      calls,
      html,
      pdfCount: prepared.attachments.filter((a) =>
        a.contentType === "application/pdf"
      ).length,
    }),
  );
} else throw new Error("invalid_rehearsal_action");
