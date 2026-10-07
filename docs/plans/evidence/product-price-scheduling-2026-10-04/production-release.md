# Product price scheduling production release

Status: ACTIVE on vstupenky.online, 0.20.96+580.

- Canonical main: 148385676d1d6bef68169ef9decf941ca76c11a2; PRs #291 and #292. Administrative merge was authorized for this deployment.
- Production branch: prod/festapptickets, ab4ea1e65d33536fb7da524e0db7e0899082d161. No other tenant branch was written or built.
- Deployment: https://github.com/festappnet/festapp/actions/runs/37202157957, successful. Intermediate runs were cancelled before upload to sequence the preceding header release and include the nested-route correction.
- Public verification: verify_web_deployment passed three consecutive probes for 0.20.96+580. Immutable main bundle contains save/cancel price RPCs, schedule metadata and the scheduling action. Bundle SHA-256: 29bbe65bbf37318dc80f78e779bf737784aa6e42c9af06161e302153045cd31e.
- Migration 20261004150000: exact authoritative SQL SHA-256 6b7184b1c9aac770cbf6f960f047df633880190ca8b7041e7aee7ad1c3927ac5. Protected full backup and before-function definitions retained on the canonical backend under product-price-scheduling-20261004. Guards checked database/tenant, prerequisites, absence of the migration and unchanged before-functions. SQL and the exact SQL ledger entry committed atomically; PostgREST was notified. Ledger digest independently matches.
- Authenticated scheduling execution is granted; direct authenticated SELECT and anonymous TRUNCATE on planned_changes remain denied. Authorized read-only product-bundle smoke confirms server time and price_changes arrays. No production fixture/order/price change was created.
- Existing control-plane job 10 is active every minute, targets the canonical runtime and succeeded after migration and final frontend deployment. No scheduler was added.
- Final checks: 113 SQL files, 1081 Flutter tests with one skip, 242 Deno tests, web/automation checks, migration and concurrency harnesses, and three local worker integration tests pass. 27 external credential-dependent cases remain skipped. Tenant drift against exact main, configuration matrix and legal checks pass.
- Full production authenticated UI editing was not exercised. Local full-app evidence and widget/SQL regressions cover scheduling, preserved old order prices, dirty refresh protection and nested-route returns.

Verified at 2026-10-04T12:34:42.393013+00:00.
