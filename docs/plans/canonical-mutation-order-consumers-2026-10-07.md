# G0/G2 correction: order membership teardown

Live catalog inspection found two current callers of the retired
`delete_occasion_user_ws(uuid,bigint)`: `delete_order_221(bigint)` and
`delete_order_internal_v1(bigint)`. This disproves the earlier consumer closure.
Final contraction is blocked until the new forward migration is applied.

Canonical authoring now has one order DML owner. The published compatibility
entrypoint delegates to the existing typed order command; both use the existing
occasion/group/activity lock prefix and `remove_occasion_user_domain_internal_v1`.
Unit-manager authorization and the additional occasion-manager/admin requirement
for ticket-bound membership removal remain. The current order email cleanup,
bank transaction preservation, sorted activity private-head invalidation and
group/activity clock updates remain transactional. No new receipt protocol or
order API is introduced. The source contract now covers 56 functions.

`20261007170000_canonical_order_membership_teardown.sql` is additive and must be
reviewed/applied before DROP. Historical migrations remain unchanged. The revised
contraction checks live function bodies for surviving legacy callers before any
DROP and declares the typed order command in the affected registry entries.
The eight-table/nine-RPC scope and expected 41-to-42 ready registry transition
remain unchanged. This supersedes the #341 SQL digest.

Standard verification: 7 SQL suites passed (new ticket-linked membership removal,
paid-order retention, email cleanup, contracted schema, source parity, internal
ACL and neighboring domains), 6 two-connection tests passed, 21 inventory/cutover
Node tests passed with zero skips. Both order entrypoints were tested after the
old teardown RPC was removed, including denied authorization and full rollback.

CSM web build 620 is deployed. No mobile release is included. Approved write
policy requires build >=620 for group/private-place/activity editors; older
mobile clients retain reads but these editors remain unavailable until their
own separately approved update. Other domains retain their existing contracts.

G3 and exact G4 authority remain required for contraction and reopening. No
production synthetic domain writes or wizard changes were made.
