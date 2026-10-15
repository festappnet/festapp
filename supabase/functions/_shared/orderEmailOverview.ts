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
export function overviewEmailSubstitutions(url: string | null) {
  const safe = url ? escape(url) : '';
  return {
    order_overview_url: safe,
    order_overview_button: safe ? `<a href="${safe}" rel="noreferrer noopener" referrerpolicy="no-referrer">Přehled objednávky</a>` : '',
  };
}
export function includeOrderOverview(prepared: PreparedEmail, url: string | null) {
  if (!url) return prepared;
  const substitutions = overviewEmailSubstitutions(url);
  if (!prepared.html.includes(`href="${substitutions.order_overview_url}"`)) {
    const link = `<p>${substitutions.order_overview_button}</p>`;
    prepared.html = /<\/body>/i.test(prepared.html) ? prepared.html.replace(/<\/body>/i, `${link}</body>`) : prepared.html + link;
  }
  return prepared;
}
