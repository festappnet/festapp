# Global MCP backend release procedure

This procedure is for the authorized global MCP rollout. It does not authorize
Wallet queue activation or other tenant releases.

The installed canonical production host retains the historical rehearsal name.
Protected target assertions, live activation, `FESTAPP_RUNTIME_DATABASE` and
`current_database()` must agree before any backend write.

## Selected source release

The current authoritative main contains Wallet queue consumers whose schema
cutover has not been authorized for production. A whole Functions bundle would
be incompatible with the installed Wallet schema. Preserve the installed
unrelated workers; do not install the Wallet migrations or scheduler.

Use the canonical builder's selected release mode for `mcp-session-exchange`.
The inspected import closure has one unselected local dependency,
`_shared/issueExistingUserSession.ts`, whose SHA-256 matches production. The
Deno lock also matches. Capture a fresh installed tree inventory with the
canonical `function-bundle-selection.py inventory` helper. The builder runs
only on clean synchronized authoritative main and records the exact source,
base tree and closure hashes. A changed base or shared dependency blocks
installation rather than falling back to an ad hoc copy.

After all exact-main GitHub release checks pass, stage the selected immutable
bundle with the same canonical installer and its matching helper. It preserves
the installed router, `_shared`, assets, lock and every other Function byte for
byte and retains the previous complete tree. Keep the result manifest and
archive digest in protected release evidence. No SQL migration is needed for
the OAuth context selection itself.

## Broker registry environment migration

The live `FESTAPP_MCP_TENANTS_JSON` is injected from the protected production
`.env` via the complete six-file Compose configuration. Editing that file or
restarting the existing container alone does not update its environment.

Preserve the existing regional entry and broker secret. Provision additional
entries only for verified, configured global contexts, with the independent
global broker secret. Resolve exact tenant IDs, first-party origins,
organization IDs, public backend profiles and activation hashes from the
approved live sources. Do not activate the global ticketing portal or any
unrelated tenant branch. The BISCUP consent route already supports the existing
broker response contract; its single global registry entry works with a
headerless client. The selected regional web release supplies the explicit
issuer selector for an origin with both services.

Write the proposed registry as a compact single-line value in a root-owned
mode-0600 file outside source control. Run the canonical
`update-production-function-environment.py --key FESTAPP_MCP_TENANTS_JSON
--value-file <protected-file>` preflight. It rejects baseline Compose drift or
any proposed model change beyond that exact Functions key. Do not print values.

Save the initial email pause state, pause and drain through the ordinary email
release boundary, then repeat with `--apply`. This deliberate configuration
migration recreates only Functions with every installed overlay, no dependency
services and no image pull. Ordinary code reloads continue to use
`restart-production-functions.py`; do not repurpose it to change environment.
Validate exact unchanged image/mounts/resources/other environment values,
authenticated MCP broker canaries, the email worker and delivery health. Resume
only the email state that this release paused, after probes succeed.

## Service cutover and rollback

Keep the global sidecar separate: native `linux/arm64` immutable image,
loopback 3400, independent state/config/keys, no regional data adoption. Verify
local image identity, notices, health, metadata, docs, legal pages and OAuth
before replacing only the retired global 410 proxy block. Regional 3399 and
its client policies remain intact. Verify public DNS/TLS and real authenticated
flows after cutover.

On failure leave email paused while recovering. Disable only the new global
route/service; restore the saved Functions tree/configuration through their
bounded canonical owners, preserving the original complete Compose inputs and
image. The environment tool automatically restores its original environment on
failed recreation, but does not claim to roll back a staged source bundle.
Keep protected backups and sanitized digests. Never restore unrelated business
data or import historical/global/regional credentials as new permissions.
