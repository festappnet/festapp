/** Pure presentation shared by delivery and build-time editor examples. */
export const escapeEmailHtml = (value: unknown) =>
  String(value ?? "").replaceAll("&", "&amp;").replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("'", "&#39;");
export type OverviewAction = { operation: string; enabled: boolean };
const available = (
  actions: OverviewAction[],
) => [
  ...new Set(
    actions.filter((a) =>
      a.enabled === true && ["cancel", "move"].includes(a.operation)
    ).map((a) => a.operation),
  ),
];
export function overviewCopy(lang: string, actions: OverviewAction[] = []) {
  const en = lang === "en", ops = available(actions);
  const names: Record<string, string> = en
    ? {
      cancel: "request cancellation",
      move: "request a date change",
    }
    : {
      cancel: "požádat o storno",
      move: "požádat o změnu termínu",
    };
  const labels = ops.map((op) => names[op]);
  const list = labels.length < 2
    ? labels[0]
    : `${labels.slice(0, -1).join(", ")} ${en ? "and" : "a"} ${labels.at(-1)}`;
  return {
    action: en
      ? "View current order status"
      : "Zobrazit aktuální stav objednávky",
    description: en
      ? "Check the current status of your order, payments and order history."
      : "V přehledu najdete aktuální stav objednávky, platby a historii změn.",
    changes: ops.length
      ? (en
        ? `You can also ${list}, subject to the organizer’s current rules.`
        : `Podle aktuálních pravidel pořadatele zde můžete také ${list}.`)
      : "",
  };
}
function button(url: string, lang: string) {
  return `<a href="${
    escapeEmailHtml(url)
  }" rel="noreferrer noopener" referrerpolicy="no-referrer" style="display:inline-block;padding:12px 18px;border-radius:6px;background:#1565c0;color:#ffffff;text-decoration:none;font-weight:600;line-height:1.4">${
    overviewCopy(lang).action
  }</a>`;
}
const companion = (changes: string) =>
  changes
    ? `<p data-festapp-order-changes="1" style="margin:0 0 12px;color:#475569;font-size:14px;line-height:1.5">${
      escapeEmailHtml(changes)
    }</p>`
    : "";
export function overviewEmailSubstitutions(
  url: string | null,
  lang = "cs",
  actions: OverviewAction[] = [],
) {
  return {
    order_overview_url: url ?? "",
    order_overview_button: url
      ? `${companion(overviewCopy(lang, actions).changes)}${button(url, lang)}`
      : "",
  };
}
export function overviewRequiredLinks(
  url: string | null,
  lang = "cs",
  actions: OverviewAction[] = [],
) {
  if (!url) return [];
  const copy = overviewCopy(lang, actions);
  const changes = companion(copy.changes);
  return [{
    url,
    companionHtml: changes,
    companionMarker: "data-festapp-order-changes",
    html:
      `<div style="margin-top:24px;padding-top:20px;border-top:1px solid #e2e8f0;text-align:left"><p style="margin:0 0 12px;color:#475569;font-size:14px;line-height:1.5">${copy.description}</p>${changes}${
        button(url, lang)
      }</div>`,
  }];
}
/** Arguments are already escaped by the producer, as before extraction. */
export function waitlistActionLink(href: string, label: string) {
  return `<a href="${href}" rel="noreferrer noopener" referrerpolicy="no-referrer" style="display:inline-block;padding:12px 20px;background:#1565c0;color:#ffffff;text-decoration:none;border-radius:6px">${label}</a>`;
}
