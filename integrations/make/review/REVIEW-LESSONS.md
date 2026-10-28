# Make connector knowledge: review and runtime

Recorded 2026-10-28 from actual EU1 runs and Make AppBot feedback, case `2351677:2082001`, message `1a18239723a8b8c6`. AppBot explicitly labels this as AI-generated and potentially mistaken. Treat findings as hypotheses, verify official documentation and runtime evidence, then correct or explain them in the existing review. Do not create another app/review.

## Before first submission

- Keep Make module labels, descriptions and groups in presentation metadata. A canonical MCP tool description may address an agent; do not copy that instruction into the Make UI. Use sentence case, uppercase ID, and third-person descriptions. Distinguish backend page size from the total list limit.
- Handle JSON Schema nullable `type: ["string", "null"]` as well as `anyOf`. Otherwise nullable money and symbol fields incorrectly become Make `any`. Preserve decimal text and currencies; never convert money to a floating number for presentation.
- Add `mode: edit` to RPC-backed fields of Get modules, remove numeric validation from select fields, set CRUD Read metadata, set an explicit RPC response limit, and include search module samples. Groups are helpful even though the published naming guidance only mandates grouping above ten modules.
- Universal modules need the standard label/description, relative URL input, method, headers, query string and body, and output body/headers/statusCode. That interface does not authorize additional endpoints. Explain a deliberately small API, preserve its server allowlist, fixed origin and scope checks, and never forward caller-supplied authentication, Host or control headers unchecked.
- Put the public OAuth client ID in connection common data. Never make arbitrary extra scopes, client secrets or other clients' credentials available merely to satisfy a template example.
- Provide a human-readable public API document as well as OpenAPI. Make's automatic reviewer could not retrieve the live OpenAPI URL even though authenticated calls and the public health/OpenAPI probes succeeded. An inaccessible review scraper does not prove the API is broken.

## Verified exceptions: do not apply these AI suggestions blindly

**Pagination body is replaced, not merged.** The official pagination page says that the body overrides the original body regardless of `mergeWithParent`. Retain event ID, page size and filters in the pagination body, then add the cursor. Without them the next request would lack required input fields. Headers and query parameters have separate merging rules.

Source: https://developers.make.com/custom-apps-documentation/component-blocks/api/pagination#body

**The total-limit fallback is intentional.** A schema/UI default does not populate a missing mapper key in API-created blueprints. In live Make, omitted limit initially returned all 52 rows. The final expression distinguishes an absent key (10) from an explicitly empty field (all within technical bounds). Replacing it with only `parameters.limit` loses that contract. The technical cap must fail explicitly when continuation remains.

Evidence: `../evidence/guardrails-20261028.json` and `live-qualification-20261028.json`.

**Seven-day consent is a server policy.** Both refresh and each read check the immutable server delegation. Two real concurrent scenarios refreshed successfully without extending `Delegation.expiresAt`. Make's displayed connection expiry can roll despite explicit response expiry; it is not the authorization authority. Do not extend server grants to satisfy an AI guess about scheduled scenarios. Document reauthorization honestly.

Evidence: `../evidence/refresh-20261028.json`, `revocation-20261028.json`.

**An empty order detail is not successful.** Before returning the Make envelope, the adapter requires exactly one row with the requested event/order IDs. Empty details, foreign events and malformed upstream detail responses fail explicitly. `first(body.data.orders)` only runs on a validated successful envelope.

Evidence: `tools/festapp/test/make-transport.test.mjs`, `../evidence/guardrails-20261028.json`.

**Access inspection does not paginate.** It returns the complete consent-filtered list and has no cursor. Apply a total module/RPC output limit, not invented pagination parameters. The RPC is a bounded option sample, not an export.

**Summary context does not identify an account.** It deliberately omits account IDs and contacts. Use an optional user-defined connection label rather than expanding the canonical privacy projection just to provide metadata.

**Some canonical values intentionally differ in representation.** Report event IDs are text, public order/event IDs and operation inputs are numeric safe integers, and report money can retain existing numeric or decimal-text values. Document these distinctions rather than silently changing the shared report contract. The `state` input is a free stored-state string; there is no fixed enum in its canonical schema.

**Special keys require escaping in Make IML.** Literal dots and other special characters can be accessed with backticks, e.g. ``{{item.capabilities.`ticket_layouts.read`}}``. A real downstream module consumed this value successfully in `../evidence/review-qualification-20261028.json`; an undefined value would have selected invalid event ID 0. Verify mapping through such a consumer, not only an accessibility snapshot or bundle count.

Source: https://developers.make.com/custom-apps-documentation/block-elements/iml

## Publication and communication

A published custom app is installable by invitation; it is not yet a verified catalogue release. One Review request creates a confirmation email and a mandatory vendor follow-up form. Finish that form, preserve its accepted receipt, and reply to the existing case for feedback. The automatic report can arrive with subject `Re: [#2351677]` in a separate Gmail thread, so search by case number as well as the original app-review subject. Never infer that no feedback exists from the original thread alone.

Retain frozen source digests and synthetic module logs. After changes, rerun the affected modules and review scenarios once on final definitions; keep valid backend tests when the backend is unchanged. Leave qualification scenarios inactive/on-demand. Expected negative runs can send error emails: the dedicated developer organization's scenario-error notifications were disabled at the owner's request; security and credit notifications remain enabled.

Publisher fees and customer credits are different. Record the provenance and limits of public cost evidence; a secondary public directory is not a written Make guarantee. Do not accept a paid order, promotional subscription or fixed fee. Do not send a support cost question after the owner declined it.
