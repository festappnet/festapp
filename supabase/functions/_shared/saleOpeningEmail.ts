import { saleOpeningSubstitutions, saleOpeningUrl } from './saleOpeningPresentation.ts';
import { openEmail } from './emailPayload.ts';
import { emailRpc } from './emailQueueClient.ts';
import { type DeliverEmailInput, renderEmail, type PreparedEmail } from './emailDelivery.ts';
import { emailPayloadHash } from './emailPayload.ts';

type Context = {organization: number; occasion: number; unit: number; recipient: string; occasionTitle: string; formLink: string; webLink: string; lang: string; hasTickets?: boolean; tone?: string; replyTo?: string; capabilities: Record<string,{hash: string; envelope: Record<string,string>}>};
type Row = {message_id: string; message_kind: string; recipient: string; organization: number; occasion: number; unit: number};
export async function renderSaleOpeningEmail(row: Row, dependencies: {
 context?: (id: string) => Promise<Context>;
 open?: (value: Record<string,string>) => Promise<{token: string}>;
 render?: (input: DeliverEmailInput) => Promise<PreparedEmail>;
} = {}) {
 const context = await (dependencies.context ?? (id => emailRpc('get_sale_opening_email_context', {p_message: id})))(row.message_id);
 if (context.organization !== row.organization || context.occasion !== row.occasion || context.unit !== row.unit || context.recipient !== row.recipient) throw new Error('sale_opening_scope_invalid');
 if (row.message_kind !== 'sale_opening_opened') throw new Error('sale_opening_kind_invalid');
 const link = async (purpose: string) => {
  const cap = context.capabilities[purpose]; if (!cap) throw new Error('sale_opening_capability_missing');
  const source = await (dependencies.open ?? openEmail<{token: string}>)(cap.envelope);
  if (!/^[0-9a-f]{64}$/.test(source.token) || await emailPayloadHash(source.token) !== cap.hash) throw new Error('sale_opening_capability_invalid');
  return saleOpeningUrl(context.webLink, context.formLink, purpose, source.token);
 };
 const unsubscribe = await link('unsubscribe');
 const action = saleOpeningUrl(context.webLink, context.formLink);
 return {prepared: await (dependencies.render ?? renderEmail)({to: row.recipient, templateCode: row.message_kind,
 context: {organization: row.organization, occasion: row.occasion, unit: row.unit}, replyTo: context.replyTo,
 subjectSubstitutions: {...saleOpeningSubstitutions(context.lang, context.occasionTitle, action, unsubscribe, {hasTickets: context.hasTickets, tone: context.tone}), occasion_title: context.occasionTitle},
 substitutions: saleOpeningSubstitutions(context.lang, context.occasionTitle, action, unsubscribe, {hasTickets: context.hasTickets, tone: context.tone})}),
 postAction: {tracking_policy: 'disabled'}};
}
