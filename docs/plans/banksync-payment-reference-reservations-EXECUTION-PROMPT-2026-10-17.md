# Execute Festapp-owned payment-reference reservations

Work in `/Users/miakh/source/festapp` and `/Users/miakh/source/banksync`. Read the authoritative revised plan:
`docs/plans/banksync-payment-reference-reservations-plan-2026-10-17.md`.

The user's 2026-10-18 correction supersedes the former cross-service design:
Festapp owns VS allocation/reservation in its PostgreSQL order transaction.
Retire the preexisting BankSync reservation API/runtime/exports as subsequently
requested by the user, preserving bank facts and historical registry data. Do not
add a reference HTTP dependency, reference preparation worker, lease saga or
application-wide payment-engine replacement.

Preserve existing working changes. Implement permanent account-wide local
reservations, alias normalization, sequence/random/exact policies, monotone form
watermarks, all finalizer callers, safe manual writes, explicit Fakturoid VS,
retry identity and current-state receipt projection. Keep dormant organization
activation with no active-scope fallback. Use standard targeted verification,
including real PostgreSQL concurrency, and prepare the import/activation runbook.

Local implementation only: no commit, push, deploy, production/history mutation,
email or real financial/provider transaction without separate authorization.
Report local results and exact remaining operational gates; never claim global
uniqueness across independent applications/databases or complete deleted history.
