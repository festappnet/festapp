# Canonical main and production tenant overlays

`main` owns all shared Flutter, web, SQL, Edge Function, worker, test,
configuration-generator and release-tooling code. Production branches are
forward-only deployment overlays over one recorded main SHA; shared features
must never be implemented by deleting source files or checking a Git branch at
runtime.

Each production branch owns `automation/project.conf`, explicitly listed brand
assets and namespaced legal/store/offline-map/recovery data. It also records:

```json
{
  "schemaVersion": 1,
  "tenantId": "csmostrava2026",
  "baseMainSha": "<40-character-main-sha>"
}
```

The allowlists, generated-path list, metadata schema and drift checker are
loaded with `git show` from `baseMainSha`. A production branch cannot expand its
own policy. The checker creates a fresh archive of main, overlays only approved
source/data paths, runs `automation/apply_config.sh` once and compares generated
leaves byte-for-byte with the branch:

```bash
git show "$BASE_MAIN_SHA:automation/check_tenant_branch_drift.sh" >/tmp/check-tenant-drift.sh
chmod +x /tmp/check-tenant-drift.sh
CANONICAL_MAIN_REF=origin/main /tmp/check-tenant-drift.sh \
  "$BASE_MAIN_SHA" "$TENANT_ID" HEAD
```

Never generate tenant B over tenant A's mutated tree. Start from a clean main
tree for every profile. `automation/tests/tenant_config_matrix.test.sh` proves
idempotence and cross-tenant isolation with synthetic public identities.

## Required legal and support contract

Every tenant `automation/project.conf` must define `PRIVACY_URL`,
`PRIVACY_CHOICES_URL`, `TERMS_URL`, `SUPPORT_URL`, and `DELETE_ACCOUNT_URL` on
the configured HTTPS deploy origin at their canonical paths. Tenant-owned
Markdown in `automation/release/legal/` is the source for the four public legal
and support documents; their `web/` HTML files are generated leaves and must
never be edited independently.

`automation/apply_config.sh` fails before generation when a required value or
source is missing. `automation/verify_web_build.mjs` rejects missing, duplicate,
foreign-branded, or SPA-fallback output, and
`automation/verify_web_deployment.mjs` repeats those checks against the live
deployment. An HTTP 200 alone is not proof that a legal route exists.

## Normal tenant upgrade

1. Develop and validate shared behavior in main.
2. Merge the exact verified main commit forward into the production branch.
3. Reapply only tenant source/data overlay paths from the pre-cutover tip.
4. Run `automation/apply_config.sh automation/project.conf` from the fresh main
   template and update `automation/tenant-overlay.json`.
5. Run the main-owned drift checker and targeted tenant build tests.
6. Commit/push/deploy only through the separately approved release workflow.

Conflicts in shared source always resolve to main's canonical content. A
conflict in an allowed overlay path is an explicit tenant decision; blanket
`ours` resolutions are forbidden.

## Private input boundary

Festapp owns public schemas and authorization/business logic.
`automation/private-inputs.schema.json` and
`automation/tenant-external-services.schema.json` declare input names and
types without values. The designated private configuration repository or an
approved secret manager owns private
credentials, provisioning material and production seed payloads. Missing
required input fails closed; the repository never searches an implicit sibling
directory or prints a supplied value.

The `AGREEMENT_PDF` external-service contract is the canonical source for
tenant organizer, clause, logo and font values used by
`generate-order-agreement`. The old tenant-named endpoint has no runtime caller
in main and is removed from the source tree. Deploying the canonical endpoint
and provisioning its tenant data are separate operational steps.
