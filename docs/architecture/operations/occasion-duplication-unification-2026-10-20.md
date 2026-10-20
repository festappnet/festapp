# One occasion duplication workflow

Regular and demo duplication previously maintained separate orchestration. The demo path directly invoked the SQL RPC and read `data.occasionId` without validating the canonical receipt. Both paths then fetched the copy, copied media and saved the entire occasion unconditionally. Even an occasion without media therefore caused a second SQL mutation and aggregate version advance. A single source URL used as both event image and ticket background also caused two identical Worker copy requests.

`OccasionDuplicator` now owns this flow for both entrypoints. Both invoke the existing typed occasion command, with optional caller-supplied command identity for demo replay. The existing public UI methods retain their result shapes. The command validates the receipt before the workflow can perform any media work.

The media copier reports whether any URL changed. No follow-up save is sent when there are no images or all returned URLs remain unchanged. Within one duplication attempt it copies each distinct source once to the same destination occasion; all references are saved together using the loaded aggregate version. This reduces duplicate requests without changing server permissions, SQL business rules, Worker ownership or the image authority.

PostgreSQL creation and external Worker copies cannot share a database transaction. They remain an explicit sequence: creation failure propagates; after confirmed creation, load/copy/save failure returns the existing occasion ID and an incomplete media result. The sequence does not replay creation in response to a media failure. Worker orphans on later failure remain an existing limitation; this change does not claim distributed atomicity or introduce destructive compensations.

Verification: 16 targeted Flutter cases passed with concurrency 1 (`/tmp/festapp-duplication-architecture-test.log`), including the existing occasion commands, owner/layout preservation, no-media and unchanged-media behavior, shared-source deduplication, supplied identity/locale/tenant parameters, failures at load/copy/save, and unconfirmed creation. Existing command mocks were repaired to include the mandatory receipt via the shared fixture. New cases remain in the existing occasion media suite; no new engine/root is registered. HTTP/provider/production execution is outside this local verification. MCP remains deferred and Blueprint V2 is excluded.

Targeted analysis of `db_occasions.dart` passed (`/tmp/festapp-duplication-analyze.log`), as did the repository architecture guard (`/tmp/festapp-duplication-architecture-guard.log`) and `git diff --check`.

Subsequent authorization and implementation: [local MCP E0](mcp-e0-local-execution-2026-10-20.md). Statements above about deferred MCP describe this earlier cleanup checkpoint.
