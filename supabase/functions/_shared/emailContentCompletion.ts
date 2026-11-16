import { ORDER_OVERVIEW_LINK_SLOT } from "./orderOverview.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";
export interface EmailRequiredLink {
  url: string;
  html: string;
  companionHtml?: string;
  companionMarker?: string;
}
/** Fill authored overview slots only; an omitted action stays omitted. */
export function completeEmailContent(
  html: string,
  links: EmailRequiredLink[],
  wrapperHtml?: string | null,
  paymentAction = "",
): string {
  if (wrapperHtml) {
    html = wrapperHtml.replace("{{content}}", html);
  }
  const paymentSlot = "<!--festapp-payment-action-->",
    authoredSlot = "{{paymentAction}}";
  html = html.replaceAll(authoredSlot, paymentSlot);
  if (html.includes(paymentSlot)) {
    if (paymentAction && !html.includes(paymentAction)) {
      html = html.replace(paymentSlot, paymentAction);
    }
    html = html.replaceAll(paymentSlot, "");
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
