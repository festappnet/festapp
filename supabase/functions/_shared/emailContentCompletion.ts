import { ORDER_OVERVIEW_LINK_SLOT } from "./orderOverview.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";
export interface EmailRequiredLink {
  url: string;
  html: string;
}
/** Complete authored content inside its wrapper, preserving explicit slots/links. */
export function completeEmailContent(
  html: string,
  links: EmailRequiredLink[],
  wrapperHtml?: string | null,
): string {
  if (wrapperHtml) {
    const wrapped = wrapperHtml.replace("{{content}}", html);
    if (
      wrapperHtml.includes("{{content}}") &&
      !wrapped.includes(ORDER_OVERVIEW_LINK_SLOT) &&
      links.some((link) => link.url &&
        !wrapped.includes(`href="${escapeEmailHtml(link.url)}"`))
    ) {
      // A fallback action belongs to the padded content, never outside it.
      html = /<\/body>/i.test(html)
        ? html.replace(/<\/body>/i, `${ORDER_OVERVIEW_LINK_SLOT}</body>`)
        : html + ORDER_OVERVIEW_LINK_SLOT;
    }
    html = wrapperHtml.replace("{{content}}", html);
  }
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
