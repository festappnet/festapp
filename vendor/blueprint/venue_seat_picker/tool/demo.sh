#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/build/demo"
STATE="$ROOT/build/demo-server.json"
command="${1:-help}"
stop_server() {
  python3 - "$STATE" "$ROOT/tool/demo_server.py" <<'PY'
import json, pathlib, subprocess, sys, os, signal
p=pathlib.Path(sys.argv[1])
if p.exists():
    state=json.loads(p.read_text())
    pid=int(state['pid'])
    command=subprocess.run(['ps','-p',str(pid),'-o','command='],capture_output=True,text=True).stdout
    if sys.argv[2] in command: os.kill(pid,signal.SIGTERM)
    p.unlink(missing_ok=True)
PY
}
start_server() {
  test -f "$KIT/flutter/index.html" || { echo 'Run tool/demo.sh build first' >&2; exit 1; }
  if test -f "$STATE"; then
    if ! python3 -c 'import json,os,sys; os.kill(json.load(open(sys.argv[1]))["pid"],0)' "$STATE" 2>/dev/null; then rm -f "$STATE"; fi
  fi
  if ! test -f "$STATE"; then
    python3 "$ROOT/tool/demo_server.py" "$KIT" "$STATE" >"$ROOT/build/demo-server.log" 2>&1 &
    for _ in {1..40}; do test -f "$STATE" && break; sleep .1; done
  fi
  PORT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "$STATE")"
}
case "$command" in
  build)
    cd "$ROOT"
    python3 tool/configure_workspace.py
    fvm flutter pub get >build-demo-pub.log 2>&1
    (cd example && fvm flutter pub get >>../build-demo-pub.log 2>&1 && fvm flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --base-href /flutter/ >../build-demo-flutter.log 2>&1)
    rm -rf "$KIT/flutter" "$KIT/js"
    mkdir -p "$KIT/flutter" "$KIT/js"
    cp -R example/build/web/. "$KIT/flutter/"
    cp LICENSE "$KIT/LICENSE"
    cp tool/kit_run.py "$KIT/run.py"
    cp tool/demo_server.py "$KIT/server.py"
    if test -x tool/build_web.sh; then tool/build_web.sh; else echo 'Missing tool/build_web.sh kernel build entry' >&2; exit 1; fi
    for entry in src dist demo package.json README.md LICENSE; do
      if test -e "web/$entry"; then cp -R "web/$entry" "$KIT/js/"; fi
    done
    mkdir -p "$KIT/js/assets/layout_fonts"
    cp -R assets/layout_fonts/. "$KIT/js/assets/layout_fonts/"
    python3 "$ROOT/tool/demo_manifest.py" "$ROOT" "$KIT"
    echo "Demo kit: $KIT"
    ;;
  open)
    start_server
    URL="http://127.0.0.1:$PORT/flutter/"
    echo "$URL"
    if test "${2:-}" = '--new-tab'; then
      if test "$(uname)" = Darwin; then open -a 'Google Chrome' "$URL"; else xdg-open "$URL"; fi
    fi
    ;;
  check)
    STATE="$ROOT/build/demo-check-server-$$.json"
    start_server
    trap stop_server EXIT
    node "$ROOT/tool/demo_check.mjs" "http://127.0.0.1:$PORT" "$KIT"
    python3 "$ROOT/tool/report_demo.py"
    ;;
  stop) stop_server; echo 'Owned demo server stopped' ;;
  *) echo 'Usage: tool/demo.sh build|check|open [--new-tab]|stop' ;;
esac
