# Repeatable help captures

The canonical scenario catalogue is
`docs/development/public-help-walkthrough-2026-10-25.json`. Its chapters own
steps, expected outcomes, screenshot identities and unverified boundaries.
`automation/release/help/media.json` owns published files, dimensions, captions
and hashes. These files are versioned; `.private/` logs are supporting evidence,
not the only source of scenario instructions. The catalogue includes manual
walkthroughs; it is not a fully automated end-to-end test suite.

All Festapp help captures must use **light** mode, regardless of the workstation
appearance. In the real web client call `ThemeService.setMode('light')`, persist
that preference and check that `body.dark-mode` is absent before every shot.
For Flutter select the actual application's light theme before starting the
chapter. External-site modal backdrops and PDF viewer chrome are not application
themes. Never recolor an existing screenshot or inject a successful RPC result.

Use an isolated headless agent-browser session, synthetic data and a disposable
local backend. Follow `festapp-local-e2e` for a fresh Flutter/local-backend setup;
reuse an already running owned fixture when available. Never use production
credentials or repeat order/admission/settings writes against production.

## Scanner errors and settings

`scanner_light.py` captures all six scanner states in Czech and English, using
actual local Auth/RPC responses and the current webclient UI. Requirements:
Python 3, agent-browser, a running webclient configured exclusively for the local
backend, a scanner code, an editor account and an existing used ticket belonging
to the synthetic occasion. The October 25 fixture is named Slavnostní ples U Lípy.
Provide current fixture identifiers rather than depending on yesterday's IDs.

```sh
export HELP_CAPTURE_EMAIL='<local editor email>'
export HELP_CAPTURE_PASSWORD='<local editor password>'
python3 automation/help_capture/scanner_light.py \
  --origin http://127.0.0.1:57982 \
  --scan-code '<fixture scanner code>' \
  --occasion '<fixture occasion ID>' \
  --ticket '<existing fixture ticket symbol>'
```

The script only permits loopback origins. It authenticates through AuthService,
looks up a deliberately missing ticket, opens editor settings, changes a draft
and previews an existing ticket. It does not save settings or confirm admission.
It checks light mode and overflow before capture and updates both provenance
registries after all twelve captures succeed. If a capture fails, review any
partially replaced PNGs before rendering; registry updates are withheld.
A saved-settings/reopen scenario remains a separate manual chapter in the
catalogue. Camera acquisition and offline synchronization remain separate checks.

For the other chapters, repeat the catalogue's real UI actions in order against
a reset local fixture. Use fresh accessibility refs after each state change.
Record actual outcomes, timestamps and hashes in both registries. Preserve
explicitly unverified steps; do not infer success from a screenshot alone.

Generate and inspect self-contained static previews, then run the targeted gates:

```sh
node automation/release/preview_help.mjs
node automation/release/preview_help.mjs --en
node --test automation/tests/help_pages.test.mjs automation/tests/help_search.test.mjs
```

These changes do not publish or deploy help. The production release remains a
separate authorized operation.
