# Confirmed MCP writes with unreadable results

Verification tier is standard. The implementation starts from PR #984 at
`adb7d55` against main `956a71ea` and addresses the reviewed portions of
issue #959. PR #986 is reviewed separately because locale negotiation is
independent of MCP command recovery.

## Outcome and ownership

A client can distinguish a write confirmed by SQL from a write whose outcome
is uncertain. It can recover using the original command and payload. SQL and
`client_mutation_receipts` remain the authority for authorization, deduplication,
conflicts and expiry. The command boundary observes matching receipts and
reports failures in result preparation. The hosted delegation owner retains
session revocation. Ticket layout saves retain pending and resume.

The published v1 HTTP problem body has a closed outcome enum and forbids extra
fields. Keep the body compatible. Use a stable problem title, and publish
confirmed outcomes and receipt metadata as documented HTTP response headers.
A known commit uses the existing error code, with the committed header providing
the added outcome signal for v1. Preserve the existing MCP error envelope and
include verified recovery information in its message.

## Implementation

1. **Preserve authorization and recognize equivalent UUIDs.** Normalize a valid
   command UUID before dispatch in `Operations.invoke`. The same canonical UUID
   must reach adapter validation and receipt matching. Preserve the original
   exception on a committed-readback error and let `DelegatedOwner.authorized`
   run its existing auth and MFA revocation handling. If the grant is already
   inactive, return the existing authentication error without result metadata.
   Prove mixed-case forms.create and identical replay, then cover a hosted
   post-commit authentication failure with a simulated upstream response.
2. **Describe recovery consistently.** Expose only the attested UUIDs and,
   for form operations, an identity checked against the selected occasion and
   any supplied form ID. Give creates and duplicates an inspect or list path,
   deletes a list path, and mention the authorized same-command replay when the
   result is still unavailable. Keep the recovery message and HTTP headers
   derived from the same validated receipt. Test the real HTTP route and check
   the generated API reference and released baseline. The compatibility check
   freezes the formal response header map, so document the added receipt
   headers in the published API guide while keeping the OpenAPI projection intact.
3. **Pinpoint output failures without recording payloads.** Known schema
   paths may name known form fields. Replace dynamic keys and array indices,
   and keep unrecognized field names and values out of the log. Record identity
   checks explicitly. Prove invalid known fields and malformed identities are
   distinguishable and that diagnostics never replace the original failure.
4. **Wire and verify CI.** Add `operations.test.mjs` to `mcp-auth-contract`.
   Regenerate the MCP reference, prepare API artifacts, and run the canonical MCP
   auth and API contract steps and CI inventory. Check the diff and current PR
   head/base before publication. Keep API compatibility archives immutable.

## Completion and rollout

Completion is a verified PR update with the covered commit, conflict, expiry,
auth, HTTP and diagnostic paths. The code introduces no new data migration or
recovery storage. Production deployment and the root cause of the live
`forms.inspect` failure remain separate from implementing this PR. During an
authorized rollout, compare the packaged and live `/healthz` source commit and
exercise form inspection with an authorized account.
