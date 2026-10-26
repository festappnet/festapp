#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 OCCASION VERSION TILE_CONTAINER_FILENAME" >&2
  exit 2
fi
if ! command -v versatiles >/dev/null 2>&1; then
  echo "Required tool is missing: versatiles" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND="$SCRIPT_DIR/out/frontend.br.tar.gz"
BUNDLE_DIR="$SCRIPT_DIR/out/$1/$2"
TILE_CONTAINER="$BUNDLE_DIR/$3"
NAMED_TILE_CONTAINER="$SCRIPT_DIR/out/versatiles-shortbread.${3##*.}"
PREVIEW_DIR="$SCRIPT_DIR/out/preview/$1/$2"

if [[ ! -f "$FRONTEND" || ! -f "$TILE_CONTAINER" ||
      ! -f "$BUNDLE_DIR/manifest.json" ||
      ! -f "$BUNDLE_DIR/style.json" || ! -d "$BUNDLE_DIR/sprites" ]]; then
  echo "Run build.sh before starting the preview" >&2
  exit 1
fi

mkdir -p "$PREVIEW_DIR/sprites" "$PREVIEW_DIR/glyphs"
cp "$SCRIPT_DIR/preview/index.html" "$PREVIEW_DIR/index.html"
cp "$BUNDLE_DIR/sprites/"* "$PREVIEW_DIR/sprites/"
cp -R "$BUNDLE_DIR/glyphs/." "$PREVIEW_DIR/glyphs/"
jq -r '
  "window.FESTAPP_OFFLINE_MAP_PREVIEW = " + ({
    title:(.occasion.slug + " · offline map preview"),
    center:[
      ((.live_content.bounds.west + .live_content.bounds.east) / 2),
      ((.live_content.bounds.south + .live_content.bounds.north) / 2)
    ],
    zoom:12
  } | tojson) + ";"
' "$BUNDLE_DIR/manifest.json" > "$PREVIEW_DIR/preview-config.js"
jq '
  .sources["versatiles-shortbread"].tiles = ["http://localhost:8080/tiles/versatiles-shortbread/{z}/{x}/{y}"] |
  .sprite = "http://localhost:8080/sprites/sprites" |
  .glyphs = "http://localhost:8080/glyphs/{fontstack}/{range}.pbf"
' "$BUNDLE_DIR/style.json" > "$PREVIEW_DIR/preview-style.json"

ln -sfn "$TILE_CONTAINER" "$NAMED_TILE_CONTAINER"
exec versatiles serve -i 127.0.0.1 -s "$PREVIEW_DIR" -s "$FRONTEND" "$NAMED_TILE_CONTAINER"
