#!/usr/bin/env bash
# Actual pub/npm-selected archives, clean public consumer and archived example.
# Publishes nothing; temporary build inputs are byte-checked against the checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/qa/archive}"
python3 "$ROOT/tool/check_architecture.py" ${BLUEPRINT_HOST_ROOT:+--host "$BLUEPRINT_HOST_ROOT"}
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/venue-archive-consumer.XXXXXX")"
cleanup() { local code=$?; if [[ "$code" -eq 0 ]]; then rm -rf "$WORK"; else printf 'Archive check failed; isolated evidence workspace: %s\n' "$WORK" >&2; fi; }
trap cleanup EXIT
cp "$ROOT/.fvmrc" "$WORK/.fvmrc"
# Parent .pubignore excludes packages/. Stage only this package outside git so
# pub can select it correctly; qa_archive proves every selected file unchanged.
mkdir -p "$WORK/core-source"
python3 - "$ROOT/packages/venue_layout_core" "$WORK/core-source" <<'PY'
import pathlib,shutil,sys
source,target=map(pathlib.Path,sys.argv[1:])
shutil.copytree(source,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.dart_tool','.git','.fvm','build','pubspec.lock','pubspec_overrides.yaml','__pycache__'))
PY
(cd "$WORK/core-source" && fvm dart pub get --offline >"$OUT/core-stage-pub.log" 2>&1)
set +e
(cd "$WORK/core-source" && fvm dart pub publish --dry-run --verbose >"$OUT/core-publish.log" 2>&1)
CORE_EXIT=$?
(cd "$ROOT" && fvm flutter pub publish --dry-run --verbose >"$OUT/wrapper-publish.log" 2>&1)
WRAPPER_EXIT=$?
set -e
printf '%s\n' "$CORE_EXIT" >"$OUT/core-publish.exit-code"
printf '%s\n' "$WRAPPER_EXIT" >"$OUT/wrapper-publish.exit-code"
python3 "$ROOT/tool/qa_publish_status.py" "$OUT/core-publish.log" "$OUT/wrapper-publish.log"
python3 "$ROOT/tool/qa_archive.py" "$WORK/core-source" "$OUT/core-publish.log" "$OUT/venue_layout_core.tar.gz" "$ROOT/packages/venue_layout_core"
python3 "$ROOT/tool/qa_archive.py" "$ROOT" "$OUT/wrapper-publish.log" "$OUT/venue_seat_picker.tar.gz"
(cd "$ROOT/web" && pnpm pack --dry-run --json >"$OUT/npm-dry-run.json" && pnpm pack --pack-destination "$OUT" --json >"$OUT/npm-pack.json")
python3 - "$OUT/npm-dry-run.json" "$OUT/npm-pack.json" <<'PYNORMALIZE'
import json,pathlib,sys
for name in sys.argv[1:]:
 p=pathlib.Path(name);value=json.loads(p.read_text())
 if isinstance(value,dict):value=[value]
 for item in value:
  if 'filename' in item:item['filename']=pathlib.Path(item['filename']).name
 p.write_text(json.dumps(value)+'\n')
PYNORMALIZE
mkdir -p "$WORK/core" "$WORK/wrapper" "$WORK/consumer/test" "$WORK/npm"
tar -xzf "$OUT/venue_layout_core.tar.gz" -C "$WORK/core"
tar -xzf "$OUT/venue_seat_picker.tar.gz" -C "$WORK/wrapper"
NPM="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["filename"])' "$OUT/npm-pack.json")"
tar -xzf "$OUT/$NPM" -C "$WORK/npm"
cat >"$WORK/consumer/pubspec.yaml" <<'YAML'
name: archive_consumer
publish_to: none
environment:
  sdk: '>=3.8.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  venue_seat_picker:
    path: ../wrapper
dev_dependencies:
  flutter_test:
    sdk: flutter
dependency_overrides:
  venue_layout_core:
    path: ../core
flutter:
  uses-material-design: true
YAML
cp "$ROOT/tool/qa_consumer_test.dart" "$WORK/consumer/test/archive_test.dart"
(cd "$WORK/consumer" && fvm flutter pub get --offline >"$OUT/consumer-pub.log" 2>&1 && fvm flutter test --concurrency=1 --reporter expanded --dart-define="QA_TEMPLATE_OUT=$OUT/templates.json" >"$OUT/consumer-test.log" 2>&1)
printf 'Clean archive consumer: inventoried templates, host seams and picker lifecycle passed.\n'
cat >"$WORK/wrapper/example/pubspec_overrides.yaml" <<'YAML'
dependency_overrides:
  venue_layout_core:
    path: ../../core
YAML
if [[ -n "${BLUEPRINT_REUSE_ARCHIVE:-}" ]]; then
  python3 - "$OUT" "$BLUEPRINT_REUSE_ARCHIVE" <<'PYREUSE'
import hashlib,json,pathlib,sys,tarfile
current,previous=map(pathlib.Path,sys.argv[1:])
assert json.loads((previous/'archive-result.json').read_text())['passed']
def contents(path):
 with tarfile.open(path) as archive:
  return {m.name:hashlib.sha256(archive.extractfile(m).read()).hexdigest() for m in archive.getmembers() if m.isfile()}
for name in ['venue_layout_core.tar.gz','venue_seat_picker.tar.gz']:
 currentFiles,previousFiles=contents(current/name),contents(previous/name)
 changed={f for f in currentFiles.keys()|previousFiles.keys() if currentFiles.get(f)!=previousFiles.get(f)}
 # The archive verification shell script is distributed tooling, not a Dart
 # import, Flutter asset or dependency. Every compiled input must be identical.
 assert changed <= {'tool/archive_check.sh'},f'Changed Flutter build input: {name}: {changed}'
assert (previous/'flutter/main.dart.js').is_file()
(current/'example-build-reuse.json').write_text(json.dumps({'from':str(previous),'identicalFlutterBuildInputs':True,'distributionOnlyException':'tool/archive_check.sh','mainDartJsSha256':hashlib.sha256((previous/'flutter/main.dart.js').read_bytes()).hexdigest()},indent=2)+'\n')
PYREUSE
  mkdir -p "$WORK/wrapper/example/build/web"
  cp -R "$BLUEPRINT_REUSE_ARCHIVE/flutter/." "$WORK/wrapper/example/build/web/"
else
(cd "$WORK/wrapper/example" && fvm flutter pub get --offline >"$OUT/example-pub.log" 2>&1 && fvm flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --base-href /flutter/ >"$OUT/example-build.log" 2>&1)
fi
# Preserve the exact built/extracted artifacts for the existing demo kit check.
# This avoids a second Flutter/kernel build for the same frozen inputs.
mkdir -p "$OUT/flutter" "$OUT/npm" "$ROOT/build/demo/flutter" "$ROOT/build/demo/js"
cp -R "$WORK/wrapper/example/build/web/." "$OUT/flutter/"
cp -R "$WORK/npm/package/." "$OUT/npm/"
cp -R "$OUT/flutter/." "$ROOT/build/demo/flutter/"
cp -R "$OUT/npm/." "$ROOT/build/demo/js/"
cp "$ROOT/LICENSE" "$ROOT/build/demo/LICENSE"
cp "$ROOT/tool/kit_run.py" "$ROOT/build/demo/run.py"
cp "$ROOT/tool/demo_server.py" "$ROOT/build/demo/server.py"
python3 "$ROOT/tool/demo_manifest.py" "$ROOT" "$ROOT/build/demo"
node "$ROOT/tool/qa_archive_browser.mjs" "$WORK/npm/package" "$WORK/wrapper/example/build/web" "$OUT/templates.json" "$OUT"
python3 - "$WORK/npm/package" "$OUT" <<'PY'
import hashlib,json,pathlib,subprocess,sys
r,out=map(pathlib.Path,sys.argv[1:]);required=['src/index.js','src/index.d.ts','dist/venue_layout_kernel.js','dist/manifest.json','demo/index.html','LICENSE','assets/layout_fonts/fixtures.json','assets/layout_fonts/manifest.json','assets/layout_fonts/Roboto-OFL.txt',*[f'assets/layout_fonts/Roboto-{weight}-{style}.ttf' for weight in [400,700] for style in ['normal','italic']]]
for f in required:assert (r/f).is_file(),f
assert 'mount' in (r/'src/index.js').read_text()
(out/'archive-result.json').write_text(json.dumps({'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'passed':True,'coreSourceByteEquivalent':True,'pubSelectedCoreAndWrapper':True,'actualNpmPack':True,'cleanConsumerTemplates':len(json.loads((out/'templates.json').read_text())),'archivedExampleBuilt':True,'archivedExampleBrowser':True,'requiredNpmFiles':{f:hashlib.sha256((r/f).read_bytes()).hexdigest() for f in required}},indent=2)+'\n')
PY
printf 'Archive gate passed: actual pub/npm selections, clean consumer and extracted example browser.\n'
