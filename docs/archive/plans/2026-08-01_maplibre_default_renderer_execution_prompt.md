# Execute: MapLibre jako výchozí offline renderer s vypnutelným legacy fallbackem

Work in `<repo-root>`.

Use the repository's applicable instructions and `verification: standard` from
the authoritative plan:

`docs/archive/plans/2026-08-01_maplibre_default_renderer_plan.md`

Read it in full before editing. The target outcome is a GPU-backed MapLibre
offline renderer that is the default for new native offline-map
configurations, preserves every current map capability, and can be explicitly
disabled per occasion to use the existing legacy renderer.

Execute the waves in dependency order. Wave 1 is a mandatory feasibility and
user-approval gate: build the real CSM Ostrava PMTiles/style/sprite/glyph
prototype, prove iOS and Android cold-start offline resource loading, open it in
the iOS Simulator for the user, and stop for explicit visual approval before
refactoring the production `MapPage`. A Simulator run is not performance proof;
the final gate requires the plan's repeatable release/profile comparison on a
physical lower-end Android device.

Use `maplibre 0.3.5` as the primary candidate. Do not add `maplibre_gl` in
parallel, use `OfflineManager.downloadRegion`, silently fall back after a
MapLibre error, render all ordinary places through `WidgetLayer`, or leave
remote tile/style/sprite/glyph URLs in the active offline style. If Wave 1
invalidates PMTiles or local resource assumptions on either platform, stop the
full migration, collect exact evidence, and update the authoritative plan
before trying the bounded `maplibre_gl` contingency.

Completion requires one renderer-neutral scene/camera contract, a single
renderer selection host, native GeoJSON/Symbol/Line layers for MapLibre,
complete feature parity, an atomic checksummed bundle, an explicit
`maplibre`/`legacy` occasion enum, compatibility protection for every existing
offline occasion, removal of the temporary prototype route, and intentionally
retained/tested legacy dependencies as the product fallback.

Run only the validation required by the plan and repository rules. Do not start
an independent review or subagent audit unless explicitly requested. Preserve
all unrelated dirty-worktree changes.

Do not upload assets, mutate any live occasion/database configuration, release,
commit, or push without separate authority. At handoff, report the selected
native surface configuration, bundle/resource contract, capability parity,
benchmark device and raw result summary, compatibility state, removed prototype
artifacts, validation results, and every exact unapplied production step.
