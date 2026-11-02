# Slunovrat native news recovery

The user authorized a temporary news and push bridge for Slunovrat Winter
Edition, occasion 1072594 / organization 19 / unit 999. Released iOS sources
including `d0f36201f` (0.20.141) use direct REST inserts when Client Sync v1 is
not selected. October's backend contraction revoked those inserts. Modern
typed-command tests did not exercise that shipped native-client path. The older
Slunovrat standalone tests replayed October 13 migrations rather than the final
database ACLs.

`automation/hetzner-supabase/runtime/slunovrat-news-emergency.sql` is an
operational exception, not the permanent application schema. Apply only from
verified main, atomically, with `expires_at=2026-11-03 21:00:00+00` (22:00 Prague).
It allows only the old client's specific columns and exact event. Both adapters
check deadline, stored event scope and current editor. The news adapter emits
canonical revisions and receipts. The push adapter reuses admission and existing
publication-gated delivery. Canonical RPC inserts skip the temporary adapters.
No historical failed request is replayed.

The two temporary operational triggers must be removed with
`slunovrat-news-emergency-remove.sql`, scheduled as part of this deployment and
verified after removal or any replacement native release. Their deadline fails
closed even if cleanup is delayed. Removal revokes the exceptional column grants
and drops the policy, triggers and functions. It does not change canonical RPCs.

The sender previously required CSM's installation tags for every tenant. The
corrected audience selects Slunovrat's dedicated app subscribers only when both
organization 19 and its exact OneSignal application ID match. Direct-recipient
tests remain direct. Other application identities retain their prior filtering.

Validation: the old native SQL operation failed with permission denied before
the bridge. The isolated full-schema SQL regression now covers insert/readback,
canonical revisions, delayed and ready push intents, recipient/editor scope,
admission limits, modern-command coexistence, expiry and complete removal. It
uses synthetic accounts, disables external dispatch and rolls everything back.
The audience regression failed against the original sender; all six Deno tests
and the sender typecheck pass. The SQL test is registered in the automation lane.
No production news or notification was submitted as a test.

The iOS release preflight found no selected Slunovrat private release manifest
or matching local signing profiles. A replacement App Store build remains
separate from this bounded server recovery.
