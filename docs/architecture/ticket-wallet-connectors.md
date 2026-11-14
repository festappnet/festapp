# Ticket Wallet connectors

Wallet follows the explicit capability binding and lazy registry pattern used by
`payments/registry.ts`. It has its own domain contract; payment methods, payment
settlement and ticket admission are not simulated as Wallet operations.

`_shared/wallet/contracts.ts` owns the canonical projection and connector port:
identity, delivery capability, `issue` and `reconcile`. `wallet/runtime.ts` is the
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

The inline HTML bootstrap captures the capability plus public provider/language
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


## Multi-ticket proposal (not implemented)

Keep each ticket's identity, QR, admission state and native updates independent.
Offer one Apple and one Google action for all eligible tickets delivered in the
order email, with individual actions retained for people arriving separately.
Use a nearby heading such as “Přidat všechny 3 vstupenky”; do not modify official
Wallet badge artwork. A single-ticket order keeps the existing direct action.

Apple supports a `.pkpasses` bundle (`application/vnd.apple.pkpasses`) containing
independently signed passes. Google supports a single Save JWT referencing
multiple pre-created EventTicketObjects. Adding together and grouping inside the
Wallet are distinct: native grouping should keep the tickets together while
retaining one QR per person. Large orders need bounded batches and link-size
handling; do not assume unlimited platform capacity.

A future bundle link needs its own explicitly authorized, frozen set of delivered
ticket IDs. A forwarded single-ticket capability must never grant access to the
rest of its order. Recheck tenant, event, eligibility and revocation for every
member before delivery; preserve the original per-ticket IDs and update sources.
The common issuance contract should accept an authorized ticket collection and
leave `.pkpasses` packaging / multi-object JWT creation to provider adapters.
There should remain one HTTP entrypoint and one link lifetime, not separate
single-ticket and bundle implementations.

Sources: [Apple distribution](https://developer.apple.com/documentation/walletpasses/distributing-and-updating-a-pass),
[Google save multiple event tickets](https://developers.google.com/wallet/tickets/events/use-cases/save-multiple-passes),
[Google grouping](https://developers.google.com/wallet/tickets/events/use-cases/group-multiple).


## Email action layout

`walletEmailTicket` renders one escaped ticket identity heading with all of its
ready provider actions beneath it. Providers do not repeat the heading or append
a second visible copy of their button label. Each live link has a ticket-specific
accessible name; previews keep actions inert. The same HTML renderer is used by
live delivery and the server-backed draft preview.

Email uses unmodified official condensed Google badges to retain 48 px height
and 8 px clear space within a narrow phone message. `wallet/presentation.js`
contains their versioned URLs and dimensions; the email provider descriptor
chooses artwork without putting provider branches into the layout. Web primary
artwork remains unchanged. Localized text actions are used when official artwork
is unavailable, including Czech Apple text. Publish every new canonical asset
before deploying the renderer that references it. Each ticket retains its own
capability and QR; this layout does not implement multi-ticket issuance.
