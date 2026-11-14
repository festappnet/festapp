# Ticket Wallet connectors

Wallet follows the explicit capability binding and lazy registry pattern used by
`payments/registry.ts`. It has its own domain contract; payment methods, payment
settlement and ticket admission are not simulated as Wallet operations.

`_shared/wallet/contracts.ts` owns the canonical projection and connector port:
identity, delivery capability, `plan`, `issue` and `reconcile`. `wallet/runtime.ts` is the
only backend composition root. It installs Google and Apple factories in the
strict `WalletRegistry`. Unknown, duplicate and mismatched IDs fail closed.
Factories acquire credentials only when their operation executes. One provider
being unavailable does not stop the other's reconciliation.

`ticket-wallet/handler.ts` owns bounded capability input, exact-origin checks and
transport dispatch. It knows redirect/file result kinds, not provider SDKs,
provider hosts, signing keys, Google classes or Apple devices. Existing JSON
requests without `provider` retain Google's explicit default at the composition
root. File delivery uses native form POST so Safari receives the actual pkpass
MIME type; tokens never enter query strings or browser storage.

`wallet/connectors/google.ts` owns Google's class/object queue and URL adapter.
`wallet/connectors/apple.ts` owns Apple pass registration and signing orchestration;
`appleWalletUpdates.ts` owns its encrypted authentication source and APNs receipt
loop. Provider persistence is part of each adapter, as with `PaymentStore`: Google
has durable class/object work, Apple has pass/device/update-tag state. Both use the
same canonical capability, paid-ticket projection, tenant scope, preferences and
support revocation. No independent admission lifecycle or persistent application
trigger is introduced. One trusted `sync-ticket-wallet` entrypoint and scheduler
reconcile the installed providers.

Apple's native update protocol is a capability of its adapter and lives at
`apple-wallet/v1/...`: authenticated registration/removal and pass fetch, opaque
device-scoped update enumeration, conditional fetch, and bounded discarded logs.
It is not a payment webhook or a new customer authorization path. Saved Apple
passes retain stable serial/authentication identities; updates can void used,
storno and deleted tickets. APNs uses the Pass Type ID certificate over mutual
TLS/HTTP2. Stale lease holders cannot acknowledge pushes; invalid tokens are
removed, and failed transport is retried with bounded backoff.

The browser composition root is `components/wallet_connectors.js`. The shared
page renders descriptors and dispatches delivery capabilities; redirect URL
policy belongs to its descriptor. The email composition root
`wallet/emailProviders.ts` binds verified email artwork to the same public labels
and artwork metadata as the browser, owned by `wallet/presentation.js`. That
module has no credentials or provider SDK imports. Email
preparation uses SQL readiness, never signing credentials. Installation and
activation remain migration/operations-owned and independent per provider.

To add a provider, install a factory implementing the contract, its persistence
and readiness projection, and public browser/email descriptors. The common HTTP
handler and reconciliation engine stay unchanged. A test-only third connector
exercises the actual common HTTP path to prove this seam.


## Email link lifetime

The inline HTML bootstrap captures the capability plus public provider/language/collection
hints before removing them from the address bar. `components/wallet_link.js`
consumes that input in memory and owns subsequent `popstate`, `hashchange`, and
restored-page input. It handles Safari reusing the same tab, including opening
the same legacy link again. One navigation is consumed once even if the browser
emits both history and fragment events. Inputs from other routes are left intact.

Each opened link has an AbortSignal. Replacing it or leaving the route aborts
its pending request; late responses cannot navigate, replace the new ticket's
status, or re-enable its controls. The router disposes the Wallet page on route
changes. The page renders named copy and dispatches through one save action;
provider descriptors own platform preference, artwork and redirect policy.

Native form delivery uses `strict-origin` referrer policy. `no-referrer` makes
cross-origin form POST Origin opaque (`null`) in browsers and fails the exact
origin allowlist. Only the public origin is sent; the capability stays in the
POST body and browser memory. Public provider and language query hints select
the email action automatically; legacy links select the installed device's
provider. Used-ticket warnings still require explicit continuation.


## Multiple delivered tickets

`prepare_ticket_wallet_collection` mints a separate encrypted capability for the
immutable delivered set (2-1000 members), bound to organization, occasion, order,
recipient and each individual capability hash/generation. Replays reuse its
source. A single-ticket capability never expands to the order; later purchases
and replaced generations never join the set. `collection_enabled` defaults false
per integration. Its rollout is limited to the explicitly selected tenant.

The SQL scope owner checks canonical paid-ticket eligibility, revocation and
current event term. Collections include active members only. `plan` exposes
counts, a scope revision and provider part sizes without IDs or QR data. A partial
set requires explicit continuation. `get_ticket_wallet_projections` loads only
the planned portion (at most ten). Issuance requires its revision and rechecks
both authorization and every selected projection after signing/synchronization.
HTTP input selects a part index, never ticket IDs.

Apple packages unchanged independently signed passes as `.pkpasses` with MIME
`application/vnd.apple.pkpasses` (at most ten, at most 150 MB per bundle). Each
member keeps its original serial and update authentication. Google synchronizes
only the selected pre-existing identities and signs one multi-object Save JWT;
the adapter partitions against the actual 1800-character signed URL limit and
the shared ten-member work bound. Individual requests retain their original
native `.pkpass` / single-object behavior.

New multi-ticket email has one Apple/Google pair for the frozen set and secondary
individual links. One-ticket email uses singular copy and direct provider
buttons. Public `scope=collection` is a presentation hint captured before URL
scrubbing, never an authorization input. Without it a group cannot issue because
its mandatory plan revision is absent. Both kinds use the same HTTP entrypoint,
connector contract and link lifetime. Large-order controls state that each group
needs confirmation. A file submission gives conditional native/Downloads instructions;
it does not claim that a wallet dialog opened or a pass was saved.
Adding together does not itself configure grouping inside either wallet.

Sources: [Apple distribution](https://developer.apple.com/documentation/walletpasses/distributing-and-updating-a-pass),
[Google save multiple event tickets](https://developers.google.com/wallet/tickets/events/use-cases/save-multiple-passes).


## Email action layout

`walletEmailTicket` renders one escaped ticket identity heading with all of its
ready provider actions beneath it. Providers do not repeat the heading or append
a second visible copy of their button label. Each live link has a ticket-specific
accessible name; previews keep actions inert. The same HTML renderer is used by
live delivery and the server-backed draft preview.

Email and web use unmodified official condensed Google badges and the installed
localized Apple badges, all at 48 px high with 8 px clear space. The approved
Apple archive supplies all six supported locales. If a locale is not installed
in an integration, use its verified English original with localized surrounding
copy/accessible labels. Never fabricate a localized badge
or reshape provider artwork. Their official corner geometry differs; alignment,
height and clear space are shared. Web labels are visually hidden while artwork
is present and become visible if loading fails. `wallet/presentation.js` owns
public URLs, dimensions, localized labels and provider handoff instructions.
Publish every new canonical asset before referencing it in live email.

Chrome on macOS may download `.pkpasses` while leaving the bridge document open.
Submitting a form proves neither native preview nor successful download. The
file connector's conditional completion copy covers a native dialog, Downloads,
and opening the original email link in Safari on iPhone. A failed submission
retains its retry state. A one-part order does not display a technical group
number; count/availability appears before the provider actions. These changes
do not alter capabilities, issuer identity, QR data, saved-pass updates or the
collection authorization boundary.
