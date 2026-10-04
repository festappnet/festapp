# HTML replacement fixture gate

These are anonymous, deterministic acceptance inputs. `email_body.html` is an
authored representative reservation email body, including nested layout tables,
variables, styles, th/td, rowspan/colspan and a button link. It is not a production
template dump. `full_document.html` separately covers the document envelope and
safe stylesheet preservation; body and application email wrapper remain separate.

The DOM foundation is tested by `html_document_codec_test.dart`:

| Fixture | Verified at the DOM seam |
| --- | --- |
| app_content | Exact no-op; Czech/emoji/NBSP/entities; nested and Quill lists; alignment and span styles survive neighboring text edits |
| song_content | Exact no-op; pre whitespace survives neighboring edits |
| email_body | Actual variable replacement inside a nested table preserves layout, CSS, links, variables and cell roles |
| full_document | Exact no-op; editing does not add a second html/body envelope or remove safe stylesheet text |
| images | Source replacement retains alt/title/style/dimensions and the remaining images; missing/relative sources stay unresolved without an explicit base |
| unsafe_content | Executable elements, event attributes, unsafe URLs/template prefixes and indirect CSS are removed; sanitation is idempotent |

`HtmlDocumentDraft` assigns stable session-local IDs to DOM text and image slots.
Text assignment modifies a parsed node, never byte offsets in the original HTML.
No-op export returns the original safe input exactly. Structural export after a
change uses the DOM serializer. Sanitation uses a conservative allowlist: unknown
elements are unwrapped; ordinary safe email CSS survives, but escaped CSS,
comments and network/executable CSS functions are excluded.

The Super Editor seam is exercised by `html_editor_document_test.dart` and
`html_clipboard_test.dart`: actual nested email/cell edits, variable replacement,
pre whitespace, semantic formatting, lists, block movement/deletion, undo/redo,
complex HTML paste and a single clipboard import pipeline. Safe original HTML is
returned exactly when unchanged. Structural moves across distinct retained layout
containers fail explicitly; arbitrary HTML layout editing is not claimed.

`html_media_service_test.dart` and `image_control_client_test.dart` cover real
bitmap decode, original animated/transparent bytes, strict MIME, owner scope,
limits, deferred upload, single-flight, unknown outcome and retry. Lifecycle
widget tests cover parent Save/Cancel, draft retention on writer failure,
Android/iOS control layouts, themes and mocked IME connections. The Chrome run
uses the headless Flutter test runner. These are not real-device clipboard,
gallery, accessibility or HEIC/orientation acceptance evidence.

Endpoint tests use mocked RPC/network responses. They prove caller-JWT
forwarding, scope validation, fail-closed permission results and safe-fetch
behavior; deployed SQL role assignments/live authorization and deployment remain
separate gates. The implementation checkpoint and deletion ledger are recorded in
`docs/plans/html-editor-replacement-plan-2026-09-30.md`.
