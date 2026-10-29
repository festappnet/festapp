# Occasion setup boundaries

The existing draft store and page `_flush/_pending` own persistence. SQL owns
permissions, validation, finalization and command receipts. Preview reads never
save a draft themselves, finalize it or enqueue email.

`SetupEmailPreviewCoordinator` uses that save owner's callback to capture a
confirmed immutable draft ID/revision, then reads through the existing RPC or
Edge renderer. It shares identical in-flight requests only. Its identity includes
message type, delivery mode and sample count. Edits invalidate earlier results;
obsolete failures cannot mark a newer edit as conflicted. Widgets retain their
generation guards and schedule a new read only for changed input or explicit
Retry. The template catalog also debounces the asynchronous communication-default
updates. A plain rebuild or failed read does not retry itself.

Wizard application revision/fingerprint conflicts use `PT409` / HTTP 409.
`setup_draft_conflict.dart` recognizes the exact historical wizard messages with
`40001` during rollout. Other PostgreSQL serialization failures remain distinct.
A foreign edit leaves the local draft intact until the organizer confirms reload;
the existing form epoch resets retained input controllers on that reload.
Deploy compatible Edge/client recognition before the SQL change. See the dated
[execution receipt](../../../../docs/operations/wizard-reliability-RESULT-2026-10-29.md).

`SetupPaymentConfiguration` projects wizard controls onto its one persisted form
settings payload. The ordinary wizard does not choose a VS strategy. Absent
policy uses the SQL default; copies retain explicit policy. The core forms helper
provides early authoring validation only. Invalid legacy drafts expose the same
advanced controls as the ordinary form editor. SQL `form_settings.sql` remains
the normalization owner, and `eshop_payment_references/` owns allocation,
account namespaces, reservations and watermarks at checkout.

The immutable ticket font catalog owns face identities and bytes. The
[setup selection](../../../../automation/tickets/setup-appearance-fonts.json)
references its existing IDs and generates the Dart map and private SQL resolver.
Run `node automation/generate_setup_appearance_fonts.mjs --check` to detect drift.
No preset or copied layout rewrites historical font bytes.
