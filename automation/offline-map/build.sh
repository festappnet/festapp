#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STYLE_DIR="$SCRIPT_DIR/style"
MANIFEST_ROOT="$SCRIPT_DIR/manifests"
DEFAULT_SOURCE_URL="https://download.versatiles.org/osm.versatiles"
DEFAULT_FRONTEND_URL="https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend-tiny.br.tar.gz"
GLYPH_BASE_URL="https://tiles.versatiles.org/assets/glyphs"
# Audited from every string property in the CSM v2 MVT region, the style
# literals, and the extra ranges requested by MapLibre Native during the
# force-offline probe (variation selectors/private-use glyphs).
AUDITED_GLYPH_RANGES=(
  "0-255" "256-511" "512-767" "768-1023" "1024-1279" "1280-1535"
  "1536-1791" "1792-2047" "2304-2559" "3840-4095" "4096-4351"
  "4608-4863" "4864-5119" "5120-5375" "5376-5631" "6144-6399"
  "7680-7935" "7936-8191" "8192-8447" "8448-8703" "11520-11775"
  "19968-20223" "20224-20479" "20736-20991" "21248-21503"
  "21504-21759" "22016-22271" "22272-22527" "22784-23039"
  "23296-23551" "23552-23807" "23808-24063" "24064-24319"
  "25088-25343" "25344-25599" "25856-26111" "26112-26367"
  "26368-26623" "26624-26879" "27648-27903" "27904-28159"
  "28160-28415" "29440-29695" "29952-30207" "30208-30463"
  "30464-30719" "32256-32511" "33024-33279" "33280-33535"
  "33792-34047" "34048-34303" "35072-35327" "36096-36351"
  "37120-37375" "38144-38399" "38400-38655" "38656-38911"
  "39936-40191" "40448-40703" "40704-40959" "64256-64511"
  "65024-65279"
)
LATIN_GLYPH_RANGES=("0-255" "256-511" "8192-8447")
FONT_STACKS=("noto_sans_regular" "noto_sans_bold")

usage() {
  echo "Usage: $0 --occasion SLUG [--occasion-link LINK] --occasion-id ID --version vN --bbox W,S,E,N --min-zoom N --max-zoom N [--source-url URL] [--style-manifest MANIFEST.json] [--maplibre-only --glyph-profile latin --max-bundle-bytes N] [--resume-existing]"
}

OCCASION=""
OCCASION_LINK=""
OCCASION_ID=""
ARTIFACT_VERSION=""
BBOX=""
MIN_ZOOM=""
MAX_ZOOM=""
SOURCE_URL="$DEFAULT_SOURCE_URL"
STYLE_MANIFEST=""
RESUME_EXISTING=false
BUNDLE_MODE="mbtiles"
GLYPH_PROFILE="audited"
MAX_BUNDLE_BYTES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --occasion) OCCASION="${2:-}"; shift 2 ;;
    --occasion-link) OCCASION_LINK="${2:-}"; shift 2 ;;
    --occasion-id) OCCASION_ID="${2:-}"; shift 2 ;;
    --version) ARTIFACT_VERSION="${2:-}"; shift 2 ;;
    --bbox) BBOX="${2:-}"; shift 2 ;;
    --min-zoom) MIN_ZOOM="${2:-}"; shift 2 ;;
    --max-zoom) MAX_ZOOM="${2:-}"; shift 2 ;;
    --source-url) SOURCE_URL="${2:-}"; shift 2 ;;
    --style-manifest) STYLE_MANIFEST="${2:-}"; shift 2 ;;
    --maplibre-only) BUNDLE_MODE="maplibre_only"; shift ;;
    --glyph-profile) GLYPH_PROFILE="${2:-}"; shift 2 ;;
    --max-bundle-bytes) MAX_BUNDLE_BYTES="${2:-}"; shift 2 ;;
    --resume-existing) RESUME_EXISTING=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

OCCASION_LINK="${OCCASION_LINK:-$OCCASION}"
if [[ -z "$OCCASION" || -z "$OCCASION_ID" || -z "$ARTIFACT_VERSION" || -z "$BBOX" || -z "$MIN_ZOOM" || -z "$MAX_ZOOM" ]]; then
  usage >&2
  exit 2
fi
if [[ ! "$OCCASION" =~ ^[a-z0-9-]+$ || ! "$OCCASION_LINK" =~ ^[a-zA-Z0-9-]+$ || ! "$ARTIFACT_VERSION" =~ ^v[1-9][0-9]*$ || ! "$OCCASION_ID" =~ ^[0-9]+$ ]]; then
  echo "occasion, occasion-link, occasion-id, or version has an invalid format" >&2
  exit 2
fi
if [[ ! "$MIN_ZOOM" =~ ^[0-9]+$ || ! "$MAX_ZOOM" =~ ^[0-9]+$ || "$MIN_ZOOM" -gt "$MAX_ZOOM" ]]; then
  echo "zoom range is invalid" >&2
  exit 2
fi
if [[ "$GLYPH_PROFILE" != "audited" && "$GLYPH_PROFILE" != "latin" ]]; then
  echo "glyph profile must be audited or latin" >&2
  exit 2
fi
if [[ "$BUNDLE_MODE" != "maplibre_only" && "$GLYPH_PROFILE" != "audited" ]]; then
  echo "reduced glyph profiles require --maplibre-only" >&2
  exit 2
fi
if [[ ! "$MAX_BUNDLE_BYTES" =~ ^[0-9]+$ ]]; then
  echo "max bundle bytes must be a non-negative integer" >&2
  exit 2
fi
if [[ "$BUNDLE_MODE" == "maplibre_only" && "$MAX_BUNDLE_BYTES" -eq 0 ]]; then
  echo "--maplibre-only requires an explicit --max-bundle-bytes budget" >&2
  exit 2
fi

if [[ "$GLYPH_PROFILE" == "latin" ]]; then
  GLYPH_RANGES=("${LATIN_GLYPH_RANGES[@]}")
else
  GLYPH_RANGES=("${AUDITED_GLYPH_RANGES[@]}")
fi

for tool in versatiles sqlite3 jq shasum curl awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool is missing: $tool" >&2
    exit 1
  fi
done

IFS=',' read -r BBOX_WEST BBOX_SOUTH BBOX_EAST BBOX_NORTH <<< "$BBOX"
if ! awk -v w="$BBOX_WEST" -v s="$BBOX_SOUTH" -v e="$BBOX_EAST" -v n="$BBOX_NORTH" \
  'BEGIN { exit !(w+0==w && s+0==s && e+0==e && n+0==n && w<e && s<n) }'; then
  echo "bbox must be W,S,E,N with increasing numeric coordinates" >&2
  exit 2
fi

OUTPUT_DIR="$SCRIPT_DIR/out/$OCCASION/$ARTIFACT_VERSION"
MAP_NAME="map-z${MIN_ZOOM}-${MAX_ZOOM}"
MBTILES_NAME="$MAP_NAME.mbtiles"
MBTILES_PATH="$OUTPUT_DIR/$MBTILES_NAME"
PMTILES_NAME="$MAP_NAME.pmtiles"
PMTILES_PATH="$OUTPUT_DIR/$PMTILES_NAME"
TRACKED_MANIFEST_DIR="$MANIFEST_ROOT/$OCCASION/$ARTIFACT_VERSION"
TRACKED_MANIFEST="$TRACKED_MANIFEST_DIR/manifest.json"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/festapp-offline-map.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -e "$TRACKED_MANIFEST" ||
      ( ( -e "$MBTILES_PATH" || -e "$PMTILES_PATH" ) && "$RESUME_EXISTING" != true ) ]]; then
  echo "Refusing to overwrite existing artifact version: $OCCASION/$ARTIFACT_VERSION" >&2
  exit 1
fi
if [[ "$RESUME_EXISTING" == true && ! -f "$MBTILES_PATH" ]]; then
  echo "Cannot resume because MBTiles does not exist: $MBTILES_PATH" >&2
  exit 1
fi

BUILD_STYLE_DIR="$STYLE_DIR"
if [[ -n "$STYLE_MANIFEST" ]]; then
  [[ -f "$STYLE_MANIFEST" ]] || { echo "Style manifest does not exist: $STYLE_MANIFEST" >&2; exit 1; }
  BUILD_STYLE_DIR="$TMP_DIR/style"
  mkdir -p "$BUILD_STYLE_DIR/sprites"
  while IFS='|' read -r role destination; do
    asset_count="$(jq --arg role "$role" '[.assets[] | select(.role == $role)] | length' "$STYLE_MANIFEST")"
    [[ "$asset_count" == "1" ]] || { echo "Style manifest must contain exactly one $role asset" >&2; exit 1; }
    asset_url="$(jq -r --arg role "$role" '.assets[] | select(.role == $role) | .url' "$STYLE_MANIFEST")"
    asset_sha="$(jq -r --arg role "$role" '.assets[] | select(.role == $role) | .sha256' "$STYLE_MANIFEST")"
    [[ "$asset_url" == https://assets.festapp.net/* && "$asset_sha" =~ ^[a-f0-9]{64}$ ]] || {
      echo "Style manifest contains an unsafe $role asset" >&2
      exit 1
    }
    curl -fsSL "$asset_url" -o "$BUILD_STYLE_DIR/$destination"
    downloaded_sha="$(shasum -a 256 "$BUILD_STYLE_DIR/$destination" | awk '{print $1}')"
    [[ "$downloaded_sha" == "$asset_sha" ]] || { echo "Style manifest checksum mismatch for $role" >&2; exit 1; }
  done <<'EOF'
style|style.json
sprite_json_1x|sprites/sprites.json
sprite_png_1x|sprites/sprites.png
sprite_json_2x|sprites/sprites@2x.json
sprite_png_2x|sprites/sprites@2x.png
EOF
fi

for asset in style.json sprites/sprites.json sprites/sprites.png sprites/sprites@2x.json sprites/sprites@2x.png; do
  if [[ ! -f "$BUILD_STYLE_DIR/$asset" ]]; then
    echo "Style asset is missing: $BUILD_STYLE_DIR/$asset (use --style-manifest for a verified immutable source)" >&2
    exit 1
  fi
done

ALLOWED_SOURCE_LAYERS='["addresses","boundaries","boundary_labels","bridges","buildings","dam_lines","dam_polygons","ferries","land","ocean","pier_lines","pier_polygons","place_labels","pois","public_transport","sites","street_labels","street_polygons","streets","water_lines","water_polygons"]'
jq -e --argjson allowed "$ALLOWED_SOURCE_LAYERS" '
  (.sources | keys) == ["versatiles-shortbread"] and
  .sources["versatiles-shortbread"].type == "vector" and
  (.sprite | startswith("https://")) and
  ([.layers[] | select(.layout["text-field"]? == "{name_en}")] | length == 0) and
  ([.layers[] | select(.layout["text-field"]? == ["coalesce", ["get", "name"], ["get", "name_en"]])] | length > 0) and
  ([.layers[] | select(.source? == "versatiles-shortbread") | .["source-layer"]] - $allowed | length == 0)
' "$BUILD_STYLE_DIR/style.json" >/dev/null

SUPABASE_ENDPOINT="${SUPABASE_URL:-}"
SUPABASE_PUBLIC_KEY="${SUPABASE_ANON_KEY:-}"
if [[ -z "$SUPABASE_ENDPOINT" || -z "$SUPABASE_PUBLIC_KEY" ]]; then
  echo "SUPABASE_URL and SUPABASE_ANON_KEY are required for the live bounds gate" >&2
  exit 1
fi

curl -fsS "$SUPABASE_ENDPOINT/rest/v1/occasions?select=id&link=eq.$OCCASION_LINK" \
  -H "apikey: $SUPABASE_PUBLIC_KEY" > "$TMP_DIR/occasion.json"
if [[ "$(jq 'length' "$TMP_DIR/occasion.json")" != "1" ||
      "$(jq -r '.[0].id' "$TMP_DIR/occasion.json")" != "$OCCASION_ID" ]]; then
  echo "Live occasion id does not match --occasion-id" >&2
  exit 1
fi

curl -fsS "$SUPABASE_ENDPOINT/rest/v1/places?occasion=eq.$OCCASION_ID&select=id,coordinates" \
  -H "apikey: $SUPABASE_PUBLIC_KEY" > "$TMP_DIR/places.json"
curl -fsS "$SUPABASE_ENDPOINT/rest/v1/path_groups?occasion=eq.$OCCASION_ID&select=id,path_data" \
  -H "apikey: $SUPABASE_PUBLIC_KEY" > "$TMP_DIR/path-groups.json"

jq -n --slurpfile places "$TMP_DIR/places.json" --slurpfile paths "$TMP_DIR/path-groups.json" '
  [
    ($places[0][] | .coordinates.latLng | select(.lat != null and .lng != null) | {kind:"place",lat,lng}),
    ($paths[0][] | .path_data[][]? | select(type == "object" and .lat != null and .lng != null) | {kind:"route_point",lat,lng})
  ]
' > "$TMP_DIR/points.json"

PLACE_COUNT="$(jq '[.[] | select(.kind == "place")] | length' "$TMP_DIR/points.json")"
ROUTE_POINT_COUNT="$(jq '[.[] | select(.kind == "route_point")] | length' "$TMP_DIR/points.json")"
PATH_GROUP_COUNT="$(jq 'length' "$TMP_DIR/path-groups.json")"
if [[ "$PLACE_COUNT" -eq 0 ]]; then
  echo "Live occasion has no geolocated places" >&2
  exit 1
fi

LIVE_BOUNDS="$(jq -c '{west:(map(.lng)|min),south:(map(.lat)|min),east:(map(.lng)|max),north:(map(.lat)|max)}' "$TMP_DIR/points.json")"
LIVE_WEST="$(jq -r '.west' <<< "$LIVE_BOUNDS")"
LIVE_SOUTH="$(jq -r '.south' <<< "$LIVE_BOUNDS")"
LIVE_EAST="$(jq -r '.east' <<< "$LIVE_BOUNDS")"
LIVE_NORTH="$(jq -r '.north' <<< "$LIVE_BOUNDS")"
MARGIN_RESULT="$(awk -v bw="$BBOX_WEST" -v bs="$BBOX_SOUTH" -v be="$BBOX_EAST" -v bn="$BBOX_NORTH" \
  -v lw="$LIVE_WEST" -v ls="$LIVE_SOUTH" -v le="$LIVE_EAST" -v ln="$LIVE_NORTH" '
  BEGIN {
    pi=atan2(0,-1); mid=(ls+ln)/2; lon_km=111.32*cos(mid*pi/180); lat_km=111.32;
    west=(lw-bw)*lon_km; south=(ls-bs)*lat_km; east=(be-le)*lon_km; north=(bn-ln)*lat_km;
    printf "{\"west_km\":%.3f,\"south_km\":%.3f,\"east_km\":%.3f,\"north_km\":%.3f}", west,south,east,north;
    if (west < 1 || south < 1 || east < 1 || north < 1) exit 7;
  }')" || {
    echo "Live bounds do not have a 1 km margin inside requested bbox: $MARGIN_RESULT" >&2
    exit 1
  }

SOURCE_HEADERS="$(curl -fsSI "$SOURCE_URL" | tr -d '\r')"
SOURCE_ETAG="$(awk 'BEGIN{IGNORECASE=1} /^etag:/ {sub(/^[^:]+:[[:space:]]*/,""); value=$0} END{print value}' <<< "$SOURCE_HEADERS")"
SOURCE_LAST_MODIFIED="$(awk 'BEGIN{IGNORECASE=1} /^last-modified:/ {sub(/^[^:]+:[[:space:]]*/,""); value=$0} END{print value}' <<< "$SOURCE_HEADERS")"

mkdir -p "$OUTPUT_DIR/sprites" "$OUTPUT_DIR/glyphs" "$TRACKED_MANIFEST_DIR"
jq --arg base_url "https://assets.festapp.net/$OCCASION/$ARTIFACT_VERSION/" '
  .sprite = $base_url + "sprites/sprites" |
  .glyphs = $base_url + "glyphs/{fontstack}/{range}.pbf"
' "$BUILD_STYLE_DIR/style.json" > "$OUTPUT_DIR/style.json"
cp "$BUILD_STYLE_DIR/sprites/"* "$OUTPUT_DIR/sprites/"

if [[ "$RESUME_EXISTING" != true ]]; then
  versatiles convert --compress gzip --bbox-border 3 --bbox "$BBOX" --min-zoom "$MIN_ZOOM" --max-zoom "$MAX_ZOOM" \
    "$SOURCE_URL" "$MBTILES_PATH"
fi
if [[ ! -f "$PMTILES_PATH" ]]; then
  versatiles convert "$MBTILES_PATH" "$PMTILES_PATH"
fi

for font_stack in "${FONT_STACKS[@]}"; do
  mkdir -p "$OUTPUT_DIR/glyphs/$font_stack"
  for glyph_range in "${GLYPH_RANGES[@]}"; do
    glyph_path="$OUTPUT_DIR/glyphs/$font_stack/$glyph_range.pbf"
    if [[ ! -f "$glyph_path" ]]; then
      curl -fsSL "$GLYPH_BASE_URL/$font_stack/$glyph_range.pbf" -o "$glyph_path"
    fi
    if [[ ! -s "$glyph_path" ]]; then
      echo "Glyph asset is empty: $glyph_path" >&2
      exit 1
    fi
  done
done

INTEGRITY="$(sqlite3 "$MBTILES_PATH" 'pragma integrity_check;')"
if [[ "$INTEGRITY" != "ok" ]]; then
  echo "MBTiles integrity check failed: $INTEGRITY" >&2
  exit 1
fi
METADATA_JSON="$(sqlite3 -json "$MBTILES_PATH" 'select name,value from metadata order by name;' | jq 'map({key:.name,value:.value}) | from_entries')"
FORMAT="$(jq -r '.format // empty' <<< "$METADATA_JSON")"
ACTUAL_MIN_ZOOM="$(jq -r '.minzoom // empty' <<< "$METADATA_JSON")"
ACTUAL_MAX_ZOOM="$(jq -r '.maxzoom // empty' <<< "$METADATA_JSON")"
if [[ "$FORMAT" != "pbf" || "$ACTUAL_MIN_ZOOM" != "$MIN_ZOOM" || "$ACTUAL_MAX_ZOOM" != "$MAX_ZOOM" ]]; then
  echo "Unexpected MBTiles metadata: format=$FORMAT minzoom=$ACTUAL_MIN_ZOOM maxzoom=$ACTUAL_MAX_ZOOM" >&2
  exit 1
fi

MBTILES_BYTES="$(stat -f '%z' "$MBTILES_PATH" 2>/dev/null || stat -c '%s' "$MBTILES_PATH")"
if [[ "$MBTILES_BYTES" -gt 47185920 ]]; then
  echo "MBTiles exceeds the user-approved 45 MiB v1 gate: $MBTILES_BYTES bytes" >&2
  exit 1
fi
TILE_COUNT="$(sqlite3 "$MBTILES_PATH" 'select count(*) from tiles;')"
PMTILES_BYTES="$(stat -f '%z' "$PMTILES_PATH" 2>/dev/null || stat -c '%s' "$PMTILES_PATH")"
versatiles probe -q "$PMTILES_PATH" >/dev/null

IFS=',' read -r MANIFEST_WEST MANIFEST_SOUTH MANIFEST_EAST MANIFEST_NORTH <<< "$(jq -r '.bounds' <<< "$METADATA_JSON")"
if ! jq -e --argjson w "$MANIFEST_WEST" --argjson s "$MANIFEST_SOUTH" --argjson e "$MANIFEST_EAST" --argjson n "$MANIFEST_NORTH" \
  'all(.[]; .lng >= $w and .lng <= $e and .lat >= $s and .lat <= $n)' "$TMP_DIR/points.json" >/dev/null; then
  echo "At least one live place or route point lies outside MBTiles metadata bounds" >&2
  exit 1
fi

VERSATILES_VERSION="$(versatiles --version | head -n 1)"
SQLITE_VERSION="$(sqlite3 --version | awk '{print $1}')"
JQ_VERSION="$(jq --version)"
SHASUM_VERSION="$(shasum --version 2>&1 | head -n 1)"
BUILT_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

ASSETS_JSON='[]'
CORE_ASSETS="pmtiles|$PMTILES_NAME|application/vnd.pmtiles
style|style.json|application/json
sprite_json_1x|sprites/sprites.json|application/json
sprite_png_1x|sprites/sprites.png|image/png
sprite_json_2x|sprites/sprites@2x.json|application/json
sprite_png_2x|sprites/sprites@2x.png|image/png"
if [[ "$BUNDLE_MODE" == "mbtiles" ]]; then
  CORE_ASSETS="mbtiles|$MBTILES_NAME|application/vnd.sqlite3
$CORE_ASSETS"
fi
while IFS='|' read -r role relative_path content_type; do
  asset_path="$OUTPUT_DIR/$relative_path"
  asset_bytes="$(stat -f '%z' "$asset_path" 2>/dev/null || stat -c '%s' "$asset_path")"
  asset_sha="$(shasum -a 256 "$asset_path" | awk '{print $1}')"
  ASSETS_JSON="$(jq -c --arg role "$role" --arg path "$relative_path" --arg type "$content_type" --argjson bytes "$asset_bytes" --arg sha "$asset_sha" \
    --arg url "https://assets.festapp.net/$OCCASION/$ARTIFACT_VERSION/$relative_path" \
    '. + [{role:$role,path:$path,url:$url,content_type:$type,bytes:$bytes,sha256:$sha}]' <<< "$ASSETS_JSON")"
done <<< "$CORE_ASSETS"

for font_stack in "${FONT_STACKS[@]}"; do
  for glyph_range in "${GLYPH_RANGES[@]}"; do
    relative_path="glyphs/$font_stack/$glyph_range.pbf"
    asset_path="$OUTPUT_DIR/$relative_path"
    asset_bytes="$(stat -f '%z' "$asset_path" 2>/dev/null || stat -c '%s' "$asset_path")"
    asset_sha="$(shasum -a 256 "$asset_path" | awk '{print $1}')"
    ASSETS_JSON="$(jq -c --arg path "$relative_path" --argjson bytes "$asset_bytes" --arg sha "$asset_sha" \
      --arg url "https://assets.festapp.net/$OCCASION/$ARTIFACT_VERSION/$relative_path" \
      '. + [{role:"glyph",path:$path,url:$url,content_type:"application/x-protobuf",bytes:$bytes,sha256:$sha}]' <<< "$ASSETS_JSON")"
  done
done

BUNDLE_BYTES="$(jq '[.[].bytes] | add // 0' <<< "$ASSETS_JSON")"
if [[ "$MAX_BUNDLE_BYTES" -gt 0 && "$BUNDLE_BYTES" -gt "$MAX_BUNDLE_BYTES" ]]; then
  echo "Bundle exceeds the explicit budget: $BUNDLE_BYTES > $MAX_BUNDLE_BYTES bytes" >&2
  exit 1
fi

if [[ "$BUNDLE_MODE" == "maplibre_only" ]]; then
  rm "$MBTILES_PATH"
  SCHEMA_VERSION=3
else
  SCHEMA_VERSION=2
fi

jq -n \
  --argjson schema_version "$SCHEMA_VERSION" --arg bundle_mode "$BUNDLE_MODE" \
  --arg glyph_profile "$GLYPH_PROFILE" --arg occasion "$OCCASION" --argjson occasion_id "$OCCASION_ID" \
  --arg version "$ARTIFACT_VERSION" --arg built_at "$BUILT_AT" \
  --arg source_name "versatiles-shortbread" --arg base_url "https://assets.festapp.net/$OCCASION/$ARTIFACT_VERSION/" \
  --arg source_url "$SOURCE_URL" --arg source_etag "$SOURCE_ETAG" --arg source_last_modified "$SOURCE_LAST_MODIFIED" \
  --argjson requested_bounds "[$BBOX_WEST,$BBOX_SOUTH,$BBOX_EAST,$BBOX_NORTH]" \
  --argjson live_bounds "$LIVE_BOUNDS" --argjson margins_km "$MARGIN_RESULT" \
  --argjson min_zoom "$MIN_ZOOM" --argjson max_zoom "$MAX_ZOOM" \
  --argjson place_count "$PLACE_COUNT" --argjson path_group_count "$PATH_GROUP_COUNT" --argjson route_point_count "$ROUTE_POINT_COUNT" \
  --arg versatiles "$VERSATILES_VERSION" --arg sqlite "$SQLITE_VERSION" --arg jq "$JQ_VERSION" --arg shasum "$SHASUM_VERSION" \
  --argjson tile_count "$TILE_COUNT" --argjson metadata "$METADATA_JSON" --argjson assets "$ASSETS_JSON" \
  --argjson bundle_bytes "$BUNDLE_BYTES" --argjson max_bundle_bytes "$MAX_BUNDLE_BYTES" '
  {
    schema_version:$schema_version,
    bundle_mode:(if $schema_version == 3 then $bundle_mode else null end),
    occasion:{slug:$occasion,id:$occasion_id},
    artifact_version:$version,
    source_name:$source_name,
    base_url:$base_url,
    built_at:$built_at,
    source:{url:$source_url,etag:$source_etag,last_modified:$source_last_modified},
    build:{requested_bounds:$requested_bounds,min_zoom:$min_zoom,max_zoom:$max_zoom,bbox_border_tiles:3,compression:"gzip",glyph_profile:$glyph_profile,bundle_bytes:$bundle_bytes,max_bundle_bytes:(if $max_bundle_bytes > 0 then $max_bundle_bytes else null end)},
    live_content:{bounds:$live_bounds,margins_km:$margins_km,places:$place_count,path_groups:$path_group_count,free_route_points:$route_point_count},
    tools:{versatiles:$versatiles,sqlite:$sqlite,jq:$jq,shasum:$shasum},
    mbtiles:{tile_count:$tile_count,metadata:$metadata},
    assets:$assets,
    manifest_note:"The manifest cannot contain its own SHA-256; record it in the rollout log."
  }
' > "$OUTPUT_DIR/manifest.json"

cp "$OUTPUT_DIR/manifest.json" "$TRACKED_MANIFEST"
curl -fsSL "$DEFAULT_FRONTEND_URL" -o "$SCRIPT_DIR/out/frontend.br.tar.gz"

MANIFEST_SHA="$(shasum -a 256 "$OUTPUT_DIR/manifest.json" | awk '{print $1}')"
echo "Built $OCCASION/$ARTIFACT_VERSION: $TILE_COUNT tiles, mode $BUNDLE_MODE, bundle $BUNDLE_BYTES bytes (MBTiles intermediate $MBTILES_BYTES, PMTiles $PMTILES_BYTES)"
echo "Manifest SHA-256: $MANIFEST_SHA"
if [[ "$BUNDLE_MODE" == "maplibre_only" ]]; then
  echo "Preview: $SCRIPT_DIR/preview.sh $OCCASION $ARTIFACT_VERSION $PMTILES_NAME"
else
  echo "Preview: $SCRIPT_DIR/preview.sh $OCCASION $ARTIFACT_VERSION $MBTILES_NAME"
fi
