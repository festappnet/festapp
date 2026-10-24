# Offline map assets

This directory builds verified bundles for native offline maps. MapLibre is the
only offline renderer. The client installs the manifest through
`OfflineMapBundleManager` and assembles local resources with
`MapLibreStyleAssembler`; standalone package/style URLs are no longer supported.

CSM Ostrava's schema 2 bundles use MBTiles in MapLibre to avoid the unproven
gzip-directory path for PMTiles. Schema 3 bundles use PMTiles. Both manifest
formats remain supported. Schema 2 keeps its existing `mbtiles` asset role and
absent/null `bundle_mode`; its data contract does not select another renderer. Festapp Web/PWA uses online raster tiles; the local preview below is a
separate content inspection tool.

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

## Resolve the canonical live bounds target

The builder does not resolve `backend-activation.json`. Its bounds gate requires
explicit `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment variables and fails if
either is missing. For current Festapp events,
verify the selected tenant's canonical activation, organization, occasion ID and
current link before starting. Then explicitly supply the verified canonical
public endpoint/key; never rely on the compiled legacy fields:

```bash
export SUPABASE_URL=https://api.festapp.net
export SUPABASE_ANON_KEY="${BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY:?load the verified tenant public key first}"
```

The key above is public configuration, not a service-role credential. The builder
checks link-to-ID equality but does not establish tenant organization/generation
by itself. Follow [backend authority](../../docs/architecture/ai_context.md).

## Build a selected event bundle

The CSM and Slunovrat commands below preserve previously used examples. Their
numeric IDs, links, bounds and versions are not a fresh canonical inventory;
replace them with the verified current scope and a new unused version before a
real build. Existing tracked versions intentionally fail the overwrite gate.


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
SQLite/PMTiles/metadata/live-point checks, enforces the approved 45 MiB MBTiles
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
the default audited glyph profile remain available for CSM-compatible MBTiles
bundles.

`--style-manifest` is the reproducible bootstrap path when the large style and
sprite inputs are not checked out locally. It accepts only `assets.festapp.net`
URLs and verifies every downloaded style/sprite against the SHA-256 recorded in
the tracked immutable manifest before the new bundle is built.

The builder has no rebuild override for an already tracked version. Preserve
its manifest and recorded hashes; do not move them aside to bypass the immutable
version gate. Corrections use the next unused `vN`. A separately scoped historical
reproduction needs isolated inputs and comparison with the preserved original,
not permission to overwrite its published key.

## Validate and preview

The build already performs the contract checks. For an explicit probe:

```bash
versatiles probe -ddd --sample 10 \
  automation/offline-map/out/csmostrava2026/v1/map-z0-14.mbtiles

versatiles probe -ddd --sample 10 \
  automation/offline-map/out/csmostrava2026/v1/map-z0-14.pmtiles

sqlite3 automation/offline-map/out/csmostrava2026/v1/map-z0-14.mbtiles \
  'pragma integrity_check; select name,value from metadata order by name;'
```

Start the interactive local preview:

```bash
automation/offline-map/preview.sh \
  csmostrava2026 v1 map-z0-14.mbtiles
```

This preview starts a tile server; stop it when inspection ends. Use a background/headless
isolated browser for automated checks; do not navigate the user's existing tab.
Open `http://localhost:8080`, inspect the selected event area and all four bbox edges,
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
`mbtiles:///...` for a schema 2 bundle or `pmtiles://file:///...` for a
MapLibre-only bundle; sprite and glyph templates must be `file:///...`.
Capture native network logs and reject any map resource HTTP(S) request.

## Publish and roll back

Production steps require separate user authority. Publish to the general public
`festapp-public` R2 bucket under the approved `<occasion>/vN/` namespace, with the content types from
the manifest and `Cache-Control: public, max-age=31536000, immutable`. Upload
all manifest assets plus `manifest.json`. Refuse an existing key; changes use a
new `vN`. Validate every `https://assets.festapp.net/...` URL with HEAD and full
GET. Compare every downloaded asset's byte count and SHA-256 with the manifest;
for a schema 2 bundle additionally verify the MBTiles SQLite integrity.
A MapLibre-only bundle has no published MBTiles file.

Only after public validation, use Occasion Settings (never direct SQL) to select
MapLibre offline mode and save `offlineMapBundleManifestURL` plus OSM attribution.
This mode sets `forceOfflineMap=true`; select Online mode to set it false.
`offlineMapRenderer`, `offlineMapPackageURL`, `offlineMapStyleURL`, and
`offlineMapLayerName` are obsolete and are discarded when this client saves map
settings. They cannot select another renderer or download source.

The client stages and verifies every asset before publishing its ready cache.
A forced offline map without a manifest, a failed download or a failed style
load shows an error with retry instead of silently selecting another renderer.
Online mode accepts an optional manifest for use when disconnected; the settings
form validates its HTTPS URL when supplied. Offline mode requires it.

Keep the complete previous map feature JSON and manifest URL in the rollout
record. Revert through Occasion Settings to a previously verified compatible
bundle or use Online mode. Do not delete immutable R2 objects. A renderer switch
to `legacy` is no longer a recovery option. Before activating forced offline
mode, verify Android and iOS cold starts in airplane mode, bundle recovery,
and performance on the supported lower-end device. This repository edit does
not change a live occasion or establish fresh physical-device acceptance.
