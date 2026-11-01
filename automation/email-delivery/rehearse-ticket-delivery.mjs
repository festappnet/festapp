/** Run with pnpm exec node from web_client; requires an already prepared disposable DB. */
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { assertLocalDatabaseUrl, assertDisposableDatabase } from '../../web_client/tests/database/disposable_database.js';
const root = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(new URL('../../web_client/package.json', import.meta.url));
const { Client } = require('pg');
const url = new URL(process.env.DATABASE_URL ?? 'invalid:');
assertLocalDatabaseUrl(url.href);
const db = new Client({ connectionString: url.href });
const output = process.env.TICKET_EMAIL_PREVIEW_DIR ?? '/tmp/festapp-ticket-email-previews';
const assert = (value, message) => { if (!value) throw new Error(message); };
async function scalar(sql, params = []) { return Object.values((await db.query(sql, params)).rows[0])[0]; }
async function rendererScalar(sql, params = []) {
  await db.query('SET LOCAL ROLE service_role');
  try {
    await db.query("SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',true)");
    return await scalar(sql, params);
  } finally {
    await db.query('RESET ROLE');
  }
}
function render(input) {
  // Deliberately no network permission: the only provider is an in-process stub.
  const result = spawnSync('deno', ['run', '--frozen', `--lock=${root}supabase/functions/deno.lock`, '--allow-env', '--allow-read',
    `${root}automation/email-delivery/ticket-delivery-rehearsal-render.ts`], { input: JSON.stringify(input), encoding: 'utf8', maxBuffer: 8_000_000 });
  if (result.status !== 0) throw new Error(result.stderr);
  return JSON.parse(result.stdout.trim().split('\n').at(-1));
}
await db.connect();
try {
  await assertDisposableDatabase(db);
  await db.query('BEGIN');
  await db.query(readFileSync(`${root}database/tests/helpers/assertions.sql`, 'utf8'));
  await db.query("UPDATE public.email_messages SET workflow_state='cancelled'; UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),max_rate=10,daily_quota=1000,provider_sent_24h=0,worker_url=NULL,next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,probe_until=NULL");
  mkdirSync(output, { recursive: true });
  const previews = [];
  for (const mode of ['pdf_attachment', 'inline_qr', 'both']) {
    const org = await scalar("INSERT INTO public.organizations(title) VALUES('Ticket delivery rehearsal') RETURNING id");
    const unit = await scalar("INSERT INTO public.units(title,organization) VALUES('Rehearsal',$1) RETURNING id", [org]);
    const hidden = await scalar("INSERT INTO public.occasions_hidden(secret) VALUES('ticket-email-local-rehearsal') RETURNING id");
    const occasion = await scalar("INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled,features,occasion_hidden) VALUES('Ticket & QR rehearsal',$1,$2,gen_random_uuid()::text,now(),now()+interval '1 day',true,$3,$4) RETURNING id", [org, unit, JSON.stringify([{ code: 'ticket', is_enabled: true, delivery_mode: mode }]), hidden]);
    const productType = await scalar("INSERT INTO eshop.product_types(occasion,title,type) VALUES($1,'Admission','select_one') RETURNING id", [occasion]);
    const product = await scalar("INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES($1,$2,'Admission',100,'CZK') RETURNING id", [occasion, productType]);
    const order = await scalar("INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,price,currency_code,data) VALUES($1,public.next_order_sequence($1),public.generate_order_symbol(),'ordered',200,'CZK','{\"email\":\"rehearsal@example.invalid\",\"tickets\":[]}') RETURNING id", [occasion]);
    const ticketIds = [];
    for (let i = 0; i < 2; i++) {
      const ticket = await scalar("INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES($1,'ordered',public.generate_ticket_symbol($2,$1)) RETURNING id", [occasion, org]);
      ticketIds.push(ticket);
      await db.query('INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES($1,$2,$3)', [order, product, ticket]);
    }
    assert((await scalar('SELECT public.update_order_and_tickets_to_paid($1)', [order])).code === 200, 'Paid transition failed');
    const row = await scalar('SELECT public.claim_email()');
    assert(String(row.order_id) === order && row.message_kind === 'order_tickets', 'Paid transition did not produce canonical ticket intent');
    const prepared = render({ action: 'prepare', recipient: row.recipient,
      details: await rendererScalar('SELECT public.get_order_details_for_email($1)', [order]),
      tickets: await rendererScalar('SELECT public.get_tickets_with_details($1)', [order]),
      products: await rendererScalar('SELECT public.get_products_and_types($1)', [occasion]),
      resolved: await rendererScalar("SELECT public.get_email_template_and_wrapper('TICKET_ORDER_PAYMENT_DONE',$1)", [JSON.stringify({ organization: Number(org), unit: Number(unit), occasion: Number(occasion) })]),
    });
    await db.query('SELECT public.prepare_email($1,$2,$3,$4)', [row.message_id, row.lease_token, prepared.snapshot, prepared.postAction]);
    const begin = await scalar('SELECT public.begin_email_send($1,$2)', [row.attempt_id, row.lease_token]);
    assert(begin.disposition === 'send', 'Send gate failed');
    const sent = render({ action: 'send', mode, snapshot: begin.message.prepared });
    assert(sent.calls === 1, 'Provider was not called exactly once');
    await db.query("SELECT public.finish_email_attempt($1,$2,'accepted',$3)", [row.attempt_id, row.lease_token, sent.provider]);
    await db.query('SELECT public.apply_email_post_actions($1)', [row.message_id]);
    assert(await scalar('SELECT state FROM eshop.orders WHERE id=$1', [order]) === 'sent', 'Order post-action failed');
    const firstScan = await scalar("SELECT public.update_ticket_to_used($1,'ticket-email-local-rehearsal')", [ticketIds[0]]);
    const secondScan = await scalar("SELECT public.update_ticket_to_used($1,'ticket-email-local-rehearsal')", [ticketIds[0]]);
    assert(firstScan.code === 200 && secondScan.code === 409, 'Email/PDF identity did not share admission state');
    // A second message cancelled after preparation must never reach the provider.
    await db.query("UPDATE public.email_capacity SET next_send_at=now()");
    await db.query("UPDATE eshop.orders SET state='paid',email_payment_version=email_payment_version+1 WHERE id=$1", [order]);
    await db.query('SELECT public.enqueue_paid_order_tickets($1)', [order]);
    const cancelled = await scalar('SELECT public.claim_email()');
    await db.query('SELECT public.prepare_email($1,$2,$3,$4)', [cancelled.message_id, cancelled.lease_token, prepared.snapshot, prepared.postAction]);
    await db.query("UPDATE eshop.orders SET state='storno' WHERE id=$1", [order]);
    const blocked = await scalar('SELECT public.begin_email_send($1,$2)', [cancelled.attempt_id, cancelled.lease_token]);
    assert(blocked.disposition !== 'send', 'Cancellation did not fence prepared message');
    previews.push(`<section><h2>${mode}</h2>${sent.html}<p>PDF přílohy: ${sent.pdfCount}</p></section>`);
    await db.query('UPDATE public.email_capacity SET next_send_at=now()');
    console.log(`PASS ${mode}: paid -> canonical queue -> encrypted preparation -> SES stub -> post-action; scan 200/409; cancellation fenced`);
  }
  writeFileSync(`${output}/index.html`, `<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ukázky doručení vstupenek</title><style>body{font:16px system-ui;margin:16px;max-width:720px}section{margin-bottom:48px}img{max-width:100%;height:auto}</style><h1>Neplatné lokální ukázky</h1>${previews.join('')}</html>`);
} finally {
  await db.query('ROLLBACK');
  await db.end();
}
