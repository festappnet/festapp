# Slunovrat image upload recovery - 2026-10-12

Scope: Slunovrat image uploads in the existing shared image Worker. No Flutter
tenant builds, app branch rollout, database changes or object migrations.

## Reproduction and authority

The live Slunovrat activation document identified `festivalslunovrat`, canonical
backend, generation 1. Protected SSH verified the expected server and database;
a read-only transaction verified organization 19, title Slunovrat, and unit 999.
All 224 existing image records for that organization used `api.festapp.net`,
not either existing public R2 hostname. No historical R2 project alias was inferred.

Before the fix, an OPTIONS upload request from `https://slunovrat.festapp.net`
returned 403 without `Access-Control-Allow-Origin`. A multipart upload selecting
`projectId=slunovrat` with an intentionally invalid diagnostic token returned
400 `UNKNOWN_PROJECT`, before authorization. Neither probe wrote an object.

## Change and deployment

Registered `slunovrat` with explicit canonical backend/anon-key configuration,
the existing `festapp-images` public bucket and `img.festapp.net` public host.
New owner paths use canonical IDs. Existing Storage images remain unchanged.
The public upload and record persistence RPCs continue to authorize the owner
using the caller's JWT. Private operations are disabled for this new entry.
Allowed origins include the two exact Slunovrat addresses, without a wildcard.

Prestate Worker version: `684241fa-7bfb-433d-aa9b-ccb0d42821c6`.
Deployed version: `cd2e8b98-aa8b-4e00-8ab1-65851ffc3a20`.
The baseline bundle matched the downloaded live script byte for byte. The new
bundle diff contained only the added Slunovrat registry entry; configuration
added the canonical public settings and Slunovrat origins. Other bindings,
project entries and public routes were preserved. Rollback script/settings and
deployment logs are local under `.git/operator-evidence/slunovrat-images-20261012`.
Deployment used the guarded `deploy.sh --deploy-control` workflow. Its remote
integration fixture suite was skipped with an explicit localhost database URL.

## Verification and limits

- Typecheck and all 40 unit tests passed. The new upload regression cases failed
  with `UNKNOWN_PROJECT` before the fix and passed afterward, covering both
  authorized storage/record writes and rejection before storage.
- Live upload preflights from both Slunovrat origins now return 204 and the
  exact matching `Access-Control-Allow-Origin`.
- Live multipart requests now recognize the project and reject the deliberately
  invalid JWT with 403 `FORBIDDEN`, including the correct CORS response header.
- An impersonating foreign origin still returns 403.

An authenticated editor upload and the complete editor UI were not exercised
on production. No test user or diagnostic image was created there. Positive
upload verification uses the actual Worker handler with mocked authorization,
record RPC and R2 boundaries, rather than an editor's live session.

## Follow-up: editor import still reported failing

The user subsequently reported the generic import/clipboard failure toast while
selecting a file from Downloads in the event-description editor at
`/2025we-copy-5e6268f4/admin/events/schedule`. Live Slunovrat remained version
`0.20.144+628`; its compiled bundle contains the existing web dimension fix.

`fvm flutter test --platform chrome test/components/html/html_media_service_test.dart
--reporter compact` passed all 14 media tests. A temporary web widget harness
opened `RichHtmlEditorDialog` under `HtmlEditingScope`, used the image toolbar
and the actual registered `FilePickerWeb`, replaced only the native chooser click
with a selected PNG, and asserted an image node and pending draft URL. This passed
with proper pumping of browser callbacks. Initial harness failures were missing
plugin setup, querying an input already detached by FilePicker, and unpumped
callbacks; they are not evidence of an application defect. Final log:
`/tmp/festapp-file-picker-web-20261012-final.log`. Harness saved outside the repo at
`/tmp/festapp-html-file-picker-web-harness-20261012.dart`.

Temporary editor logging was removed. No additional application change or release
was made. The user's exact failing file/session is still needed to reproduce the
reported failure; successful fixture insertion is not proof of recovery for it.

## Consolidated all-client repair and authenticated editor verification

The duplicate diagnostic session transferred sole ownership back to this session.
Its handoff is `/tmp/festapp-images-handoff-2026-10-12.md`. It had subsequently
repaired missing exact origins across all 11 active clients, pinned project A's
server configuration to canonical Auth, and added a registry guard against former
Festapp backend origins. Its last deployed Worker was
`c1ed2c8a-049f-489f-b4d8-16e02860e767`. Prestate, deployment and 76 passing unit-test
evidence are under `/tmp/festapp-all-images-production-20261012/`; regression
workflow/build/deploy gates remain uncommitted local changes. All 11 clients
passed its signed-in upload/GET/delete matrix. Those first matrix fixtures had
invalid PNG IDAT CRCs, so that evidence establishes transport/persistence only.
The later editor fixture is a valid deterministic PNG.

The receiving session reused the existing isolated headless browser and the
already authorized disposable production event. It captured the real web file
picker input by replacing only its native chooser click, then selected the valid
fixture through `agent-browser upload`. FilePicker's immediate input removal had
prevented the previous CSS-only automation; this is an automation limitation,
not the reported application failure. The actual editor/media/codec code was
not replaced or mocked.

The image appeared in the editor. Inline apply plus parent Save produced one
permanent image URL in the test event's stored description, no pending draft
URL, and public GET 200. Reopening the event editor displayed the persisted
image. Screenshots: `/tmp/festapp-image-smoke-20261012/after-real-import.png` and
`reloaded-saved-image.png`; stored URL evidence: `ui-saved-images.json` there.
No import error was reproduced with this valid PNG. This does not establish
that the user's particular Downloads file or clipboard path works.

Cleanup was completed by the receiving session: Worker deletion removed the
UI image and its database record, and public GET returned 404. One guarded
transaction removed the marker-verified hidden event, every smoke identity
membership, profile, auth identity, refresh tokens and sessions; post-delete
assertions passed. The isolated browser was closed and credentials/session files
were deleted. Cleanup log: `/tmp/festapp-image-smoke-20261012/cleanup.log`.
A final `node automation/verify_image_service.mjs --all-tenants` passed all 11
current client configurations. No further frontend/Worker deployment, commit
or push occurred during takeover. The exact user file is still required for
reproducing the remaining reported import failure.

## Reported JPEG and prepared client compression

The user supplied the actual Downloads JPEG: 6,830,898 bytes, 4662x3108 pixels,
14.49 MP. A Chrome test exercised that original file through the description
modal's image toolbar and the registered web FilePicker. The existing client
successfully inserted it in the clean fixture, so the original toast is still
not reproduced. The existing code preserved the full 6.8 MB JPEG without
resizing. The user explicitly requested large-file resizing and clarified that
no frontend update had been deployed.

Prepared a focused shared-client change in `html_media_service.dart`: JPEGs
above 2048 px or 800 KiB are decoded at bounded dimensions and re-encoded to
at most 800 KiB, reducing resolution/quality further when needed. The existing 10 MiB
input limit, 16 MP cap, serial decode and pending budget remain. Other formats
retain animated GIF/WebP/PNG preservation.
The upload boundary remains parent save, with the same permission checks.

The generated large-JPEG regression failed before the change (3000 px retained)
and passes afterward. All 15 native media tests and all 16 Chrome cases passed,
including the user's exact photo through the dialog/toolbar and assertions on
its compressed draft bytes/dimensions. Analysis reported only existing style
infos, no errors/warnings. Logs: `/tmp/festapp-jpeg-resize-red.log`,
`/tmp/festapp-jpeg-native-final.log`, `/tmp/festapp-jpeg-web-compression-green2.log`
and `/tmp/festapp-jpeg-analyze.log`. The user's photo is not a repository fixture;
its temporary Chrome harness was moved to
`/tmp/festapp-reported-photo-picker-web-harness-20261012.dart`.

A clean review worktree at `/tmp/festapp-jpeg-resize-20261012` starts from fetched
main `2272a7b81b1ce9cc4dcae879dbca83b84c1d6928` and contains only the media change
and generated regression. Main requires one PR approval. The handoff additionally
records the user's no-commit-before-browser-confirmation instruction. An explicit
publication question is pending for commit/PR/admin merge and Slunovrat-only web
release. No commit, push or frontend deployment has occurred for compression.
Current fetched Slunovrat source is `51141b4dd8c815416523d8a2919ce86e349b34f5`,
configured `0.20.146+630`; live frontend previously verified `0.20.144+628`.
Do not describe the prepared compression as a shipped fix for the original toast.
