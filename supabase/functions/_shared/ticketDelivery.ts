import QRCode from "npm:qrcode";
import type { EmailAttachment } from "./emailDelivery.ts";

export type TicketDeliveryMode = "pdf_attachment" | "inline_qr" | "both";
export function ticketDeliveryMode(feature: any): TicketDeliveryMode {
  if (!Object.hasOwn(feature ?? {}, "delivery_mode")) return "pdf_attachment";
  if (
    !["pdf_attachment", "inline_qr", "both"].includes(feature.delivery_mode)
  ) {
    throw new Error("invalid_ticket_delivery_mode");
  }
  return feature.delivery_mode;
}
export function escapeTicketText(value: unknown): string {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
}
/** Shared admission boundary: no PDF resources are needed to select tickets. */
export function issuableTickets(tickets: any[], occasionId: number) {
  const selected = (tickets ?? []).filter((t) =>
    !["storno", "waitlisted"].includes(t.state)
  )
    .sort((a, b) => Number(a.id) - Number(b.id));
  if (!selected.length) throw new Error("ticket_set_empty");
  const ids = new Set();
  for (const t of selected) {
    if (t.occasion != null && t.occasion !== occasionId) {
      throw new Error("ticket_cross_occasion");
    }
    if (
      !Number.isSafeInteger(t.id) || ids.has(t.id) ||
      typeof t.ticket_symbol !== "string" || !t.ticket_symbol.trim()
    ) {
      throw new Error("ticket_identity_invalid");
    }
    ids.add(t.id);
  }
  return selected;
}
export async function qrPng(symbol: string): Promise<Uint8Array> {
  return await QRCode.toBuffer(symbol, {
    type: "png",
    errorCorrectionLevel: "M",
    margin: 4,
    width: 256,
    color: { dark: "#000000ff", light: "#ffffffff" },
  });
}
/** No symbols or data-derived IDs are interpolated into the email markup. */
export async function inlineTicketBlock(
  symbols: string[],
  both = false,
  png = qrPng,
) {
  const attachments: EmailAttachment[] = [];
  // MIME Content-IDs are unique across messages; retries retain this in the snapshot.
  const messageId = crypto.randomUUID();
  let html = both
    ? "<p>QR v e-mailu a PDF v příloze patří ke stejné vstupence.</p>"
    : "";
  for (let i = 0; i < symbols.length; i++) {
    const contentId = `festapp-ticket-${messageId}-${
      i + 1
    }@tickets.festapp.net`;
    attachments.push({
      filename: `qr-${i + 1}.png`,
      content: await png(symbols[i]),
      contentType: "image/png",
      encoding: "binary",
      disposition: "INLINE",
      contentId,
    });
    const label = symbols.length > 1
      ? `QR ${i + 1} z ${symbols.length}`
      : "QR vstupenky";
    html += `${
      symbols.length > 1 ? `<p>${label}</p>` : ""
    }<p><img src="cid:${contentId}" alt="${label} - pro zobrazení povolte obrázky" width="256" height="256" style="display:block;width:256px;max-width:100%;height:auto;background:#ffffff" /></p>`;
  }
  return { html, attachments };
}
type PdfFactory = (
  occasion: any,
  ticket: any,
  order: any,
) => Promise<(ticket: any) => Promise<{ bytes: Uint8Array }>>;
export async function prepareTicketDelivery(
  occasion: any,
  order: any,
  raw: any[],
  pdf: PdfFactory,
  png = qrPng,
) {
  const tickets = issuableTickets(raw, occasion.id);
  const feature = occasion.features?.find((f: any) => f.code === "ticket");
  const attachments: EmailAttachment[] = [];
  let html = "";
  if (feature?.is_enabled) {
    const mode = ticketDeliveryMode(feature);
    if (mode !== "inline_qr") {
      const render = await pdf(occasion, tickets[0], order);
      for (const ticket of tickets) {
        const { bytes } = await render(ticket);
        attachments.push({
          filename: `ticket_${ticket.ticket_symbol}.pdf`,
          content: bytes,
          contentType: "application/pdf",
          encoding: "binary",
        });
      }
    }
    if (mode !== "pdf_attachment") {
      const inline = await inlineTicketBlock(
        tickets.map((t) => t.ticket_symbol),
        mode === "both",
        png,
      );
      attachments.push(...inline.attachments);
      html = inline.html;
    }
  }
  return { tickets, attachments, html };
}
