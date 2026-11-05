# Opening notification settings UX audit - 2026-11-05

Scope: the shared Flutter settings dialog in `sale_opening_settings.dart` and its actual `FormEditorContent` modal. Review requested by the owner and performed with an independent GPT-6 Astra agent at medium reasoning, followed by implementation and review of rendered captures.

## Findings and decisions

| Priority | Observed problem | Final change |
| --- | --- | --- |
| P1 | Reversible collection pause and irreversible campaign cancellation look like peer actions, although disabling a campaign closes active subscriptions and prevents re-enabling it. | One labeled switch controls new subscribers. Its hint explains that previously subscribed people still receive the opening email. Permanent cancellation is behind a labeled disclosure, explains the irreversible result, and still requires confirmation. |
| P2 | The same subscriber count appears as prose and in the list action. | Show one `Subscribers (count)` list entry. Readers without contact-list access retain one noninteractive count. |
| P2 | State prose repeats what the control already communicates. | The collection switch carries state. Explicit text remains for unavailable, pending cancellation, loading/error and terminal states. |
| P2 | A long title wraps on narrow screens and policy copy interrupts the main controls. | Use a shorter dialog heading, retain the explicit menu label, and group the date-change note directly under the scheduled date. |
| P2 | An unchanged dialog offers Cancel and an unusable Apply button. Save guidance is repeated even when nothing changed. | Unchanged dialog has Close. Changed dialog has Cancel/Apply; save guidance appears only for pending local or parent changes. |

## Preserved behavior

The schedule remains read-only here. The surrounding editor still owns persistence: Apply changes the parent draft and the normal form Save persists it. Cancel/Close do not write campaign settings. Unsaved initial activation can be undone using its original baseline. Capability checks, terminal-phase restrictions and permanent-cancellation confirmation remain in place. No database or public subscription-flow contract changed.

## Evidence

- 15 targeted Flutter tests cover pause/resume, single-count display, cancellation disclosure and confirmation, initial activation undo, modal Cancel/Apply/Close, permissions, terminal and failed-load states, and narrow layout with enlarged text.
- Four additional temporary rendering checks used the actual `FormEditorContent` menu path and shared modal, real Futura/icon fonts and a fixture Supabase transport. Captures passed at 1280 x 900 and 375 x 812 in light and dark appearance without layout exceptions. Subscriber counts were synthetic; no real subscription or email was created.
- 24 public-translation tests passed. The six canonical locale catalogs and their generated public copies remain synchronized.
- Targeted Dart analysis reported no errors or warnings; existing informational lints remain.

The rendered checks establish hierarchy and layout, not a complete assistive-technology certification. Screen-reader announcements were not independently exercised on a device. Existing shared modal focus and dismissal behavior was preserved.
