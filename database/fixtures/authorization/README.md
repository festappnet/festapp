# Independent pre-cutover authorization inputs

Extracted from immutable source `a4296c57687294b34826e59c7b232eef582c9748`. These expectations must never be
regenerated from current SQL or runtime output. Normal tests/generation need no
historical dumps, Git history or database capture.

| Fixture | Original path under `docs/plans/evidence/canonical-authorization-20261020/` | Original SHA-256 | Projection |
|---|---|---|---|
| `pre-cutover-policies.json` | `catalog-before.json` | `21b222e1ba622b53adc62e380802e8c1eb50dbdafcb161e8fb759a2666bae8d2` | All 408 policy rows and all eight fields, including expressions, nulls, role order and metadata. |
| `pre-cutover-acl.json` | `catalog-before-pristine.json` | `24778d17289fb1e11a23df4aa67c397dc4f2bce2a56b8caf967a13c0ec6a671a` | Complete columnGrants, schemaGrants, defaultGrants, roles, roleMemberships and tableGrants collections; all 1013 functions projected to signature and complete grants. |

Extraction preserves array membership/order and every selected value. Fixtures
use compact UTF-8 JSON and one trailing newline. The policy generator consumes
expressions; PostgreSQL regressions independently compare RLS metadata and full
ACL collections, retaining the original reviewed grant exceptions.
See [historical conclusions and recovery](../../../docs/archive/canonical-authorization-evidence-2026-10-20.md).
