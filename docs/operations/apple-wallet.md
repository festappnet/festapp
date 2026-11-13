# Apple Wallet

Apple Wallet uses the existing organization Wallet connector, `wallet_enabled`
preference, encrypted email capability and `/wallet` page. Google activation
remains independent. Apple issuance does not call Google or create Google objects.
The exact original ticket QR is preserved; the canonical scanner owns admission.

## Delivery

`POST /functions/v1/ticket-wallet` accepts `{token, provider: "apple"}` or a
native URL-encoded form with exactly those fields. Safari receives the signed
`application/vnd.apple.pkpass` response directly, with filename `ticket.pkpass`.
The form keeps the 256-bit capability out of URLs and browser storage. Origin,
request-size, token/source rate, scope, payment and revocation checks use the
existing Wallet boundary. The projection is resolved again after signing to
reject concurrent changes. GET never issues a pass. Existing Google JSON
requests remain unchanged. No app entitlement or installed Festapp app is needed.

Serial numbers hash the immutable environment, organization, occasion and ticket
ID. Downloading again updates the same Apple pass. Used tickets are voided;
inactive, revoked, unpaid, expired or deleted tickets cannot be downloaded.
Saved passes include the native update service and an independent encrypted
pass authentication source. Devices register their APNs tokens, poll scoped
monotonic update tags and fetch signed updates using `ApplePass` authorization.
Conditional fetch supports ETag and Last-Modified, including multiple changes
within the same second. The common scheduler checks registered passes every
minute; changed passes notify devices over certificate-authenticated APNs HTTP/2.
Failures back off and preserve identity; invalid APNs tokens are removed. A
phone can remain offline, so the canonical scanner always owns admission.

See [the shared connector architecture](../architecture/ticket-wallet-connectors.md).

## Activation

The selected rollout is `festapptickets` / `vstupenky.online`, organization 3.
Source preparation and production verification are recorded separately; do not
infer deployment from certificate creation or local tests. Use the canonical release workflow for
one selected tenant, including its exact-main CI gate and protected backend
restart. The migration is `20261113180000_apple_ticket_wallet.sql`; regenerate via
`python3 automation/assemble-apple-ticket-wallet-migration.py`. The native update
service is `20261113190000_apple_ticket_wallet_updates.sql`, regenerated with
`python3 automation/assemble-apple-ticket-wallet-updates-migration.py`.

1. Create or select a Pass Type ID and its signing certificate in the restored
   Apple Developer membership. An Apple Distribution certificate is insufficient.
   The verified Pass Type ID is `pass.net.festapp.tickets`, team `8WKBB6L8LT`.
   Certificate `RF679Q7ZSL` expires on 2027-12-13. Certificate and key were verified
   through Apple APIs, matching key material and the Apple WWDR G4 chain.
2. Persist the private key/certificate in Apple Passwords/iCloud when supported,
   otherwise encrypted login Keychain, record only their locators in the protected
   credential index, and verify storage. Never commit or log private key values.
3. Set backend secret `APPLE_WALLET_CREDENTIALS` to JSON containing
   `passTypeIdentifier`, `teamIdentifier`, `signerCert`, `signerKey`, `wwdr`, and
   optional `signerKeyPassphrase`. PEM values include real newlines. `wwdr` is the
   matching Apple WWDR intermediate. The adapter checks validity dates, certificate
   signature, Pass Type ID, team and private-key match before every issuance. Set `APPLE_WALLET_WEB_SERVICE_URL` to
   `https://api.festapp.net/functions/v1/apple-wallet`. The production Edge Runtime
   crypto path is tested separately from workstation Deno.
4. Configure exact HTTPS origins in `TICKET_WALLET_ALLOWED_ORIGINS`. Existing
   `GOOGLE_WALLET_ALLOWED_ORIGINS` remains the fallback when the shared setting is
   absent. No wildcard is accepted.
5. On the existing `eshop.ticket_wallet_integrations` row, set
   `apple_pass_type_identifier`, `apple_team_identifier` to the signing identity.
   Keep `apple_publishing_ready=false` until the real Apple chain, runtime signing,
   update protocol and APNs connection probes pass. Enable it independently of
   Google's `publishing_ready`, with a native-device acceptance check recorded
   separately from server availability.
   Apple-only rows can omit the Google issuer. Never change the established
   environment, team or pass type for issued passes as a retry strategy.
6. The web build bundles the unmodified official badge from
   `assets/brand/apple-wallet/en.svg`. Email supports the same badge after canonical
   image Worker publication at `assets/apple-wallet/v1/en.svg`, configured as
   `badge_urls.apple.en`. Without it the translated Apple text link still works.

Readiness is fail-closed and fingerprinted per provider for unsent email snapshots.
A disabled provider does not prevent the other provider's email offer. Preference
changes affect future email offers, not previously issued capabilities.

## Evidence and remaining external checks

Tests use disposable signing certificates, independently verify the detached CMS
signature and manifest digests, inspect the ZIP/QR/identity and exercise the HTTP
boundary and native form. They cannot attest Apple trust or native installation.
Before activation verify the actual Apple chain, add the pass on iPhone, inspect
QR scanning, seating, locale, repeat download and used/storno behavior. Record actual native installation separately; server success does not prove
that a user accepted the pass into their Wallet.

References: [building passes](https://developer.apple.com/documentation/walletpasses/building-a-pass),
[distribution](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/PassKit_PG/DistributingPasses.html),
[official artwork](https://developer.apple.com/wallet/add-to-apple-wallet-guidelines/).

## Bounded environment migration

`automation/hetzner-supabase/runtime/configure-apple-wallet.py` installs exactly
the two Apple inputs while preserving the complete six-file Compose model and
all unrelated services/environment. It requires paused, drained email before
application; creates private backups; deliberately recreates only Functions
using every installed overlay; validates running configuration and worker auth;
and restores previous configuration on failure. Email remains paused until
release probes and queue health pass. This is a configuration migration, so the
ordinary code-only restart script must not be substituted.

The signing key and certificate are retained in encrypted login Keychain under
`festapp.apple-wallet.pass-signing-key` and
`festapp.apple-wallet.pass-signing-cert`, account `pass.net.festapp.tickets`.
iCloud synchronization is not verified. Never copy protected input values to
release receipts or repository files.

The router proof allowlist must include `apple-wallet` and its shared
`emailWorkerEnvironment` filter must pass Apple inputs only to the three Wallet
owners. Apply the canonical proof-route patch to the backed-up installed router
before the guarded Functions configuration migration. Native requests carry
ApplePass authentication, not a Supabase user JWT.
