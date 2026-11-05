# Notification release source reconciliation

Scope: `prod/festapptickets`, `https://vstupenky.online`, canonical organization 3.

The original workspace was on pre-compaction main `a31277e3c`; authoritative
main was `082864cc44bb4f3012abd3ff388c5a477fef6df5`. A private local snapshot
`25d119683` retained all 766 changed tracked/untracked paths. Only that working
change was cherry-picked onto current authoritative main, without reintroducing
the obsolete Git ancestry or modifying the original dirty checkout.

Published order details, bank observation ordering, presale/form editing,
blueprint dependencies and guides remain authoritative on overlapping paths.
Notification projection/view/client changes and their canonical domain hooks
were combined with those revisions. Translation additions retain current public
catalogs. The new migration and source-parity contract were regenerated from the
combined owners. The redundant local hidden-member source/migration duplicate
was omitted because the canonical November 1 hidden-member migrations already
own that behavior. The original local files remain preserved in the source
snapshot and original checkout.

The original package cleanup from the local main change is retained; the
published TrinaGrid 2.4 dependency was resolved into the lockfile. The combined
source passed all 46 notification Flutter tests and 34 targeted SQL contracts
against a fresh disposable database including the later presale migration.
Release CI, exact source publication, backend installation and tenant rollout
are recorded separately; this reconciliation receipt is not a deployment claim.
