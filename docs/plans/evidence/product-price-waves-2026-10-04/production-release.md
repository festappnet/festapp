# Product price waves release

ACTIVE on vstupenky.online, 0.20.97+581.

- PR https://github.com/festappnet/festapp/pull/293 merged using the existing administrative deployment authorization. Main: 6456c3ae6bde8b82f02f851b3dcae866dc4a24b0; source: 4697f2dfade4513cfdd12ea87bdf1d59d453edc8.
- Production: prod/festapptickets, 9f6d91035cbf249cc345dee3951ac2e67c307a17. No other tenant branch was written or built. Base main and previous production tip were fetched and unchanged immediately before publication. Tenant drift, configuration matrix and legal checks passed.
- Deployment https://github.com/festappnet/festapp/actions/runs/37205699848 succeeded. Public verifier passed three consecutive probes. Immutable bundle: main.dart.0.20.97-581.js; SHA-256 4fe47080c78d21bab696b963bb766ace2a114450ce8d75a8706b1264d37d51ad. All four wave RPC names, visibility_changes and p_is_hidden are present.
- Exact migration 20261004180000 canonical SQL and ledger SHA-256: eef591aa0c33ae435695e85704c95e5c7b50fc2e782f62b1e01bff73fc747447. Protected full backup, previous functions and exact SQL retained under product-price-waves-20261004 on the canonical backend. Database/organization/prerequisite/before-function guards passed. SQL and full migration ledger committed atomically, then PostgREST notified.
- Authenticated wave mutation execute is granted; anonymous execute and direct authenticated wave reads are denied; RLS enabled. Authorized read-only production bundle smoke confirmed price_waves and per-product visibility_changes.
- Existing job 10 remains active every minute against the canonical runtime and succeeded after migration/deployment. No scheduler was added.
- Full test results and screenshot limitations are in validation.md. No production fixture, order, price or visibility change was created; production authenticated editing was not exercised.

Verified 2026-10-04T13:34:44.265656+00:00.
