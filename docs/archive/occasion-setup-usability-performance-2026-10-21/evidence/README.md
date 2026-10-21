# Occasion setup measurement - 2026-10-21

Compared baseline main `f4aa0b6ed` with the usability implementation in the same disposable canonical Supabase workspace `festapp-wizard-usability-main-20261021`, REST 56821, PostgreSQL 56822, Flutter debug web 56880. The old dirty checkout and its earlier measurements are excluded. Six synthetic source events each have one schema2 plan with 180 seats and a paid form. The first two share a title. No production/customer data was used.

## Method

Four sequential runs per RPC stage and four real UI journeys per revision, same machine/browser session, backend, fixture, and debug build mode. First UI sample is the first measured journey after startup (not a cold browser/cache guarantee); remaining three are repeats. REST body sizes are uncompressed UTF-8 bytes, not transfer size. Local admission ceilings for `occasion.creation` and `occasion.draft` were raised to the existing hard caps for both phases; production defaults were unchanged. Drafts and local abuse usage were cleared before each phase. Finalized measured copies were removed outside the timed stages; the baseline required deleting its new blueprint seat bindings before its existing delete command because of the FK bug fixed in this change.

`full-before.json` and `full-after.json` preserve every RPC sample. The exact scripts used are retained alongside them; their absolute temporary paths identify the execution environment, not a production runbook. They read credentials only from the disposable local defines. Set up the fixture using `automation/run_occasion_setup_local.py --enable-wizard`, `FESTAPP_WIZARD_WORKSPACE`, and `test/fixtures/occasion_setup/usability.sql`. Do not run the fixture or measurement mutations against production. Baseline and changed UI both use the same canonical-context bootstrap adapter (`useLegacyAppConfig: false`) and ticketing-only app flag.

`ui-main-before.json` and `ui-main-after.json` record actual browser MutationObserver-to-next-animation-frame durations. Detectors observe source controls, question 2, `Uloženo`, and the create button after returning to the list. The after script observes the new source picker button, not the removed dropdown. The observer setup used only the helper declarations in the first six lines of `ui-watch.js`, then reset `window.__uiSamples=[]`; its final two lines were not used in the final timed run. Each action waits for the preceding render/save. UI autosave includes the retained 600 ms debounce. RPC measurements are transport+server wall time, not isolated SQL execution time.

## Results

RPC medians across all four runs:

| Stage | Before ms | After ms | Before bytes | After bytes |
|---|---:|---:|---:|---:|
| Unit overview | 9.48 | 8.20 | 6212 | 6338 |
| Create private draft | 14.99 | 4.38 | 2947 | 2960 |
| Source startup | 14.50 | 1.86 | 329376 | 936 |
| Selected detail | Included above | 3.24 | Included above | 54928 |
| Save blueprint draft | 8.16 | 5.00 | 56747 | 56721 |
| Editor resource RPC | 5.68 | 3.88 | 251 | 251 |
| Save edited draft | 6.31 | 5.13 | 56754 | 56728 |
| Finalize | 53.72 | 46.71 | 133 | 134 |

Startup replaces one full manifest RPC with one metadata RPC, reducing this fixture's response body by 99.72%. Selecting a source adds one detail RPC; repeated reads of the same selection use the page-local cache. Draft creation uses a single provisional source projection instead of loading every event. Save/finalization semantics and the debounce were retained. Overview grows slightly because sale status now carries the form's ticket/registration domain.

UI milliseconds, first measured journey / median of three repeats:

| Stage | Before | After |
|---|---:|---:|
| Wizard actionable | 293.3 / 128.1 | 196.7 / 137.5 |
| Question transition | 39.9 / 44.6 | 59.4 / 43.7 |
| Saved indicator | 678.0 / 671.5 | 656.4 / 665.5 |
| Return to overview | 529.4 / 559.4 | 558.2 / 574.3 |

The payload reduction is conclusive for this fixture. Repeated UI times are broadly unchanged and the overview did not improve; these results do not establish a production latency cause or a universal speedup. Editor-resource RPC timing is not the full font/image/editor render time. Functional browser checks separately exercise that journey.

Later main commits bounding sale availability product evaluation and fixing DOM-ready web startup are included in the release. Their affected SQL/JS checks were run after integration; the above comparison isolates the usability patch against the recorded baseline rather than attributing their effects to it.
