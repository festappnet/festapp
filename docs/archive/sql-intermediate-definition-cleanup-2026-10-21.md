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
