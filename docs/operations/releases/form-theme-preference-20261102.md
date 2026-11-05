# Automatic form appearance preference release - 2026-11-02

Live https://vstupenky.online, **0.20.489+995**.

- PR #703 administratively merged after user approval and all five required checks passed.
- Main: `5ee2bcec6275283eb6638a85c29d3101b05fcf0e`.
- Only prod/festapptickets published: `6542cd9d3c7d70c24efa606da2fd87b0d24a3a28`; previous `78c60c566a8a99f0cfa83338f5a53c1f05dd1d16` retained as ancestor.
- Canonical drift/ancestry, protected manifest, local Flutter/web build and build verifier passed. Direct Pages: https://f38427a2.vstupenkyonline.pages.dev.
- Live version/build/legal checks passed three consecutive coherent probes. Primary independently confirmed published refs and deployment receipt.

Automatic forms inherit the shared portal appearance before the device preference, in public web and Flutter. Explicit form light/dark remains authoritative. Public settings reflect the inherited preference and allow changing it for automatic forms. Six help catalogs updated; existing storage values and legacy preference migration preserved.

Validation: 28 JS preference/theme/settings tests and 18 Flutter AdaptiveTheme/form-design compatibility tests passed. Targeted Dart analysis had no errors and two existing form_page.dart warnings (duplicate import, mutable route field).

Logs: /tmp/festapptickets-form-theme-build.log, /tmp/festapptickets-form-theme-deploy.log, /tmp/form-theme-final-js-tests.log, /tmp/form-theme-native-tests.log, /tmp/form-theme-analyze.log.
Release worktree: /Users/miakh/source/festapp-festapptickets-form-theme-release-20261102.

No backend operations; previous read-projection migration was not reapplied. Local review ports 58631/58621/58622 remain off, independently checked after release.
