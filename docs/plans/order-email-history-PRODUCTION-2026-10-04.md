# Order email history navigation

Status: verified implementation; production release pending. User explicitly requested removal of the standalone Email tab and a read-only Email history subtab under Orders. UI deployment is authorized only for `prod/festapptickets` / https://vstupenky.online.

Remove standalone admin/reservations Email routes and navigation items. Add `/reservations/orders/email-history` alongside current Orders and Orders history. Reuse the read-only event/attempt detail, scoped to the current occasion; show order ID, message kind, state and timestamp. Hide organization-wide switching and account email kinds in this subtab.

Extend the existing page RPC with optional `p_orders_only=false`; old named-argument callers keep their behavior. Filter `order_id IS NOT NULL` before LIMIT/keyset pagination so archived order-linked unknown messages remain visible. Existing rights checks, redaction and grants remain. Migration replaces the former overload atomically to avoid PostgREST default-argument ambiguity and reloads its schema cache.

Validation: 109 Flutter email history/navigation tests and six local SQL email suites passed against the isolated database on port 55434. Targeted analyzer has no errors or warnings; the existing app-router constant naming informational diagnostic remains. Production results will follow the canonical-main SQL and single-tenant release.
