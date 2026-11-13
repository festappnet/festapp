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
`wallet/emailProviders.ts` contains only public labels/artwork descriptors. Email
preparation uses SQL readiness, never signing credentials. Installation and
activation remain migration/operations-owned and independent per provider.

To add a provider, install a factory implementing the contract, its persistence
and readiness projection, and public browser/email descriptors. The common HTTP
handler and reconciliation engine stay unchanged. A test-only third connector
exercises the actual common HTTP path to prove this seam.
