# Google Wallet local verification - 2026-11-10

Local implementation and registration only. No production SQL, deployment,
activation, commit or push was performed. See the [runbook](google-wallet.md)
and [issuer registration](google-wallet-registration-2026-11-10.md).

## Confirmed evidence

- 20 Deno tests passed for Google signatures/reference JWTs, stable identities,
  exact barcode data, 409/429/5xx, leases/recovery, capability HTTP boundary,
  compatible native appearance, all delivery modes and email composition.
- 3 SQL files passed against the explicitly marked local disposable database:
  `ticket_wallet_test.sql`, `ticket_delivery_test.sql`, `communication_test.sql`.
  The Wallet test covers replay, historical-token rejection, scoped support
  reissue/audit, manual delivery, expiry/rescheduling, preference preservation,
  both send-fence directions, immutable retry snapshots, claims, used/storno,
  order invalidation and retained identity after ticket deletion.
- 16 Node tests passed for the page/token lifecycle and isolated-browser startup.
  The isolated real Chromium `/wallet` fixture passed with Node 22.23.3 and
  agent-browser 0.39.4: fragment removed before startup, no automatic issuance,
  explicit action, recoverable provider failure, no token in localStorage.
- The standalone native Flutter preview test passed with `--concurrency=1`.
  Its [light Czech preview](google-wallet/wallet-preview-cs.png) uses an explicitly
  invalid sample QR. The initial canonical ticket-preview-and-delivery lane
  passed; subsequent affected Edge checks encounter the unrelated in-progress
  payment runtime export described below.
- Actual Google Class and Object creation, Google account save, same-object
  venue/date updates, `COMPLETED` after canonical scanner admission and `INACTIVE`
  after local storno were verified. The exact original symbol matched Google
  readbacks and a second canonical scanner operation returned `already_used`.
  [Sanitized API evidence](google-wallet/demo-api-evidence.json) contains no QR,
  capability, JWT or credential.
- The subsequent [optical simulation](google-wallet/optical-scan-evidence.json)
  passed: an authentic 364 x 364 screenshot of the saved Google Wallet QR was
  fed through production `ScannerInput.frame`/jsQR, decoded to the exact original
  symbol, accepted on first admission and rejected on the second as `already_used`.
  The same saved pass then read back as `completed`, `hasUsers=true` and unchanged
  QR. Physical camera hardware was not used.

## Canonical CI status and remaining gates

The selected canonical lanes were invoked through `automation/test_ci.sh` with
pinned runtimes. They are **not all green**. The shared working tree acquired
unrelated order/payment edits during this task:

- SQL parity currently rejects authored `get_order_deletion_context_v1(bigint,uuid)`
  because its changed source is not in the effective migration head. This blocks
  both seat-checkout and web measurement. The canonical source-contract generator
  must be rerun after that owner's source/migration alignment; do not waive it.
- A later Flutter run hit the absent `DbOrders.insertManualTransaction` member.
- A later ticket-edge run hit the absent `stripeHostedPaymentDependencies`
  export required by the changed payment runtime (10 entrypoint failures).

Those foreign edits were preserved. Prior passing receipts do not certify these
later changed inputs. After the other owners finish, regenerate the canonical
source contract and run the affected canonical lanes on the final combined tree.
The changed Wallet SQL and ticket-write-contract assemblers themselves pass
`--check`. No release/publication gate was bypassed.

Public rollout additionally requires confirmed Google publishing access, an
explicit tenant/release authorization, immutable badge publication, protected
backend secret staging, dormant worker activation after its probe, measured
five-minute reconciliation capacity. The requested optical simulation is now
verified; a physical camera/phone-display check remains separate device QA.
The publishing request was clicked once but its submission is unconfirmed;
this is not a verified pending/approved publishing state.
