# Apple Wallet verification - 2026-11-13

Selected tenant: `festapptickets`, `vstupenky.online`, canonical organization 3.
The live activation document reports generation 1 and the canonical backend;
SSH host, configured runtime database, actual database and stored organization
were independently matched. The historical `rehearsal` host/database names are
the canonical live target, as recorded in the runtime guard.

Apple created Pass Type ID `pass.net.festapp.tickets` (resource `83NJA6C966`) and
certificate `RF679Q7ZSL`, team `8WKBB6L8LT`, valid through 2027-12-13 18:18:44 UTC.
Apple WWDR G4 chain and private-key match were verified. Certificate and key are
retained in encrypted login Keychain; iCloud synchronization is not verified.
No secret material is included here.

The exact production-image local smoke used
`supabase/edge-runtime:v1.74.0@sha256:ac5a8314e0c45b0f65d091643c1d6f5293e3a38f31fd3d15186e04a9d5c91cb7`,
the real certificate and an explicitly invalid sample admission QR. It generated
a signed 10079-byte pass with native update metadata. An HTTP/2 mutual-TLS APNs
request returned the expected invalid-device result for the all-zero test token;
no device was notified. This caught unsupported Node X509 methods in that runtime,
which were replaced by the maintained crypto implementation used by PKPass.

Targeted evidence: 22 Edge tests passed, including actual detached CMS verification
through OpenSSL, manifest digests, stable/scoped identity, HTTP authentication,
conditional updates, third-connector extensibility and notification fencing.
Eight web tests passed for provider choice, retry, safe redirects and native POST.
The disposable SQL lifecycle test passed for independent provider readiness,
saved authentication, device registration, monotonic update tags/Last-Modified,
used/storno/deletion and stale receipt rejection. Two configuration-migration
tests verify bounded changes, idempotence and injection/identity rejection.

These are preparation receipts, not production-release completion. Production
source/tenant revisions, release gates, deployment and live artifact verification
must be recorded by the rollout executor. Actual acceptance into a physical
user's Wallet and physical camera scanning have not been performed by this agent.
