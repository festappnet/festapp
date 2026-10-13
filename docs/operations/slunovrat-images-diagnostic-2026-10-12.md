# Slunovrat event-description image failures - 2026-10-12

Reported surface: `https://slunovrat.festapp.net/2025we-copy-5e6268f4/admin/events/schedule`, event description editor, clipboard and image toolbar action.

## Verified production failures

- Public activation reports tenant `festivalslunovrat`, canonical backend, generation 1.
- `version.json` and `flutter_bootstrap.js` select `0.20.144+628`.
- An OPTIONS upload request with `Origin: https://slunovrat.festapp.net` returns HTTP 403, `ORIGIN_NOT_ALLOWED`. The checked-in Worker allowlist lacks this origin.
- An upload request with `projectId=slunovrat`, an empty diagnostic file and a deliberately invalid bearer token returns HTTP 400, `UNKNOWN_PROJECT`. Project resolution fails before token validation; no authenticated write occurred.
- The tenant branch's `automation/project.conf` and generated `lib/app_config.dart` declare `slunovrat`; the Worker registry supports `default`, `a`, `akhweb`.

## Prepared local change

Added the two established Slunovrat origins from `automation/cloudflare/festapp-public-cors.json` to the Worker allowlist. Added `tests/unit/slunovrat-cors.test.ts`, asserting upload preflight acceptance and rejection of an impersonating domain. Before the change, two acceptance assertions failed with HTTP 403; after the change, all 37 Worker unit tests and typecheck passed.

`fvm flutter test test/components/html/html_clipboard_test.dart --reporter compact` passed all three existing insertion/clipboard tests. This does not establish that the user's browser inserts images correctly. The event editor supplies the event's occasion ID to the media owner.

## Completed production repair

The user explicitly authorized repairing and deploying both failures, including direct backend access. The configured SSH alias's proxy script was missing locally. Its original scripts were recovered from the private `miakh/development-tools` branch `feat/festapp-backend-access-20261003` into `/tmp/festapp-slunovrat-access-20261012/`, without modifying SSH configuration or exporting credentials. Existing Keychain authentication and host-key verification were retained.

Read-only SQL verified the expected host, runtime database and `current_database()`, organization 19 (`Slunovrat`), occasion 1072594 and unit 999. Slunovrat has 224 image records, all referencing `api.festapp.net`, with no historical R2 mapping in those records.

The other existing Codex session for this same user request completed the registry/configuration repair and deployment during this investigation. The resulting `slunovrat` project has explicit canonical Auth configuration and uses the existing Festapp public bucket for new uploads. Private operations are disabled for this project. Existing Storage links remain valid. No Flutter application release was needed.

Independent verification observed active Worker version `cd2e8b98-aa8b-4e00-8ab1-65851ffc3a20`, deployed at 2026-10-12 16:14:30 UTC with 100% traffic. The Slunovrat upload preflight now returns HTTP 204 with its exact origin and Authorization/Content-Type headers. The deliberately invalid bearer-token upload now reaches authorization and returns HTTP 403 `FORBIDDEN`, instead of `UNKNOWN_PROJECT`. An impersonating domain still receives `ORIGIN_NOT_ALLOWED`. No authenticated diagnostic upload or customer-data write occurred in this session.

Final local verification passed typecheck and all 40 Worker unit tests. Full insertion and save through the user's authenticated event editor remains unverified and should be checked by the user. This session made no commits or pushes; unrelated dirty files were preserved.
