# Tab Save and single-form follow-up

The occasion settings Save caller still called
`navigateToOccasionAdministration`, which opens the shell root and selects its
default section. It now refreshes RightsService metadata in place. Renaming an
occasion replaces only the first URL segment, retaining the nested selection
and query parameters. Changed-link settings loads reject stale completions.

The forms selector automatically replaces itself with the sole form's editor
after its occasion-scoped list loads. Zero or multiple forms retain the list.
Explicit detail Back uses `?list=true`, retaining other query parameters, so a
single-form redirect cannot trap the user. Existing detail membership checks
remain authoritative.

Validation: `fvm flutter test test/components/navigation
test/components/occasion/occasion_save_state_test.dart` passed 88 tests.
Targeted Dart analysis reports no errors or warnings (existing style infos).
Tests cover route retention on save/rename, zero/one/multiple forms, explicit
list entry, retained drafts, disabled sections and foreign-object access.
These are widget/router checks with injected data, not authenticated production
Save operations. The deployment workflow separately validates the web build.

The reusable local E2E skill now includes Save-caller checks and single-object
Back behavior in its canonical development-tools source and installed symlink.
