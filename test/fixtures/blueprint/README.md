# Canonical Blueprint text references

These are recorded Dart/SQL references, independent of the JS kernel under test.
Compact UTF-8 JSON with one trailing newline preserves every value and scenario.
SQL roundtrip/scenes keep separate `admin`, `public`, `copy` and `setup` views.

Regeneration owners:

- `canonical-text-scene.json`: `automation/blueprint_capture_text_corpus.ts` captures canonical text resources with the existing renderer inputs.
- `canonical-text-sql-roundtrip.json`: `automation/blueprint_capture_canonical_text_sql.mjs` captures the four SQL readbacks against its disposable local database.
- `canonical-text-sql-scenes.json`: `fvm dart run automation/blueprint_export_sql_scenes.dart` compiles the recorded roundtrip with the selected Dart core distribution, without database access.

All producers serialize compact JSON. Do not derive expected Dart scenes from
JS output or merge scenarios. SQL/provider capture is unnecessary for formatting.
The 2026-10-21 whitespace-only reduction was deep-compared to source revision
`f4aa0b6edfa688b03937197d74b0506d2ae81db7`; original raw SHA-256 values:

- `canonical-text-scene.json`: `347e4dd295f44fb9fe37c559ba51eeb78f88a0fd483f7c01d916667965fe7ac5`
- `canonical-text-sql-roundtrip.json`: `8e69f125dbc75b3d22aca242d5736a6daa5aa7e900a5066cb2fe5ee9c26649fd`
- `canonical-text-sql-scenes.json`: `5cc1fce7b9d47a8d0ca008d63858dff104d583a8025feeb876dbdb2d1c6ebba2`

The scenes file's ancillary `document` fields predate the current roundtrip.
All four `scene` and `selectionUnits` values match the current Dart exporter and
JS comparisons exactly. Preserve that recorded document data during formatting;
use the exporter's optional output path to check regeneration without replacing
historical provenance: `fvm dart run automation/blueprint_export_sql_scenes.dart /tmp/blueprint-scenes.json`.

`text-corpus-input.json` is the complete 4-row producer-input projection
(fontId, text, language, direction) of the recorded preparation corpus at
`f4aa0b6edfa688b03937197d74b0506d2ae81db7:docs/plans/evidence/blueprint-typography-20261020/engine-probe.json`,
original SHA-256 `3f3986515b188901b3a8b3883ff4119c666f823561cc938910dce9aa72750448`. It retains scenario
order and values independently of current shaping output. The capture producer
needs no historical measurement dump. The one-time engine/Edge probes were subsequently retired; their recorded
results and original source are recoverable from the cleanup records.
