# Blueprint typography: measured engine decision and implementation status

2026-10-20. Verification: standard. This is partial implementation evidence,
not completion of the canonical rendering plan.

## Authority and preserved inputs

The user authorized local execution of the canonical rendering/fonts execution
prompt, then clarified the intended interaction: an ordinary editable text field,
conversion of its whole contents to vector paths, and rendering of the resulting
vectors. The user additionally requested legitimate SVG/vector-graphic import.
That addition is recorded in the authoritative plan with V1-V3 acceptance.
It has not yet been implemented in the editor.

`baseline.json` records both planned HEADs, original binary diff hashes and
relevant input hashes before changes. Both HEADs matched the plan. The original
`/Users/miakh/source/festapp` checkout was only inspected and was not changed.
The existing package 0.2.3 archive, host lock and scoped-font work were preserved.
No commits, pushes, registry publication, production queries or deployment occurred.

## Engine decision

Choose **harfbuzzjs 1.6.3 / HarfBuzz 14.6.0** as the single Blueprint shaping
backend. The independently installed native oracle is pinned and checked as
**hb-shape / HarfBuzz 14.4.0**. Distinct engine versions are recorded explicitly;
matching this corpus does not assert that every possible text shapes identically
across those versions.

`automation/blueprint_typography_probe.ts` downloads only exact Google Fonts
hash-addressed assets via the existing TicketFontResolver, validates their byte
hashes, embeds them through the existing PDF validation boundary, and compares
positioned glyphs with the native oracle. It uses the existing generator's new
`extractFaceVariants` entrypoint, not another font catalog or a parallel parser.
Existing catalog generation and face IDs have not changed.

Results in `engine-probe.json`:

- 12 cases compare exact glyph IDs, x/y advances and x/y offsets. HarfBuzz also
  compares original UTF-8 cluster offsets. All 12 HarfBuzz comparisons pass.
- Fontkit 2.0.4 differs on `Á ž ạ́`, Arabic combining marks, and the Devanagari
  control fixture. Consequently it is rejected as the Blueprint shaping backend;
  it remains the existing Ticket font parser/validator and is used only as a
  candidate comparator in the offline proof.
- The corpus includes AV/To/Wa, office/ffi/fi, ligature/kerning feature on/off,
  Czech/Slovak/Polish/German text, euro/multiplication signs, NFD marks, Arabic
  and Indic input. This is not yet mixed-direction paragraph/wrap coverage.
- Ten actual static faces were resolved: all four combinations for Roboto and
  Amiri, and regular/italic for Tiro Devanagari Hindi. Weight and italic metadata
  are checked against OS/2 flags, not inferred from names or italicAngle.
  Roboto's italicAngle is zero even for its actual italic faces; the OS/2 italic
  bit is true. The two unavailable Tiro bold combinations are not synthesized.

The production preparation primitive is
`supabase/functions/_shared/layoutTextShaper.ts`. It uses one immutable backend,
verifies font identity, rejects variable/color font tables and .notdef output,
preserves source text and UTF-8 cluster mapping, and emits original curve commands
indexed by glyph ID. `LayoutTextFace.vector` joins the contextually positioned
outlines into one whole-run path in y-down baseline coordinates, with advance
and ink bounds. No per-character width layout or faux style is added.

**This primitive is not yet connected to the Blueprint renderer or Save.** The
existing schema-1 renderer remains active. A shape run is not yet a complete
paragraph layout implementation; bidi itemization, final-line reshaping, wrapping,
fit/clip, manifest/request identity and stored protocol-2 resources remain open.
No request contract or resource identity has been frozen prematurely.

## Actual Edge proof and Unicode choices

`automation/blueprint_typography_edge_probe.py` runs a fresh container from
`public.ecr.aws/supabase/edge-runtime:v1.74.2@sha256:a82676277615aee03c4f288cbbbf68dedb5ba8693073e567ab8dbfdd11ba5d45`.
It copies only the required public source/fixture files into the container;
it does not mount the repository or supply credentials. An actual Edge **user
worker**, with a 150 MB worker budget, imports the same preparation primitive.
It compares 11 default-feature cases against the native oracle and creates their
whole-run vector paths. All pass. The twelfth feature-toggle probe belongs to
the offline engine comparison and is not falsely counted as Edge coverage.
Containers and staging files are removed in finally blocks.

`edge-probe.json` records the executed script and shaper hashes, immutable image,
three tested regular faces, first-request timing and 60 batch samples. The final
run measured a cold 11-label batch at approximately 76 ms and warm p50/p95 at
approximately 5.2/9.1 ms. Startup plus the first local request was approximately
2.4 seconds. These are local Edge/CPU observations, **not** authorization,
storage, network, UI typing or complete preparation latency measurements.

The same worker successfully imports and exercises these candidates:

| Function | Pinned implementation | Unicode data | License |
| --- | --- | --- | --- |
| Bidi (UAX #9) | bidi-js 1.1.0 | 13.0.0 | MIT |
| Line opportunities (UAX #14) | linebreak 1.1.0 | 13 | MIT |
| Graphemes (UAX #29) | unicode-segmenter 0.17.3 | 17.0.0 | MIT |
| Script properties | unicode-properties 2.0.1 | 12 | MIT |

These versions deliberately have **different** Unicode data generations; no
single Unicode-17 conformance claim is made. Only runtime/smoke support has been
established. Final script itemization and Unicode conformance/corpus gates must
precede a protocol freeze. HarfBuzzJS is MIT; the bundled HarfBuzz license is the
upstream permissive HarfBuzz license. Exact npm dependency identity for the new
shaper is recorded in the existing Deno lock, without a client-side WASM engine.

Primary implementation references:
[HarfBuzzJS](https://github.com/harfbuzz/harfbuzzjs),
[Fontkit](https://github.com/foliojs/fontkit),
[bidi-js](https://github.com/lojjic/bidi-js),
[linebreak](https://github.com/foliojs/linebreak),
[unicode-segmenter](https://github.com/cometkim/unicode-segmenter).
Measured behavior above comes from the checked-in proof outputs.

## Schema-1 admission repairs

Canonical SQL changes in `database/functions/blueprint/{validation,resources}.sql`:

- Override masks must be arrays of known strings without duplicates. Null,
  scalar masks, unknown keys and non-string entries reject before aggregate writes.
- The existing font dependency closure now includes the full ×/0-9 symbol alphabet
  for an actually used numeric role: capacity areas and the same first atomic
  furniture membership from which the core derives its badge. Couch-only hidden
  labels do not acquire numeric dependencies. The badge uses the document face,
  independently of the furniture's authored label face.
- A new forward migration,
  `20261020110000_blueprint_masks_numeric_resources.sql`, contains the canonical
  resources and validation SQL. The previously applied 10:00 migration was not
  rewritten. The new migration was applied only to the disposable database after
  checking its ownership marker.

The new regressions demonstrably fail against the pre-fix disposable SQL. After
the migration both layout integration and copy/setup suites pass. Invalid masks
are tested at direct validation and full-save boundaries. Numeric tests reject
no symbols, missing ×, and a missing currently unused digit, without changing
revision or bindings. A ready atomic furniture then saves and is read through
admin/public/setup/copy. The unrendered couch remains valid without those glyphs.

This is a schema-1 stabilization boundary, not a substitute for the later shared
contract metadata/projection owner. The existing duplicated host/SQL collectors
are not claimed retired. Source-to-generator cutover remains required.

## Scene evidence and checks

`automation/blueprint_capture_font_corpus.mjs` checks the fixed loopback database's
marker `festapp-blueprint-b-e2e-20261019`, runs synthetic SQL fixtures in one
transaction, captures admin/public/setup/copy readbacks and always rolls back.
It does not read .env credentials or touch a live tenant.

The package's existing `parity_fixture.dart` now accepts `--sql-corpus` to compile
full Dart scenes from those actual SQL readbacks. The saved numeric scene corpus
is compared with the distributed JS kernel using full structural equality,
including paths, matrices, bounds, paint order and selection units. The archive
itself was extracted into a temporary directory; the owning web tests loaded its
actual kernel through BLUEPRINT_KERNEL_FILE. This proves the bounded numeric
corpus, not the later whole-text protocol, SVG import, raster quality or the
complete archive release gate.

Checks on the final relevant inputs:

- SQL layout integration + copy/setup: 2 suites pass. Disposable marker checked;
  no reset, production access, changes to seat/ticket identities or finance.
- Host `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart
  --plain-name blueprint_layout_assets`: 8 actual tests pass, including numeric
  full-scene comparison. No other Flutter task was running when it started.
- Actual extracted 0.2.3 npm archive: all 21 owning blueprint web tests pass,
  including mask admission and exact numeric scene parity. Archive SHA256 remains
  `4c5c7daf3fdf4d7195e4f5b750193babff571e9a44a6ff2161e8d18583c3552f`.
- Deno shaping + outline: 5 tests pass. Whole-vector conversion, exact oracle,
  UTF-8/NFD/CRLF/astral mapping, missing glyphs, invalid immutable bytes and numeric
  notation cases ×0/×1/×2/×10/×5000/×20000 are covered.
- Existing preview-ticket-layout: 24 tests pass with the repository's prescribed
  --allow-env --allow-net --allow-read permissions. The initial read-only invocation
  could not boot its existing Undici dependency due to missing env permission;
  no application code was changed to bypass that requirement.
- Four affected catalog-generation/extraction/bundle tests pass. The complete
  ticket-font-catalog file also contains an existing failing historical migration
  consistency assertion for ticket_layout.sql. Its function/migration inputs are
  byte-identical to HEAD and were not changed by this work. This unrelated failure
  is recorded rather than hiding it or modifying historical migrations.
- Both worktrees pass git diff --check. `final-inputs.json` records selected hashes.

## Remaining mandatory work

Wave 0 is not fully closed: full paragraph bidi/line/fit policy, conformance and
service/end-to-end latency still need proof before resource freeze. The two
specific schema-1 admission regressions from wave 1 have been repaired and the
bounded SQL/core/distributed-kernel corpus passes.

Waves 2-7 remain open: document/schema 2 and importer, canonical appearance and
text request owners, immutable family manifests, full protocol-2 text preparation,
reader/writer integration and removal of the old rune/faux path, transaction/history
and product-intent repairs, captured async Save, complete migration/parity/raster/
performance corpus, SVG/vector import and UI journeys, and final coherent archives.
No user-facing feature is claimed finished merely because the engine proof passes.
