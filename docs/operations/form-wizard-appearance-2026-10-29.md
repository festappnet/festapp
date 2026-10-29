# Form and Wizard color compatibility

The form editor now uses the Wizard solid/gradient setting. Solid mode exposes
one primary color; gradient mode exposes both colors. Disabling the gradient
preserves its secondary color. Opening a legacy one-color form does not invent
a stored mode or secondary color. Wizard appearance reads the current form
design, so later form edits replace stale Wizard appearance snapshots.

The canonical form settings owner accepts only solid/gradient (or null reset)
for design.background_mode. Migration 20261029130000 contains the exact
canonical SQL, preserving private helper ACLs. No stored form rows are rewritten.

Validation: 28 targeted Flutter tests passed, followed by the extended 2-test
widget/legacy suite covering actual primary and secondary hex edits and mode
round-trips. All 12 PostgreSQL settings tests passed against the protected local
disposable database. Targeted Dart analysis reported only existing info-level
notices, no errors or warnings. Impeccable detector returned no findings.

Public form rendering also uses the primary color when a gradient has no
secondary override, and clears an explicit background when its primary color
is reset. Two public-theme runtime tests passed for retained, missing and
reset colors.

Final UI refinement by the requested Astra Medium agent uses one shared
AppearanceColorControls widget in both editors. Solid mode labels the editable
color as the theme color; gradient mode exposes first and second colors.
Outlined buttons expose the label and hex, support keyboard operation and stack
on narrow screens or with large text. Wizard color controls are immediately
visible below presets. Shared copy is translated into six app locales.

Final refinement validation: 31 targeted Flutter tests passed, including
320/390/800px layouts at normal and doubled text size, keyboard activation,
actual form hex edits and Wizard font/preset regressions. Targeted analyzer
reported no errors or warnings; only two existing form deprecations remain.
The final Impeccable detector reported no findings.

Released to vstupenky.online as **0.20.447+952**, including the separately
validated blank-plan gallery and narrow-screen Wizard navigation fixes. Local
canonical build, tenant drift/ancestry, PWA, CSP and build verification passed.
Three consecutive production version/asset/legal probes passed.
[Combined release receipt](releases/festapptickets-form-appearance-2026-10-29.json).

Completed implementation/release worktrees and branches were removed after
preserving original patch-equivalent commits in the protected cleanup archive.
Unfinished independent Joomla/Shoptet work and newly requested further QA stay
isolated from clean main. This release does not claim exhaustive payment,
email, OAuth, date-picker or delivery-mode end-to-end coverage; further QA is
a separate active task.
