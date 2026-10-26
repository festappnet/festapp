#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/automation/offline-map/build.sh"
PREVIEW="$ROOT/automation/offline-map/preview.sh"
PREVIEW_HTML="$ROOT/automation/offline-map/preview/index.html"

help="$($BUILD --help)"
grep -Fq -- '[--occasion-link LINK]' <<<"$help"
grep -Fq -- '[--style-manifest MANIFEST.json]' <<<"$help"
grep -Fq -- '[--maplibre-only --glyph-profile latin --max-bundle-bytes N]' <<<"$help"
grep -Fq 'MAP_NAME="map-z${MIN_ZOOM}-${MAX_ZOOM}"' "$BUILD"
grep -Fq '.sprite = $base_url + "sprites/sprites"' "$BUILD"
grep -Fq '.glyphs = $base_url + "glyphs/{fontstack}/{range}.pbf"' "$BUILD"
grep -Fq '/rest/v1/occasions?select=id&link=eq.$OCCASION_LINK' "$BUILD"
grep -Fq 'BUNDLE_MODE="maplibre_only"' "$BUILD"
grep -Fq 'SCHEMA_VERSION=3' "$BUILD"
grep -Fq 'LATIN_GLYPH_RANGES=("0-255" "256-511" "8192-8447")' "$BUILD"
grep -Fq 'Bundle exceeds the explicit budget' "$BUILD"
grep -Fq 'Style manifest checksum mismatch' "$BUILD"
grep -Fq 'https://assets.festapp.net/*' "$BUILD"

if grep -Fq '/rpc/get_occasion_by_link' "$BUILD"; then
  echo "offline map build must not depend on a tenant-specific RPC migration" >&2
  exit 1
fi

if grep -Eq 'MBTILES_NAME="ostrava-|PMTILES_NAME="ostrava-' "$BUILD"; then
  echo "offline map artifact names must be tenant-neutral" >&2
  exit 1
fi

grep -Fq 'BUNDLE_DIR="$SCRIPT_DIR/out/$1/$2"' "$PREVIEW"
grep -Fq 'TILE_CONTAINER="$BUNDLE_DIR/$3"' "$PREVIEW"
grep -Fq 'versatiles-shortbread.${3##*.}' "$PREVIEW"
grep -Fq '"$BUNDLE_DIR/style.json"' "$PREVIEW"
grep -Fq '"$BUNDLE_DIR/sprites/"*' "$PREVIEW"
grep -Fq '"$BUNDLE_DIR/glyphs/."' "$PREVIEW"
grep -Fq '"$BUNDLE_DIR/manifest.json"' "$PREVIEW"
grep -Fq 'preview-config.js' "$PREVIEW"
grep -Fq '.glyphs = "http://localhost:8080/glyphs/{fontstack}/{range}.pbf"' "$PREVIEW"
grep -Fq 'window.FESTAPP_OFFLINE_MAP_PREVIEW' "$PREVIEW_HTML"
grep -Fq 'preview-style.json?contract=local-bundle-v2' "$PREVIEW_HTML"
if grep -Fq '"$SCRIPT_DIR/style/' "$PREVIEW"; then
  echo "offline map preview must use the selected tenant bundle" >&2
  exit 1
fi
if grep -Eqi 'CSM|Ostrava|18\.282|49\.8346' "$PREVIEW" "$PREVIEW_HTML"; then
  echo "offline map preview must not contain tenant-specific labels or coordinates" >&2
  exit 1
fi

echo "Offline map build contract passed."
