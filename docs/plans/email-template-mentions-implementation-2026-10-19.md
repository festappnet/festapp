# Email template mentions - implementation evidence

Worktree: `/Users/miakh/source/festapp-email-mentions-20261019`.
Branch: `feat/email-template-mentions-20261019`, based on canonical main `9638008fe`.
Original dirty checkout remains separate. No commit, push, migration, send or deployment.

## Source correction

The older planning checkout described standalone `ORDER_OVERVIEW` and a plain
link producer. Canonical main has already retired that template and owns blue
status buttons plus an insertion slot inside the order card. The implementation
preserves that source behavior. See the correction in the authoritative plan.
Waitlist tone strings are read from the existing SQL source by the generator;
no new SQL behavior or production dependency is introduced.

## Contract and ownership

- Storage/RPC continues to receive existing `{{code}}` subject/HTML strings.
- Pure portable metadata, guards, ranking, title ranges and preview completion
  live under `packages/festapp_core/lib/src/email_templates`.
- Production HTML belongs to existing order/change/payment/platform renderers
  and extracted `emailActionLink.ts`; `emailContentCompletion.ts` preserves
  current href detection, order-card slot and body/fragment completion.
- Deterministic JSON examples contain 54 supported combinations; the source
  digest includes fixture inputs, renderers, producer branches and tone source.
  The companion `assets/email_templates/preview_reference.html` works directly
  from disk without network or actionable links.
- Preview substitutions scan authored content once; rich fragments are not
  interpreted as attributes, scalar attribute values are escaped, unknown
  tokens remain intact and inserted example contents are never reprocessed.

## Removed authoring paths

The static `_buildSubsDefinition` inventory and its technical typing instructions
are removed. `getUsageDetails` derives its compatibility `subs` key once from
the canonical registry. Manual rich `defaultValue` HTML and placeholder prose
(`Order details here`, `Payment details table`) and invalid sample dates are
removed. Producer button markup and completion have moved to their single pure
owners; delivery callers use those helpers. Generic embedded blocks for other
domains remain unchanged.

## Targeted validation

- `fvm dart test test/email_templates` in `packages/festapp_core`: 7 passing.
- Targeted core `fvm dart analyze`: no issues.
- `deno test --no-lock --allow-env --allow-net --allow-read` on
  `emailContentCompletion_test.ts`, `orderEmailOverview_test.ts`,
  `waitlistEmailRenderer_test.ts`, `send-email/deposit_templates_test.ts`:
  45 passing. These cover extracted HTML, idempotent completion, existing
  order-card slot placement, waitlist tones and deposit branches.
- Generator `deno check --no-lock`: passes.
- Documented frozen/read-only generator `--check`: 54 scenarios fresh.
- Dart and TS completion consume the same five generated contract fixtures:
  fragment, full document, existing link, order-card slot, unavailable link.

## Editor integration findings

The focused integration found native library behavior that source feasibility
alone did not prove: subject and body need distinct IME roles; explicit chooser
search must retain the insertion selection across focus changes; the native
ActionTag reaction needs transaction scheduling so its decoration does not add
a separate undo step. Actual typed query -> token -> one undo is covered,
as are stale revisions and explicit title replacement/withdrawal.

Rendered checks also found two presentation defects beyond unit coverage:
320px fullscreen needed its toolbar at the top, and placeholder widgets were
applying text scaling twice at 200%. These were corrected in the Astra UI slice.

## Final Flutter and UX receipts

Astra medium owns the completed UI slice. The initial codec/history/clipboard
gate passed. The final broader targeted Flutter batch passed 52 tests:

```sh
fvm flutter test --concurrency=2 test/components/html/template_authoring_cases.dart test/components/html/html_editor_document_cases.dart test/components/html/rich_html_editor_lifecycle_cases.dart test/components/email_templates/email_templates_cases.dart
```

After subsequent focused fixes, the affected adapter/template acceptance batch
passed 17 tests. The final subject-specific chooser test additionally verifies
IME Done acceptance, focus restoration and a real Control+Z key event in one
passing regression. These runs overlap; counts are not a unique-test total.
New case suites are registered under existing HTML/email template collectors.
Logs: `/tmp/email-mentions-final-all.log`,
`/tmp/email-mentions-acceptance-passed.log`, `/tmp/email-keyboard-final.log`.

The final analyzer over changed Dart files, including the resolver, exited 0:
zero errors/warnings and 78 informational style diagnostics. Core analysis had
no issues. Analyzer log: `/tmp/email-mentions-analyzer-final.log`.
`git diff --check` passed after UI source/test freeze.

Actual isolated browser checks covered desktop, 320px fullscreen and search,
German with 200% text, production order/payment blocks, matching 800 Kč total,
visible inert status buttons, current-draft preview and the generated static
reference. Screenshots:

- [320px fullscreen](/tmp/email-mentions-320-final.png)
- [320px search](/tmp/email-mentions-search-320.png)
- [German, 200% text](/tmp/email-mentions-de-200-final.png)
- [Actual order block](/tmp/email-mentions-order-actual.png)
- [Total and button](/tmp/email-mentions-total-button.png)
- [Draft preview](/tmp/email-mentions-full-preview.png)
- [Generated HTML reference](/tmp/email-mentions-reference.png)

Browser keyboard-undo automation remains a specific verification limitation:
`agent-browser ... press Meta+z` produced DOM events `Numpad6/x`, `F20/ctrl`,
`KeyP/Unidentified`, rather than the requested `KeyZ/meta`. This did not prove
a product undo defect. Actual Flutter shortcut/focus/history dispatch is covered
by the passing widget regression; the browser shortcut itself is not claimed
as verified. Some pre-existing German common/usage strings remain untranslated;
new authoring controls are localized in all six catalogs.

The named browser session was closed, temporary Flutter harness session 83685
exited successfully and its port 18765 has no listener. No server was left running.
Content preview intentionally excludes inherited tenant wrappers/banners;
Flutter/email-client CSS rendering is not promised to be pixel-identical.

Implementation is complete locally with the documented verification limits.
No commit, push, email, migration, production operation or deployment occurred.

## Publication readiness - 2026-10-19

The user subsequently authorized a PR, merge to main and a local web release
for vstupenky.online only. The original implementation was rebased onto fetched
main `56f85d4215c72cff05fe3acac59db9f12a374235`. Both conflicts preserved upstream
embedded-block support/movement guards alongside template authoring. The updated
four-suite Flutter batch passed 59 tests; core 7 and TS 45 passed again; generator
freshness/typecheck passed. Regeneration changed only the source digest, preserving
preview content. Root targeted analysis exited 0 with no warning/error (78 infos).
Rebase receipts: `/tmp/email-rebase-flutter.log`, `/tmp/email-rebase-analyzer.log`,
`/tmp/email-publish-core.log`, `/tmp/email-publish-ts.log`.
