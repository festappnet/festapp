# Canonical email variable cutover

The active catalog covers all 15 system template kinds, including team invitation/access messages. Identity placeholders are `{{orderSymbol}}`,
`{{occasionTitle}}` and `{{occasionAdminUrl}}`. Their earlier spellings are not interpreted by the editor,
preview or delivery renderer. The generated catalog has no alias map. Delivery
rejects retired placeholders in authored templates before preparing a message.
Customer data inserted during rendering is still literal data.

`20261109160000_canonical_email_variables.sql` converts existing subjects and HTML
at all inheritance levels, wrappers, and `occasion_setup_drafts.data.emailTemplateOverrides`.
It changes only the reserved placeholders, including whitespace variants. IDs,
scope, custom prose, formatting, wrapper timestamps and unrelated draft data are
preserved. Changed drafts get a new revision to prevent stale saves. Validated
CHECK constraints reject attempts to reintroduce the retired format through any
writer. The converters exist only in `pg_temp` during the atomic migration and
are explicitly dropped afterward. Reapplying it changes nothing further.

Sent/prepared encrypted messages, command receipts and their hashes are history.
They must not be rewritten. Pending order/waitlist/notification intents retain
their canonical business facts and render from the converted template sources.

## Coordinated release

1. Resolve and verify the selected tenant's activation and backend using
   `.agents/skills/festapp-backend-access/SKILL.md`. The confirmed release target
   is `vstupenky.online` / `festapptickets`, canonical generation 1, organization 3.
   Verify the live activation again before executing; the default working-tree
   configuration does not identify the live target.
   Do not apply this to another tenant by assumption.
2. Freeze the reviewed canonical source revision, generated assets and migration
   digest. Pass the required publication and exact-source release CI gates.
   Prepare the selected tenant's new client and Functions files before pausing.
3. Arrange an authoring maintenance window so open editors can save and close.
   Capture the read-only counts from
   `automation/email-template-cutover/inventory.sql`. Retain a protected backup
   of the affected template/wrapper/draft rows, including scope and revisions.
4. Record the previous email pause state, pause `public.email_capacity`, and drain
   all `preparing`/`sending` work through the normal queue workflow. The migration
   locks the pause row and refuses an unpaused or undrained queue.
5. Apply the exact reviewed SQL and migration-ledger entry in one transaction.
   Do not apply unrelated pending migrations. On SQL failure everything rolls
   back; keep email paused while diagnosing it.
6. Activate the matching Functions source with the approved
   `automation/hetzner-supabase/runtime/restart-production-functions.py` workflow.
   Preserve the existing container/environment. Publish the prepared selected
   tenant client through its authorized local release path and existing gates.
7. Verify zero remaining retired placeholders in active sources, all three CHECK
   constraints validated, the canonical catalog/client, and dry-rendered default
   and scoped custom messages. Use the normal worker health probe. No test email
   or resend is implied by this procedure.
8. Restore the original pause state only after all checks pass and record delivery
   health. Leave the queue paused on failure and repair the canonical path;
   do not silently restore an alias fallback or rewrite immutable mail receipts.

The migration is global to the selected backend's email template contract. A
shared-backend release must account for every client that writes those sources;
data conversion alone is not a completed production cutover.

## Rehearsal

Use the marked disposable local database, never production:

```sh
python3 automation/generate_email_variables.py --check
python3 automation/assemble-email-variable-cutover-migration.py --check
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  pnpm --dir web_client exec node --test tests/database/email_variable_cutover.test.js
```

The test converts populated global/organization/unit/occasion custom templates,
wrappers and drafts; checks unchanged history, scope and custom content; reapplies
the migration; verifies the pause prerequisite and rejects legacy writes. It
rolls the entire rehearsal back.

## Internal system-template completion

`20261109170000_system_email_variables.sql` is a forward-only continuation of
the installed `20261109160000` migration. The earlier bytes are pinned and never
regenerated. It converts team `eventTitle` to `occasionTitle` and `eventUrl` to
`occasionAdminUrl` at every source scope, wrapper and draft override, then
strengthens the same constraints. It uses the same pause/drain, backup and
matching Functions/client deployment procedure above. Historical messages and
receipts remain unchanged.

Team producers now pass raw values to the shared composer; scalar fields are
escaped once there, including application and occasion names and links. All
registered system fields come from the catalog. Arbitrary values supplied by
the external custom-message API retain their existing wire contract in that
same composer; they cannot reintroduce retired placeholders into authored sources.

The retired `ORDER_OVERVIEW` type remains data-only for historical identity
retention; it has no first-party sender or registered editor preview. Password reset
uses `resetLink` everywhere; forward17 also converts `resetPasswordLink`.
