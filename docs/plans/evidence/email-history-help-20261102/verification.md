# Email legend and order timeline - 2026-11-02

Native Flutter tooltip captures at 420px with actual local Futura and Material fonts. Synthetic data only. Shared grid EmailDeliveryIndicator widgets provide the legend icons, including the existing SVG delivery/open checks; examples are inert and do not issue requests.

Read-only production diagnosis scoped to the screenshot recipient in festapptickets organization 3 confirmed two cancelled order-reminder schedules with last_error=reminder_superseded and no provider submission, alongside one accepted reminder. Runtime host/database/org and canonical activation generation were verified before querying. No backend data or email dispatch was changed.

The compact order timeline omits only cancelled reminder_superseded schedules without any accepted/delivery/open/click/bounce/complaint evidence. All metadata remains in the full reporting/audit history. Explicit message targets remain reachable, generic cancellations and actual delivery problems remain visible. Pagination still drains the complete authorized history before presentation filtering.

Validation: 4 new targeted tests passed, then 28 combined tests passed, covering model/audit preservation, timeline projection, direct targets, visual legend icons in both themes, existing email history/indicator behavior and keyboard/tooltip Escape interactions. Targeted analyzer: no errors or warnings, 19 informational diagnostics. Mechanical design scan run; native captures visually inspected.

Logs: /tmp/email-history-help-tests.log, /tmp/email-history-help-final-tests.log, /tmp/email-history-help-analyze.log. Base main verified current at 522809b5cca7c34b627d1d55318c19e0be1abcfe before publication.

Additional user corrections included in the same PR: typo guidance is shown only for a current failure/uncertainty affecting the stored recipient (not obsolete/cancelled/waiting-repair issues); capacity-only applications omit physical-seat counters. Counters appear only when floor-plan geometry exists and still count unique active non-standing assigned seats. Final combined 86 tests passed, including Czech/English count cases, actual seat geometry, healthy/problem email hint and existing repair behavior. No capacity inventory or admission authority was recalculated or changed.
Logs: /tmp/email-extra-fixes-tests.log, /tmp/email-extra-fixes-analyze.log.
