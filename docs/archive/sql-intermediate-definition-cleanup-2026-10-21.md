# Redundant SQL definitions - 2026-10-21

Authorized follow-up on `task/artifact-reduction-20261021`, in the isolated
artifact-reduction worktree. Original SQL recovers from
`f4aa0b6edfa688b03937197d74b0506d2ae81db7` using `git show <revision>:<path>`.
No production access, migration deployment, ledger rewrite, commit or push.

## Removed

Only three superseded `CREATE OR REPLACE FUNCTION` statements, each replaced
later **inside the same migration**, were removed:

| Migration in `supabase/migrations/` | Function | Removed bytes |
| --- | --- | ---: |
| `20261014000000_waitlist_admin_delete.sql` | `delete_order_client_sync_v1(bigint,uuid)` | 3,408 |
| `20261020190000_blueprint_canonical_scoped_readers.sql` | `get_blueprint(uuid,uuid,bigint)` | 4,803 |
| `20261020220000_blueprint_private_svg_originals.sql` | `get_blueprint(uuid,uuid,bigint)` | 4,833 |

Total: **13,044 bytes and 298 newline characters**. Every byte outside those
three statements is preserved, including final definitions, grants/revokes,
other DDL, comments and trailing whitespace. No migration file/version was
removed. Existing immutable migration hash safeguards were preserved.

## Evidence

- Static replay using the repository's SQL statement/signature parser confirms
  identical effective function bodies at all **217 migration file boundaries**.
  Each removed function already exists before its removed intermediate version.
  Between it and its replacement are only function declarations and function
  grants/revokes, with no top-level DML, backfill, call, rename, drop or DO block.
- Actual PostgreSQL **17.6** replay started from the verified September 6
  baseline, its reference seed, managed Auth/Storage schema DDL from the local
  disposable test provider, and synthetic tenant identity. No user data was
  copied. The order-symbol upgrade stage was applied and its remaining count
  checked. All forward migrations through the current head were replayed.
- Immediately before each affected migration, that database was cloned twice.
  The complete original migration ran in one clone and the reduced migration
  in the other. Schema/data `pg_dump` outputs matched for **all three pairs**,
  including function bodies/attributes, owners, ACL/default ACL, other schema,
  rows and sequence values. Dumps used `--no-publications --no-subscriptions`;
  that unchanged DDL is outside the three removed statements. Generated dump
  session fences/version headers were excluded; data was not normalized.
- Demo maintenance migrations ran as their required `postgres` identity;
  extension-owning migrations used `supabase_admin`. Fixture background workers
  were disabled for cloning without changing repository SQL or its guards.
  This is synthetic fresh-install evidence, not a populated production upgrade
  rehearsal.
- `python3 automation/generate_canonical_source_contract.py --check` passed.
  All **9** `test_canonical_source_contract.py` tests passed. Immutable abuse,
  Blueprint, order-seating and operations-foundation checks passed unchanged.

The owned Docker fixture used no network, published ports or bind mounts, and
was removed with its volume. Existing local databases were not modified.
Temporary proof scripts, original SQL copies and receipts are under
`/tmp/festapp-sql-prune-*`; they are diagnostic evidence, not another runtime
or a committed copy of deleted SQL.

## Retained candidates

The broader scan found about 5.48 MB of definitions later replaced or dropped.
That is only an upper-bound inventory: intermediate backfills, grants, dependent
DDL, dynamic SQL and installed-history constraints have not been proven safe
across those boundaries. Apart from the proven exact duplicates below, those
cross-file candidates remain unchanged. There is
no automatic history-pruning rule or bypass of immutable migration checks.

## Follow-up: exact duplicate in the global order-limit migration

Removed the `update_form_internal_v1(jsonb)` declaration from
`20261013170000_global_ticket_order_limit.sql`. The complete CREATE statement,
including signature and attributes, exactly matches its predecessor in
`20261013160000_ticket_product_type_cutover.sql`. The earlier declaration stays
in place. Order creation, the limit helper and their grants remain unchanged.
No canonical source or generator was changed. The generator requires a new
output path and already refuses to overwrite existing migrations.

Savings: **35,427 definition bytes plus two trailing newline bytes**. The
combined four-definition cleanup now saves **48,473 bytes**. Static replay
confirmed equal effective functions at all 217 migration boundaries on the final
SQL. Nine source-contract tests, the generated source-contract check, all four
immutable migration checks and the targeted whitespace check passed.

A new network-isolated PostgreSQL 17.6 fixture replayed the verified baseline
and all **217 forward migrations**. Immediately before the affected migration,
two database clones received the original and reduced SQL. Complete schema/data
dumps matched, including function metadata, owners, ACL/default ACL, sequences,
publications and subscriptions. Only dump session fences/version headers were
normalized. Subsequent EOF blank-line trimming does not change a SQL statement.
The fixture and its volume were removed; no existing database was modified.

Matching dump SHA-256: `03f98726886d99debd518d9ffec800f121cfecfb95046d23ab411a631977f141`.
Proof script, checks and receipt: `/tmp/festapp-sql-order-limit-*`. As above,
this proves the synthetic replay, not a populated production upgrade rehearsal.

## Follow-up: customer order overview helpers

Removed another **16 byte-identical CREATE statements** across six migrations.
The earlier declarations remain available. Grant/revoke, table/constraint,
email-template insertion and different-overload DROP statements are preserved.
No source function, generator, immutable migration or migration version changed.

| Migration | Removed definitions | Saved bytes |
| --- | ---: | ---: |
| `20261015170000_customer_order_overview.sql` | 5 | 9,545 |
| `20261015210000_customer_order_journey.sql` | 1 | 597 |
| `20261015230000_customer_overview_readable_journey.sql` | 2 | 4,291 |
| `20261015233000_customer_payment_recorded_time.sql` | 2 | 2,064 |
| `20261015234500_customer_overview_product_order.sql` | 3 | 5,790 |
| `20261016001500_customer_payment_history_method.sql` | 3 | 5,790 |

This batch saves **28,077 bytes**; all SQL batches together remove **20
definitions and 76,550 bytes**. Exact-removal checks and effective function
comparison passed at every one of the 217 migration boundaries. The generated
source-contract check, nine source-contract tests, four immutable migration
checks and targeted whitespace checks passed.

A new PostgreSQL 17.6 fixture replayed the baseline and all 217 forward
migrations. Before each of the six affected files, its state was cloned twice
and the original/reduced migration applied. All six complete database dumps
matched, including data, sequences, function metadata, owners, ACL/default ACL,
publications and subscriptions. Only dump session fences/version headers were
normalized. The order-overview table DDL and email-template insertion ran in
both variants and were included in the comparison. This remains synthetic
replay evidence, without production/customer data.

The own network-none container had no ports or bind mounts. Its scheduler stayed
inactive; workers were temporarily disabled only for cloning. The container and
its volume were removed. Existing local databases and production were unchanged.
Temporary originals, manifest, proof script, checks and receipt use
`/tmp/festapp-sql-customer-*`. Matching dump hashes:

- `20261015170000_customer_order_overview.sql`: `2460ff1b273df07f60ac50b7b7b5fe23b0e9bf0b48fdc09da76a0addc79d6e87`
- `20261015210000_customer_order_journey.sql`: `e310e8fd9d6daba233d5caca5f217e7a266c1ef0c636027542b9aef04b20f2cd`
- `20261015230000_customer_overview_readable_journey.sql`: `0836c4c065ecf392162f1953b2aa70a3709363ec11571a471dd40688072785a8`
- `20261015233000_customer_payment_recorded_time.sql`: `6ce6710a72e9f9e3798f59a453076ba935670c927c2b5b2d4a625e2d3c4d8217`
- `20261015234500_customer_overview_product_order.sql`: `16c6632e15e0df18caca42159aa636ff74cf371eec060e840e7ac68086535c15`
- `20261016001500_customer_payment_history_method.sql`: `4a6e3bb51eb5fa560907af921aeb2417b6fd41fa6b8aa2f7867485723cd209f6`

## Follow-up: repeated Blueprint declarations

Removed **137 exact duplicate declarations** from another 22 migration snapshots.
The two explicitly immutable Blueprint migrations were excluded, along with
immutable abuse, operations-foundation and order-seating history. Prior effective
declarations stay in place; function bodies, parameters, return types and CREATE
attributes match the removed declarations. Grants/revokes, owner changes, table
and index DDL, different-signature DROPs, transaction boundaries and NOTIFY remain
unchanged. Selected files contain no top-level data backfills. Runtime source,
font/image assets and generators were not changed.

| Migration | Removed definitions | Saved SQL bytes |
| --- | ---: | ---: |
| `20261005151000_occasion_setup_separate_blueprint.sql` | 5 | 5,174 |
| `20261014120000_disabled_blueprint_form_capacity.sql` | 3 | 2,243 |
| `20261019100000_blueprint_layout_integration.sql` | 3 | 1,588 |
| `20261019110000_blueprint_verified_image_assets.sql` | 5 | 5,757 |
| `20261019130100_blueprint_public_hold_availability.sql` | 2 | 492 |
| `20261019210000_blueprint_canonical_layout_cutover.sql` | 3 | 1,587 |
| `20261020100000_blueprint_scoped_font_dependencies.sql` | 2 | 4,022 |
| `20261020110000_blueprint_masks_numeric_resources.sql` | 3 | 5,052 |
| `20261020140000_blueprint_product_assignment_modes.sql` | 7 | 8,960 |
| `20261020150100_blueprint_protected_product_modes.sql` | 1 | 245 |
| `20261020170000_blueprint_captured_text_references.sql` | 5 | 5,856 |
| `20261020180000_blueprint_canonical_document_validation.sql` | 1 | 2,500 |
| `20261020190000_blueprint_canonical_scoped_readers.sql` | 5 | 4,591 |
| `20261020200000_blueprint_optional_furniture_text_roles.sql` | 4 | 3,230 |
| `20261020210100_blueprint_canonical_setup_resources.sql` | 21 | 27,829 |
| `20261020220000_blueprint_private_svg_originals.sql` | 16 | 38,226 |
| `20261020230000_blueprint_typed_assembly_admission.sql` | 6 | 14,216 |
| `20261020260000_blueprint_grid_pin_boundaries.sql` | 7 | 16,171 |
| `20261020270000_blueprint_assembly_physical_profiles.sql` | 8 | 16,642 |
| `20261020280000_blueprint_closed_assembly_variants.sql` | 7 | 14,687 |
| `20261020290000_blueprint_canonical_runtime_cutover.sql` | 22 | 33,730 |
| `20261021000000_blueprint_geometry_metadata_binding.sql` | 1 | 2,500 |

This batch saves **215,298 SQL bytes**, including four bytes of EOF whitespace
cleanup. Across all SQL batches: **157 declarations and 291,848 SQL bytes**.
Exact-removal verification and effective function-body comparisons passed at all
217 migration boundaries.

A new isolated PostgreSQL 17.6 fixture replayed the verified baseline, staged
order-symbol backfill and all 217 forward migrations. Before each selected file,
two clones received its complete pre-batch and reduced SQL respectively. All
**22 complete pg_dump pairs matched**: schema, rows, sequences, function metadata,
owners, ACL/default ACL, publications and subscriptions. Only generated dump
session fences/version headers were normalized. This is synthetic replay, not
a populated production upgrade rehearsal.

The source-contract generator now points two provenance comments to the earlier
retained operations-foundation declarations. A comparison confirmed that every
executable assertion is byte-identical. The regenerated contract check, all nine
source-contract tests, four immutable migration checks and targeted whitespace
checks passed. No guard or hash expectation was weakened.

The owned network-none container had no ports or bind mounts; scheduling stayed
inactive. It and its volume were removed, with no leftover matching container.
Existing local databases, production and branches were not written. Proof inputs,
manifest, original snapshots, checks and receipt: `/tmp/festapp-sql-blueprint-*`.
Receipt SHA-256: `36db81cb2ea76971f858ef07ce696717b7f7d12fbf063d72ccf0ed3567f969e2`.

## Follow-up: activity, legal verification and scanner declarations

Removed another **23 byte-identical CREATE statements**, saving **52,339 SQL
bytes**. Across all batches: **180 declarations and 344,187 SQL bytes**.

| Migration | Removed definitions | Saved SQL bytes |
| --- | ---: | ---: |
| `20261007120000_canonical_activity_mutations.sql` | 4 | 22,030 |
| `20261018230000_unit_legal_verification.sql` | 10 | 13,820 |
| `20261019010000_unit_verification_notifications.sql` | 2 | 8,221 |
| `20261019040000_scanner_settings_editors.sql` | 7 | 8,268 |

Prior declarations remain effective. Grants/revokes, legal-profile table/index
DDL, RLS, transaction boundaries and comments are preserved. No source function
or generator changed. The integration reconciliation migration was excluded:
its generator explicitly preserves installed history and checks the full output.
Its bytes were verified against the original recovery revision unchanged; no
expectation or historical hash was modified.

Exact-removal checks and effective function-body comparison passed at all 217
migration boundaries. The generated source contract is byte-identical to the
pre-batch version. Its check, nine source-contract tests, four immutable migration
checks and targeted whitespace checks passed.

The own network-none PostgreSQL 17.6 fixture replayed the verified baseline,
order-symbol stage and all 217 forward migrations. Four original/reduced
migration pairs ran on clones taken immediately before their respective files.
All four complete dumps matched, including rows, sequences, function metadata,
owners, ACL/default ACL, other schema, publications and subscriptions. Only dump
session fences/version headers were normalized. This remains a synthetic replay,
without production/customer data.

No published port or bind mount was used. The fixture and volume were removed,
and no matching container remains. Existing databases and production were not
modified. Originals, manifest, static/database proof scripts, checks and receipt:
`/tmp/festapp-sql-domain-*`. Receipt SHA-256: `01f4e6c70e866ea9ea263c06c5d0b90582b5d4244aa900c0bd7e82d602e47d95`.

## Follow-up 2026-10-22: bank, payment and order helpers

Removed another **40 exact duplicate CREATE statements** across five migrations,
saving **37,239 SQL bytes**. Cumulative SQL reduction: **220 declarations and
381,426 bytes**.

| Migration | Removed definitions | Saved SQL bytes |
| --- | ---: | ---: |
| `20261004203000_bank_sync_full_cutover_prepare.sql` | 10 | 7,639 |
| `20261006130000_order_symbol_expand.sql` | 10 | 8,785 |
| `20261014000200_waitlist_email_offer_presentation.sql` | 5 | 6,869 |
| `20261018200000_festapp_payment_reference_reservations.sql` | 5 | 5,933 |
| `20261019120000_bank_sync_email_providers.sql` | 10 | 8,013 |

Earlier identical declarations remain. Owner changes, grants/revokes, table and
constraint DDL, different-overload DROPs, dynamic permission blocks, transaction
boundaries, lock settings and NOTIFY are preserved. No activation or payment
operation was called. Canonical runtime source, generators and immutable history
were unchanged. The historical-bank-dates migration was excluded from this batch
because it also updates rows with current timestamps.

Exact-removal checks and effective function-body comparison passed at all 217
migration boundaries. The generated source contract remained byte-identical.
Its check, nine source-contract tests, four immutable migration checks and
targeted whitespace checks passed without changing a guard or hash expectation.

A new network-none PostgreSQL 17.6 fixture replayed the verified baseline,
order-symbol backfill stage and all 217 forward migrations. Each affected file
was compared on two database clones taken immediately before that file. All
**five complete database dump pairs matched**, including table data, sequences,
function metadata, owners, ACL/default ACL, schema, publications and subscriptions.
Only generated dump session fences/version headers were normalized. This is
synthetic replay evidence, not a populated production upgrade rehearsal.

The own fixture used no published ports or bind mounts and scheduling remained
inactive. Its container and volume were removed, and no matching container
remains. Existing local databases and production were not changed. Originals,
manifest, proof scripts, checks and receipt use `/tmp/festapp-sql-payments-*`.
Receipt SHA-256: `44e906badf53a7c5dc333dee4e4c780401f090e7fb82a26ad9639c1ec0736c30`.

## Follow-up 2026-10-22: demo and occasion setup helpers

Removed another **65 exact duplicate CREATE statements** in ten migrations,
saving **60,492 SQL bytes**. Cumulative SQL reduction: **285 declarations and
441,918 bytes**.

| Migration | Removed definitions | Saved SQL bytes |
| --- | ---: | ---: |
| `20261005133000_occasion_setup_full_flow.sql` | 3 | 2,254 |
| `20261005143000_occasion_setup_canonical_initialization.sql` | 3 | 2,719 |
| `20261007160000_canonical_mutation_write_release.sql` | 3 | 2,300 |
| `20261010030000_cancelled_orders_read_only.sql` | 3 | 3,219 |
| `20261013160000_ticket_product_type_cutover.sql` | 3 | 792 |
| `20261014000000_waitlist_admin_delete.sql` | 5 | 4,625 |
| `20261014150000_demo_occasions.sql` | 42 | 41,224 |
| `20261019180000_occasion_setup_feedback.sql` | 1 | 383 |
| `20261020173000_ticket_layout_legacy_fence.sql` | 1 | 215 |
| `20261021120000_restore_team_invitation_password_guard.sql` | 1 | 2,761 |

Prior effective declarations remain. Tables, indexes, RLS policies and policy
validation blocks, dynamic permission blocks, grants/revokes, transaction
boundaries and distinct-signature DROPs are preserved. No application-row
backfill was changed, no fixture seeder was invoked, and no canonical runtime
source, generator or immutable migration changed.

Exact-removal checks and effective function-body comparisons passed at all 217
migration boundaries. Two generated source-contract provenance comments now
point to earlier retained declarations; executable assertions are byte-identical.
The regenerated contract check, nine source-contract tests, four immutable
migration checks and targeted whitespace checks passed. No guard or hash
expectation was weakened.

A new network-none PostgreSQL 17.6 fixture replayed the verified baseline,
order-symbol stage and all 217 forward migrations. Each selected file's complete
pre-batch and reduced SQL ran on two clones taken immediately before that file.
All **ten complete database dump pairs matched**, including schema, RLS policies,
rows, sequences, function metadata, owners, ACL/default ACL, publications and
subscriptions. Only generated dump session fences/version headers were
normalized. This remains synthetic replay evidence, not a populated production
upgrade rehearsal.

The own fixture had no published ports or bind mounts; scheduling remained
inactive. Its container and volume were removed and no matching container
remains. Existing local databases and production were not changed. Original SQL,
manifest, proof scripts, checks and receipt use `/tmp/festapp-sql-setup-*`.
Receipt SHA-256: `37d833e748f4827cd70f54a28db94f14b7e39382a5b1c4ad0e09fcabed79f56f`.

## Follow-up 2026-10-22: email, public links, bank dates and scanner

Removed **53 exact duplicate declarations** across four migrations, saving
**66,481 SQL bytes**. Cumulative SQL reduction: **338 declarations and 508,399
bytes**. These migrations include data operations, so this batch adds an explicit
per-declaration idempotence check rather than relying only on file-end parity.

| Migration | Removed definitions | Saved SQL bytes |
| --- | ---: | ---: |
| `20261004020000_email_capacity_runtime_guards.sql` | 15 | 19,590 |
| `20261004205000_bank_sync_historical_bank_dates.sql` | 11 | 10,344 |
| `20261015200000_pretty_public_links.sql` | 21 | 31,792 |
| `20261019030000_web_scanner.sql` | 6 | 4,755 |

Each of the 53 original CREATE statements was executed in the original variant
between probes taken immediately before and after it. Every probe verified
unchanged pg_proc fields (including owner, ACL, body, defaults, attributes and
configuration), incoming/outgoing pg_depend rows and role/ACL pg_shdepend rows.
Only diagnostic `:location` offsets inside parsed default/body trees were
normalized; argument values, resolved objects and runtime attributes were kept.
All 53 replacements were catalog/dependency no-ops at their actual position in
the migration chain. The probe helper is disposable verification code under
`/tmp/festapp_sql_probe.py`, with no new application or migration dependency.

The original data INSERT/UPDATE statements, including the bank-inbox timestamp
update, remain byte-identical. Table/index DDL, constraints, locks, transaction
boundaries, different-overload DROPs, role/permission blocks and grants/revokes
also remain unchanged. No canonical runtime source, generator or protected
migration was changed.

A new network-none PostgreSQL 17.6 fixture replayed the verified baseline,
order-symbol stage and all 217 forward migrations. Four original/reduced pairs
ran on clones taken immediately before their files. All four complete dumps
matched, including data, sequences, metadata, owners, ACL/default ACL, schema,
publications and subscriptions. Only generated dump session fences/version
headers were normalized in dump comparison. This remains synthetic replay with
sparse reference data, not a populated production upgrade rehearsal; per-CREATE
probes separately establish that the removals themselves preserve catalog state
seen by the unchanged data operations.

Exact-removal checks and effective function-body comparison passed at every one
of 217 migration boundaries. The generated source contract stayed byte-identical.
Its check, nine source-contract tests, four immutable migration checks and
targeted whitespace checks passed without weakening assertions or hashes.

The owned fixture had no ports or bind mounts and scheduling stayed inactive.
It and its volume were removed, with no leftover matching container. Existing
local databases and production were unchanged. Originals, manifest, proof scripts,
checks and receipt use `/tmp/festapp-sql-idempotent-*`.
Receipt SHA-256: `24f0244b04fe02f190294db3dba0523c99cf9857f5bb5b0fdacad6b0098e6eea`.

## Follow-up 2026-10-22: final small wrappers

Removed three exact duplicate declarations (`update_occasion_203(jsonb)`,
`delete_order_221(bigint)` and `apply_planned_changes()`) from respectively
`20261002010000_occasion_default_form_link.sql`,
`20261013180000_allow_cancelled_order_deletion.sql` and
`20261021220000_occasion_sales_setup_and_catalog.sql`. Savings: **719 SQL bytes**,
including two EOF whitespace bytes. Cumulative: **341 declarations / 509,118
SQL bytes**. Prior declarations and all surrounding statements remain.

All three per-CREATE metadata/dependency probes and three complete database dump
comparisons passed in a new isolated PostgreSQL 17.6 fixture; all 217 forward
migrations replayed. Static comparison passed at all 217 boundaries. Generated
contract changes are provenance comments only; executable assertions are
byte-identical. Its check, nine tests, four immutable migration checks and
whitespace checks passed. The fixture and volume were removed, with no leftover
container and no writes to existing databases or production. Evidence:
`/tmp/festapp-sql-wrappers-*`; receipt SHA-256: `8f221b1e06cc8fd466a02692acb68f0395b98831aae3d55efd1b5c416571cec8`.

The larger remaining repetitions belong to explicit immutable history or
full-output generator contracts. They remain intact. The two small repetitions
in the scheduler-bearing canonical email migration still need their own matching
proof setup; font-related snapshots remain outside the user's cleanup scope.
This is not blanket permission to prune overwritten bodies or weaken guards.

## Follow-up 2026-10-22: scheduler-bearing email migration

Removed the remaining two exact copies in `20261003200000_canonical_email_delivery.sql`:
`get_fakturoid_ticket_order_state_v1(bigint)` and `update_occasion_203(jsonb)`.
Savings: **703 SQL bytes**. Cumulative: **343 declarations / 509,821 SQL bytes**.

The proof used stopped, container-owned PostgreSQL data snapshots so both
variants retained the real `postgres` database name required by pg_cron. An
initial comparison differed only in the unchanged initializer's `next_send_at`
wall-clock value. The successful comparison installs the byte-identical common
prefix once, checkpoints it immediately before the first removed CREATE, and
executes original/reduced suffixes on physical copies. The extra checkpoint
commit exists only in the disposable fixture; repository transaction boundaries
are unchanged. Both variants retain identical initialized data and scheduler
context, without normalizing timestamp values or bypassing scheduler checks.

Both per-CREATE metadata/dependency probes and the complete database dump
comparison passed. The full reduced migration also replayed normally, within its
original transaction, as part of all 217 forward migrations. Static checks passed
at every boundary; the generated source contract stayed byte-identical. Its
check, nine tests, four immutable migration checks and whitespace checks passed.
This remains synthetic replay, not a populated production upgrade rehearsal.

All owned containers and both temporary snapshot images were removed and their
absence verified. No ports or bind mounts were used; cron job launching remained
off. Existing local databases and production were unchanged. Evidence:
`/tmp/festapp-sql-email-*`; receipt SHA-256: `e5532a8c7478e0fd53acbad11784b446662f87a2c6bf76aa31bfb14a91399a6e`.

The exact-repetition inventory now retains explicit immutable/full-generator
contracts plus two `can_edit_ticket_layout(bigint)` copies embedded in ticket
appearance/font migration files, left outside this batch. These are permission
helpers; no font asset or font runtime change was attempted.
Earlier overwritten/dropped bodies remain a separate, unproven candidate class.

## Completed continuous sweep - 2026-10-22

The user authorized continuing through all provably safe findings without
intermediate handoffs. This sweep removed the two remaining identical
`can_edit_ticket_layout(bigint)` declarations from historical snapshots, plus
**1,006 function GRANT/REVOKE statements that are structural catalog no-ops**.
Font definitions/assets and canonical runtime SQL were unchanged. No new
application implementation or pruning framework was added to the repository.

Across all SQL cleanup batches, **345 function declarations and 1,006 redundant
permission statements** were removed. Direct comparison against recovery revision
`f4aa0b6edfa688b03937197d74b0506d2ae81db7` measures **617,396 fewer SQL bytes in
136 migration files**. All 217 versioned files remain; no ledger or baseline
manifest was rewritten. Effective function bodies match the original revision
at every one of the 217 file boundaries.

### Permission proof and repeated audit

The first real PostgreSQL audit identified 1,002 no-op permission statements;
whole-file original/reduced comparisons passed for all 134 affected files. A
subsequent sweep found four further no-op permission statements in the two
ticket appearance/font snapshots. Both additional whole-file comparisons passed.
Every removed permission statement was checked immediately before/after execution
against pg_proc state and shared role dependencies. Canonical SQL sources still
retain their intended authorization declarations; this removes historical copies.

In total this sweep passed **136 complete database dump pairs on PostgreSQL
17.6**, with no retained/unproven files. Dumps include schema, rows, sequences,
function attributes, owners, ACL/default ACL, policies, publications and
subscriptions. Only pg_dump session fences/version headers were normalized.
The physical-checkpoint method described above preserves the common initializer
data for scheduler/time-sensitive files; fixture checkpoint commits never change
repository transactions. Scheduling stayed inactive and all 217 forward
migrations replayed successfully.

A separate **PostgreSQL 15.8** provider audit executed all **1,006 removed ACL
statements and both CREATE declarations** at their original positions. All were
catalog/dependency no-ops there too, and all 217 migrations replayed. PG15 used
its cached immutable image ID and its actual password-authenticated fixture;
no authentication rule was weakened. This checks the provider-version risk of
relying on default ACLs. These are synthetic installations, not populated
production upgrade rehearsals.

The final independent ACL sweep returned **zero** unprotected no-op permission
statements. A fresh CREATE scan found **zero** unprotected exact repetitions;
all **277** remaining exact copies belong to **nine explicitly protected
immutable/full-generator-contract snapshots**. Each of those nine files was
verified byte-identical to the recovery revision. A conservative scan found zero
repeated already-proven-absent top-level function DROPs. The canonical source
scan found one repeated signature with genuinely different reviewed-migration
behavior; it was retained. Different historical implementations are not classified
as dead merely because a later migration replaces them.

The canonical generated contract, all nine source-contract tests, four immutable
migration checks, composed final-source hashes and whitespace checks passed. No
assertion, historical hash or generator contract was weakened. All owned
containers and temporary snapshot images were removed and absence verified.
Existing local databases, production, commits and published branches were not
changed. Detailed ephemeral proof inputs/receipts use `/tmp/festapp-sql-final-*`,
`/tmp/festapp-sql-font-acl-*`, `/tmp/festapp-sql-pg15-*` and
`/tmp/festapp-sql-acl-exhaustion-*`.

The compact durable [verification receipt](sql-reduction-verification-2026-10-22.json)
records totals, provider checks, proof-receipt hashes and the protected residual
file hashes. Within these audited classes, no further safe unprotected reduction
remains; a new baseline/cutover or behavior change is separate work.
