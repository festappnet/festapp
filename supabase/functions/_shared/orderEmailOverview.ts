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
export { overviewEmailSubstitutions } from './emailActionLink.ts';
import { overviewRequiredLinks } from './emailActionLink.ts';
import { completeEmailContent } from './emailContentCompletion.ts';
export function includeOrderOverview(prepared: PreparedEmail, url: string | null, lang = 'cs') {
  prepared.html = completeEmailContent(prepared.html, overviewRequiredLinks(url, lang));
  return prepared;
}
