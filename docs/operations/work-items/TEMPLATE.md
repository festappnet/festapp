# Work item: <outcome>

Opened: YYYY-MM-DD
Updated: YYYY-MM-DD
Status: ready | in-progress | blocked | verification
Verification: low-risk | standard | release

## Authoritative sources

- Plan, issue or runbook: `<relative link>`
- Execution prompt, when applicable: `<relative link>`
- Evidence or receipt: `<relative link>`

## Outcome

State the externally observable end state. Do not restate the full design.

## Fixed point

- Repository branch/SHA or deployed version:
- Relevant external resource/version IDs:
- Last verified production state:

## Completed actions

- Record only actions that have a receipt or direct verification.

## Next action

Name exactly one bounded action, its target, expected result and validation.

## Remaining order

1. List later actions in dependency order.

## Current blocker

State the unavailable external condition or `None`.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| `<production mutation>` | `<exact confirmation>` | pending |

## Rollback and recovery

- Record the pre-state and exact rollback identifier for the next mutation.
- State what cannot be rolled back and how it is superseded safely.

## Definition of complete

- [ ] Every client, data and runtime boundary uses the canonical contract.
- [ ] Required production state and adoption are verified.
- [ ] Temporary compatibility and legacy artifacts are removed.
- [ ] Observation and cost/health evidence is recorded.
- [ ] The item is moved to `completed/` and the open index is updated.

## Operational log

| Date/time | Action | Receipt/evidence | Result |
|---|---|---|---|
| YYYY-MM-DD | `<action>` | `<non-secret ID/hash/link>` | `<result>` |
