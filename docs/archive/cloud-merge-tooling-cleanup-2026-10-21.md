# Cloud merge tooling cleanup - 2026-10-21

Local continuation on `task/artifact-reduction-20261021`, isolated from the
original dirty checkout. Immutable source recovery revision:
`f4aa0b6edfa688b03937197d74b0506d2ae81db7`. Scope is the remaining `automation/hetzner-supabase/merge`
command chain and its callers/tests/docs. Images and font files are untouched.
No production/cloud call, source mutation, database migration, branch publication,
commit or push is part of this cleanup.

## Completed ownership boundary

Removed 25 obsolete merge files plus two tests solely for the retired
cloud freeze/cutover-mode commands. This includes catalog/managed exports and
staging, collision classification and Auth identity merging, schema/migration
history reconciliation, tenant-cohort and pre-cutover readiness checks, their
exclusive schema/policy/fixture inputs, and engage/rollback cloud-freeze recipes.
Those completed commands are not current setup/release prerequisites.

Kept installed `source-registry.json`, `reference-registry.json`,
`runtime-writer-policy.json` and its evaluator, Function test-coverage gate,
writer discovery/classification and the original adapter declarations.
The shared module no longer reads `.env.local`, retrieves a token, queries a
Supabase management API or builds the obsolete catalog manifest.

The exact local `loadWriteAuthorityPolicy`/`auditLegacyAdapters` implementation
moved to `client-adapter-audit.mjs` without logic changes. All **12** supported
runtime/security/privacy/writer/adapter/historical-SQL test bodies were preserved
verbatim, including the actual nine-adapter repository audit and negative direct-
DML fallback test. Tests exclusively for deleted exporters, historical merge
classification and retired cloud command behavior were retired with those tools;
they are not skipped or silently counted as passing current runtime coverage.

The runtime/recovery shell contract lost only the check for the deleted managed
staging recipe. Backup, restore, ingress/firewall, runtime-switch, deployment,
upgrade and promotion checks remain unchanged. Current SQL, activation, runtime,
backup/restore and release safeguards are not replaced by a new implementation.

## Recovery

Use `git show f4aa0b6edfa688b03937197d74b0506d2ae81db7:<original-path>` for any removed file.
For deliberate replay recover the whole original subtree and its matching private
inputs in an isolated historical checkout; do not reconstruct historical facts
from the current runtime. Frozen historical runbooks carry recovery notices and
incoming links point here. Original conclusions/retention decisions remain in
the dated records. Removing a cloud freeze recipe does not change installed cloud
freeze state or authorize unfreezing any retained source.

## Verification and source measurement

- Targeted Node batch: **62 passed, 2 failed, 0 skipped**. All merge ownership,
  current adapter/writer audits, Edge coverage, backup, infrastructure, readiness,
  promotion, private-input and operation-inventory checks passed. The 12 retained
  test bodies and adapter implementation were compared byte-for-byte to the
  original selected blocks.
- Two broader security checks already fail on pristine base main: generated
  `20261016171000_server_security_authorization.sql` disagrees with current source,
  and `admit_image_upload_v1` lacks a matching definer-header declaration in the
  existing contract. Reproduced both exact failures in a temporary `git archive`
  of pristine `f4aa0b6edfa688b03937197d74b0506d2ae81db7`. This cleanup changes none of those SQL, contract,
  generator or test inputs. These failures are reported as existing verification
  limitations, not fixed by weakening tests or changing unrelated migrations.
- Current runtime/recovery shell contract passed. Only the assertion for the
  removed managed-export recipe was retired; supported runtime/backup checks remain.
- The required Function coverage CLI passed for **35 production Functions**,
  no uncovered Functions and no blockers. Remaining module syntax and
  `git diff --check` passed. No provider, production, database or Flutter task ran.
- Hash comparison verified **1,072 protected files**, including all selected
  runtime/backup/restore and SQL inputs, installed registries/policy/evaluators,
  image files and font files, remain byte-identical to the pre-cleanup state.
  Exact deleted-path scan finds no active consumers; remaining short names occur
  only in removal guards, ownership explanations and historical recovery notices.

Logs: `/tmp/festapp-merge-{tests,runtime,edge-coverage,baseline-security}.log`.
Temporary baseline extraction was removed. No owned process or server remains.

## Deleted source paths

All paths below recover from the full source revision above; no compressed copies
or alternative live implementations replace them.

- `automation/hetzner-supabase/merge/canonical-drift.mjs`
- `automation/hetzner-supabase/merge/collision-inventory.mjs`
- `automation/hetzner-supabase/merge/collision-lib.mjs`
- `automation/hetzner-supabase/merge/cutover-mode-gate.mjs`
- `automation/hetzner-supabase/merge/default-transform-policy.json`
- `automation/hetzner-supabase/merge/export-managed-schemas.mjs`
- `automation/hetzner-supabase/merge/export-source.mjs`
- `automation/hetzner-supabase/merge/fixtures/inventory-a.json`
- `automation/hetzner-supabase/merge/fixtures/inventory-default.json`
- `automation/hetzner-supabase/merge/hybrid-readiness.mjs`
- `automation/hetzner-supabase/merge/identity-decision.schema.json`
- `automation/hetzner-supabase/merge/inventory.mjs`
- `automation/hetzner-supabase/merge/manage-cloud-freeze.mjs`
- `automation/hetzner-supabase/merge/manifest.schema.json`
- `automation/hetzner-supabase/merge/merge-policy.json`
- `automation/hetzner-supabase/merge/migration-history-inventory.mjs`
- `automation/hetzner-supabase/merge/rehearsal-export-clouds.mjs`
- `automation/hetzner-supabase/merge/repository-cutover-preflight.mjs`
- `automation/hetzner-supabase/merge/resolve-auth-collisions.mjs`
- `automation/hetzner-supabase/merge/schema-fingerprint.mjs`
- `automation/hetzner-supabase/merge/source-schema-drift-policy.json`
- `automation/hetzner-supabase/merge/stage-managed-export.mjs`
- `automation/hetzner-supabase/merge/table-import-readiness.mjs`
- `automation/hetzner-supabase/merge/tenant-config-inventory.mjs`
- `automation/hetzner-supabase/merge/tenant-cutover-policy.json`
- `automation/tests/hetzner_supabase_cloud_freeze.test.mjs`
- `automation/tests/hetzner_supabase_cutover_mode_gate.test.mjs`

## Exact incremental measurement

This phase: **27 files removed, 14 modified, 3 added**.
Complete changed-file storage: **358,882 -> 177,923 bytes**, net
**180,959 bytes saved**. LF separators: **7,688 -> 3,297**,
net **4,391 fewer**. Script-source LF separators alone shrink by
**4,316** (comments/blank lines included).
The merge directory moves from **33 files to 10**, including its new ownership
README and the extracted local adapter audit. No image or font optimization,
re-encoding, relocation or dependency change is included. These are current-tree
bytes; Git history/clone packfiles retain the original source.
