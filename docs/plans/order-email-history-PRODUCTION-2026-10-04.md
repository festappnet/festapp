# Order email history navigation

Status: ACTIVE on vstupenky.online, version 0.20.86+570, including the standard-grid follow-up. User explicitly requested removal of the standalone Email tab and a read-only Email history subtab under Orders. UI deployment is authorized only for `prod/festapptickets` / https://vstupenky.online.

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


## Prepared editor release

- Canonical main `13ce208e0f870836a57273eb1c17f9bb9d53c0fe` ([PR #274](https://github.com/festappnet/festapp/pull/274)) contains the remaining prepared ticket-editor branding and contrast changes, preserving newer editor canvas/zoom/save behavior. The newer occasion report and navigation title metrics were already canonical, so the earlier local report draft was not reapplied.
- `prod/festapptickets` advanced to `02502792c06d5a31fd235828cef0e27d1d79a410`, version `0.20.85+569`, with matching main ancestry and a passing canonical tenant drift check. [Deployment 37192057969](https://github.com/festappnet/festapp/actions/runs/37192057969) succeeded. Independent live manifest verification confirmed this version. 183 targeted editor/navigation tests passed.

## Standard-grid follow-up

Email delivery history now uses the same `SingleTableDataGrid`, `SingleDataGridController` and `ITrinaRowModel` flow as Orders history. The custom list, dropdown filters and load-more controls are removed; the shared grid provides column filters and sorting. Columns show order ID, date, kind, delivery state and a redacted detail action. All columns are read-only, creation/deletion are disabled, and persistence actions are disabled. Refresh reloads the authorized reporting source.

The model drains the existing read-only RPC's descending-ID keyset pages (100 records per request) before local grid filtering, retaining occasion/order/user and orders-only scope on every request. Malformed/non-progressing pages fail visibly through the existing exception handler. Row references retain metadata without interpreting formatted display values. Context changes recreate the controller; the shared grid now ignores late initial-load completion after disposal. Organization overview and per-user/per-order dialogs keep their existing scope, with no parallel legacy list implementation.

No SQL, RPC contract, backend deployment, e-mail sending or other tenant rollout is needed. Targeted email/grid/navigation checks: 123 passing tests. Targeted changed email/model/test analyzer: no issues. Full `automation/test_all.sh` passed against the isolated database on port 55434: 1056 Flutter tests (one skip), 240 Deno tests, web/SQL/automation checks and three worker integration tests. 27 remote integration cases were intentionally skipped without external test credentials; no production fixtures or capacity test was used. Production deployment and independent live verification succeeded as recorded below.


### Standard-grid production evidence

- Canonical main `5edfe3207c394b0172457abed5aec47fefba60d9` ([PR #277](https://github.com/festappnet/festapp/pull/277)); upstream was fetched before publication and the intervening organization-scoping fix was merged and its SQL regression passed locally. The release also includes the concurrent template-dialog footer change from main.
- `prod/festapptickets` advanced from `02502792c06d5a31fd235828cef0e27d1d79a410` to `ac3e6623d40c4fce4b01b83e8e0ada6f68a256de`, with recorded base matching canonical main, regenerated tenant manifests and a passing main-owned drift check. Version: `0.20.86+570`. Main and production heads were freshly checked before the push; no other tenant branch was pushed or built.
- [Deployment 37192837015](https://github.com/festappnet/festapp/actions/runs/37192837015) succeeded, including live release gates. At `2026-10-04T09:45:46.117Z`, an independent fetch confirmed manifest `0.20.86+570`, bundle `main.dart.0.20.86-570.js`, Orders email route/path, the typed grid model and keyset pager, and absence of the standalone Email route. Bundle SHA-256: `4a8dfd2dc3f4a2a406ef955721d5b81e39039822400ef9429182cded8743be67`.
- Full isolated SQL suite: 107 passing files. The full Flutter/Deno/web/automation results above and targeted grid tests passed. The grid tests verify disabled persistence controls, read-only columns, redacted error details, refresh, organization scoping, 102-row keyset pagination and safe disposal during scope changes.
- Read-only production identity/ledger checks confirmed organization 3 `vstupenky.online` in `festapp_rehearsal_20260909220601` and the separately deployed `20261004100000` orders organization-scope migration. This UI change required no backend write or sending changes.

The live Orders subtab now uses the shared datagrid, keeps order-only authorization filtering on the server, and retains the delivery/attempt detail dialog. Prepared editor changes from version 0.20.85 remain included.
