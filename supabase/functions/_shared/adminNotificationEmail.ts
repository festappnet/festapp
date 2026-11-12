import type { PreparedEmail } from "./emailDelivery.ts";
import { emailRpc } from "./emailQueueClient.ts";
import { formatDisplayNumber } from "./numberFormatting.ts";

type Source = {
  organizationId: number;
  organizationTitle: string;
  occasionId: number | null;
  occasionTitle: string | null;
  occasionLink: string | null;
  webLink: string | null;
  orderId: number | null;
  bankAccountId?: number;
  unitId?: number;
  provider?: string;
  affectedOccasions?: { id: number; title: string; link: string }[];
};
type Item = Source & {
  key: string;
  kind: string;
  sources: Source[];
  facts: {
    count: number | null;
    amount?: number;
    currency?: string;
    reassigned?: boolean;
  };
};
export type DigestContext = {
  locale: string;
  address: string;
  fingerprint: string;
  items: Item[];
};
const escape = (value: unknown) =>
  String(value ?? "").slice(0, 500).replace(
    /[&<>"']/g,
    (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]!),
  );
const labels: Record<string, string[]> = {
  cs: [
    "Souhrn administrátorských oznámení",
    "Další změny",
    "Objednávky",
    "Stornované objednávky",
    "Přihlášky",
    "Čekací listina",
    "Problém bankovního spojení",
    "Problém doručování",
    "Platba vyžaduje pozornost",
    "Přijaté platby",
    "Změny",
    "Vstupenky",
    "Otevřít",
    "Přiřazení přijaté platby",
  ],
  en: [
    "Administration notification summary",
    "More changes",
    "Orders",
    "Cancelled orders",
    "Registrations",
    "Waiting list",
    "Bank connection problem",
    "Delivery problem",
    "Payment needs attention",
    "Payments received",
    "Changes",
    "Tickets",
    "Open",
    "Assignment of received payments",
  ],
  de: [
    "Zusammenfassung der Verwaltungsmitteilungen",
    "Weitere Änderungen",
    "Bestellungen",
    "Stornierte Bestellungen",
    "Anmeldungen",
    "Warteliste",
    "Problem mit der Bankverbindung",
    "Zustellungsproblem",
    "Zahlung erfordert Aufmerksamkeit",
    "Eingegangene Zahlungen",
    "Änderungen",
    "Eintrittskarten",
    "Öffnen",
    "Zuordnung eingegangener Zahlungen",
  ],
  pl: [
    "Podsumowanie powiadomień administracyjnych",
    "Dalsze zmiany",
    "Zamówienia",
    "Anulowane zamówienia",
    "Zgłoszenia",
    "Lista oczekujących",
    "Problem połączenia bankowego",
    "Problem doręczenia",
    "Płatność wymaga uwagi",
    "Otrzymane płatności",
    "Zmiany",
    "Bilety",
    "Otwórz",
    "Przypisanie otrzymanych płatności",
  ],
  sk: [
    "Súhrn administrátorských oznámení",
    "Ďalšie zmeny",
    "Objednávky",
    "Stornované objednávky",
    "Prihlášky",
    "Čakacia listina",
    "Problém bankového spojenia",
    "Problém doručovania",
    "Platba vyžaduje pozornosť",
    "Prijaté platby",
    "Zmeny",
    "Vstupenky",
    "Otvoriť",
    "Priradenie prijatej platby",
  ],
  uk: [
    "Підсумок адміністративних сповіщень",
    "Інші зміни",
    "Замовлення",
    "Скасовані замовлення",
    "Реєстрації",
    "Список очікування",
    "Проблема банківського з’єднання",
    "Проблема доставки",
    "Платіж потребує уваги",
    "Отримані платежі",
    "Зміни",
    "Квитки",
    "Відкрити",
    "Призначення отриманих платежів",
  ],
};
const kindIndex: Record<string, number> = {
  order_created: 2,
  order_cancelled: 3,
  occasion_joined: 4,
  waitlist_registered: 5,
  provider_problem: 14,
  bank_problem: 6,
  email_problem: 7,
  payment_problem: 8,
  order_payment_received: 9,
};
function detailUrl(source: Source): string | null {
  if (!source.webLink) return null;
  try {
    const url = new URL(source.webLink);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    if (source.unitId != null && source.provider != null) {
      url.pathname = `/unit/${encodeURIComponent(source.unitId)}/edit`;
      url.search = "";
    } else if (source.unitId != null && source.bankAccountId != null) {
      url.pathname = `/unit/${
        encodeURIComponent(source.unitId)
      }/edit/bank-accounts/${
        encodeURIComponent(source.bankAccountId)
      }/connection`;
      url.search = "";
    } else if (source.occasionLink) {
      url.pathname = `/${
        encodeURIComponent(source.occasionLink)
      }/reservations/orders/current`;
      url.search = source.orderId == null
        ? ""
        : new URLSearchParams({ orderId: String(source.orderId) }).toString();
    } else {
      url.pathname = "/";
      url.search = "";
    }
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}
/** Presentation only: the SQL context owns facts, privacy and membership. */
export function adminNotificationEmail(
  context: DigestContext,
  from: string,
): PreparedEmail {
  const providerLabels: Record<string, string> = {
    cs: "Problém platební brány", en: "Payment gateway problem", de: "Problem mit dem Zahlungsanbieter",
    pl: "Problem z bramką płatniczą", sk: "Problém platobnej brány", uk: "Проблема платіжного шлюзу",
  };
  const words = [...(labels[context.locale] ?? labels.en), providerLabels[context.locale] ?? providerLabels.en];
  const groups = new Map<string, Item[]>();
  for (const item of context.items) {
    const key = JSON.stringify([item.organizationId, item.occasionId]);
    groups.set(key, [...(groups.get(key) ?? []), item]);
  }
  let remaining = 100, omitted = 0, htmlBytes = 0;
  let overflowLink: string | null = null;
  const encoder = new TextEncoder();
  const sections: string[] = [];
  for (const items of groups.values()) {
    if (remaining <= 0) {
      omitted += items.length;
      overflowLink ??= detailUrl(items[0]);
      continue;
    }
    const [first] = items;
    const rows = items.slice(0, remaining);
    remaining -= rows.length;
    omitted += items.length - rows.length;
    const counts = new Map<string, Item[]>();
    for (const item of rows) {
      const category =
        item.kind === "order_payment_received" && item.facts.reassigned
          ? item.kind + ":assigned"
          : item.kind;
      counts.set(category, [...(counts.get(category) ?? []), item]);
    }
    const summary = [...counts].map(([kind, entries]) => {
      const ticketCount = entries.every((item) => item.facts.count != null)
        ? entries.reduce((sum, item) => sum + item.facts.count!, 0)
        : null;
      const currencies = new Map<string, number>();
      for (const item of entries) {
        if (item.facts.currency && typeof item.facts.amount === "number") {
          currencies.set(
            item.facts.currency,
            (currencies.get(item.facts.currency) ?? 0) + item.facts.amount,
          );
        }
      }
      const amounts = [...currencies].map(([currency, amount]) =>
        escape(
          formatDisplayNumber(amount, context.locale, {
            style: "currency",
            currency,
          }),
        )
      ).join(", ");
      const links = entries.flatMap((item) => item.sources ?? [item])
        .flatMap((source) =>
          source.unitId != null || source.occasionLink ||
            !source.affectedOccasions?.length
            ? [source]
            : source.affectedOccasions.map((occasion) => ({
              ...source,
              occasionId: occasion.id,
              occasionTitle: occasion.title,
              occasionLink: occasion.link,
            }))
        ).map(
          (source) => {
            const url = detailUrl(source);
            return url
              ? `<a href="${escape(url)}">${
                escape(
                  `${source.organizationTitle}: ${
                    source.occasionTitle ?? source.provider ?? words[12]
                  }`,
                )
              }</a>`
              : "";
          },
        ).filter(Boolean);
      return `<li>${
        escape(
          kind === "order_payment_received:assigned"
            ? words[13]
            : words[kindIndex[kind] ?? 10],
        )
      }: ${formatDisplayNumber(entries.length, context.locale)}${
        ticketCount != null && ticketCount > 0 &&
          ["order_created", "order_cancelled", "waitlist_registered"].includes(
            kind,
          )
          ? ` (${escape(words[11])}: ${
            formatDisplayNumber(ticketCount, context.locale)
          })`
          : ""
      }${amounts ? ` - ${amounts}` : ""}${
        links.length
          ? `<br>${[...new Set(links)].slice(0, 10).join(" · ")}`
          : ""
      }</li>`;
    }).join("");
    const section = `<section><h2>${escape(first.organizationTitle)}</h2>${
      first.occasionTitle ? `<h3>${escape(first.occasionTitle)}</h3>` : ""
    }<ul>${summary}</ul></section>`;
    const size = encoder.encode(section).length;
    if (htmlBytes + size > 48_000) {
      omitted += rows.length;
      overflowLink ??= detailUrl(first);
    } else {
      sections.push(section);
      htmlBytes += size;
    }
  }
  return {
    from: `Festapp <${from}>`,
    to: context.address,
    subject: words[0],
    html: `<html><body><h1>${escape(words[0])}</h1>${sections.join("")}${
      omitted
        ? `<p>${escape(words[1])}: ${
          formatDisplayNumber(omitted, context.locale)
        }${
          overflowLink
            ? ` <a href="${escape(overflowLink)}">${escape(words[12])}</a>`
            : ""
        }</p>`
        : ""
    }</body></html>`,
    replyTo: from,
    attachments: [],
  };
}
export async function renderAdminNotificationEmail(
  row: {
    data: { dispatchId: string };
    recipient: string;
    recipient_user: string;
  },
) {
  const context: DigestContext = await emailRpc(
    "get_notification_center_email_context",
    { p_dispatch: row.data.dispatchId, p_recipient: row.recipient_user },
  );
  if (
    !context || context.address !== row.recipient || context.items.length === 0
  ) throw new Error("notification_context_unavailable");
  return {
    prepared: adminNotificationEmail(
      context,
      Deno.env.get("DEFAULT_EMAIL") ?? "",
    ),
    postAction: {
      notification_fingerprint: context.fingerprint,
      tracking_policy: "disabled",
    },
  };
}
