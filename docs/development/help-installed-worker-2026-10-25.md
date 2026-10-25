# Help runtime with an already installed PWA worker

Supersedes the incomplete clean-browser evidence in help-header-parity-2026-10-25.md.

Reproduction on live 0.20.397+898: open `/events` to install/control the page with
its service worker, then open `/napoveda/`. The document loads but its shared
`/web-assets/` graph waits for an app version report that help never sends.
`body.dataset.publicTheme` and `user-header` remain absent. A clean browser alone
misses the issue. With OS dark and light global variables, the no-JS theme could
also render pale text over a light background.

Fix:
- Publish the existing compiled client runtime, stylesheet/font dependencies and
  translations under `/napoveda/assets/`, the network-owned scope already
  bypassed by installed workers. Relocate absolute asset URLs, preserving
  relative module imports and the same tenant/session/theme configuration.
- Newly generated workers also classify help clients before shared-module
  version pinning, including after worker restart. App offline behavior remains
  covered by its existing suite.
- Use coherent dark fallback surfaces independently of shared light variables.

Verification:
- New regression for a help client without a version report failed before the
  worker fix and passed afterward (`pwa_offline.test.mjs`).
- Built-help integration test failed before runtime relocation and passed after:
  entry, relative and absolute imports, preload dependency strings, CSS, binary
  font bytes and translation JSON.
- Help rendering/hosting/runtime tests: 4 passed. PWA home/manifest tests passed.
- Isolated real Chrome: old production worker 0.20.397+898 installed locally,
  corrected compiled help graph loads with that unchanged worker, light/dark
  screenshots inspected, no browser JS errors.
- Same setup with an isolated build using only disposable local backend config:
  normal Sign in UI, real local password authentication, avatar A and My events,
  persisted account after navigating to the orders guide. No production account
  credentials or production data mutations used.

Private screenshots: /tmp/help-fixed-old-worker-{light,dark}.png.
