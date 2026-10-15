import { prepareAccountEmail } from "./emailQueueClient.ts";
import type { WaitlistEmailContext } from "./waitlistEmail.ts";

export async function prepareOrderOverviewEmail(context: WaitlistEmailContext & { orderSymbol: string }, url: string, prepare = prepareAccountEmail) {
  const escape = (value: string) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
  return await prepare({
    to: context.recipient, templateCode: "ORDER_OVERVIEW",
    context: { organization: context.organization, occasion: context.occasion, unit: context.unit },
    substitutions: { occasion_title: escape(context.occasionTitle), order_symbol: escape(context.orderSymbol),
      order_overview_url: escape(url), order_overview_button: `<a href="${escape(url)}" rel="noreferrer noopener" referrerpolicy="no-referrer">Přehled objednávky</a>` },
  });
}
