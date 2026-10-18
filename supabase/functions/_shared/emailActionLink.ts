/** Pure presentation shared by delivery and build-time editor examples. */
export const escapeEmailHtml = (value: string) =>
  value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll(
    "<",
    "&lt;",
  ).replaceAll(">", "&gt;");
const overviewCopy = (lang: string) =>
  lang === "en"
    ? {
      action: "View current order status",
      description:
        "Check the current status of your order, payments and order history.",
    }
    : {
      action: "Zobrazit aktuální stav objednávky",
      description:
        "V přehledu najdete aktuální stav objednávky, platby a historii změn.",
    };
export function overviewEmailSubstitutions(url: string | null, lang = "cs") {
  const safe = url ? escapeEmailHtml(url) : "";
  return {
    order_overview_url: safe,
    order_overview_button: safe
      ? `<a href="${safe}" rel="noreferrer noopener" referrerpolicy="no-referrer" style="display:inline-block;padding:12px 18px;border-radius:6px;background:#1565c0;color:#ffffff;text-decoration:none;font-weight:600;line-height:1.4">${
        overviewCopy(lang).action
      }</a>`
      : "",
  };
}
export function overviewRequiredLinks(url: string | null, lang = "cs") {
  if (!url) return [];
  return [{
    url,
    html:
      `<div style="margin-top:24px;padding-top:20px;border-top:1px solid #e2e8f0;text-align:left"><p style="margin:0 0 12px;color:#475569;font-size:14px;line-height:1.5">${
        overviewCopy(lang).description
      }</p>${
        overviewEmailSubstitutions(url, lang).order_overview_button
      }</div>`,
  }];
}
/** Arguments are already escaped by the producer, as before extraction. */
export function waitlistActionLink(href: string, label: string) {
  return `<a href="${href}" rel="noreferrer noopener" referrerpolicy="no-referrer" style="display:inline-block;padding:12px 20px;background:#1565c0;color:#ffffff;text-decoration:none;border-radius:6px">${label}</a>`;
}
