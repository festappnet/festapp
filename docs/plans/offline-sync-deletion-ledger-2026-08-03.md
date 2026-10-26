# Offline sync v1 deletion ledger

Repository state: 2026-08-03. The v1 runtime has no internal dual-write or
dual-read path. The names below remain only as released compatibility facades;
their implementations delegate to the listed canonical owner.

| Compatibility surface | Canonical owner | Consumer/owner | Retirement gate |
|---|---|---|---|
| Event save/delete, attendance, saved schedule and counseling legacy RPCs | `save_event_client_sync_v1`, `delete_event_client_sync_v1`, `set_event_attendance_client_sync_v1`, `set_saved_program_client_sync_v1`, counseling v1 commands | Released Flutter clients / Program | Supported-version telemetry is zero for one rollback window |
| Map, information, news, speaker, group and activity CRUD RPCs | Their typed `*_client_sync_v1` commands | Released editor clients / feature owners | Same telemetry gate; generated clients contain no legacy call |
| `update_occasion_203`, `update_unit`, `duplicate_occasion`, `delete_occasion`, service/game RPCs | Occasion/unit/config v1 commands | Released admin clients / Occasion | Same telemetry gate; creation and edit versions are v1-only |
| Profile/import/group-assignment RPCs, `add_user_to_occasion`, `delete_unit_user` | Profile, membership and import v1 commands | Released admin clients / Profile | Same telemetry gate and no supported direct-DML client |
| `delete_user` | `delete_companion_client_sync_v1` only; other meanings return 410 | Released companion UI / Profile | Legacy companion traffic is zero; account deletion stays its dedicated service workflow |
| Cleaning and feedback RPCs | Cleaning/feedback v1 commands | Released clients / Cleaning and Feedback | Same telemetry gate, including anonymous feedback versions |
| Product, form, blueprint and inventory RPCs | Typed commerce/inventory v1 commands | Released admin clients / Commerce | Same telemetry gate and queue worker health is proven |
| Order create/update/swap/delete/storno RPCs and `send-ticket-order` request shape | Order/ticket v1 commands; Edge is a typed adapter | Released web/Flutter clients / Commerce | Stable-command clients are the minimum supported versions |
| `apply_planned_changes` | `apply_planned_changes_client_sync_v1` | pg_cron / Commerce | All installed cron definitions call the v1 name |
| `sync_source_via_http` | `sync_source_via_http_client_sync_v1` | pg_cron / External sync | All installed jobs call the v1 name and one complete schedule interval succeeds |

Internal handlers ending in `_internal_v1` or `_obsolete_v1` are ungranted to
ordinary roles and are not compatibility surfaces. Wave 7 may delete them only
after the corresponding facade retirement gate; until then they remain the
single domain implementation behind that facade.

Operational Wave 6 items—migration application, initial publication, capability
enablement, production smoke, monitoring and rollback-window telemetry—are not
completed by this repository-only execution and must not be inferred from this
ledger.
