import { ORDER_OVERVIEW_LINK_SLOT } from "./orderOverview.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";
export interface EmailRequiredLink {
  url: string;
  html: string;
  companionHtml?: string;
  companionMarker?: string;
}
export type EmailPaymentQrBlock = {
  html: string;
  paymentDetails: string[];
};

const paymentQrSlot = "<!--festapp-payment-qr-->";

/** Fill authored action slots, and place any server-issued payment QR. */
export function completeEmailContent(
  html: string,
  links: EmailRequiredLink[],
  wrapperHtml?: string | null,
  paymentAction = "",
  paymentQr?: EmailPaymentQrBlock,
): string {
  if (paymentQr) html += paymentQrSlot;
  if (wrapperHtml) {
    html = wrapperHtml.replace("{{content}}", () => html);
  }
  const paymentSlot = "<!--festapp-payment-action-->",
    authoredSlot = "{{paymentAction}}";
  html = html.replaceAll(authoredSlot, paymentSlot);
  if (html.includes(paymentSlot)) {
    if (paymentAction && !html.includes(paymentAction)) {
      html = html.replace(paymentSlot, () => paymentAction);
    }
    html = html.replaceAll(paymentSlot, "");
  }
  if (paymentQr) {
    const details = [paymentAction, ...paymentQr.paymentDetails].find(
      (candidate) => candidate && html.includes(candidate),
    );
    if (details) {
      const afterDetails = html.indexOf(details) + details.length;
      html = html.slice(0, afterDetails) + paymentQr.html +
        html.slice(afterDetails);
    } else if (html.includes(paymentQrSlot)) {
      html = html.replace(paymentQrSlot, () => paymentQr.html);
    } else {
      html += paymentQr.html;
    }
    html = html.replaceAll(paymentQrSlot, "");
  }
  for (const link of links) {
    // Preserve authored content and its one existing button. Add only the
    // server-derived companion if the author used a raw overview URL.
    const anchor = `href="${escapeEmailHtml(link.url)}"`;
    if (
      link.companionHtml && link.companionMarker &&
      !html.includes(link.companionMarker) && html.includes(anchor)
    ) {
      const index = html.lastIndexOf("<a", html.indexOf(anchor));
      if (index >= 0) {
        html = html.slice(0, index) + link.companionHtml + html.slice(index);
      }
    }
    if (
      !link.url || html.includes(`href="${escapeEmailHtml(link.url)}"`) ||
      !html.includes(ORDER_OVERVIEW_LINK_SLOT)
    ) {
      continue;
    }
    html = html.replace(ORDER_OVERVIEW_LINK_SLOT, link.html);
  }
  return html.replaceAll(ORDER_OVERVIEW_LINK_SLOT, "");
}

export function paymentQrEmailHtml(
  cs: boolean,
  source?: string,
  informal = false,
): string {
  if (source === undefined) {
    const notice = cs
      ? informal ? "Platební QR kód najdeš v příloze." : "Platební QR kód najdete v příloze."
      : "The payment QR code is in the attachment.";
    return `<p style="margin:16px 0">${notice}</p>`;
  }
  const alt = cs
    ? "QR kód pro platbu bankovním převodem"
    : "Bank transfer QR code";
  const title = cs
    ? informal ? "Zaplať pomocí QR kódu" : "Zaplaťte pomocí QR kódu"
    : "Pay with the QR code";
  const scanInstructions = cs
    ? informal
      ? "Naskenuj ho v aplikaci mobilního bankovnictví."
      : "Naskenujte ho v aplikaci mobilního bankovnictví."
    : "Scan it in your mobile banking app.";
  const hint = cs
    ? informal
      ? "QR kód si můžeš stáhnout z přílohy."
      : "QR kód si můžete stáhnout z přílohy."
    : "You can download the QR code from the attachment.";
  return `<div style="margin:16px 0"><p style="margin:0 0 4px;font-size:18px;font-weight:bold">${title}</p><p style="margin:0 0 8px">${scanInstructions}</p><img src="${escapeEmailHtml(source)}" alt="${alt}" width="280" style="display:block;width:280px;max-width:100%;height:auto;border-radius:8px;background:#ffffff"><p style="margin:8px 0 0">${hint}</p></div>`;
}
