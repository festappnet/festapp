# Disposable Blueprint B business runtime

This setup is restricted to project `festapp-blueprint-b-e2e-20261019`, API
`127.0.0.1:59521`, PostgreSQL `127.0.0.1:59522`, and image bridge port `59525`.
It preserves other local projects and contains synthetic data only.

From the isolated Festapp checkout:

```sh
python3 automation/blueprint_local_e2e.py
python3 automation/blueprint_local_e2e_fixture.py
supabase functions serve --workdir /Users/miakh/source/festapp-blueprint-b-e2e-20261019
python3 automation/blueprint_local_e2e_order.py
python3 automation/blueprint_local_e2e_finance.py
```

The bootstrap restores the canonical schema baseline, only newer forward
migrations, reference identities required by guarded migrations, and the normal
synthetic seed. It records completed migrations so an interrupted task can resume.
Demo maintenance migrations that explicitly require `postgres` retain that role.
Other forwards run with the local extension-owning admin; application functions
created by that admin are reassigned to canonical `postgres` ownership, excluding
extension members. This matters because trusted email producers check the actual
function owner. No permission guard is weakened.

`private-defines.json`, `fixture.json`, image HMAC environment variables and command
receipts live under the owned backend directory with mode 0600. The fixture JSON
is the current source of form/occasion links, node/spot identities and hold tokens.
Old IDs from an earlier database must not be reused.

The fixture contains persisted V2 geometry, genuine registered Futura outlines,
free standard/premium seats, blocked and unassigned seats, used/ordered seats,
foreign and own holds, an atomic couch, mixed/default/empty groups and standing
inventory. Paid fixtures include a two-ticket order and two separate orders with
100/150 CZK seat products and matching payment facts. All subsequent swap and
checkout scenarios use canonical SQL commands and real receipts.

The real `send-ticket-order` Edge function is used. Synthetic bank configuration
produces the normal payment reference/QR, while external service configuration is
empty. Every scheduler job is inactive, `email_capacity.paused=true` and its worker
URL is null. Order confirmations remain real queued email intents. No email
provider, bank provider, payment gateway or invoice service is called.

Observed evidence:

- Actual anonymous hold plus addressed seat and standing checkout committed order
  7 for 180 CZK. An identical command/client replay returned the same order.
- Paid-to-free, same-order and different-order swaps ran through authenticated
  preview and receipted commands. Replay did not change balances. An inverse
  command restored payment amounts, paid values and spot/ticket identities.
- Single used-seat preview is accepted by the existing swap authority; preview
  rolls back all changes. Atomic used-unit rejection remains covered by the SQL
  domain tests. This is recorded policy, not an invented client restriction.

Current private evidence is `order-smoke.json` and `finance-smoke.json` in the
owned backend directory. Console output contains only IDs, amounts and verdicts.
The smoke scripts do not establish delivery to a real email address or live
payment-provider behavior.

Setup-draft verification now uses the same disposable backend and canonical
finalizer. `database/tests/blueprint/setup_draft_integration_test.sql` runs in a
rollback transaction and proves source geometry/product/context remapping, no
copied holds/orders, aggregate revision 1, identical-command replay, new standing
capacity through the inventory owner, and atomic rollback on invalid capacity.
`automation/blueprint_local_e2e_setup_font.py` additionally exercises the actual
authorized Edge endpoint before an occasion exists: real Futura outlines (316
glyphs including Ž), followed by the unit-scoped safe resource read. It deletes
its disposable draft. The first outline request took 3.98 seconds; the ready
resource request took 0.242 seconds.

The actual JavaScript buyer UI also committed order 8: two addressed couch seats
and two standing tickets, with payment amount 360 CZK. Confirmation and reminder
remain queued behind the paused local delivery boundary. Sanitized persistence
evidence is `checks/js-ui-checkout.json`. These sold seats remain intact for
review.

C05 public availability is now read from the existing form catalog projection,
including visible offers, maximum/ordered counts and dynamic inventory state.
The actual anonymous HTTP read returned four products with all availability
fields and no customer metadata. `public_hold_availability_test.sql` proves
whole-unit maximum and shared-context rejection without partial holds, hidden
and unoffered rejection, real planned-price/visibility worker behavior, and own
hold retry/release preserving the original expiry after availability changes.

`setup_named_slot_copy_test.sql` proves both wizard finalization and existing
occasion duplication use the same extracted private resource/slot and empty-spot
copy owners. Named slot metadata and exact physical supply survive; allocations
do not. The real schema enforces resources.capacity NOT NULL, so the fixture
uses capacity 2 and two named slots without weakening that constraint.
Migration 20261019130000 was applied only to the owned disposable project; the
20261019100000 and 20261019120000 historical migrations were preserved.

A further rollback regression reproduced an addressed-seat PIC oversubscription:
two different products held seats with inventory_context NULL against one shared
remaining slot, and both requests previously returned 200. Hold admission now
counts existing active addressed spot holds through their PIC quantities, using
the existing spot hold records and context/pool locks. It subtracts direct
physical occupancy already counted and ignores expired/ordered records.
`addressed_hold_context_admission_test.sql` proves the second hold rejects
atomically, original retry expiry survives, release restores admission, quantity
2 consumes two units, direct context occupancy is not counted twice, and expired
indirect holds no longer consume admission. The public catalog/wave/unit
regression also remains passing. Checkout retains its existing final authority.

The final setup forward 20261019200000 retains the entire approved main finalizer
from commit 6cbb4b163d14118a7cdcda2b79cf12694a435cff, including communication,
reply defaults, payment-account checks and price-wave materialization. Its only
B changes are the V2 active-empty guard, the source form-link identity guard,
and aggregate V2 blueprint materialization. The six active-feature scenarios
and source/fresh setup integration tests passed against this full owner.

The actual Flutter buyer created order 19 with Free standard plus one standing
ticket, price/payment 180 CZK. Admin swaps persisted ticket 4 at Same order A,
ticket 3 at Same order B, ticket 5 at Other order B, and ticket 6 at Free premium.
The first admin replacement attempt returned an application error inside HTTP
200 and created no order. The local bootstrap table owner on waitlist_offer_slots
was corrected to the canonical postgres owner; no application grants or RLS
were relaxed. The facade now rejects such application failures and V2 swaps
always invoke the existing receipted TicketCommands authority.

Canonical runtime cutover (210000) removes the old update_blueprint RPC and its
internal legacy writer, archival geometry projections/discovery, and duplicate
object remapping. Runtime readers require layout; offline migration alone uses
BlueprintModel.fromLegacyJson. Actual poison-archive and registry tests pass.

The private reviewed migration (220000) accepts exact reviewed source text, its
SHA256, the canonical request and command UUID. It compares the locked UTC
export projection by JSONB equality, validates stable IDs/products/titles/groups,
then seeds only binding metadata before the same aggregate implementation.
Existing spot rows, ticket state, payment facts and current hold tokens/expiry
remain byte-for-byte unchanged, including NULL titles and holds changed after
review. Real rollback tests cover ordered, used, active hold, stale geometry,
wrong hash, changed group/title, rollback and exact receipt replay. A separate
actual demo test proves this explicit private migration succeeds while normal
aggregate edits and normal mutation receipts still reject demo writes. The
private implementations have no API-role execute grants. Production data
migration and activation remain unapplied by this agent.

Final actual admin replacement created order 20: three addressed tickets for
350 CZK. Order 3 retained its other ticket and amount 150; order 4 became storno
with no assigned spots. Its historical payment facts remained intact. Wizard
UI creation produced occasion 104 (zcavyver), blueprint 55 revision 1, 15 new
bindings, the edited group label and no copied reservations/orders.

The final all-source SQL replay also passed 49/49 reviewed layouts and 4516
physical seats, including identical-command replay, on synthetic local IDs with
full rollback (`/tmp/blueprint-b-reviewed-replay.log`). Production migration and
activation remain unapplied.
