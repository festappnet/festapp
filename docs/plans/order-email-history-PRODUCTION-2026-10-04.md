# Order email history navigation

Status: ACTIVE on vstupenky.online, version 0.20.84+568. User explicitly requested removal of the standalone Email tab and a read-only Email history subtab under Orders. UI deployment is authorized only for `prod/festapptickets` / https://vstupenky.online.

Remove standalone admin/reservations Email routes and navigation items. Add `/reservations/orders/email-history` alongside current Orders and Orders history. Reuse the read-only event/attempt detail, scoped to the current occasion; show order ID, message kind, state and timestamp. Hide organization-wide switching and account email kinds in this subtab.

Extend the existing page RPC with optional `p_orders_only=false`; old named-argument callers keep their behavior. Filter `order_id IS NOT NULL` before LIMIT/keyset pagination so archived order-linked unknown messages remain visible. Existing rights checks, redaction and grants remain. Migration replaces the former overload atomically to avoid PostgREST default-argument ambiguity and reloads its schema cache.

Validation: 109 Flutter email history/navigation tests and six local SQL email suites passed against the isolated database on port 55434. Targeted analyzer has no errors or warnings; the existing app-router constant naming informational diagnostic remains. Production results follow below.

## Production release evidence

- Shared source: canonical main `7a52c940b9222b518100a9789025f35cdb2c8e66` ([PR #272](https://github.com/festappnet/festapp/pull/272)); main fetched and current immediately before both publications.
- UI branch: `prod/festapptickets`, forward upgrade from `ed2072f77e1756eb01cfd65ec364b4f79eedced3` to `f40b82ae9100da7c470e1cc0aa76525f8ca0dda2`. Main-owned drift check passed; generated canonical backend activation and sync manifests are included. No other tenant branch was pushed or built.
- Deployment: [GitHub Actions 37190713939](https://github.com/festappnet/festapp/actions/runs/37190713939) completed successfully, including tenant/config/legal/build and live release verification gates. Independent live manifest/compiled-bundle verification confirmed version `0.20.84+568`, `OrdersEmailHistoryRoute` and `email-history`, with `EmailDeliverySectionRoute` absent.
- Backend: canonical migration `20261004090000_order_email_history_scope.sql` applied transactionally with its migration-ledger record after a fresh protected database dump, catalog validation and digest verification. Evidence under `/var/lib/festapp-rehearsal-evidence/orders-email-history-20261004`. Only one page RPC overload remains, its nine optional defaults preserve old clients, SECURITY DEFINER has explicit search_path, anonymous execution is denied and authenticated execution is granted. PostgREST schema cache was notified.
- Queue remains unpaused, verified quota refresh continues through the new Edge Function and health reports no operational alerts. Both owner Edge canaries remain accepted/delivered with completed post-actions. The two historical unknown messages remain quarantined.

The standalone tab is removed on this authorized web release. Email history is read-only under Orders and includes only messages with an order association. The generic user-specific history and existing email template editor retain their existing roles.
