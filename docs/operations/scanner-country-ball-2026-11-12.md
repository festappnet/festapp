# Country bál scanner isolation - 2026-11-12

Applied the reviewed one-off data repair to the canonical Festapp database for
`festapptickets` (organization 3). Production branch activation and live
`backend-activation.json` both identified canonical generation 1; server
hostname and runtime database matched the target assertions.

- Occasion 32316 (`Country bál 2026`) moved from shared hidden relationship 1
to unique relationship 37. Its scan resolver returns exactly `{32316}`.
- Sibling occasions 13, 82 and 11438 remain on relationship 1; its secret
  digest remained unchanged.
- Five active Country bál scanner sessions were revoked; zero remain active.
- Repair SQL SHA-256:
  `0f3cc602d713b9fec232dd352fe2d8d9182115dccc2d8e425aaf140860f3467f`.
- The public REST RPC resolved to occasion 32316, `Country bál 2026`. The
  verification request used the canonical public anon key and did not expose the
  scan code. No scan secret or secret digest is recorded here.

The live repair changed no schema, function, application code, other tenant,
or release artifact.

## Cause and systemic correction

Historical occasion copies retained `occasion_hidden`, so rotating the code
updated the same secret for multiple events. Scan entrypoints used `LIMIT 1`
and did not reject ambiguity. All live copy-function overloads now delegate to
the three-argument implementation, which inserts NULL for `occasion_hidden`;
the historical shared relationships were not repaired by that code change.

The separate forward migration `20261112235500_scanner_occasion_isolation.sql`
is prepared locally, **not applied to production**. It makes the private scan
proof resolver reject every non-unique match, routes retained entry/export
readers through that owner, rejects ambiguous proofs in admission/password
operations and existing scan-link sessions, and refuses ordinary rotation of a legacy shared hidden row. Such a group
requires a whole-group credential retirement, so gradual splitting cannot
reactivate a previously disclosed code for its last remaining event. Rotations serialize
allocation and reject empty or already-used codes before changing the epoch.
A private fingerprint registry also permanently rejects currently shared historical
codes, even if a copy is later deleted; retired values cannot be recycled.
This preserves current rejection as security metadata without rotating event
credentials in other tenants.

The new `scan_code_isolation_test.sql` failed before the correction with
`shared hidden row must never identify an occasion: expected 0, got 2`.
After applying the migration to a dedicated local clone, the new test plus
`legacy_scan_proof_test.sql` and `settings_test.sql` all passed (three files,
real PostgreSQL, transaction rollback). The clone used the existing local test
DB dump, omitted the database-specific pg_cron extension, and restored schema
permissions required by the tests. This is targeted SQL verification, not the
full canonical CI mirror or release gate. The one-off repair was also rehearsed
against a minimal four-event fixture, checking sibling preservation, session
revocation, epoch scope and idempotency before production application.

Old distributed Country ball links contain the formerly shared code and cannot
be reinterpreted as Country ball without also changing the other events' links.
The organizer must fetch and distribute Country ball's new link from its admin
dialog. Never store that credential in this receipt.

## Scan code format normalization

At the user's follow-up, normalized only occasion 32316's exclusive hidden
relationship 37 from its intermediate 32-character code to the expected five
uppercase letters/digits. The public RPC resolved the new code to occasion 32316,
`Country bál 2026`; the previous code now returns `invalid_scan_code`.

- Format check passed: uppercase alphanumeric, length 5.
- Scanner epoch advanced exactly once; zero active Country bál sessions remain.
- Sibling relationships and the original shared secret remained unchanged.
- Normalization SQL SHA-256:
  `0909a2e7aa0eb198f812427e5af48c623e860328087ef47a2bbfc61798cc0036`.
- No scan code or secret digest is recorded here.
