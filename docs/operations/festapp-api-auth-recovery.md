# Integration authorization recovery and capacity

One process owns the existing encrypted SQLite store. A restart using the current
DB retains active grants. A restored older DB can resurrect revoked grants and
consumed refresh credentials. Never open ingress against a rolled-back snapshot.

1. Close both API ingresses and MCP/token traffic; stop the sole owning process.
2. Restore DB and its matching storage key using protected operational storage.
   Preserve the separate issuer signing keys, broker secret and cookie key ring.
3. Run `node tools/festapp/src/remote/main.mjs recover-restored-state --secrets
   /absolute/protected/secrets.json --data /absolute/protected/state` offline.
   It takes the owning process lock, atomically removes all restored OAuth,
   delegation, backend-session and interaction records, retaining only metadata.
   It neither touches domain command receipts nor creates replacement commands.
4. Start the reviewed matching source/image + docs pair, verify expired/revoked
   token rejection, then reopen ingress and require new explicit consent.
5. If an earlier command outcome is uncertain, an authorized administrator must
   establish its original SQL result. Reconsent is never permission to retry with
   a new UUID. Domain receipt access may depend on the old backend session binding.

Signing rotation: publish overlapping public verification keys with unique `kid`,
keep the old signing key through all admitted flow/token lifetimes, then retire.
Opaque token revocation requires grant/token revocation; signing rotation alone
is insufficient. Broker rotation requires coordinated issuer/broker deployment
and pending-flow handling. Cookie rotation keeps the previous verification key
through admitted interactions. Storage-key rotation requires offline transactional
re-encryption, current-state backup, decrypt/readback verification and an atomic
DB/key switch. The offline command is:

`node tools/festapp/src/remote/main.mjs rekey-storage --from-secrets
/absolute/protected/old.json --to-secrets /absolute/protected/prepared-new.json
--data /absolute/protected/state`

Prepare and retain the new credential in the approved secret manager/Keychain
before running it. Both protected files must be outside the data directory and
must differ only in storageKey. Stop the owning service first; its process lock
blocks online use. The command re-encrypts and reads back every record inside
one FULL SQLite transaction. Failure rolls back all rows. After success, start
with the prepared new secrets path; preserve the old file only for its matching
historical backup. An interrupted/lost response requires offline key/readback
verification, never reopening ingress with a guessed backup. At commit, the DB
accepts exactly one key; a wrong configuration fails closed. The command does
not rewrite or print either secret file and does not implement online rekey.
New retained local credentials belong in Keychain, not only a mode-0600 export.

Provider 9.12.2 retains spent refresh credentials for reuse detection. The
versioned `refresh-replay-v1` upgrade packs their exact payload and original
expiry into 256 encrypted compressed buckets in this same SQLite owner. It
preserves existing opaque credential strings. Adapter lookup reconstructs the
exact consumed payload, so provider client/key/expiry checks and family reuse
revocation still apply. Upgrade is transactional and cannot discard live proofs.

Each bucket has a 128 KiB compressed and 2 MiB decoded limit. Total compressed
replay payload is bounded by 32 MiB plus AES overhead; one lookup decodes at most
2 MiB. Appending prunes only expired entries. Overflow refuses consumption
atomically and leaves the current credential usable. Main records retain the
20,000-row cap; API and MCP share admission, with at most 16 new active/pending
connections across the owning runtime. Existing legacy connections are not
revoked to create space. New consent also requires 2,000-row headroom and replay
storage below 24 MiB. Refresh reserves live-token headroom before consumption
and permits at most 12 valid rotations per connection per minute, using the
existing limiter. Saturation returns temporarily_unavailable; it does not relax
reuse detection or evict evidence. A known rejection before consumption can be
retried after Retry-After, preserving the credential; a lost response remains
uncertain and requires reconnect.

Consent defaults to seven days. Registered policy may explicitly allow 30, 90
or 365 days, with the original fixed consent deadline and 30-day idle limit.
See the year-refresh benchmark evidence for actual five-minute exchange/store
results; a capacity cap is not an availability promise for arbitrary adversarial
load. Issuer token_window audit events report exchange/rejection counts, latency,
queue size, active connections, record count and replay bytes without tokens.
Connect the existing protected log pipeline to alerts before rollout: record
occupancy >=90%, replay bytes >=24 MiB, queue saturation, repeated exchange
rejection/reuse and elevated latency. Deployment must verify alert delivery;
local instrumentation is not evidence that production monitoring is enabled.

Do not raise row/heap/container limits or discard unexpired reuse evidence.
Single-flight client refresh and atomic persistence remain mandatory; a lost
refresh response requires reconnect without a grace window. An older DB backup
must still undergo invalidate-restored-state, even if the encryption key matches.


Activation rollback closes the new API ingresses and disables new API clients
while retaining the reviewed runtime and current authorization DB for MCP.
Do not open a pre-refresh-replay-v1 binary against a migrated live store: that
binary cannot look up the packed spent proofs. Binary rollback requires an
explicit offline matching DB/config recovery plus invalidation/reconsent before
traffic; it is not a drop-in image swap. Preserve both immutable image generations.
