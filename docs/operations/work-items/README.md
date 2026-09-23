# Operational work items

This directory is the canonical cross-session registry for work that is approved
or already started but is not operationally complete.

Use it for releases, production migrations, infrastructure cutovers, external
account actions, observation windows and cleanup that must survive a handoff.
Ordinary implementation ideas and unapproved backlog belong in the issue
tracker; architectural and implementation design belongs in `docs/plans`.

## Structure

- `open/` — active, blocked, in-progress or verification-stage work.
- `completed/` — closed operational receipts retained for audit/history.
- [`TEMPLATE.md`](TEMPLATE.md) — required structure for a new work item.

Each work item links to its authoritative plan and evidence instead of copying
their architecture. It owns only live state: fixed point, completed mutations,
next action, blockers, authority gates, rollback identifiers and closure proof.

## Status model

- `ready` — the next bounded action can run immediately.
- `in-progress` — an identified command or rollout is currently running.
- `blocked` — external state or separate authority is required.
- `verification` — implementation is live and only an observation gate remains.
- `completed` — every closure condition is proven; move the file to
  `completed/` and update this index in the same commit.
- `closed by user decision` — the user withdraws the remaining work; move the
  record to `completed/` while preserving unverified facts and retained resources.

Do not mark an item complete because code was merged. Production state,
installed-client adoption, legacy contraction and required observation must be
proven when they are part of the outcome.

## Open items

| Work item | Status | Fixed point | Next action |
|---|---|---|---|
| [Image delivery cost cutover](open/image-delivery-cost-cutover-2026-08-24.md) | blocked | Public image hosts still on Worker; R2 domains absent; recent rejected `/private/` traffic | Resolve installed-client adoption and legacy traffic before P3/P4; no mobile publication now. |
| [EUR payment reference rollout](open/eur-payment-reference-rollout-2026-08-24.md) | blocked | Both migrations live; three EUR accounts lack verified payee names; no recent EUR orders or open forms | Decide whether EUR ordering is needed, then obtain legal payee names before a pilot. |
| [Exposed runtime credential rotation](open/runtime-credential-rotation-2026-08-24.md) | blocked | No former env files in `main` or 11 active tenant branches; revocations unverified | Inventory provider credentials and record non-secret rotation/revocation receipts. |

## Maintenance rules

1. Create an item as soon as approved work gains an external action, production
   mutation, separate authority gate or cross-session blocker.
2. Update the item immediately after every material state change; record IDs and
   hashes, never secrets.
3. Keep exactly one next action. Later steps remain ordered but are not presented
   as concurrently executable.
4. Never use a work item to authorize its own production mutation. Record the
   required authority and the receipt after it is granted and executed.
5. On closure, update authoritative evidence, move the item to `completed/`, and
   remove its row from the open table in one commit. A withdrawn task must say
   which cleanup remains undone; closure is not evidence of decommissioning.
