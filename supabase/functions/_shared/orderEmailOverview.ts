import { openOrderOverviewUrl } from "./customerOrderAccess.ts";
import { prepareOrderOverviewSource } from "./waitlistEmail.ts";

export async function orderEmailOverviewUrl(
  row: { order_id: number; recipient: string; message_id: string },
  rpc: (name: string, params: Record<string, unknown>) => Promise<any>,
) {
  const params = {
    p_order_id: row.order_id,
    p_recipient: row.recipient,
    p_command_id: row.message_id,
  };
  let context = await rpc("get_order_email_overview_source_v1", params);
  if (!context) return null;
  if (!context.source) {
    context = await rpc("get_order_email_overview_source_v1", {
      ...params,
      p_delivery: await prepareOrderOverviewSource(context),
    });
  }
  if (!context?.source) return null;
  // SQL has checked the current recipient against both requested/root orders.
  // The reusable order capability retains its historical sealed contact; a
  // contact repair must not rewrite that evidence or rotate the existing link.
  // Keep verification of its tenant, root order, unit, token and content hash.
  const { recipient: _currentRecipient, ...orderContext } = context;
  return await openOrderOverviewUrl(orderContext, context.source);
}
export { overviewEmailSubstitutions } from "./emailActionLink.ts";
