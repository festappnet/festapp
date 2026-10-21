#!/usr/bin/env python3
"""Bind explicit HTTP/worker and dynamic-SQL reviews to source bytes."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];F=ROOT/'docs/plans/evidence/canonical-authorization-20261020'
s=json.loads((F/'source-inventory.json').read_text())
edge={
'auth-email-hook':'Verified Auth hook signature; durable account email enqueue. Technical sender identity, not organizer editorial authority.',
'bank-sync-manage':'Verified JWT; check_is_admin_bank_account delegates to two-role bank owner; connect/update SQL rechecks actual account before mutation.',
'bank-sync-reconcile':'Protected system request secret and explicit monitor organization; service reconciliation owns stored bank connections, no caller role override.',
'bank-sync-webhook':'BankSync webhook secret; authenticated provider event resolves stored connection before service processing.',
'cancel-reception-registration':'Caller JWT passed to canonical reception cancellation command; stored registration binds occasion and scoped participant-manage predicate.',
'confirm-account-deletion':'One-use account deletion proof; SQL request/expiry/state transition and protected asset cleanup service boundary.',
'customer-order-access':'Verified user or scoped customer proof; service resolve_customer_order_access_v1 binds actual order, actor and delivery.',
'delete-order':'JWT user command locks/authorizes actual order; service invoice saga follows admitted receipt, no arbitrary service order deletion.',
'download-ticket':'Scoped customer access proof, caller JWT canonical ticket-read SQL, or protected system request-secret lane. Ticket/order relationship resolved in SQL.',
'email-confirmation-status':'SHA256 of one-use confirmation capability; SQL returns limited confirmation state, not email/profile content.',
'email-provider-events':'Verified provider event signature; durable message/attempt references, no arbitrary organizer role.',
'exchange-login-qr':'One-use login QR proof and SQL consume/expiry boundary; identity exchange, no editorial capability snapshot.',
'exchange-sign-in-code':'One-use sign-in proof consumed by Auth/SQL flow; durable authentication email lifecycle, no organizer policy formula.',
'fetch-http-data':'Caller JWT admit_external_image_fetch_v1 shares media owner before bounded pinned public HTTPS fetch. No service-secret bypass.',
'fetch-transactions':'Verified JWT; canonical two-role scoped unit-account query, provider only after nonempty authorized result. No global service unit listing.',
'generate-order-agreement':'Caller JWT canonical order-read context, or protected system request-secret lane; actual order binds agreement data.',
'google-auth-callback':'Shared Google OAuth state/nonce, origin and code verification; external identity authentication, not domain roles.',
'google-auth-complete':'Shared Google OAuth state/nonce and one-use completion; external identity authentication, not domain roles.',
'google-auth-start':'Shared origin-validated Google OAuth state/nonce setup; no organizer authorization grants.',
'mcp-session-exchange':'Allowlisted configured tenant origin, one-use session exchange and verified user; SQL operations separately intersect consent/OAuth scope.',
'notify':'Protected webhook token and stored organization push configuration. Technical push delivery, not a public editorial endpoint.',
'preview-ticket-layout':'Caller JWT canonical authoring/read-only layout or owned setup-draft admission; renderer receives only admitted bytes.',
'process-email-queue':'Protected system request secret; service claim/attempt state transitions and current intent validation, no arbitrary public enqueue.',
'register':'Public account registration Auth flow, configured organization initialization, durable verification email and abuse controls; no existing organizer role override.',
'report-exchange-rates':'Verified Auth user identity, bounded external exchange-rate report. No tenant-private reads or mutations.',
'request-account-deletion':'Verified JWT user; own account one-use deletion request and durable confirmation email, no caller-selected victim.',
'send-app-links':'Verified actor; enqueue_participant_notice_for_actor_v1 rechecks live participant-management rule and stored recipient/template before dedupe.',
'send-custom-email':'Verified actor; enqueue_custom_email_for_actor_v1 owns live custom-email rule, actual scope and dedupe authorization.',
'send-email':'Protected system request-secret lane or verified caller; canonical enqueue_order_email owns order intent and actor authority.',
'send-occasion-team-invitations':'Caller JWT setup invitation access; service enqueue validates stored invitation/creator scope and intended recipient.',
'send-reset-password-link':'Public bounded Auth reset request; durable account email flow, no organizer role or arbitrary private profile data.',
'send-sign-in-code':'Own sign-in/Auth proof flow; optional team notice uses SQL projection and actor-bound enqueue owner. Role fields only format recipient labels.',
'send-ticket-order':'JWT replacement command or scoped public order submission path; canonical order/invoice command binds resource and receipt before provider side effects.',
'send-tickets':'Verified actor or protected system request secret; canonical enqueue_order_email owns live order admission and dedupe.',
'waitlist-commands':'Verified JWT actor passed only over trusted service boundary; execute_waitlist_command_client_sync_v1 owns actual order/offer/capability and replay.',
}
other={
'supabase/functions/_shared/accountDeletion.ts':'Dependency fetch type, not an endpoint. Protected own-account deletion service flow.',
'supabase/functions/_shared/googleAuthFlow.ts':'Shared OAuth state/nonce/code/origin verification; fetch dependency injection, not another domain-policy boundary.',
'supabase/functions/_shared/ticketFonts.ts':'Font fetch/store interface, not an endpoint; admitted renderer/service font requests only.',
'supabase/functions/fetch-http-data/handler.ts':edge['fetch-http-data'],
'supabase/functions/fetch-http-data/safeFetch.ts':'Bounded DNS/IP/content validation and pinned public HTTPS fetch after caller admission. Fetch interface is not independent editorial authority.',
 'tools/festapp/src/auth/session.mjs':'Transport identity/session adapter; no domain role formulas. SQL commands own live admission.',
 'tools/festapp/src/mcp/server.mjs':'Fixed catalog MCP tool/resource registration. Identity, OAuth and consent narrow calls; domain SQL owns resource admission.',
 'tools/festapp/src/operations/catalog.mjs':'Fixed operation dispatch plus input validation and consent narrowing; SQL owner checks current actual resource.',
 'tools/festapp/src/remote/delegation.mjs':'Consent/OAuth resource narrowing, expiry/revocation and verified actor; no detached authoritative role preflight.',
 'web_client/src/services/flutter_runtime_handoff.js':'Fetch dependency for compiled runtime handoff/version activation, not private domain authorization.',
 'workers/image-worker/src/index.ts':'Public R2 reads; private/presign/upload/delete delegate JWT plus canonical scoped SQL admission. Account-assets/fonts use protected service boundary.',
 'workers/self-hosted-monitor/src/index.mjs':'Scheduled fixed-target health checks with monitoring token; no domain role combination or arbitrary tenant operation.',
 'workers/storage-retirement/index.mjs':'Rejects retired Storage paths; no private asset read/write admission.',
 'workers/supabase-legacy-keepalive/src/index.mjs':'HTTP returns404; scheduled fixed legacy Auth pings only. No domain data writes or provider migration.',
 'workers/sync-publisher/src/worker.ts':'Protected wake token or scheduled fixed service publication; SQL materialization owns stored resource publication. Publishes public projection only.',
 'workers/sync-worker/src/index.ts':'Public read-only GET/HEAD R2 sync heads, bounded path and cache; no private data or mutations.',
}
records=[]
for b in s['transportBoundaries']:
 path=b['source'];name=path.split('/')[2] if path.startswith('supabase/functions/') else None
 review=edge.get(name) if path.endswith('/index.ts') else None
 review=review or other.get(path)
 assert review,'Unreviewed transport '+path
 records.append(dict(**b,admission=review,sourceSha256=hashlib.sha256((ROOT/path).read_bytes()).hexdigest()))
dynamic=[]
for b in s['dynamicSqlCandidates']:
 path=b['source']
 if path.endswith('reset_all_sequences.sql'):review='Trusted maintenance utility, quoted stored catalog identifiers; invoker privilege boundary, not application role dispatch.'
 elif path.endswith('generate_schema_triggers_ddl.sql'):review='Schema-DDL text generator; EXECUTE appears in returned DDL text, not dynamic application authorization.'
 elif path.endswith('operation_rules.sql') or path.endswith('retire_storage.sql'):review='Comment candidate, not executable dynamic SQL.'
 elif path.endswith('image_projects.sql'):review='Migration-time fixed import/adoption DML, not a per-request dynamic endpoint.'
 else:review='Migration/schema installation DDL over catalog-owned quoted identifiers; explicit grants, policies or technical triggers, not runtime domain dispatch.'
 dynamic.append(dict(**b,review=review,sourceSha256=hashlib.sha256((ROOT/path).read_bytes()).hexdigest()))
(F/'boundary-ledger.json').write_text(json.dumps(dict(state='all inventoried transport/dynamic SQL candidates explicitly classified',
 limits='Boundary descriptions are source inspection. Provider/Auth delivery is mocked in tests; no production or paid provider was called.',
 transportBoundaries=records,dynamicSqlCandidates=dynamic),indent=2)+'\n')
print(f'Bound {len(records)} transport candidates and {len(dynamic)} dynamic-SQL candidates to reviewed source bytes.')
