# Email template authoring - visual follow-up

The user's feedback on 0.20.272+760 replaces the earlier fixed-white preview
and label-only token presentation. Continue from canonical main b5a092779 in
`fix/email-template-visual-authoring-20261019`, isolated from other work.

Required behavior:

- A selected variable is an atomic object showing its illustrative content
  immediately. Scalar values show actual sample text; composite components show
  their HTML, including when imported inside a mixed paragraph. Quiet identity
  and accessible help distinguish samples from literal authored content.
- Subject editing looks like a compact normal subject field; the body is a
  readable document. They retain the shared engine, history and canonical codes.
- Both inline components and full draft preview follow the app's light/dark
  theme. Theme adaptation affects presentation only, never saved or sent HTML.
- Restore informative descriptions and concrete examples for every available
  variable through accessible help/inventory and chooser details.
- One parent Save persists the subject and body together. Borrowed inline and
  fullscreen sessions keep the parent draft on close/collapse; they do not add
  a confusing second Save. Standalone editors in other domains keep their own
  workflow. Discard/error/keyboard safeguards remain.

## Contextual data

The existing permission-checked product catalog RPC supplies up to two visible,
priced products in one currency from the selected occasion. The known scoped
route link is retained by the email-template adapter (the existing SQL response
omits it); a RightsService link is used only when occasion IDs agree. No new
backend endpoint, permission or production customer/order reader is added.
Synthetic Jana Nováková/contact details remain illustrative. Catalog failure,
missing scope or no priced items uses a visibly labelled coherent model example.

The production TS renderers generate optional context templates alongside their
static examples. Their slots replace display data, not markup/layout. Dart binds
product/type titles, prices, matching total/deposit/change sample values and
sample dates once for the entire authoring session. Product strings are escaped;
inserted values are never recursively interpreted. These templates/slots and
sample values cannot enter saved subject/HTML, which retain only `{{code}}`.

## Evidence so far

Astra medium reproduced the exact UI symptoms with a red-capable test command:
`fvm flutter test --no-pub test/components/email_templates/email_visual_authoring_cases.dart`.
The initial three regressions caught label-only scalar rendering, absent mixed
rich-component rendering and a white canvas in dark mode. Native rich selection
additionally exposed a stale action-tag range during destructive block insertion;
the fix must cancel native composition while that original range still exists.

Parent data checks on final inputs:

- Core `fvm dart test test/email_templates`: 12 passed.
- Existing targeted TypeScript batch: 45 passed.
- Generator freshness and typecheck: pass, 54 scenarios.
- Targeted data/core analyzer: no issues.
- Context tests prove exact original-renderer HTML under original fixture data,
  scoped catalog data, currency coherence, escaped/nonrecursive bindings,
  matching amounts, safe fallback and absence of preview slots in resolved HTML.

UI verification:

- Affected Flutter batch: 69 passing cases; the remaining case initially used a
  fullscreen TextButton locator for an IconButton. With that locator corrected,
  the focused case passes (70 cases covered across the two runs).
- Two additional all-rich-body cases pass: scalar and rich insertion do not
  mutate source merely by opening the chooser, export no placeholder artifact,
  and one undo restores the exact clean original.
- Targeted UI analyzer: zero errors or warnings (existing informational lints).
- Native rich `@` insertion and one undo, explicit chooser after a selected rich
  block, mixed-paragraph rendering, compact subject, one parent Save, fullscreen
  draft preservation and failed-save retry have focused regressions.
- Isolated headless browser: light/dark desktop, 320 px dark editor/fullscreen,
  help inventory and full preview. Mocked existing catalog RPC supplies
  Místo u stolu (720 Kč) and Večeře & dezert (480 Kč), total 1 200 Kč.
  Recipient/contact examples remain synthetic. Screenshots are local artifacts
  under `/tmp/email-visual-*.png`.

Publication and selected-tenant release receipts follow the validated source.
No production data mutation is part of the preview.
