# Execute: ticketing authoring and issued-ticket MCP

Only begin implementation after it is requested. Read repository instructions,
the authoritative `festapp-canonical-operations-plan-2026-10-20.md` and the full
`festapp-ticketing-mcp-plan-2026-10-20.md` in this directory. Use standard
verification and preserve unrelated working-tree changes.

Follow parent E0-E6: first layout inspect and viewable preview through stdio,
then gated layout save, then blueprint/forms, products/inventory and issued-ticket
operations. Complete other readers/refactors by E5, without blocking E0/E1 on
unrelated families. Gate each write family on parent 1I. Reuse existing preview
modes, font catalog, schema, renderer and fixtures; do not build a second canvas
or a universal framework. Validate one final-input batch per coherent slice and
reuse passing evidence unless affected inputs change. Repair
blueprint rejection atomicity and cross-blueprint seat scope, scrub hold secrets,
add real baseline-version enforcement across supported writers, preserve form
patch/deletion semantics and layout-specific permissions. Use stable immutable
command intents and exact compare-and-clear; reuse receipts, aggregate versions,
queue and existing domain owners. Extract effective migration-only definitions
into authored SQL with fresh forward migrations, never rewrite applied history.

Implement shared fixed-schema handlers and MCP tools for seating creation/edit,
forms, products/pricing/capacity, ticket artwork/preview and issued-ticket/order
operations. Visual ticket design is a primary acceptance gate: inspect resources,
edit an unsaved draft, return viewable MCP previews, refine and validate a final
PDF through the canonical renderer before saving the reviewed revision. Check
typography, backgrounds, Czech/long text, print dimensions and QR readability;
valid JSON alone is insufficient. Create forms closed atomically, keep sales activation explicit and
keep edits separate from export/delivery. Do not use raw admin bundles, arbitrary
RPC/SQL tools, copied pricing logic or service-role impersonation. Remove replaced
writers; bound required legacy adapters with a tested retirement/fencing policy.

Prove rejection leaves domain state unchanged, foreign IDs fail, live holds and
allocations survive geometry conflicts, stale edits conflict and retries do not
duplicate resources or delivery. Test only isolated fixtures with repository
lanes, including shared-handler/MCP interoperability. Hosted writes additionally
require remote plan 4D with operation grants and honest in-flight revocation
semantics. No independent subagent audit, live tenant writes, deployment,
external connector configuration, commit or push without separate authority.

Update plans when source evidence changes. Report completed families, removed
paths, actual validation and exact remaining local/live gates. Do not describe
four read tools as completion of the required ticketing-write scope.
