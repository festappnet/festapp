# API artifact history cutover - 2026-11-14

The owner explicitly approved force-push/history rewriting and confirmed a
service window with other Festapp writers and publishers paused.

The validated graph preserves all 5,611 original commits and their topology.
73 commits change because they contain removed API output paths, depend on
changed parents, or hold tenant `baseMainSha` references to those parents.
Every other commit retains its exact original object, including valid signatures.
Seven invalidated signature headers on rewritten commits are removed; signatures
are not fabricated. Current application source is byte-identical to the
pre-cutover main `9a52d0ea7fa127cc0933866ca8f759e4ed4c9650`.
The equivalent rewritten application commit is
`37f6ca5fd35aef625ea8d7dcfdeed114dd6b6e4d`; this documentation is an additive
child commit, recorded separately in the final ref manifest.

The whole reachable graph was audited. Only
`tools/festapp/contracts/api-v1/` is removed; the only pre-existing file changes
outside it are exact `baseMainSha` substitutions in tenant overlay metadata.
All current tenant ancestry remains valid. The unchanged canonical drift checker
passes for festapptickets, festappticketsglobal and festivalslunovrat, with
original generated API manifests restored into the disposable replay context
from verified external build inputs. No application deployment is part of this
operation. Other 25 remote references retain their exact original values.

The archive release [api-contract-archive-20261114](https://github.com/festappnet/festapp/releases/tag/api-contract-archive-20261114)
retains the published JSON snapshot archive and complete historical generated
HTML/manifests/baseline build inputs. Their SHA256 pins, the complete commit map,
12-ref publication manifest and final readback receipt accompany that release.
The first archive remains unchanged at SHA256
`650962babfd9fc4eef0eda39b77a4a607e2c37ac9af1e2cefec0c79e85ef0b39`.
Historical build inputs have SHA256
`f701cf31b1748101805b097d742da42bc35ffd441c699fba0a0ab890d58ff4ef`.
Old receipt SHAs are pre-cutover provenance and resolve through the commit map;
they must not be silently rewritten as if the old execution used a new SHA.

The independent remote backup contains all 37 heads/tags. Local dirty work,
ignored user data and local refs have protected recovery copies outside the
normal source directories. Old working copies are quarantined without push
capability; active copies use the rewritten graph. Recovery backups require
review 14 days after all owners are restored, not automatic deletion during
cutover. Generated inputs and published API contracts remain a deliberate
long-term archive.

Before publication the ordinary regression mirror is executed on the rewritten
source. Publication uses one atomic push with explicit old-SHA leases for every
changed ref. The post-push exact-main CI gate is verified again. Product rollout
and additional tenant releases require their normal independent release gates.

The compact local pack was 255.19 MiB before and 253.83 MiB after filtering,
before this small documentation commit. This is about 1.36 MiB of compressed
Git data, distinct from the 8,430,496 net text lines removed from tracked source.
A fresh network clone and actual post-push size are recorded in the readback
receipt rather than inferred from raw JSON size.

GitHub can retain old objects in read-only PR refs, cached SHA views, forks and
backups. GitHub Support does not purge non-sensitive generated artifacts on
request. This operation proves removal from controlled heads/tags and ordinary
new clones; it does not claim physical removal from every hosting cache or fork.
Official references: [GitHub history removal](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository),
[explicit leases and atomic pushes](https://git-scm.com/docs/git-push).
