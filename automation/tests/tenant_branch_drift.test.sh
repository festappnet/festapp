#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_ROOT=$(mktemp -d /tmp/festapp-drift-test.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT
REPO="$TMP_ROOT/repo"
mkdir -p "$REPO"

(cd "$PROJECT_ROOT" && while IFS= read -r -d '' path; do
  [[ -e "$path" || -L "$path" ]] && printf '%s\0' "$path"
done < <(git ls-files -co --exclude-standard -z)) |
  (cd "$PROJECT_ROOT" && tar --null -T - -cf -) |
  tar -xf - -C "$REPO"

git -C "$REPO" init -q -b main
# The real repository intentionally tracks a small set of generated FVM pins
# below an otherwise ignored .fvm directory. Preserve that tracked baseline in
# the synthetic repository so replay validation exercises the production tree.
git -C "$REPO" add -Af
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm base
BASE_SHA=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" switch -qc prod/csmostrava2026
cp "$REPO/automation/tests/fixtures/tenants/csmostrava2026.conf" "$REPO/automation/project.conf"
# Exercise the actual tenant source -> generated web-font contract, including
# the filename normalization used by CSM's custom font.
mkdir -p "$REPO/fonts"
printf 'tenant-font-fixture' > "$REPO/fonts/Gill Sans Regular.ttf"
printf '\nFONT_FILES="fonts/Gill Sans Regular.ttf"\n' >> "$REPO/automation/project.conf"
(cd "$REPO" && bash automation/apply_config.sh automation/project.conf >/dev/null)
node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({schemaVersion:1,tenantId:"csmostrava2026",baseMainSha:process.argv[2]},null,2)+"\n")' "$REPO/automation/tenant-overlay.json" "$BASE_SHA"
git -C "$REPO" add -A
git -C "$REPO" add -f web_client/src/assets/fonts/GillSansRegular.ttf
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm valid-overlay
VALID_TIP=$(git -C "$REPO" rev-parse HEAD)
cmp "$REPO/fonts/Gill Sans Regular.ttf" "$REPO/web_client/src/assets/fonts/GillSansRegular.ttf"
git -C "$REPO" show "${BASE_SHA}:automation/check_tenant_branch_drift.sh" > "$TMP_ROOT/checker.sh"
chmod +x "$TMP_ROOT/checker.sh"
(grep -Fq 'git hash-object --no-filters "$expected"' "$TMP_ROOT/checker.sh" &&
  grep -Fq 'git rev-parse "${PROD_TIP}:${path}"' "$TMP_ROOT/checker.sh" &&
  grep -Fq 'git -c core.autocrlf=false archive "$BASE_MAIN_SHA"' "$TMP_ROOT/checker.sh" &&
  grep -Fq 'git -c core.autocrlf=false archive "$PROD_TIP" -- "$path"' "$TMP_ROOT/checker.sh") || {
  echo 'Drift checker must materialize and compare repository bytes independently of autocrlf' >&2
  exit 1
}
(cd "$REPO" && CANONICAL_MAIN_REF=main "$TMP_ROOT/checker.sh" "$BASE_SHA" csmostrava2026 "$VALID_TIP" >/dev/null)

expect_failure() {
  local label=$1 tip=$2 tenant=${3:-csmostrava2026}
  if (cd "$REPO" && CANONICAL_MAIN_REF=main "$TMP_ROOT/checker.sh" "$BASE_SHA" "$tenant" "$tip" >"$TMP_ROOT/$label.log" 2>&1); then
    echo "Expected drift rejection: $label" >&2
    exit 1
  fi
}

git -C "$REPO" switch -qc tamper-shared "$VALID_TIP"
printf '\n// drift fixture\n' >> "$REPO/lib/main.dart"
git -C "$REPO" add lib/main.dart
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm tamper-shared
expect_failure shared "$(git -C "$REPO" rev-parse HEAD)"

git -C "$REPO" switch -qc tamper-generated "$VALID_TIP"
printf '\n<!-- drift fixture -->\n' >> "$REPO/web/index.html"
git -C "$REPO" add web/index.html
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm tamper-generated
expect_failure generated "$(git -C "$REPO" rev-parse HEAD)"

# Generated-font allowlisting still requires exact regeneration from approved
# tenant source: edited copies and unconfigured additions remain forbidden.
for mode in changed orphan; do
  git -C "$REPO" switch -qc "tamper-font-$mode" "$VALID_TIP"
  if [[ "$mode" == changed ]]; then
    printf 'tampered-font' > "$REPO/web_client/src/assets/fonts/GillSansRegular.ttf"
  else
    printf 'orphan-font' > "$REPO/web_client/src/assets/fonts/Unconfigured.ttf"
  fi
  git -C "$REPO" add -f web_client/src/assets/fonts
  git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm "tamper-font-$mode"
  expect_failure "generated-font-$mode" "$(git -C "$REPO" rev-parse HEAD)"
done

git -C "$REPO" switch -qc tamper-policy "$VALID_TIP"
printf '\nlib/**\n' >> "$REPO/automation/tenant-overlays/csmostrava2026.paths"
git -C "$REPO" add automation/tenant-overlays/csmostrava2026.paths
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm tamper-policy
expect_failure policy "$(git -C "$REPO" rev-parse HEAD)"

git -C "$REPO" switch -qc tamper-base "$VALID_TIP"
node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.baseMainSha="0000000000000000000000000000000000000000";fs.writeFileSync(p,JSON.stringify(v,null,2)+"\n")' "$REPO/automation/tenant-overlay.json"
git -C "$REPO" add automation/tenant-overlay.json
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm tamper-base
expect_failure base "$(git -C "$REPO" rev-parse HEAD)"

git -C "$REPO" switch -qc tamper-schema "$VALID_TIP"
node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.branchCanRelaxPolicy=true;fs.writeFileSync(p,JSON.stringify(v,null,2)+"\n")' "$REPO/automation/tenant-overlay.json"
git -C "$REPO" add automation/tenant-overlay.json
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm tamper-schema
expect_failure schema "$(git -C "$REPO" rev-parse HEAD)"

git -C "$REPO" switch -qc prod/festivalslunovrat "$BASE_SHA"
cp "$REPO/automation/tests/fixtures/tenants/festivalslunovrat.conf" "$REPO/automation/project.conf"
(cd "$REPO" && bash automation/apply_config.sh automation/project.conf >/dev/null)
node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({schemaVersion:1,tenantId:"festivalslunovrat",baseMainSha:process.argv[2]},null,2)+"\n")' "$REPO/automation/tenant-overlay.json" "$BASE_SHA"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm valid-slunovrat-overlay
SLUNOVRAT_TIP=$(git -C "$REPO" rev-parse HEAD)
(cd "$REPO" && CANONICAL_MAIN_REF=main "$TMP_ROOT/checker.sh" "$BASE_SHA" festivalslunovrat "$SLUNOVRAT_TIP" >/dev/null)

git -C "$REPO" switch -qc prod/cavfotofest "$BASE_SHA"
cp "$REPO/automation/tests/fixtures/tenants/cavfotofest.conf" "$REPO/automation/project.conf"
(cd "$REPO" && bash automation/apply_config.sh automation/project.conf >/dev/null)
node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({schemaVersion:1,tenantId:"cavfotofest",baseMainSha:process.argv[2]},null,2)+"\n")' "$REPO/automation/tenant-overlay.json" "$BASE_SHA"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm valid-cav-overlay
CAV_TIP=$(git -C "$REPO" rev-parse HEAD)
(cd "$REPO" && CANONICAL_MAIN_REF=main "$TMP_ROOT/checker.sh" "$BASE_SHA" cavfotofest "$CAV_TIP" >/dev/null)

git -C "$REPO" switch -qc tamper-slunovrat-shared "$SLUNOVRAT_TIP"
printf '\n// Slunovrat shared drift fixture\n' >> "$REPO/lib/main.dart"
git -C "$REPO" add lib/main.dart
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm tamper-slunovrat-shared
expect_failure slunovrat-shared "$(git -C "$REPO" rev-parse HEAD)" festivalslunovrat

git -C "$REPO" switch -qc prod/festappticketsglobal "$BASE_SHA"
cp "$REPO/automation/tests/fixtures/tenants/festappticketsglobal.conf" "$REPO/automation/project.conf"
(cd "$REPO" && bash automation/apply_config.sh automation/project.conf >/dev/null)
node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({schemaVersion:1,tenantId:"festappticketsglobal",baseMainSha:process.argv[2]},null,2)+"\n")' "$REPO/automation/tenant-overlay.json" "$BASE_SHA"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm valid-english-overlay
EN_TIP=$(git -C "$REPO" rev-parse HEAD)
(cd "$REPO" && CANONICAL_MAIN_REF=main "$TMP_ROOT/checker.sh" "$BASE_SHA" festappticketsglobal "$EN_TIP" >/dev/null)

# Inactive regional press artifacts are deterministically absent in Global.
# Generated-path permission must still reject reintroducing arbitrary payloads.
test ! -e "$REPO/web/organizers/press"
test ! -d "$REPO/web/organizers-media/press-kit"
for mode in page asset; do
  git -C "$REPO" switch -qc "tamper-global-press-$mode" "$EN_TIP"
  case "$mode" in
    page) press_path=web/organizers/press ;;
    asset) press_path=web/organizers-media/press-kit/unauthorized.txt ;;
  esac
  mkdir -p "$REPO/$(dirname "$press_path")"
  printf 'unauthorized press output\n' > "$REPO/$press_path"
  git -C "$REPO" add -- "$press_path"
  git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm "tamper-global-press-$mode"
  expect_failure "global-press-$mode" "$(git -C "$REPO" rev-parse HEAD)" festappticketsglobal
done

# Even the Global branch cannot fork shared code, media recipes or release tools.
git -C "$REPO" switch -qc tamper-global-shared "$EN_TIP"
printf '\n# Global-only capture change\n' >> "$REPO/automation/landing_capture/scenario_contract.py"
git -C "$REPO" add automation/landing_capture/scenario_contract.py
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm forbidden-global-capture-fork
expect_failure global-capture "$(git -C "$REPO" rev-parse HEAD)" festappticketsglobal

# Help is generated locally and excluded from tenant overlays. Even a forced
# addition of either build copy must be rejected as forbidden branch drift.
git -C "$REPO" switch -qc prod/festapptickets "$BASE_SHA"
cp "$REPO/automation/tests/fixtures/tenants/festapptickets.conf" "$REPO/automation/project.conf"
node -e 'const fs=require("fs"),p=process.argv[1];fs.writeFileSync(p,fs.readFileSync(p,"utf8").replaceAll("tickets.example.invalid","vstupenky.online"))' "$REPO/automation/project.conf"
(cd "$REPO" && bash automation/apply_config.sh automation/project.conf >/dev/null)
node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({schemaVersion:1,tenantId:"festapptickets",baseMainSha:process.argv[2]},null,2)+"\n")' "$REPO/automation/tenant-overlay.json" "$BASE_SHA"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm valid-help-overlay
HELP_TIP=$(git -C "$REPO" rev-parse HEAD)
(cd "$REPO" && CANONICAL_MAIN_REF=main "$TMP_ROOT/checker.sh" "$BASE_SHA" festapptickets "$HELP_TIP" >/dev/null)
test -f "$REPO/web_client/public/napoveda/index.html"
test ! -e "$REPO/web/napoveda"
test -z "$(git -C "$REPO" ls-tree -r --name-only "$HELP_TIP" -- web/napoveda web_client/public/napoveda)"
for mode in legacy public; do
  git -C "$REPO" switch -qc "tamper-help-$mode" "$HELP_TIP"
  case "$mode" in
    legacy) help_path=web/napoveda/index.html ;;
    public) help_path=web_client/public/napoveda/index.html ;;
  esac
  mkdir -p "$REPO/$(dirname "$help_path")"
  printf 'unauthorized generated copy\n' > "$REPO/$help_path"
  git -C "$REPO" add -f -- "$help_path"
  git -C "$REPO" -c user.name=cutover-test -c user.email=cutover@example.invalid commit -qm "tamper-help-$mode"
  expect_failure "help-$mode" "$(git -C "$REPO" rev-parse HEAD)" festapptickets
done

echo "Tenant branch drift tests passed"
