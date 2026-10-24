# Landing footage - repeatable capture

Current language: Czech. Real application UI and synthetic local fixtures;
no translated overlays, fake application states or production writes.

Pending retake: [scenario revision 2026-10-23](scenario-revision-2026-10-23.md)
supersedes the empty hall opening and the short discontinuous form-builder cut.
Current delivered assets still use the earlier recordings until that retake.

| Chapter order | Clip | Recipe | Future source use |
|---|---|---|---|
| 1 | layout-build | [layout](layout/README.md) | Empty hall, native table drags, copies and automatic chairs |
| 2 | layout-style | [layout](layout/README.md) | Global style change, Galaxy cinema and theatre templates |
| 3 | form-build | [admin](admin/README.md) | Add text/select/checkbox, require an answer and save |
| 4 | form-style | [admin](admin/README.md) | Finished form (historical asset ID retained) |
| 5 | ticket-design | [admin](admin/README.md) | Native text and QR drag; resulting editor design |
| 6 | seat-select | [picker](picker/README.md) | Genuine Festapp public selection and next step |
| 7 | payment-qr | [picker](picker/README.md) | Actual unpaid local order and QR disclosure |
| 8 | check-in | [admin](admin/README.md) | Actual mobile scanner in a phone frame |
| 9 | orders-overview | [admin](admin/README.md) | Actual Czech revenue report, order filter and ticket export |

The canonical delivery manifest is `automation/release/organizers/clips.json`.
It records sources, posters, dimensions, durations and text. Capture recipes
record locale selection, initial data, real UI steps, cue timing, framing and
encoding settings. Set a new output directory for each locale and take; retain
clean source frames and epoch-timed cue manifests. English requires re-running
the actual application with its English locale and translated fixture content,
then inspecting the result. It is not an already validated English delivery.

For a later YouTube film, use the order above and the clean source masters;
keep gesture/result pairs at native speed and add transitions between chapters.
No long film is created by this task. Editor portrait clips are reframed desktop
captures; customer picker and scanner use actual narrow viewports.

Use only the disposable backend described by the local E2E skill. Credentials
belong in protected local files, not these recipes. Check the workstation's
single Flutter slot. Every browser command must specify the task-owned empty
config, headless mode and unique namespace/session. Verify ownership before CDP.
Close owned browsers, app servers and disposable backend after capture; review
pages work directly from `file://` and need no server.
