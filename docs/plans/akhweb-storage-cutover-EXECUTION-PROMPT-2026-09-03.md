# Execute: AKH web storage cutover and Pilgrimway retirement

Work in `/Users/miakh/source/festapp` and `/Users/miakh/source/akhweb`.

Use each repository's applicable instructions and standard verification.
Implement the entire authoritative plan:

`docs/plans/akhweb-storage-cutover-plan-2026-09-03.md`

Read it in full before editing. The outcome is an AKH web whose DB/Auth remain
on `iinvsjtnbyxfrdygsfpo` while all images use the canonical Festapp image API,
a dedicated R2 bucket and `akh.img.festapp.net`, with no runtime dependency on
`lwfpdjxsdmkfyrzqbrlk`, plus retirement of unused Pilgrimway.
Completion requires migrated and hash-verified objects, rewritten persisted
URLs, canonical proxy behavior, removal of legacy functions/secrets/fallbacks,
live validation and the plan's deletion ledger being satisfied.

Execute waves in dependency order. Do not leave placeholders, parallel storage
implementations or speculative fallbacks. If runtime evidence invalidates a
fact, update the plan before adapting the wave. Preserve source Storage objects
until the broader legacy-project deletion gate; do not delete the project.

The user has authorized the scoped production migration, deploy/push and exact
Pilgrimway unpublish/retirement. Do not modify `festapp-rideshare`, migrate AKH's
own project to Festapp self-hosting, or delete legacy source data. At handoff,
report canonical ownership, migrated data/callers, deleted artifacts,
validation, rollback boundary and any exact blocker.
