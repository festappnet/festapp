# Order admin email/payment/plan release - 2026-11-02

Live https://vstupenky.online, **0.20.488+994**.

- PR #702 administratively merged following explicit user approval; all eight required checks passed for head dbc09a456933a6e10a9f08408cfc1b0bcede2fbd.
- Canonical main: 4a37489ffaf912aceef8e39aedbd345c2b124986.
- Only selected tenant prod/festapptickets published: 78c60c566a8a99f0cfa83338f5a53c1f05dd1d16. Previous 1fceb696972d7c594cfc30732c8bb7a61dfe86f6 retained as ancestor.
- Exact read-only projection migration 20261102153000_order_admin_bank_payment_details applied via protected SSH after verified activation/host/runtime DB/org identity and baseline function body match. SHA256: 4cdbb4b41a47ccfa95fadeea2d0bb06a1210017cc83d222d56f6dc18eca9439f.
- Migration/function ACL plus ledger applied atomically with PostgREST NOTIFY. Ledger verified once; authenticated EXECUTE true, anon false. Live function body matches merged canonical source. Private before/after function backups mode0600 under /tmp/festapp-order-admin-detail-{before,after}-20261102.sql.
- Canonical tenant drift/ancestry, protected manifest, local Flutter/web build and build verifier passed. Direct Pages: https://b8e1a0e2.vstupenkyonline.pages.dev.
- Live version/build/legal verification passed three consecutive coherent probes. Primary independently checked published refs and deployment receipt. Existing Wix help/search/sitemap artifact and live checks passed.

Shipped: real-icon email legend; compact history omits unsent superseded reminder schedules while preserving audit/deep links; typo guidance only for current issues; capacity-only applications omit physical-seat counters; canonical bank destination/VS/RF/amount/deadline panel including paid orders; future-only localized deadline suffix in six languages; smaller aligned customer icon; main plan navigation highlights all order places without changing operational selection.

Validation evidence under docs/plans/evidence/email-history-help-20261102/ and docs/plans/evidence/order-payment-plan-20261102/. 137 combined Flutter tests plus root-route/projection probes passed; real disposable PostgreSQL read contracts passed under BEGIN/ROLLBACK. Native light/dark/large-text captures reviewed by Astra Medium and primary.

Logs: /tmp/festapptickets-order-admin-payment-build.log and /tmp/festapptickets-order-admin-payment-deploy.log. Release worktree: /Users/miakh/source/festapp-festapptickets-order-admin-payment-release-20261102.

No other backend/provider/email or tenant operations. Local review ports 58631/58621/58622 remain stopped, independently verified. The subsequent form theme-preference correction is a separate follow-up and is not part of this version.
