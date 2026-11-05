# Sale opening notification UX release - 2026-11-05

- Source main: `ff3916b99e5d6b9b800cd72414cbba97e47e3650`.
- Selected tenant: `prod/festapptickets`, commit `f13e505e2b00ea2e064157cb2a4b48ebefca7f0f`.
- Previous production: `69c6eb41d664a888a4be7ac2c4dd4504dcd3e3d1`, retained as parent.
- Version: `0.20.502+1009`.
- Local build, direct Wrangler OAuth deployment: https://d8038220.vstupenkyonline.pages.dev
- Main-owned tenant drift, build/legal verification and three coherent live probes passed.
- Backend activation and public legal/support routes passed; backend was not modified.

Notification settings now live under the Availability card overflow menu. The
isolated dialog exposes named enable/pause/resume actions and an explicit apply
step before the normal parent Save. A paused subscription-only public page
shows its planned opening instead of rendering blank. A bounded timer fixes
repeated loading for opening dates beyond the browser timer delay limit.

Validation: 45 targeted Flutter tests passed, including authorization, editor,
notification and bounded timer behavior; 11 latest notification JS tests passed
(previous broader JS batch 42). Local browser exercised cancel without save,
resume/apply/save and public view, pause/apply/save and public date; persisted
settings were read back. Public JS mobile/desktop and manual closure passed.
Unsaved public-view navigation was not independently clicked in browser.
Nine broader occasion suite failures also reproduce against upstream occasion
source; they were documented and unrelated tests were not rewritten.

The existing production form collection remains paused. No production
subscription or email was created for testing. Final live browser check passed on `/form/hwnsne2t` at 1280 and 375 px:
"Přihlašování se otevře středa 9. prosince 2026 v 4:00." No blank or closed
state, horizontal mobile overflow, or browser errors. Loaded JS entry
`/web-assets/index-BZv5bZHC-0.20.502-1009.js` and version manifest both match
0.20.502+1009. The isolated session was closed.
