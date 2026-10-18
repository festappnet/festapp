import { ORDER_OVERVIEW_LINK_SLOT } from "./orderOverview.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";
export interface EmailRequiredLink {
  url: string;
  html: string;
}
/** Preserve delivery's slot, exact href detection and body/fragment fallback. */
export function completeEmailContent(
  html: string,
  links: EmailRequiredLink[],
): string {
  for (const link of links) {
    if (!link.url || html.includes(`href="${escapeEmailHtml(link.url)}"`)) {
      continue;
    }
    html = html.includes(ORDER_OVERVIEW_LINK_SLOT)
      ? html.replace(ORDER_OVERVIEW_LINK_SLOT, link.html)
      : /<\/body>/i.test(html)
      ? html.replace(/<\/body>/i, `${link.html}</body>`)
      : html + link.html;
  }
  return html.replaceAll(ORDER_OVERVIEW_LINK_SLOT, "");
}
