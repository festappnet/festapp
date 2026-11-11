# General MCP completion result

Implemented on `fix/mcp-completion-20261110` in the isolated
`/Users/miakh/source/festapp-mcp-completion` worktree. The original working tree
and its uncommitted changes were left untouched. No source push/publication or
production migration was performed.

## Changes

- One client policy now serves consent, token/refresh checks, invocation and
  account management. Trusted native client metadata uses the pinned OAuth
  provider, with explicit trust/profile and an optional integration-specific
  ceiling. General operator clients default to the complete catalog.
- Partial consent records declined scopes through the provider's Grant API;
  requesting creation but selecting only an existing event no longer loops.
  Standalone consent now displays translated functional choices and submits the
  choices actually approved. Safe OAuth errors distinguish client registration,
  metadata, callback and scope problems.
- The Inspector setup command emits both configurations without mutating files
  or authenticating. It derives scopes from the shared permission contract.
- The missing stock-assignment action adds three tools, taking the source catalog
  from 193 to 196. Its SQL facade calls the same UI assignment command and uses
  the original receipt. There is no second allocator, business-policy engine,
  service-role writer or mutation ledger. Reads are bounded and omit secrets.
- The existing administration inventory is covered by a CI contract. The two
  account-only connection/Google actions remain account UI. Future HTTP adapters
  are documented to reuse Operations and the canonical SQL owners.

## Verification

The canonical `mcp-auth-contract` step passed: 124 Node, 51 web and 15 Deno tests.
Four real PostgreSQL adapter tests and two SQL regression files passed. They
cover response-loss replay, the exact UI receipt, real concurrent UI/MCP same-command processing, stale input, whole-batch
rollback, replay after resource deletion, foreign scope and role revocation.
The generated MCP reference, forward migration and canonical source hashes agree.

Through the official Inspector UI in main Chrome/Panerelay, existing hidden
occasion 1072645 and closed form 625 passed an edit, identical replay, rejected
stale edit, independent inspection and actual admin reload. A separate read-only
grant exposed five tools, omitted writes and rejected another event. All Inspector test
grants and local OAuth copies were removed afterward.

## Live versus local

The live Inspector registration's artificial eight-scope ceiling was removed;
the same server image remains healthy and other clients/grants were preserved.
The new server code, metadata support and SQL migration are locally implemented
and verified, **not production-deployed**. Follow the plan's normal release order:
SQL migration, updated standalone image, then explicitly configured metadata
trust. The public ChatGPT plugin and its review were not changed.

[Authoritative plan](mcp-completion-plan-2026-11-10.md) ·
[Sanitized evidence and counts](../operations/mcp-completion-2026-11-10.json)


Before publication, an actual concurrent UI/MCP test reproduced a deadlock in
an early delegated-wrapper lock order. The wrapper now calls the canonical
receipt owner first, then locks/rechecks current stored bindings. Post-replay
binding locks do not impose a new printed-content mutation check. The same
controlled two-session test passes with one receipt and one applied assignment.
The user subsequently authorized deployment and a more sophisticated browser
scenario; its production result is recorded separately after the release gates.


The standalone form parser budget includes the existing resource/device budget
plus all functional scope choices. A real OAuth fixture with 100 maximum-range
occasion IDs and every functional permission previously returned HTTP 400 and
now completes a narrowed token without creation rights. This preserves the
supported resource limit rather than imposing an accidental function limit.
