import { ORDER_OVERVIEW_LINK_SLOT } from './orderOverview.ts';
import { openOrderOverviewUrl } from './customerOrderAccess.ts';
import { prepareOrderOverviewSource } from './waitlistEmail.ts';
import type { PreparedEmail } from './emailDelivery.ts';

export async function orderEmailOverviewUrl(
  row: { order_id: number; recipient: string; message_id: string },
  rpc: (name: string, params: Record<string, unknown>) => Promise<any>,
) {
  const params = { p_order_id: row.order_id, p_recipient: row.recipient, p_command_id: row.message_id };
  let context = await rpc('get_order_email_overview_source_v1', params);
  if (!context) return null;
  if (!context.source) {
    context = await rpc('get_order_email_overview_source_v1', {
      ...params, p_delivery: await prepareOrderOverviewSource(context),
    });
  }
  return context?.source ? await openOrderOverviewUrl(context, context.source) : null;
}
const escape = (value: string) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const overviewCopy = (lang: string) => lang === 'en'
  ? { action: 'View current order status', description: 'Check the current status of your order, payments and order history.' }
  : { action: 'Zobrazit aktuální stav objednávky', description: 'V přehledu najdete aktuální stav objednávky, platby a historii změn.' };
export function overviewEmailSubstitutions(url: string | null, lang = 'cs') {
  const safe = url ? escape(url) : '';
  return {
    order_overview_url: safe,
    order_overview_button: safe ? `<a href="${safe}" rel="noreferrer noopener" referrerpolicy="no-referrer" style="display:inline-block;padding:12px 18px;border-radius:6px;background:#1565c0;color:#ffffff;text-decoration:none;font-weight:600;line-height:1.4">${overviewCopy(lang).action}</a>` : '',
  };
}
export function includeOrderOverview(prepared: PreparedEmail, url: string | null, lang = 'cs') {
  const substitutions = overviewEmailSubstitutions(url, lang);
  if (url && !prepared.html.includes(`href="${substitutions.order_overview_url}"`)) {
    const link = `<div style="margin-top:24px;padding-top:20px;border-top:1px solid #e2e8f0;text-align:left"><p style="margin:0 0 12px;color:#475569;font-size:14px;line-height:1.5">${overviewCopy(lang).description}</p>${substitutions.order_overview_button}</div>`;
    prepared.html = prepared.html.includes(ORDER_OVERVIEW_LINK_SLOT)
      ? prepared.html.replace(ORDER_OVERVIEW_LINK_SLOT, link)
      : /<\/body>/i.test(prepared.html) ? prepared.html.replace(/<\/body>/i, `${link}</body>`) : prepared.html + link;
  }
  prepared.html = prepared.html.replaceAll(ORDER_OVERVIEW_LINK_SLOT, '');
  return prepared;
}
