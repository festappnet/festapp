# Offline map assets

This directory reproducibly builds one native offline bundle from a single
source. Dual-renderer bundles use MBTiles in both the legacy and MapLibre
renderers; MapLibre-only bundles use PMTiles. Keeping MapLibre on MBTiles for
dual bundles avoids the still-unproven gzip-directory path in MapLibre Native
without changing the renderer or the vector data. It does not add offline map support to Festapp
Web/PWA. The browser step below is a local VersaTiles/MapLibre content preview,
not a Festapp Web acceptance test.

## Source and license

Tiles come from the official OSM Shortbread distribution at
`https://download.versatiles.org/osm.versatiles`. Map data is © OpenStreetMap
contributors and remains attributed with a link to
`https://www.openstreetmap.org/copyright`.

`style/style.json` is the renderer-compatible JM2025 style snapshot. Its only
source id is `versatiles-shortbread`; the sprite base URL is the immutable
CSM Ostrava v1 R2 path. The bundled 1x/2x sprites are the matching VersaTiles
Basics assets. The bundle contains local glyph PBFs for `noto_sans_regular` and
`noto_sans_bold`. The range list in `build.sh` was audited from every string in
the CSM v2 MVT region and style, plus the variation-selector/private-use ranges
requested during the native force-offline probe. Text layers
that previously requested only `name_en` use `coalesce(name, name_en)` so
Shortbread's local Czech names render first and English remains the fallback.
This expression is supported by the pinned `vector_tile_renderer 5.2.1`
([upstream PR #16](https://github.com/greensopinion/dart-vector-tile-renderer/pull/16)).

## Build CSM Ostrava v1

Install `versatiles`, `sqlite3`, `jq`, `shasum`, and `curl`, then run:

```bash
automation/offline-map/build.sh \
  --occasion csmostrava2026 \
  --occasion-link csmostrava2026 \
  --occasion-id 643 \
  --version v1 \
  --bbox 18.13,49.76,18.36,49.89 \
  --min-zoom 0 \
  --max-zoom 14
```

`--occasion` is the stable public asset namespace while `--occasion-link` is
the current public application link used to resolve live content. They are
separate because a tenant can keep an immutable asset namespace while an
occasion is duplicated or renamed.

The script fails before download unless current public occasion data has at
least 1 km of margin inside the requested bbox. It refuses to overwrite an
existing local or tracked version, validates the style/source-layer contract,
builds MBTiles and PMTiles from the remote VersaTiles container, downloads both
font stacks for every audited 256-codepoint range, runs
SQLite/PMTiles/metadata/live-point checks, enforces the approved 45 MiB legacy
package limit, creates asset checksums, and downloads the official preview
frontend archive. Vector tiles are explicitly recompressed
from upstream Brotli to gzip because MBTiles supports gzipped PBF and the native
Festapp provider opens the package with gzip enabled.

The original 30 MiB estimate was exceeded by the first exact build. Its
41,041,920-byte result was accepted by the user on 2026-08-01, so v1 uses a
45 MiB safety gate. Crossing that revised gate still stops the build.

If conversion completed but a later local gate stopped before the manifest was
written, repeat the same command with `--resume-existing`. This recovery mode
never runs the conversion or accepts an existing tracked manifest; it reruns
all live/style/SQLite/size/checksum validations before finalizing the local set.

Generated MBTiles, PMTiles, glyphs, copied publishing assets, and preview files live under
ignored `out/`. The audit manifest is also copied to
`manifests/<occasion>/<version>/manifest.json`; it contains no local paths.
Schema 2 gives every asset an immutable HTTPS URL, local relative path, byte
count, SHA-256 and renderer role. Its own checksum is printed by the
build and must be copied to the rollout record because a file cannot contain
its own stable SHA-256.

For a MapLibre-only occasion, use the explicit compact contract:

```bash
automation/offline-map/build.sh \
  --occasion festivalslunovrat \
  --occasion-link 2025-copy-98cf835a \
  --occasion-id 6 \
  --version v2 \
  --bbox 17.85,49.87,17.97,49.98 \
  --min-zoom 0 \
  --max-zoom 14 \
  --style-manifest automation/offline-map/manifests/festivalslunovrat/v1/manifest.json \
  --maplibre-only \
  --glyph-profile latin \
  --max-bundle-bytes 33554432
```

This produces schema 3 with `bundle_mode: maplibre_only`: PMTiles, style,
sprites and both font stacks for Latin, Latin Extended and General Punctuation.
The verified MBTiles file remains a local conversion intermediate and is
removed before the asset manifest is assembled, so clients do not download a
second copy of the tiles. The explicit byte budget fails closed. Schema 2 and
the default audited glyph profile remain unchanged for existing dual-renderer
rollback bundles.

`--style-manifest` is the reproducible bootstrap path when the large style and
sprite inputs are not checked out locally. It accepts only `assets.festapp.net`
URLs and verifies every downloaded style/sprite against the SHA-256 recorded in
the tracked immutable manifest before the new bundle is built.

To rebuild the same published version locally, first move the existing ignored
output and tracked manifest aside. Never do this for an already published R2
key: corrected content must use the next `vN` directory.

## Validate and preview

The build already performs the contract checks. For an explicit probe:

```bash
versatiles probe -ddd --sample 10 \
  automation/offline-map/out/csmostrava2026/v1/map-z0-14.mbtiles

versatiles probe -ddd --sample 10 \
  automation/offline-map/out/csmostrava2026/v2/map-z0-14.pmtiles

sqlite3 automation/offline-map/out/csmostrava2026/v1/map-z0-14.mbtiles \
  'pragma integrity_check; select name,value from metadata order by name;'
```

Start the interactive local preview:

```bash
automation/offline-map/preview.sh \
  csmostrava2026 v1 map-z0-14.mbtiles
```

Open `http://localhost:8080`, inspect central Ostrava and all four bbox edges,
and verify labels, roads, expected map content, and empty space beyond the
extract. Save one full-extract screenshot and one centre-detail screenshot in
`automation/offline-map/out/csmostrava2026/v1/rollout/`. Upload must not start
until the user explicitly approves this preview.

`preview.sh` serves a small local MapLibre shell before the official frontend
archive. It uses the tracked production style and sprites, changing only their
tile/sprite URLs to localhost; this is still a content preview, not Festapp Web
offline support.

The native feasibility probe must be relaunched after network access is removed
and after the MapLibre ambient cache is cleared. Its style source must be
`mbtiles:///...` for a dual-renderer bundle or `pmtiles://file:///...` for a
MapLibre-only bundle; sprite and glyph templates must be `file:///...`.
Capture native network logs and reject any map resource HTTP(S) request.

## Publish and roll back

Production steps require separate user authority. Publish to the general public
`festapp-public` R2 bucket under `csmostrava2026/vN/`, with the content types from
the manifest and `Cache-Control: public, max-age=31536000, immutable`. Upload
all manifest assets plus `manifest.json`. Refuse an existing key; changes use a
new `vN`. Validate every `https://assets.festapp.net/...` URL with HEAD and full
GET, then compare the downloaded MBTiles SHA-256 and SQLite integrity.

Only after public validation, use Occasion Settings (never direct SQL) to set
the complete offline package URL, style URL, source name
`versatiles-shortbread`, OSM attribution, and initially
`forceOfflineMap=false`. Preserve the whole pre-change map feature JSON in the
rollout record. Roll back through Occasion Settings by restoring that snapshot;
do not delete immutable R2 objects. Set `forceOfflineMap=true` only after both
Android and iOS pass the documented cold-start airplane-mode acceptance.

### Renderer rollout contract

Before releasing a client where an absent renderer means `maplibre`, inventory
every live occasion with an offline map. In Occasion Settings, save
`offlineMapRenderer=legacy` for each existing occasion and verify a readback of
the complete map feature JSON. Keep the before/after snapshots in the rollout
record; do not update selected JSON keys independently.

For a MapLibre canary, publish a new immutable `vN` bundle first, verify every
asset GET, byte count, and SHA-256, then set both
`offlineMapBundleManifestURL` and `offlineMapRenderer=maplibre` through Occasion
Settings. The bundle must include style, PMTiles, legacy MBTiles, both sprite
scales, and every declared regular/bold glyph range. The client downloads into
staging files, verifies the complete bundle, and only then publishes its ready
directory; it never falls back silently after a MapLibre failure.

Rollback is the single Occasion Settings change
`offlineMapRenderer=maplibre` → `legacy`. Preserve the legacy package/style/
source fields and all immutable bundle versions for at least one stable release
cycle so rollback requires neither an app deploy nor another asset upload.

For CSM Ostrava, the user explicitly overrode the staged canary on 2026-08-01
and requested immediate JM2025-equivalent forced-offline behavior. Occasion
643 was first protected with an explicit `legacy` renderer and then atomically
activated with `forceOfflineMap=true`, `offlineMapRenderer=maplibre`, and the
immutable `csmostrava2026/v2/manifest.json` after all 131 bundle assets had been
downloaded from the public CDN and SHA-256 verified. Public RPC readback, iOS
automatic download/render, and an iOS cold restart from the ready local bundle
passed. The legacy v1 fields remain configured for one-setting rollback.
Physical lower-end Android release/profile performance and cold airplane-mode
acceptance remain follow-up release gates; the immediate production activation
was an explicit user-approved exception to the normal ordering above.
