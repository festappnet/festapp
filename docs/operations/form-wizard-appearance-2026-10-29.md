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
