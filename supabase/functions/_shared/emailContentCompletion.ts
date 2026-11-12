import { ORDER_OVERVIEW_LINK_SLOT } from "./orderOverview.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";
export interface EmailRequiredLink {
  url: string;
  html: string;
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
  const paymentSlot = "<!--festapp-payment-action-->", authoredSlot = "{{paymentAction}}";
  html = html.replaceAll(authoredSlot, paymentSlot);
  if (html.includes(paymentSlot)) {
    if (paymentAction && !html.includes(paymentAction)) html = html.replace(paymentSlot, paymentAction);
    html = html.replaceAll(paymentSlot, "");
  }
  for (const link of links) {
    if (!link.url || html.includes(`href="${escapeEmailHtml(link.url)}"`) ||
      !html.includes(ORDER_OVERVIEW_LINK_SLOT)) {
      continue;
    }
    html = html.replace(ORDER_OVERVIEW_LINK_SLOT, link.html);
  }
  return html.replaceAll(ORDER_OVERVIEW_LINK_SLOT, "");
}
