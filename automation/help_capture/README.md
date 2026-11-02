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

All visible example data must match the guide's locale, including event and
form names, organizers, product names, field labels, venue names and addresses.
For Czech guides use natural Czech examples such as “Slavnostní ples U Lípy”,
“Spolek U Lípy” and “Vstupenka s místenkou”; use English equivalents for English
guides. Technical fixture labels such as “Synthetic seats” or “Synthetic
Organizer” belong only in internal metadata, never in published captures.
Localize the disposable fixture before capturing each locale, then recapture the
real UI and refresh the media hashes. Do not translate screenshots by painting
over them. Keep fixture IDs and routing keys stable for automated tests.

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

The `joomla-module-installation` chapter adds the public ZIP install, module
configuration, native article save and public desktop/mobile result. Start the
disposable Joomla environment with `integrations/joomla/scripts/environment.py`.
The CLI readiness probe now runs as `www-data`, so the namespace cache remains
writable by the web installer. Use the official matching cs-CZ language package
for Czech administration captures. Follow the recorded local HTTPS/DNS fixture
boundary; never navigate a synthetic form URL against production. English
captures use the English Joomla administration.

The completed seating follow-up uses its own current-schema Supabase project
`festapp-joomla-help-20261029` (API 59931, PostgreSQL 59932). The Vite fixture
checks its disposable identity before allowing that API. Load the canonical
baseline, reference tenants, ledger and forward migrations using the same
extension-owner/ownership steps as `automation/bootstrap_local_db.sh`; then
load `supabase/seed.sql`, `web_client/tests/fixtures/embedded-checkout/tenant.sql`
and the WordPress fixture fixes. Remove the synthetic migration reference
organization before the embed tenant's fresh-backend check; do not load demo
occasion data into this dedicated embed fixture. Register its disposable marker.
After the fixture fixes and before captures, apply the locale overlay to this
owned local database only:

```sh
docker exec -i supabase_db_festapp-joomla-help-20261029 \
  psql -U postgres -d postgres -v help_locale=cs \
  < automation/help_capture/localize_embed_fixture.sql
```

Use `help_locale=en` for English captures and select the same UI locale. The
overlay is repeatable, keeps the original fixture links as aliases and rejects
unrelated fixture data. Use the localized public link in module screenshots.

The shared embed seed creates V2 geometry and one binding for each of twelve
places directly. Older branch-specific databases with incompatible ledgers
must not be reused for this capture. The completion receipt records a real A1
hold/release through the UI, verified in PostgreSQL, and zero submitted orders.

Generate and inspect self-contained static previews, then run the targeted gates:

```sh
node automation/release/preview_help.mjs
node automation/release/preview_help.mjs --en
node --test automation/tests/help_pages.test.mjs automation/tests/help_search.test.mjs
```

These changes do not publish or deploy help. The production release remains a
separate authorized operation.
