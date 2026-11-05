# Sale opening notifications - focused abuse review

Reviewed the local single opt-in flow, not the whole platform or deployed ingress.
Recipient and tenant admission, duplicate suppression, queue send gates, contact
permissions and encrypted unsubscribe capabilities are present. This does not
prove resistance to arbitrary HTTP floods or ownership of submitted addresses.

## Remaining limitation 1 - medium: third-party address enrollment

Location: `database/functions/sale_opening_notifications/commands.sql:24-42`.
Evidence: a syntactically valid public request creates state `active`; ownership
verification was explicitly removed at the user's request. Someone can enroll
another person's address for one launch email. Shared recipient/tenant quotas,
suppressions and launch deduplication bound the effect but cannot prove consent.
Do not describe these contacts as verified. Restoring address verification would
change the approved interaction and has not been done.

## Remaining limitation 2 - medium: request-volume protection not established

Location: `supabase/functions/sale-opening-notifications/handler.ts:15-44` and
`database/functions/sale_opening_notifications/commands.sql:28-35`.
Evidence: input is capped at 4096 bytes and new-contact admission is budgeted in
SQL, but the handler has no source-based request limiter or bot challenge. An
existing active address returns before charging admission. This is deliberately
idempotent and creates no mail, but repeated requests still cost Edge/SQL work.
Deployed ingress rate controls were not inspected; this review does not certify
HTTP flood protection. A source limiter must use identity from a trusted ingress,
not client-supplied forwarded headers or browser-only validation.

## Fixed finding 3 - low: unnecessary worker wake amplification

Location: `supabase/functions/sale-opening-notifications/handler.ts:46-48`.
Removed the unconditional shared worker wake after public commands. Neither
subscribe nor unsubscribe creates mail; launch maintenance owns dispatch.
Regression test proves both public operations invoke only the domain RPC, and
removed confirmation requests cannot invoke any mutation.

## Verified controls and evidence

- SQL resolves tenant/form from stored links, not client organization IDs; writes
  require service role. RLS and contact permission matrix protect address reads.
- Shared ordinary quotas are charged before new contact insertion, transactionally.
  Seed defaults are 6/minute and 20/day per recipient, 500/day per unit and
  2000/day per organization; effective overrides and shared usage can differ.
- Duplicates create neither another contact nor another email. One stable launch
  key survives retries; live scope/version/availability gates precede no-order sends.
- Suppressed recipients are not enrolled; response does not expose existing state.
- Unsubscribe tokens use 32 random bytes, hashes and encrypted sources. They are
  purpose/version bound, revoked on resubscription and never returned in signup.
- Focused SQL lifecycle test passed with forced recipient exhaustion and with a
  rotated recipient rejected by the shared unit budget; rejected contacts are not
  persisted. Existing real concurrency and final send-fence tests passed earlier.
- Six Edge handler tests passed, including streaming-size cap, service payload,
  controlled errors, encryption failure and absence of worker wake amplification.

No production requests, real email sends or live ingress changes were performed.

## Follow-up implementation - Turnstile

At the user's request, subscription now requires a provider-validated Turnstile
proof before the domain RPC runs. Validation binds exact hostname, action and
form/contact hash. Missing configuration or provider failure fails closed; stale
or replayed proofs cannot create contacts. A dedicated Managed widget was created,
with interaction-only presentation and no IP-only identity assumption. No live
backend configuration or deployment was performed. Native Flutter has no provider
adapter yet; this implementation covers the two public browser clients.

Eleven Edge tests, 38 JS tests, six Flutter widget/model tests and the targeted
Dart web-adapter analyzer passed. Provider responses in unit tests are simulated;
local browser provider evidence is recorded separately. See
[configuration and boundary](../backend/sale-opening-bot-protection.md).

The remaining source-volume limitation above concerns HTTP resource exhaustion,
not an unguarded subscription write: missing proofs no longer reach SQL. A
volumetric network attack still needs ingress/WAF capacity controls. The remaining
address-ownership limitation is unchanged by bot verification.
