# Hidden note and overdue payment UI - 2026-11-02

Native Flutter captures with real local Futura/Material fonts and synthetic data, 400px wide at 1.4x text scale. Both reviewed by Astra Medium and primary. The readonly/wide variants are archived privately beside the full native captures.

- Hidden note: standard outlined multiline input, one fixed floating label, directly editable. Shared sticky Save/Discard owns draft persistence. Other inline fields retain their existing visual style.
- Overdue: shared themed icon/text notice in overview and Payments, using canonical server overdue/dueAt/amounts. A past local date alone never creates overdue state. Cancelled orders suppress the notice.
- Original canonical transaction UI and N/A financial semantics retained. Final deadlines remain visible for ordinary payments without deposits.
- 78 targeted tests passed, including actual Payments content with mocked standard RPC transport. After correcting the test MaterialApp locale to match production, all 61 affected presentation/summary tests passed and renders show Czech dates.
- Targeted analyzer: no errors/warnings, 11 existing informational diagnostics. Mechanical design scan: no findings. No backend changes.

Logs: `/tmp/order-note-overdue-tests.log`, `/tmp/order-note-overdue-locale-tests.log`, `/tmp/order-note-overdue-analyze.log`.
Base main verified at `d5f286c8755e60e6cd95a2caaff020313d3f6a96` before publication. Release must use latest canonical main, incorporating all other merged changes as explicitly requested.
