# Barion sandbox probe

Operator-only protocol verification. This is not a registered application
connector, marketplace activation, or evidence of a successful payment.
`BarionSandboxProvider` can only call `api.test.barion.com`; live snapshots and
redirects to the live payment gateway are rejected.

The probe reads the existing sandbox POSKey and verified wallet email from the
macOS login Keychain (`festapp-barion-sandbox-poskey` and
`festapp-barion-sandbox-payee`, account `festapp-sandbox`). Keys never go in CLI
arguments, output, repository files or `/tmp`. Login Keychain is local encrypted
storage; iCloud synchronization has not been established.

An authorized independent test requires an approved sandbox shop and this
explicit command, with its non-secret shop identifier:

```sh
FESTAPP_BARION_SANDBOX_SHOP_ID='<sandbox-shop-id-32-hex>' \
  deno run --frozen --lock=supabase/functions/deno.lock \
  --allow-env --allow-read --allow-write --allow-net --allow-sys=homedir \
  --allow-run=security,cloudflared,curl \
  automation/payments/barion_sandbox_probe.mjs --dispatch-sandbox \
  --case=unique-independent-test-case
```

It prepares a private durable intent before one 1 CZK sandbox Start. Receipts
are retained under `~/.local/share/festapp/barion-sandbox/` with restricted
permissions. A temporary Cloudflare quick tunnel exposes only a constant return
page and a random callback path, not an application or production backend.
Readiness uses publicly resolved DNS and normal TLS verification, without
modifying system/browser DNS or disabling certificate verification.

The callback is only a hint. Financial state is fetched with shop authentication
and bound to the saved payment/command identity. Polling is separated by at
least 5.5 seconds. In the active terminal, `status` reads state and `stop` closes
the local server/tunnel. Browser checkout interaction must use the delegated
Terra/Panerelay workflow and the private checkout metadata, without logging keys
or private URLs.

The latest active receipt is referenced by `/tmp/festapp-barion-sandbox-active.json`.
A named case is reserved once and cannot be replayed. If a previous active
Start is unresolved/dispatched, a distinct independent operator test also needs
`--independent-of=<previous-attempt-UUID>`. This preserves the predecessor's
uncertainty; it is never recovery or a replacement payment for the same order.
Do not remove case guards. `--resume-prepared=<attempt-UUID>` with the same case
can resume local bootstrap only before remote dispatch. It rejects dispatched
or uncertain receipts. No Start is automatically retried.

The probe does not initiate refunds, install SQL, register a provider for sales,
or send requests to a production endpoint. The sandbox shop is now approved and
has a CZK wallet account. See the dated approval/payment receipt in
`docs/plans/payment-provider-hardening/` for actual evidence and remaining gates.
The first Start remains unresolved because its status/body was not retained;
later account responses do not retrospectively establish its outcome.

## Registered sandbox connector and operator followups

The application connector now lives in `_shared/barion/` and SQL `eshop_barion/`.
It uses the common financial owner; the probe above remains an independent
operator experiment. SQL, Edge, Dart and JS explicitly register Barion, while
public sales/recipient discovery and live mode stay disabled. Server configuration
requires `BARION_SANDBOX_ENABLED=true`, `BARION_SANDBOX_SHOP_ID`,
`BARION_SANDBOX_POSKEY`, `BARION_SANDBOX_PAYEE`,
`BARION_SANDBOX_CALLBACK_URL` (the generic webhook with `provider=barion`), and
JSON `BARION_SANDBOX_ALLOWED_ORIGINS`. Never place secret values in this document,
CLI arguments, receipts or the repository. A service operator configures explicit
sandbox form IDs through `configure_barion_sandbox_connection_internal`;
this is not a customer credential/onboarding API.

`barion_sandbox_observe.mjs` reads a known retained attempt, optionally selected
with `--attempt=<UUID>`. An explicit `--dispatch-sandbox-refund`,
`--refund-minor=<integer>` and `--command=<new UUID>` permit one sandbox-only
operator refund. A durable refund intent is created first. Dispatched/uncertain
refunds block subsequent commands on the same payment; do not delete receipts
to retry. This tool is not an application refund capability. It uses the same
Deno permissions as the probe, but only `--allow-run=security`.

`barion_sandbox_apply.mjs --attempt=<UUID>` is a real authenticated read through
the actual adapter and common recovery engine into disposable SQL. It requires
local `BARION_DATABASE_URL`, `--allow-run=security,psql` and the retained Keychain
credentials. The database identity must be `festapp-payment-provider-hardening`.
Synthetic orders, tickets and queued email intents are rolled back; no workers
or outbound emails run. No external mutation or Start is performed by this tool.

For expiry-only experiments, the original probe accepts
`--window-seconds=60` (default 1860, maximum 1860). An expired original transaction
can retain Total=1 while the payment's Total becomes 0; this is not a payment.

## GoPay sandbox pilot

GoPay is installed by `20261125130000_gopay_sandbox_connector.sql`. It starts
disabled and supports CZK card checkout with one sandbox merchant in a test
deployment. The organization must explicitly allow the payment method. Set one
operator-managed connection on a disposable tenant using
`configure_gopay_sandbox_connection_internal`. Bind the same connection under
`payments.providerConnections.gopay` on the two test forms. The service RPC
checks that both forms belong to the unit and organization. Enable the
connection only after the test storefront routes and backend environment match.

Use a first-level Pages custom domain such as
`prodej-test.vstupenky.online` for the pilot. The DNS alias must serve the same
application build and disposable backend for both forms. Set the exact origin in
`GOPAY_SANDBOX_STOREFRONT_ORIGIN` and in the connection. Set
`GOPAY_SANDBOX_GO_ID`, `GOPAY_SANDBOX_CLIENT_ID`,
`GOPAY_SANDBOX_CLIENT_SECRET` and `GOPAY_SANDBOX_NOTIFICATION_URL` in the
server environment before setting `GOPAY_SANDBOX_ENABLED=true`.
The notification URL targets `payment-webhook?provider=gopay&hook=…`. Use a
random 64-character hexadecimal hook value. Keep endpoint URLs containing that
value and GoPay secrets in the protected server configuration.

Both forms use the same GoPay merchant and storefront return path. Run a test
payment on each. Check GoPay's return, asynchronous notification, and the order
and ticket state. Check declined and expired payments separately. If a
create response is lost, the original checkout stays unresolved until the
merchant ID can be verified. Refund states hold admission pending verification
of the refund history contract. The documented history examples repeat the
payment ID and give calendar dates, so they cannot establish a unique refund
movement or its precise time. Processing fees and the platform service charge
are outside the customer payment facts.
