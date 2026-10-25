# Public help header and theme parity

Homepage and help use `initAccountHeader` and the same `user-header` component,
canonical Supabase session and browser theme preference. No separate help login
or theme store is introduced.

ThemeService now rereads the preference on cross-tab storage changes and BFCache
page restoration. Existing form colors are reapplied through their current model.

Verification:
- Full web-client suite: 756 tests, 726 passed, 30 skipped, no failures.
- Shared initializer regression covers both `/` and `/napoveda/`.
- Isolated headless Chrome, current source and disposable local Supabase: real
  password authentication, identical account avatar A and My events on both
  routes, restored session on opening homepage from help.
- Changing light mode on homepage updated already-open help; changing dark mode
  on help updated already-open homepage, including native color-scheme.
- Local browser and task-specific dev server closed after checks. No production
  account credentials or production data were used.
