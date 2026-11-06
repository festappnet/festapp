# Canonical main integration

## Scope and execution

1. Preserve the original local main and every pending file before integration.
2. Integrate PRs #746, #747 and #748 with their original heads in the ancestry.
3. Port the local payment-provider feature and meaningful pending changes onto
   current upstream main. Retain newer canonical owners when older local copies
   would restore retired APIs, migrations or duplicate implementations.
4. Verify the combined source, including a production-order database upgrade,
   real local Auth/REST, image uploads, payment authorization and MCP refresh.
5. Publish canonical main and synchronize the original main checkout. Resolve
   the integrated pull requests and require all eight CI jobs on that exact SHA.
6. Release the selected `prod/festapptickets` tenant with local builds and direct
   deployment, plus the affected shared backend, image Worker and MCP sidecar.
   Publish prepared CMS upgrades after the live central embed checks pass.

## Preservation and conflict decisions

The original local head is `d7d170314c77d1d0298a9b78f4c4d178a0651c83`.
All 877 pending paths are recoverable from the immutable snapshot commit
`3ef49eefda081c660fd0e9e21410a1969f2dbcb5`, also retained under
`refs/backup/main-unification-20261106/local-wip`. The original index, binary
patch, file fingerprints and per-path audit manifests are retained privately
outside the working tree. Verify those fingerprints before replacing the
original checkout.

The integration preserves provider-aware payments and callback handoff, the
form-editor permission regression test, historical release evidence and two
historical immutable Joomla archives. Current measurement consent, central
embed appearance, notification and authorization owners take precedence over
older overlapping local copies. The vendored venue editor remains at 0.3.10;
the retired 0.3.9 archive and duplicate generated font registry stay removed.
Current translations retain the added keys. Current help generation, SVG and
public-brand support, image tooling versions and MCP safety contracts remain
canonical. Cash-only reservation documents are preserved as plans.

## Release boundaries

Production scope is `prod/festapptickets` / `https://vstupenky.online` only.
Shared service updates must preserve existing bindings, secrets, keys, volumes
and rollback provenance. Barion remains disabled and sandbox-only. Do not
activate commercial payments, provision measurement runtimes for additional
units, or build or modify other production branches.

Fresh-schema tests do not establish upgrade safety: the pending 12:00 provider
migration must also be tested after the already-applied 12:10 privacy migration.
Production SQL and its ledger must use the verified canonical migration bodies
and the protected backend access path. Keep email paused and drained for the
required Functions restart and resume only after successful worker probes.

Test and deployment receipts establish completion; this plan is not a claim
that publication or production verification has already occurred.
