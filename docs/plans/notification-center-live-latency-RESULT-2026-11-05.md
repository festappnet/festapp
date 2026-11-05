# Live notification opening latency correction

The first release did not meet the user's observed opening latency. The earlier
single-occasion SQL benchmark missed the cost of organization-wide permissions.
Live `pg_stat_statements` recorded the new open RPC at 2566.9 ms mean over two
calls; the production rollback diagnostic reproduced a ready 30-row open at
2335.5 ms. The active organization-wide view had 89 rows and 334 allowed scopes.
No database test fixtures, account changes or seen/read acknowledgments were
committed during these production diagnostics.

Component probes found approximately 436 ms in scope discovery, 239 ms in the
display fingerprint, 199 ms in badge calculation and 73 ms in 30-row rendering.
The original request repeated scope discovery for catalogue insertion,
truncation, display revision and badge. SQL timings exclude browser/network.

The correction batches current membership/admin/demo reads into candidate
scopes, derives one live scope vector inside the payload SQL snapshot, and uses
it for event access and source fingerprints. Subject visibility remains a
per-event live check. No permission result is cached across requests. The
canonical event authorization predicate remains the equivalence oracle for all
role/category branches, including bank administration, demo occasions, foreign
organizations, affected occasions and NULL inputs. Private helper execution is
still revoked. Catalogue insertion and truncation share one candidate query.
A fully seen, ready badge can return false without enumerating scopes; preparing
continues to return an unknown badge rather than falsely clearing it.

Temporary session-local copies of the exact new functions were compared on the
production data under the same diagnostic context, with each invocation rolled
back. Old/new item JSON was equal. The final comparison was 2518.8 ms versus
301.7 ms (first call); repeated candidate opens measured 265.8, 224.2, 214.9 and
235.3 ms. These are measured server-side samples, not a browser click percentile
or a claim that the 50 ms design objective is satisfied. Browser verification
confirmed build 513 and the new RPC names, but an isolated authenticated browser
session was unavailable, so no live click-to-content measurement is claimed.

Local regression coverage adds a 111-occasion, 445-scope, 30-row open and bounds
canonical per-event ACL invocations during candidate discovery. It measured
35.0 ms locally. A separate matrix compared the batched predicate against the
canonical authority in 1560 cases. The complete targeted SQL/parity/security
batch passed 37 files, and migration/protocol assembly tests passed five.

The sealed 1200 and 1810 migrations are unchanged. Forward migration
`20261105190000_notification_prepared_scope_discovery.sql` owns this correction;
its active manifest records the immutable prerequisites and current canonical
sources. There is no Flutter or Edge code change and no web rebuild is needed.
Production application and final post-apply timings are recorded in the release
receipt when complete.

The wide-scope regression was also run with only the scope-discovery function
replaced by the released b41 body inside a disposable transaction. It failed the
canonical ACL invocation bound, then rolled back. The corrected source passes
that same fixture, so the regression detects the diagnosed serial authorization
work independently of host timing variance.
