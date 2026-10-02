# Festapp live HTML editor release - 2026-09-30

User authorized web deployment of the original Festapp tenant after the local
canonical cutover. Subsequent messages also authorized the backend change and
using the existing Chrome only through a new tab. No other tenant was in scope.

- Origin: https://live.festapp.net; Pages project: festapplive.
- Released version: 0.20.20+504 (previous live version 0.20.19+503).
- Main: abf36440f9d60b3b79b7fd2970382d0d9332f87c ->
  05fb3f23f3734fb1bc6e2a4a3a382623ace62fe1.
- prod/festapp: f8775e73e97298bafba086b71140b0e2b17326ec ->
  a646438d489770c17bf9d93421df1e8f880c506a.
- Exact upstream heads were fetched and compared immediately before publication.
  Both refs advanced atomically; other prod branches were not published/built.
- Deployment: https://github.com/festappnet/festapp/actions/runs/36761581812,
  conclusion success. Local direct build correctly stopped without the private
  FESTAPP_RELEASE_MANIFEST; the existing GitHub workflow supplied its approved
  Festapp-specific secret. No manifest or backend evidence was fabricated.
- Tenant drift and legal gates passed. The isolated tenant checkout passed 75
  targeted Flutter tests. CI compiled Flutter release web plus the public web
  client and verified the build/deployment through the repository workflow.
- Independent verify_web_deployment.mjs: ok, 3 consecutive probes for 0.20.20+504.
  Activation document: tenantId festapp, generation 1, backend canonical.
- Chrome preview: a new background tab (t21), version 0.20.20+504, inline news
  editor and zero iframe elements. No Save/publish/notification was invoked.
  The participant was released, leaving the user's preview tab open.
- Slunovrat remained 0.20.19+503 and is outside this release scope.

Publication incident: GitHub accepted the main push through the account's
administrative bypass despite its PR requirement. This rule should have been
checked before attempting direct publication. It was disclosed to the user;
future main publication must respect the required PR workflow.

Browser incident: the global agent-browser configuration selected Panerelay.
A named session alone did not isolate Chrome, and an initial open navigated an
existing user tab. This was disclosed and the participant closed. The user then
explicitly allowed their Chrome with new tabs; a new preview tab was created.
Pin the owned tab ID before every operation. For background/headless work use
an explicit separate config with no provider and verify the effective runtime
before navigation; global provider defaults must never be assumed isolated.

The shared fetch-http-data function is NOT deployed. Backend authorization is
approved, but no usable canonical self-hosted deployment access is available:
Hetzner CLI has no active context/token, and the available local Supabase token
belongs to the former cloud target. Do not deploy there. Remote/unit image
import may therefore retain old endpoint limitations until the canonical
function update is installed. No SQL migration, image worker update, or
production data write was performed for this release.

Concurrent blueprint changes, form prototype seams, wizard/prototype artifacts
and the unrelated SQL migration were excluded from the release. The local main
ref was subsequently aligned to the published shared commit with working files
preserved; hashes of concurrent blueprint/form/migration files were unchanged.
Real Android/iOS clipboard, gallery/HEIC/orientation and mobile accessibility
remain separate unverified gates, as documented in the implementation plan.

Local logs: /tmp/festapp-live-drift.log, /tmp/festapp-live-tests.log,
/tmp/festapp-live-verify.log. Browser evidence:
/tmp/festapp-html-live-new-editor.png. Local release checkouts:
/tmp/festapp-html-live-main and /tmp/festapp-html-live.

## Image preview/import hotfix - 0.20.21+505

A production PNG fetch returned HTTP 200 with valid 1024x1024 bytes, but the
Flutter web editor failed at `ImageDescriptor.width`. The same unsupported API
blocked bitmap import. The Chrome media suite reproduced this exact exception.
The fix reads supported image metadata on web before full decode; the native
ImageDescriptor path, 16 MP guard, authentic decode and raw image bytes remain.

Validation: 53 HTML tests passed in the native runner, 14 media tests passed in
headless Chrome (PNG/JPEG import, existing-image preview, animated/transparent
bytes, upload lifecycle, oversized metadata). Targeted analysis had no errors or
warnings; existing style info remained.

PR: https://github.com/festappnet/festapp/pull/166. The user explicitly approved
administrative merge and live-only deployment after being shown the protected
main review requirement. Main merge: 24f0663097594a5007d65a6a3c59b1809843ed7c.
Verified feature SHA: e79cd6dc94e3cd6d7fbaaf50b2bb25a4eccf1f77 (tree identical to
merged main). Festapp release SHA: 0601646527978317e298390b1c2d1d592cc08200.
Production overlay passed the main-owned drift gate; authoritative main and
prod/festapp heads were fetched/compared before publishing. No other prod ref
was updated. Release job: https://github.com/festappnet/festapp/actions/runs/36771465787.
Release job completed successfully, including Flutter release compilation, web
client build and coherent deployment checks. Independent verify_web_deployment:
ok, 0.20.21+505, three consecutive probes. Server manifest and a new user-browser
tab both reported 0.20.21+505. Local log: /tmp/festapp-images-live-verify.log.

The new background tab (t28) remained on the app bootstrap/loading screen during
visual inspection; no browser exception was captured, but image rendering on
live was not visually confirmed. This is not recorded as a visual acceptance
pass. The participant was released, leaving the new tab at /admin. No existing
user tab was navigated and no content was saved/uploaded/published during this
check. PNG/JPEG preview/import are proven by the 14 Chrome media tests, not by
this incomplete production visual check.


## News Save and existing-image cache correction - 0.20.22+506

- Reproduced in a newly created Chrome tab on `live.festapp.net/conference2024/news`: Save of news 73 returned HTTP 403 and `permission denied for table news` from the obsolete direct PATCH writer. The occasion is using the reader without aggregate versions; this does not authorize direct table mutations on the canonical backend.
- All inline news updates now invoke `save_news_client_sync_v1`. For a reader without aggregate versions, a conflict may bind the server version only when its HTML exactly matches the frozen edit-start snapshot. There is one additional attempt; changed server content and a second conflict remain conflicts. The existing versioned-client behavior remains strict.
- Existing editor image sources use the same CachedNetworkImage provider as HtmlView. Only newly imported sources require the authorized media fetch/validation path. Existing public previews reuse the decoded image cache; imports retain owner checks, pixel/byte limits and deferred upload.
- Save completion no longer invokes a disposed field's callback after a projection/page refresh.
- Production diagnosis did not change the article HTML: the canonical RPC returned HTTP 200 with conflict/version 54/same HTML, then HTTP 200 with unchanged/version 54/same HTML. Temporary private request captures were removed immediately and credentials are absent from repository artifacts.
- Validation: 55 native HTML tests, 5 command tests and 2 Chrome widget regressions pass; the final cache fixture separately passes natively. Targeted analysis has no errors or warnings, with existing informational lints. Tests cover cache reuse, field disposal, matching/stale snapshots and a second conflict.
- Reviewed artifact: https://github.com/festappnet/festapp/pull/167 . Admin merge continues the already approved live release operation in this session. Authoritative base before publication: `24f0663097594a5007d65a6a3c59b1809843ed7c`; fix head `862cda31c124090c7ba00e0d18d23fce90decab5`; main merge `ba9e97589e6fb122836c0b5820e1b49ad7aa167b`.
- Only `prod/festapp` was updated: `41f887a6f08d9b49902dcbb438d5a4472a2de0bd`. Tenant drift passed against the literal canonical main SHA. No other tenant builds or deployments were triggered. Local main was aligned while preserving all four pre-existing user-modified files byte-for-byte.
- Deployment: https://github.com/festappnet/festapp/actions/runs/36776325043 - success. Independent `verify_web_deployment.mjs` passed three consecutive probes for 0.20.22+506.
- Live UI verified in the new diagnostic Chrome tab: the normal PWA update banner initially retained 0.20.21+505; clicking `Načíst` loaded 0.20.22+506. Save of the unchanged news 73 produced canonical command conflict followed by unchanged/HTTP 200/version 54, closed the editor, and produced no new exception. The previously captured 403 remained only in historical console output. The article HTML was not changed.
- Opening the same image-bearing editor again generated zero additional media proxy or image requests, confirming cache reuse. The diagnostic editor was cancelled afterward. The exact browser participant was released while keeping the newly opened preview tab available.


## Full page expansion - 0.20.23+507

- The inline editor's expand action now opens a Material page on the root navigator. It covers the complete viewport and the underlying tab navigation, with no Dialog widget and no desktop 1000px content limit.
- One controller retains the draft throughout expansion and return. The page's overlay exit completion is awaited before the inline editor remounts, avoiding duplicate layout keys and IME clients during route transitions.
- All eight lifecycle widget tests pass, including root-page size 1200x800 from a nested navigator and edits retained after close/return.
- PR https://github.com/festappnet/festapp/pull/168 ; feature 6deb65e52e875d3e0db390756be8052d10f30871 ; main 2808a16f5bbdfd050da358fa343c305f1b202e05. Fresh main was fetched and compared immediately before publication. Admin merge continues the session's approved live release operation.
- Only prod/festapp was updated. Tenant drift passed against the recorded main SHA. Deployment https://github.com/festappnet/festapp/actions/runs/36778126943 - success. Independent production verification passed three consecutive probes for 0.20.23+507. New diagnostic Chrome tab loaded that version. Subsequent feedback requires instant transitions and a pinned toolbar; follow-up work is below.


## Instant fullscreen and fixed vertical left toolbar - 0.20.24+508

- User explicitly selected a vertical panel along the left edge. Fullscreen now uses a fixed 56px left rail and a separately scrolling document viewport. The toolbar has independent overflow scrolling for short windows. Inline editing retains horizontal tools.
- Expansion and return use a PageRouteBuilder with zero forward and reverse transition durations. The existing overlay-removal guard retains one layout key and IME client for the shared draft.
- Nine native lifecycle widget tests and two focused Chrome tests pass. Coverage asserts zero transition durations, full viewport, retained draft, vertical ordering of bold/italic tools, and unchanged toolbar position while the document moves 300px.
- Shared changes: PR https://github.com/festappnet/festapp/pull/169 followed by the confirmed orientation refinement in https://github.com/festappnet/festapp/pull/170 . Only their combined result was rolled into production version 508. The session's approved admin release authority was reused; fresh main was fetched and compared before both publications.
- Canonical main: 7a26a08560022fc2b5fb1ab3b2a8dce446669bea. Production head: 050e23531c460d0040156a5a5de144c948b3b834. Tenant drift passed against the literal canonical main SHA. Only prod/festapp was pushed/built/deployed; existing user-modified files remain byte-identical.
- Deployment https://github.com/festappnet/festapp/actions/runs/36779957565 succeeded; independent deployment verification passed three consecutive probes for 0.20.24+508. The previous diagnostic browser participant was released without cancelling the user's active drafts; a fresh tab was created for this release.

## Form loading and fullscreen control placement - 0.20.25+509

- Reproduced the user's blank Form tab at `/festapp2025/reservations` in a new Chrome tab running 508. Canonical activation is organization 1; app configuration selected occasion 59, form 22. `get_form_for_edit` returned HTTP/code 200 with `form.data = [null, {"phone_prefixes": null}]`; release rendering threw `NoSuchMethodError`.
- Minimal regression using this exact metadata failed before the change with a List-to-Map type error at `FormModel.fromJson`. The model now folds concatenated object entries in order, ignores null entries and preserves every setting; writes retain the existing object contract. Ordinary object and null metadata are unchanged. Non-object entries are rejected rather than silently discarding settings.
- The inline fullscreen button is now above the editor, aligned right. Zero-duration full-page expansion and the pinned vertical left toolbar remain covered by the lifecycle tests.
- Validation: 13 native targeted tests and 2 focused Chrome tests passed. Targeted analysis reported only the pre-existing brace-style info in `EditableHtmlField`. Main publication PR171, main `d57397156c621bfd086ed1c567b09525b77408fe`; tenant Festapp release `65047aa6932021eb687e756027ccf66c5de28f3c`. Fresh upstream and tenant drift gates passed.
- Deployment https://github.com/festappnet/festapp/actions/runs/36781364988 succeeded. Independent verification passed three consecutive probes for 0.20.25+509. A fresh Chrome tab confirmed runtime 509, canonical form 22/occasion 59, all seven fields in the successful response, and the rendered editor with its product, Add field and Save controls. Console errors were empty. No production form data was modified during diagnosis or validation. Four unrelated user source changes remain byte-identical and uncommitted.

## Fullscreen typing focus and static answer previews - 2026-10-01, 0.20.26+510

- Reproduced both issues with failing widget regressions: fullscreen mounted without focus; selected text fields exposed a second editable TextFormField for the sample answer.
- Fullscreen autofocus reattaches the shared focus node and retains the existing document selection. Returning inline also requests focus after remount. The regression positions the caret inside a paragraph, expands, checks focus/selection/IME registration and immediately types at that position without another click.
- The shared FormFieldsGenerator now renders generic answer previews as static InputDecorator/Text rather than text inputs. This covers text, email, name, surname, phone, city, address, nationality, birth year and note. Configuration title fields and specialized definition/default controls remain editable; public reservation forms remain interactive. Long type labels stay within the existing type control.
- Validation: 19 native targeted tests passed, 11 focused Chrome tests passed. Targeted analysis has only 25 pre-existing informational diagnostics, no errors or warnings. Browser test fixtures do not fetch translation assets. Two exploratory Chrome fixture runs were interrupted when asset loading stalled; the final self-contained fixture passed.
- Source PR172, main e20d4b1101751adbe5e4db9b9c16e32dae54fee9. Fresh upstream comparisons and Festapp tenant drift gate passed. Four unrelated user source files remain byte-identical and uncommitted.
- Deployment https://github.com/festappnet/festapp/actions/runs/36783374844 succeeded for tenant release e7a9d8b114c1a285067a68e046e1dc464ab07868. Independent live verification passed three consecutive probes for 0.20.26+510. A new diagnostic browser tab confirmed runtime 510 and no console errors, but its background Flutter first frame remained paused, so production UI interaction was not used as additional evidence. The 11 passing isolated Chrome widget tests cover the exact focus/typing and answer-preview behavior. The empty diagnostic tab was closed without touching existing user tabs. Only prod/festapp is in rollout scope.

## Datagrid modal fullscreen toggle - 2026-10-01, 0.20.27+511

- Add a fullscreen toggle to the upper-right app bar of the shared modal HTML editor, covering all datagrid callers. It switches the modal's single live editor between bounded dialog and whole-page scaffold, avoiding parallel editor instances and preserving the same controller and selection. Fullscreen retains the fixed vertical left toolbar and autofocus; toggling back requests focus after remount.
- Existing modal Save, cancellation/discard protection, title and media ownership remain on the original route. Save directly in fullscreen returns the draft through the original show result.
- Validation: all 10 native editor lifecycle tests passed; the updated modal regression passed natively and in Chrome after exercising expand, immediate typing with retained selection, return to dialog, re-expansion and fullscreen Save. Targeted analysis reports only three existing brace-style infos. Fresh upstream comparison and Festapp tenant drift passed. Four unrelated user source files remain byte-identical.
- Source PR173, main 4e992b450eff1d6ec429c0a5d19681f8451a5ad6. Deployment https://github.com/festappnet/festapp/actions/runs/36785678757 succeeded for release ca11d3dbc10a61eb2ba3eb2586f3e8ae013a09bf. Independent live verification passed three consecutive probes for 0.20.27+511. Modal interaction behavior was verified by native and isolated Chrome widget tests; no existing user Chrome tab was navigated or changed for this release. Only prod/festapp is in rollout scope.

## Fullscreen completion and explicit exit action - 2026-10-01, 0.20.28+512

- Fullscreen expansion now returns a typed Save/Cancel/Collapse outcome after the page completely unmounts. The original EditableHtmlField applies its existing scoped writer or cancels its session for Save/Cancel, so the original parent dialog remains open with the HTML in viewing mode. Collapse retains the editing session, draft and focus. System back remains a collapse action.
- Both fullscreen variants have a visible upper-right button combining the shrink icon and localized exit-fullscreen text (Czech: Zmenšit editor). Labels are present in all six catalogs, and text/icon foreground inherits the app bar action theme for contrast. The datagrid modal retains its existing Save/cancel/discard behavior and original return contract.
- Regression tests first reproduced Save/Cancel leaving the original inline editor active. Final tests use an actual parent DialogRoute and verify the parent stays open, editing ends, Save calls the writer once with changed HTML, and Cancel makes no write and restores the original HTML. Collapse retains cursor and supports immediate typing; modal fullscreen Save remains covered.
- Validation: all 12 native lifecycle tests and four focused Chrome tests passed. Targeted analysis reports two existing brace-style infos, no warnings or errors. Six translation catalogs parse successfully. Fresh main publication and Festapp tenant drift gates passed. Source PR174, main 56522640ae8a897e01690e5a3c601199003dd1fe. Four unrelated user source changes remain byte-identical.
- Deployment https://github.com/festappnet/festapp/actions/runs/36787332596 succeeded for release 076b0c8e03ce73f2a3518aa99e4ee8e50fd48f5e. Independent live verification passed three consecutive probes for 0.20.28+512. Action semantics and the retained parent modal were verified with native and isolated Chrome widget tests; no production content was modified and no user browser tab was navigated. Only prod/festapp is in rollout scope.

## Pending selection toolbar and conference event save - 2026-10-01

- Implemented a desktop/web selection formatting popover using SuperEditor's selection layer links and focus-preserving popover. Actions: bold, italic, underline, strike and link. Existing pinned toolbar remains available.
- Event editor reads now obtain the canonical aggregate version independently of the occasion's reader mode. Event saves and their parent/role relations use `save_event_client_sync_v1`; attached speakers use the versioned speaker command. Removed the direct event/table-relation writes from these save paths. This addresses a code-level legacy-reader write-path mismatch; the event 3 production error was not directly captured in this turn.
- Added regressions for selection formatting/focus/lifetime and for `DbEvents.updateEvent` using canonical HTTP RPC with legacy readers, preserving optimistic version and relations.
- Targeted Dart analysis reported no errors or warnings (existing style notices remain). Flutter test execution is blocked by sandbox denial of its localhost server socket. Tool configuration and cached SDK/native assets were placed in permitted temporary directories without altering global installations.
- NOT PUBLISHED OR DEPLOYED: the current environment makes repository `.git` read-only, restricts network access and rejects browser-tool approval requests under approval policy `never`. Production remains the previously verified 0.20.28+512. No live event data was changed. Changes remain in the workspace for validation and the established prod/festapp rollout in an environment with the required access.

## Selection toolbar and canonical conference event Save - 2026-10-01, 0.20.29+513

- Completed the pending release above. Existing-event reads now load the canonical aggregate version for admin/editor users independently of the occasion reader mode. Event Save, parent/role relations and attached-speaker updates use the existing versioned commands; obsolete direct event mutation paths were removed. No SQL or backend deployment was needed.
- Desktop/web selected text exposes bold, italic, underline, strike and link actions in a focus-preserving popover. Existing fullscreen and inline toolbars remain available.
- Fixed the previously unexecuted test fixtures: explicit desktop target (reset before widget test invariant checks), HTTP response request metadata and initialized timezone. All 756 native Flutter tests, 193 web tests (9 skipped) and 138 Edge Function tests pass. Selection formatting/selection retention/focus/toolbar dismissal also pass in isolated headless Chrome; the 14 targeted native tests pass with the Festapp tenant configuration. Targeted analysis has no warnings or errors, only informational lints.
- Full automation runner reaches a pre-existing failing rehearsal-schema assertion requiring FESTAPP_SUPABASE_ADMIN_SITE in Caddyfile, while canonical main uses FESTAPP_SUPABASE_ADMIN_HOSTNAME on the loopback admin listener. Both files are unchanged from the fetched baseline. DB and live integration tests skipped without a disposable database target. This unrelated full-suite failure was disclosed; no infrastructure behavior was modified.
- PR https://github.com/festappnet/festapp/pull/175; feature 37d33b3c1; main a70196c008e5f79f5f4a60526b62dd65c3454716. The established admin-merge authority for the ongoing live release was reused. Fresh publication base was 56522640ae8a897e01690e5a3c601199003dd1fe.
- Only prod/festapp was pushed and explicitly dispatched: 076b0c8e03ce73f2a3518aa99e4ee8e50fd48f5e -> 380db4a6865fbd894081b1e975f67aee8df09c75. Fresh authoritative main/tenant heads matched immediately before publication. Main-owned tenant drift and legal checks passed.
- Deployment https://github.com/festappnet/festapp/actions/runs/36835726402 completed successfully, including release compilation and coherent production checks. Independent verify_web_deployment passed 3 consecutive probes for 0.20.29+513. Live activation matches tenant festapp, canonical generation 1.
- No production event data was changed and event 3 Save was not exercised in an authenticated production browser. HTTP regression tests prove the canonical Save route with legacy readers; production probes prove the release is served, not authenticated editor acceptance. No user browser tab was touched.
- Local main aligned to the published main with all four unrelated blueprint/form source changes verified byte-identical. Existing prototype/planning/migration artifacts were preserved. Logs: /tmp/festapp-event-tests.log, /tmp/festapp-event-chrome.log, /tmp/festapp-event-all-tests.log, /tmp/festapp-event-tenant-tests.log, /tmp/festapp-event-analyze-final.log, /tmp/festapp-event-drift.log, /tmp/festapp-event-live-verify.log.

## Inline actions, Save availability and safe Escape - 2026-10-01, 0.20.30+514

- Moved inline Save and Cancel above the document alongside expansion. Save stays visible but is disabled until actual document changes exist, including after Undo returns to the baseline. Dialog/fullscreen Save uses the same rule. The controller distinguishes user changes from its existing sanitization dirty-state contract.
- Inline Cancel and Escape now confirm before discarding user changes; an unchanged edit exits immediately. Dismissing the prompt keeps the draft and restores focus. Repeated cancellation requests cannot stack prompts. Fullscreen Cancel/Escape confirms before returning the original field to viewing; collapse keeps its existing draft semantics.
- The session-owned cancellation callback is handled ahead of SuperEditor's selection keyboard actions, fixing Escape after Undo or with a selection. Standalone editor callers without the callback retain their original keyboard handling. Focused shortcut bindings cover action-button focus as well.
- Validation: 64 native HTML tests, three focused isolated Chrome tests, 16 tenant-configured lifecycle tests passed. Tests cover top action placement, initial disabled Save, enabling on edits, disabling after Undo, clean Escape, dirty confirmation, prompt dismissal retaining draft/focus, and fullscreen cancellation back to the original view. Targeted analysis has no errors/warnings; canonical formatter check reported zero changes. The unrelated full-run infrastructure failure recorded under version 513 remains unchanged and was not rerun.
- PR https://github.com/festappnet/festapp/pull/176; feature c88bd5262; canonical main f428b276a0f0db9d3d2682db896b3de08a42e7b9. Fresh publication base a70196c008e5f79f5f4a60526b62dd65c3454716. Reused the established administrative merge authority for the ongoing live release.
- Only prod/festapp was released: 380db4a6865fbd894081b1e975f67aee8df09c75 -> 437ab7eb0fd22033331fdb042bbe48fe28b6af41. Fresh authoritative refs matched before publication. Main-owned tenant drift and legal gates passed. Deployment https://github.com/festappnet/festapp/actions/runs/36848359576 succeeded; independent production verification passed three consecutive probes for 0.20.30+514.
- No production content was changed and no user browser tab was touched. UI acceptance evidence is the isolated Chrome regressions; public live probes verify the deployed assets. Local main aligned to published main; all four unrelated blueprint/form source changes remained byte-identical and other existing artifacts remained untouched.
- Logs: /tmp/festapp-inline-tests.log, /tmp/festapp-inline-chrome.log, /tmp/festapp-inline-analyze.log, /tmp/festapp-inline-format-check.log, /tmp/festapp-inline-tenant-tests.log, /tmp/festapp-inline-drift.log, /tmp/festapp-inline-live-verify.log.

## Information Save with legacy readers - 2026-10-01, 0.20.31+515

- Reproduced the information writer's obsolete direct-DML path with a deterministic HTTP fixture that rejects information mutations with 403 / 42501 / permission denied for table information. The same actual DbInformation save regression passed after removing occasion reader-mode selection from command writes. No shared HTML serialization failure was observed.
- Occasion information saves now always invoke save_information_client_sync_v1. Editor grid reads always obtain get_information_editor_bundle_v1. Public information loading for inline editor users replaces regular information rows with complete canonical content/version snapshots, retaining other public types and excluding hidden rows. Ordinary public readers do not invoke the editor RPC. Conflicts remain strict and do not overwrite a newer version. Shared information writes cover inline information, occasion information grids and typed information editors; the separate unit-owned boundary is unchanged.
- Audited all RichHtmlEditor/EditableHtmlField/dialog call sites and followed their persistence boundaries: event, news, map, form, occasion, activities, inventory, email templates and speaker editors use their domain command/RPC. Did not conflate legacy RPC facades with denied direct table mutations or change unrelated workflow/data boundaries.
- Validation: 96 targeted native tests spanning information, HTML and related command domains; five Chrome HTTP/widget regressions; nine tenant-configured information tests passed. The Chrome regression loads canonical content/version, edits actual inline HTML, executes the real information writer, verifies the RPC HTML/version and observes editing finish. Coverage also protects public read separation, other public content types and conflict rejection. Targeted analysis has no errors/warnings; formatter and diff checks passed.
- PR https://github.com/festappnet/festapp/pull/177; feature c2704b9b3; main b85a37d791fb530ceb03123dd8ae210797f37d7e. Fresh publication base f428b276a0f0db9d3d2682db896b3de08a42e7b9. Continued the established approved admin-merge/live-release workflow.
- Only prod/festapp released: 437ab7eb0fd22033331fdb042bbe48fe28b6af41 -> 4ea6eda4e7916f56ab208f56f5da4ca6f352789b. Fresh main/production heads matched before push; tenant drift and legal checks passed. Deployment https://github.com/festappnet/festapp/actions/runs/36850586545 succeeded. Independent production verification passed three consecutive probes for 0.20.31+515. No SQL/backend deployment was needed.
- Authenticated production Save was not exercised. The cached named-user Cloudflare Access session for SQL diagnosis was unavailable; no login, credential workaround, production content mutation or user browser interaction was performed. The failure reproduction and editor acceptance evidence are HTTP/native/isolated Chrome fixtures. The unrelated full-suite infrastructure failure recorded under 513 is unchanged and was not rerun.
- Local main aligned to the published main while verifying all four unrelated blueprint/form modifications byte-identical; existing untracked work remains. Logs: /tmp/festapp-info-red.log, /tmp/festapp-info-tests.log, /tmp/festapp-info-chrome.log, /tmp/festapp-info-analyze.log, /tmp/festapp-info-format-check.log, /tmp/festapp-info-tenant-tests.log, /tmp/festapp-info-drift.log, /tmp/festapp-info-live-verify.log.

## Information cache version fix and combined inline toolbar - 2026-10-01, 0.20.32+516

- The remaining production failure was the offline cache roundtrip: InformationModel.toJson omitted aggregate_version. InfoPage reloads cached models after canonical reads, so version 54 became 0 and Save conflicted. The previous 515 widget regression skipped this cache seam. Information JSON now preserves the aggregate version. No shared HTML serialization change or database migration is needed.
- Extended the inline Save regression to serialize/reload cached models before editing and saving. It fails before the fix with expected version 7, actual 0. Chrome uses the actual OfflineDataService and IndexedDB store. Existing public reads, typed content preservation and strict concurrent-conflict behavior remain covered.
- Inline Storno, Save and fullscreen share the formatting toolbar at widths of at least 800 logical pixels; narrower layouts keep actions above the tools. Save stays disabled until changed. Layout regressions cover desktop alignment and compact display without overflow; existing cancellation/fullscreen behavior passes.
- Validation: 73 targeted native information/HTML tests, five Chrome tests using the real web cache, and five tenant-configured Save tests pass. Targeted analysis has no errors or warnings (22 existing style infos). Tenant drift and legal checks pass. Existing unrelated full-suite infrastructure failure recorded under 513 remains unchanged and was not rerun.
- PR https://github.com/festappnet/festapp/pull/178; feature 2cfa301a1; main 8eba7a5f1cf9b3f7898f0e4c4bd7e3be04b2406c. Fresh authoritative publication base b85a37d791fb530ceb03123dd8ae210797f37d7e. Used the established authorized admin-merge/live-release workflow. Only prod/festapp released: 4ea6eda4e7916f56ab208f56f5da4ca6f352789b -> d10acfa961b0ea0a9efdae0b8fd3c770ee32b3ef.
- Deployment https://github.com/festappnet/festapp/actions/runs/36853001003 succeeded. Independent deployed asset verification passed three consecutive probes for 0.20.32+516.
- Authenticated live evidence used the previously authorized new background Chrome tab t34 through the Panerelay browser skill, leaving the user's existing tab t30 and drafts untouched. Before release, the actual information cache lacked aggregate_version while the canonical Accommodation record id 2 was version 54. Identical-content RPC probes returned 200/unchanged at 54 and 409/conflict at 0. After release, only the owned test tab was reloaded; its actual refreshed IndexedDB record preserved version 54 and matched canonical content. Saving that unchanged cached snapshot returned HTTP 200, code 200, status unchanged, version 54. No production HTML changed. The owned tab and browser participant were closed. Changed-content acceptance is covered by the native and real-cache Chrome widget regression, rather than a production content mutation.
- Local main aligned to published main while all four unrelated blueprint/form source changes remained byte-identical; existing untracked work was preserved. Logs: /tmp/festapp-info-cache-red.log, /tmp/festapp-info-cache-final-tests.log, /tmp/festapp-info-cache-chrome-final.log, /tmp/festapp-info-cache-analyze.log, /tmp/festapp-info-cache-tenant-tests.log, /tmp/festapp-info-cache-drift.log, /tmp/festapp-info-cache-deploy.log, /tmp/festapp-info-cache-live-verify.log.

## Contact autolinks in displayed and saved HTML - 2026-10-01, 0.20.33+517

- Historical inspection confirmed that the old HtmlHelper.detectAndReplaceLinks used custom regular expressions, not a standard linkifier library. Its phone expression explicitly required separators between digit groups. The replacement app-content profile kept this limitation and only ran during saving, so an existing plain 731140198 remained unlinked. The contiguous-number behavior was already absent in the old editor.
- Share one DOM-text contact linker between HtmlView rendering and the app-content save profile. Recognize contiguous or grouped nine-digit local numbers, international +/00 prefixes and separators including nonbreaking spaces. Normalize only the tel target and preserve the displayed number. Existing text gains contact links without a database update. URL and email alternatives classify links correctly, including email-like URL query strings and case-insensitive WWW prefixes.
- Existing anchors and their descendants, HTML attributes, styling, code/preformatted text and template placeholders are untouched. Song and email save profiles retain their prior behavior. Unmatched HTML is returned exactly as supplied; the view transformation does not alter stored content.
- Validation: 77 native HTML tests, 13 targeted Chrome contact/view tests and 16 tenant-configured contact/view tests pass. Targeted analysis has no errors/warnings and two existing infos. A broader Chrome HtmlView run hit a pending 10-second external-image timer in its existing image fixture and cascaded into its next offline-video test; all contact regressions passed. The focused browser batch excludes those unchanged network/media fixtures. Native image and video regressions passed. Tenant drift and legal checks pass.
- PR https://github.com/festappnet/festapp/pull/179; feature 1c0e41c67; main b70ba2da7025c6a656f71b0a6f6f680e532caaa4. Fresh publication base 8eba7a5f1cf9b3f7898f0e4c4bd7e3be04b2406c. Continued established authorized admin merge and live release. Only prod/festapp released: d10acfa961b0ea0a9efdae0b8fd3c770ee32b3ef -> 6f0b6952f2f6132cb7388c9a197559466720ec2a.
- Deployment https://github.com/festappnet/festapp/actions/runs/36854770253 succeeded. Independent asset verification passed three consecutive probes for 0.20.33+517. No production content was changed and no user browser was operated for this release. Clickable-view acceptance is the isolated Chrome regression, not an actual production dial/email action.
- Local main aligned to published main; all four unrelated blueprint/form modifications remain byte-identical. Existing untracked work remains untouched. Logs: /tmp/festapp-autolinks-tests.log, /tmp/festapp-autolinks-chrome.log, /tmp/festapp-autolinks-chrome-targeted.log, /tmp/festapp-autolinks-analyze.log, /tmp/festapp-autolinks-tenant-tests.log, /tmp/festapp-autolinks-drift.log, /tmp/festapp-autolinks-deploy.log, /tmp/festapp-autolinks-live-verify.log.

## Inline toolbar in narrower desktop cards - 2026-10-01, 0.20.34+518

- The previous 800-logical-pixel breakpoint stacked inline Save/Cancel/fullscreen above tools inside narrower desktop cards. Reduce the breakpoint to 400 and keep actions beside the existing horizontally scrollable formatting strip, reserving at least 48 pixels for tools. Constrain the actions to the available width and use Wrap so long labels or very narrow screens do not overflow. Below 400 pixels, actions remain above the tools.
- The layout regression now verifies one row at 800 and 600 pixels, no overflow at 450, and the stacked fallback at 320. The added 320 case first exposed the prior fixed action Row overflowing by 150 pixels with untranslated test labels; the constrained Wrap fixes this too. All 16 native lifecycle tests and the focused isolated Chrome layout test pass, including Save state, undo, Escape, fullscreen and save retry. The same layout test passes with tenant configuration. Formatter/diff checks, tenant drift and legal checks pass.
- PR https://github.com/festappnet/festapp/pull/180; feature b8bd2eaef; main 0525e3440662d48620c71df02ae860826fc4d1bb. Fresh publication base b70ba2da7025c6a656f71b0a6f6f680e532caaa4. Continued the established authorized admin merge/release workflow. Only prod/festapp released: 6f0b6952f2f6132cb7388c9a197559466720ec2a -> cfa87d73c5a9857f978c5c803106db2ff97ccab5.
- Deployment https://github.com/festappnet/festapp/actions/runs/36857459525 succeeded. Independent asset verification passed three consecutive probes for 0.20.34+518. Visual alignment acceptance uses native and isolated Chrome widget geometry, without navigating the user's browser or mutating production content.
- Local main fast-forwarded to published main; four unrelated blueprint/form modifications remained byte-identical and other untracked work was preserved. Logs: /tmp/festapp-toolbar-tests.log (initial narrow-layout failure), /tmp/festapp-toolbar-tests-final.log, /tmp/festapp-toolbar-chrome-final.log, /tmp/festapp-toolbar-tenant-tests.log, /tmp/festapp-toolbar-drift.log, /tmp/festapp-toolbar-deploy.log, /tmp/festapp-toolbar-live-verify.log.

## Restore event-detail saved-program feedback - 2026-10-01, 0.20.35+519

- The shared saved-program writer already has localized added/removed success toasts, gated by an applied result and mounted context. EventPage explicitly passed showSuccessToast:false for both its floating and collapsed controls, suppressing those confirmations. Historical blame points to 72c5102414 (shared offline/admin/release platform promotion), predating the recent HTML editor replacement. Remove that opt-out and reuse the existing success path, translations and error handling.
- Validation: eight existing saved-program coordinator/UI tests pass. No new test mirrors the one-line default restoration. Targeted EventPage analysis reports no errors, two existing warnings (mutable EventPage.id and unnecessary set literal) and four infos; those areas are unchanged. Diff checks, tenant drift and legal checks pass. No production user schedule was mutated and the toast was not exercised through a logged-in production browser.
- PR https://github.com/festappnet/festapp/pull/181; feature efd2ce7e7; main 691ddcb6e0f3e9ce836a81b5d9bc2afde6173279. Fresh publication base 0525e3440662d48620c71df02ae860826fc4d1bb. Continued established authorized admin merge and release. Only prod/festapp released: cfa87d73c5a9857f978c5c803106db2ff97ccab5 -> f4e8e3118c9fd8c670d55ce01c1394b670da21c9.
- Deployment https://github.com/festappnet/festapp/actions/runs/36860687668 succeeded. Independent deployed asset verification passed three consecutive probes for 0.20.35+519. Local main fast-forwarded to published main, preserving four unrelated blueprint/form modifications byte-for-byte and other untracked work.
- Logs: /tmp/festapp-feedback-tests.log, /tmp/festapp-feedback-analyze.log, /tmp/festapp-feedback-drift.log, /tmp/festapp-feedback-deploy.log, /tmp/festapp-feedback-live-verify.log.

## Accepted HTML editor cutover on main and vstupenky.online - 2026-10-01, 0.20.38+522

- User accepted the new editor and explicitly authorized publication to main plus vstupenky.online. The deployment branch for that domain is prod/festapptickets, not the obsolete prod/ticketonline branch. Only main and prod/festapptickets were written for this rollout; other tenant branches were not deployed.
- Cutover owner is the canonical RichHtmlEditor, EditableHtmlField and dialog path, with HTML document codec, media ownership and scoped persistence. Runtime audit finds no old HtmlEditorPage/HtmlEditorWidget/NativeHtmlEditorWidget classes, their routes/generated registrations, or quill_html_editor/html_editor_enhanced editor packages. Editing entry points across 19 component files reach the new path. Quill list/style classes and the Super Editor transitive delta dependency remain intentional support for stored content, not an alternate editor implementation. No database/content migration is required.
- Removed the last obsolete Android WebView dependency override justified by the deleted Quill fork. All resolved package versions remain identical; WebView stays a normal transitive dependency for the existing YouTube player. Cleanup PR https://github.com/festappnet/festapp/pull/182; feature c7411704d; final main e7d798cdca92f391d1ef4df6fa3e45445c2a2aa7, based on fresh 691ddcb6e0f3e9ce836a81b5d9bc2afde6173279. Existing editor fixes were already on main. Continued established authorized admin-merge workflow.
- Validation: 88 targeted main tests spanning HTML, forms, news and information; five Chrome tests including the actual information IndexedDB cache/save seam; 78 tenant-configured HTML/form tests all pass. Tenant drift and legal checks pass. No full-suite rerun or unrelated infrastructure change was performed.
- Merged the verified canonical main forward into prod/festapptickets while preserving its tenant configuration/branding and prior mobile homepage startup recovery. Updated version and overlay release metadata consistently to 0.20.38+522. Fresh authoritative main and tenant heads matched before push. Tenant release 01614de6b -> 732a6e607922b679131436033eb9ae36be03fcba.
- Deployment https://github.com/festappnet/festapp/actions/runs/36886678143 succeeded. Independent https://vstupenky.online deployment verification passed three consecutive probes for 0.20.38+522, covering canonical admin bundle/manifest/service worker and public legal pages. Actual authenticated ticket-tenant editing was not exercised in production; behavior acceptance is the targeted native/Chrome fixtures plus the tenant build/deployment gates. No production content or user schedule was mutated.
- Local main aligned to the authoritative head and the four unrelated blueprint/form source changes remained preserved. User's later audio-indicator comment was explicitly withdrawn as belonging to another session; no audio UI changes were made. The requested main/vstupenky.online cutover is complete.
- Logs: /tmp/festapp-cutover-pubget.log, /tmp/festapp-cutover-tests.log, /tmp/festapp-cutover-chrome.log, /tmp/festapp-cutover-tickets-tests.log, /tmp/festapp-cutover-drift.log, /tmp/festapp-cutover-deploy.log, /tmp/festapp-cutover-live-verify.log.

## Blueprint centering after zoom-to-fit - 2026-10-01, 0.20.39+523

- Reproduced the blueprint displacement in the shared venue_seat_picker component with a rendered 40-column/72-row scene inside the editor-style column. Before the fix its horizontal center was 138.89 instead of 350, a 211.11-pixel leftward displacement. The initial fit matrix scaled X/Y below 1 but left Z at 1; viewport bounds and InteractiveViewer use getMaxScaleOnAxis, which consequently reported 1 and clamped the correct centering translation to zero.
- Fix the controller fit matrix to scale all axes uniformly. No seat coordinates, backdrop, selection, stored configuration or persistence behavior changes. A regression checks the actual rendered scene center in both axes. The earlier hypothetical viewport-sizing workaround was not retained.
- Validation: all 24 package tests passed, and all five Chrome viewport tests passed, including the rendered-center regression, bounded panning and small-plan zoom/resize behavior. Targeted package-controller analysis reports no issues. Both Festapp blueprint-seat adapter tests pass. Tenant drift and legal checks pass. Actual production blueprint editing was not exercised; physical alignment acceptance is the isolated Chrome regression and deployment verification checks the live assets.
- Shared package main was unprotected and updated directly after fresh upstream comparison, following user-owned repository publication rules: venue_seat_picker c829a33d07de9a8fa376b407658875d22abd246e. Existing package release metadata is 0.1.2; no pub.dev publication was performed. Its local main was fast-forwarded.
- Festapp pins the verified package commit in pubspec/lock. PR https://github.com/festappnet/festapp/pull/183; feature 46a79a08f; main 93c88fb0c93c6d3bcdc506b60820cf8709aca223. Fresh publication base e7d798cdca92f391d1ef4df6fa3e45445c2a2aa7. Continued established authorized admin merge/live-release workflow. Selected production scope remains prod/festapptickets only; other tenant branches were not deployed.
- Tenant release 732a6e607922b679131436033eb9ae36be03fcba -> 8f2f33d5ead09a72ffb2c9368fde058afba1a4a0, version 0.20.39+523. Fresh canonical and tenant heads matched before push. Deployment https://github.com/festappnet/festapp/actions/runs/36890685807 succeeded. Independent https://vstupenky.online verification passed three consecutive probes for 523.
- Local Festapp main aligned and dependencies refreshed. All four existing blueprint-prototype/form edits remained byte-identical; unrelated untracked work was preserved. No production data or user browser was changed.
- Logs: /tmp/venue-centering-red.log, /tmp/venue-centering-tests-final.log, /tmp/venue-centering-chrome-final.log, /tmp/venue-centering-analyze.log, /tmp/festapp-centering-tests.log, /tmp/festapp-centering-drift.log, /tmp/festapp-centering-deploy.log, /tmp/festapp-centering-live-verify.log.

## Dark-mode HTML editor caret - 2026-10-01, 0.20.40+524

- The desktop caret inherited Super Editor's fixed black default, independent of the app theme. Replace only the default desktop caret overlay with theme-aware color (white in dark mode, black in light); retain mobile controls/overlays. Covers shared inline and fullscreen editor callers.
- Regression exercises the rendered CaretDocumentOverlay for both layouts, light/dark themes and live theme switching. Original test failed with black instead of white; the theme transition is allowed to settle before checking. All 17 native lifecycle tests and the isolated Chrome regression pass. Targeted analysis has no errors or warnings (21 existing style infos). Tenant drift and legal checks pass.
- Feature 89eafdd81, PR184, canonical main c8dd906b3766bcd9f6226ee1c385bfaa030832ad. Immediately fetched main before publication and verified unchanged base 93c88fb0c. Root main fast-forwarded while all unrelated tracked modifications were hash-verified unchanged.
- Selected tenant only: prod/festapptickets 8f2f33d5ead09a72ffb2c9368fde058afba1a4a0 -> 238e828f51f862e273ad0fe3c3367a7273ef7dc2, version 0.20.40+524. Exact authoritative main and tenant heads verified before push. Deployment https://github.com/festappnet/festapp/actions/runs/36898485707 succeeded; independent https://vstupenky.online deployment verification passed three consecutive probes. No production content/data edited.
- Logs: /tmp/festapp-caret-red.log, /tmp/festapp-caret-tests.log, /tmp/festapp-caret-chrome.log, /tmp/festapp-caret-analyze.log, /tmp/festapp-caret-drift.log, /tmp/festapp-caret-deploy.log, /tmp/festapp-caret-live-verify.log.


## HTML display/editor typography parity - 2026-10-02, 0.20.49+533

- Displayed HTML and editing share one base typography resolver. Inline editing retains the field font size and fullscreen expansion carries its resolved style. Editor text no longer falls back from 18px to bodyLarge/16px, adds theme letter spacing or forces a 1.4 line height. Heading sizes scale with the base size; existing explicit HTML formatting remains supported.
- Exact typography regression failed before the fix (expected 18, actual 16), then passed natively and in isolated headless Chrome. All 79 HTML tests pass in the selected tenant; all 819 native Flutter tests pass (one skip). Web tests: 204 pass, zero fail. Targeted analysis has informational lints only. Full local suite has eight unrelated database failures; three Deno modules cannot initialize without SUPABASE_URL and remote integration is skipped without credentials. These residual local gates were disclosed before the user explicitly approved administrative merge and deployment. Tenant drift and required legal pages pass.
- User explicitly selected only live.festapp.net/prod/festapp and approved administrative merge of PR https://github.com/festappnet/festapp/pull/207 despite its required review. Publication base 422afe74568fe2e3598cfeadad721c39e4a5e39d; verified feature 4b0ae43e7dfc464dd2a370fb11d3fe961579e46f; canonical merge f6eedc4408320cc97001906bad84e589cad0071f (tree identical to tested feature). Shared/tenant heads were freshly fetched and compared before publication.
- Tenant release 9e2f5f66e53ec83f64c5402157017bec80c592ef -> e1d106f6fb99edea98818741e11dec42f69fc5ee, recorded canonical main f6eedc4408320cc97001906bad84e589cad0071f. Only prod/festapp was pushed/built/deployed. Isolated worktrees excluded concurrent workspace changes; original working files and local main were preserved.
- Deployment https://github.com/festappnet/festapp/actions/runs/36991167838 succeeded. Independent verify_web_deployment passed three consecutive production probes for 0.20.49+533; public version.json confirms 533. No live content/data or user browser was modified. Live typography was not visually inspected; acceptance is the Chrome rendering regression plus verified deployed artifact.
- Logs: /tmp/festapp-html-typography-release-tests.log, /tmp/festapp-html-typography-chrome.log, /tmp/festapp-html-typography-analyze.log, /tmp/festapp-html-typography-all-tests.log, /tmp/festapp-html-typography-remaining-tests.log, /tmp/festapp-html-typography-drift.log, /tmp/festapp-html-typography-tenant-tests.log, /tmp/festapp-html-typography-deploy.log, /tmp/festapp-html-typography-live-verify.log.
