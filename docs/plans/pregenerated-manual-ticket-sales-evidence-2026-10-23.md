# Pregenerated manual ticket sales - implementation evidence

The feature is integrated with the current canonical architecture. Release
validation and remaining rollout gates are recorded in
`pregenerated-manual-ticket-sales-release-check-2026-10-23.md`.

- Ordinary checkout and stock creation share the private product materializer.
  Creation owns existing ticket/QR/OPT/seat/allocation identities; cash sale moves
  those identities into one paid order through the existing transaction/pairing
  owner. Stock blocks capacity and never admits, including unpaid overrides.
- Create/sell/void commands are atomic, receipted and reauthorize before replay.
  Existing order capabilities, Blueprint save, inventory and report owners enforce
  the stock/sale rules. Fakturoid incompatibility is rejected before mutations.
- Frozen PDF resources and single-ticket documents live in the existing private
  R2 bucket behind a dedicated Worker create/read capability. SQL owns access,
  manifests and fenced leases. Neither new Supabase Storage nor public delivery
  URLs are introduced. Email and ZIP use exact stored singles; one complete A4
  export packs frozen ticket areas at physical size when they fit.
- New migration versions are 20261024020000 and 20261024021000. Installed historical
  migrations remain byte-identical. The latter makes previously implicit function
  ACLs explicit while preserving the effective anon/authenticated/service role
  matrix. Current source contracts and exact historical digests are both checked.
- New registry sources inherit the installed cutover phase. Fresh additive
  bootstraps stay inactive, while an already activated production registry stays
  ready. Existing readiness is never promoted by an upsert.
- Baseline test repairs use current canonical saved layouts, actual hold leases,
  current typed permissions and explicit email confirmation. Financial reference
  replacement injects a real payment failure and verifies transaction rollback;
  concurrency harnesses validate localhost, disposable identity and container port.
  Production fixtures are never used by these tests.

The initial full validation exposed existing failures as well as stale fixture
and release-inventory contracts. The user authorized completing those repairs
before merging and releasing. The final results and explicit skipped acceptance
coverage are recorded in the release check, without counting skips as passes.
