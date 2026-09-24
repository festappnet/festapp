# Execute: Image delivery without per-view Worker charges

Work in `<repo-root>`.

Use the repository's applicable instructions and standard verification recorded in the plan.

Implement the entire authoritative plan:

`docs/plans/image-delivery-cost-cutover-plan-2026-08-23.md`

Read it in full before editing. The target outcome is public Festapp images delivered from project-specific public-only R2 custom domains and cache without per-view Worker invocations, while a fail-closed `image-api.festapp.net` Worker owns authenticated upload, delete, private reads and signing.

Execute the waves in dependency order and distinguish locally code-ready work from the plan's P0-P4 authorized production checkpoints. Treat the private/public bucket split, installed-client control-route adoption gate, server-enforced transformation cardinality, varied-image purge semantics, stored-link delete authorization and project isolation as hard gates. Do not attach a public custom domain to any bucket until aggregate inventory proves it contains no private objects. Do not enable URL transformations until the exact source allowlist and fail-closed zone rule prove that handcrafted options cannot bypass the three presets. Do not retain arbitrary caller-selected Supabase origins/keys, default-bucket fallback, key-path-only public delete authorization, public GET Worker routing, mixed data/control origins, arbitrary `w/f/q` variants or a permanent compatibility path.

Preserve the existing public contracts `img.festapp.net` = default project bucket and `a.img.festapp.net` = project A bucket; they are project/data boundaries, not thumbnail/original variants. Reuse those hostnames for direct public delivery only after old clients no longer call their control endpoints. The target control request selects an allowlisted stable `projectId`; the temporary canonical-URL alias may exist only for the measured adoption window and must ignore caller-supplied credentials.

If current repository or production evidence invalidates a factual premise, update the authoritative plan with the evidence and adapt the affected wave without silently changing the requested outcome. Use official current Cloudflare documentation and the live account for the Wave 0 pricing/entitlement preflight; do not enable a paid product without explicit monetary approval.

Run only the validation required by the plan and repository rules. Ensure the Worker validation actually includes both `tests/unit/` and `tests/integration/`, and include the config propagation fixture and targeted SQL/Flutter/web tests named by the affected wave. Do not start an independent review or subagent audit unless explicitly requested.

Do not perform production bucket creation/migration/deletion, DNS/custom-domain or cache-rule mutation, Cloudflare Images activation, Worker deploy, app release, commit or push without separate authority. Stop at each production gate with the exact target, pre-state, rollback identifier, expected cost and validation query. At handoff, report the canonical contracts, migrated callers/data, deleted legacy artifacts, validation results, cost evidence and any exact blocker or still-unapplied operational step.
