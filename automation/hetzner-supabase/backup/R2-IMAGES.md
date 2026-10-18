# Canonical R2 asset backups

New v2 `festapp-assets` sets contain the database, globals, protected runtime
and exactly the canonical public/private R2 archive. They contain no Storage
archive. The sealed registry and private orphan custody are checked during
independent restore; separate capture intervals are not an atomic snapshot.
The explicit v1 reader remains available for historical encrypted sets.

The canonical timer runs at 02:30 and 14:30 UTC with up to 20 minutes jitter.
The existing monitor warns after 18 hours without a successful set, before the
24-hour file recovery-point objective is exhausted. Healthy jobs must finish
within that remaining margin; an incomplete or failed job never advances the
verified recovery point. Database PITR retains its separate 15-minute objective.
Retention remains 14 days and four completed weekly copies, preserving the
latest three sets. Unknown, extended and incomplete formats are kept outside
pruning. V2 manifests use the same canonical selected-set validator as restore.

Production deployment and actual recovery evidence are recorded in
`docs/operations/security-remediation-20261016/storage-r2-retirement-execution-20261018.md`.
Do not infer runtime activation or completed recovery from this source file.
