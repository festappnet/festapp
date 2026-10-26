# Execute: retire Supabase Storage and consolidate Festapp assets

Work in Festapp, in a task worktree from current canonical main. Read applicable
AGENTS.md, CLAUDE.md and docs/architecture/ai_context.md, then read the entire
authoritative `docs/plans/storage-r2-retirement-plan-2026-10-18.md`.

Implement its dependency-ordered waves using standard verification. Outcome:
one public and one private Festapp asset bucket; public sync/private backups
separate; independent AKH unchanged; all current text/HTML/nested JSON references
and fonts migrated; Storage/imgproxy and three redundant buckets retired only
after exact copy, ownership, active-reference, backup and recovery proofs.
Preserve existing R2 URLs at a thin boundary. Do not retain Supabase Storage URL
compatibility, fallback writers, speculative aliases or a second storage service.

User chose 4 GB, Studio continuously available, DB recovery point <=15 minutes,
files <=24 hours, isolated recovery testing with no production outage, and at
most ten minutes downtime in an agreed maintenance window. Old Storage links in
already delivered content may break. No paid resize or live disaster switch.
Do not drop source objects just because they look old or unreferenced.

Use canonical approved main for backend releases and obey current publication
review gates. Do not publish unrelated tenant branches; default optional web
release is prod/festapptickets. Coordinate any additional required tenant scope
before its publication. Delegate routine deployment execution and monitoring to
the standing authorized cheaper release agent with frozen exact revisions.

Refresh factual premises once; update the authoritative plan if evidence differs.
Keep customer payloads, mapping manifests and secrets in protected operational
evidence. No independent subagent review. Finish with measured behavior, absence
of retired paths, actual production state, source/receipt links and any remaining
concrete decision. A plan, code merge or unit test alone is not completion.
