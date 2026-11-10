# CI input reuse

All eight canonical check names remain required on the exact release main SHA.
A green job means either the full lane executed, or its selector verified a
previous successful execution covering identical inputs. This changes test
execution, not release admission, build provenance or live deployment checks.

## Pull requests and releases

- Draft PRs skip the expensive regression jobs. GitHub does not allow merging a
  draft. Marking Ready for review triggers all lanes on the current merge ref.
- A newer PR update cancels obsolete runs of the same workflow and PR. Converting
  back to draft also cancels them. Main and deployment runs are not cancelled.
- Later ready-PR updates and main pushes run changed lanes; unchanged lanes can
  reuse executed main evidence. PR evidence is never promoted into main evidence.
  A lane changed anywhere in the PR may therefore run again on subsequent updates.
- Manual workflow dispatch and `merge_group` always execute the full lanes.
  Merge queue support does not enable a queue or change repository protection.
- The first run after introducing/changing this policy executes all lanes.
  There is no compatible old execution marker from which to inherit evidence.
- The local mirror continues to run the explicitly selected affected lanes.

## Conservative dependency boundary

`automation/ci/inputs.json` classifies independent components. Every path outside
those explicit components is shared by every lane. New packages and unknown
paths therefore invalidate every lane. Shared contracts, automation, workflow
files, root dependency locks, SDK configuration and assets remain shared inputs.
Known Flutter packages include their package-local manifests and locks.
Repository documentation under `docs/` has no runtime lane consumers; its edits
alone do not invalidate a test result. Generated public help under `automation/`
is still a shared input, and package-local README contracts retain their owners.

Within each component, the policy lists all consuming lanes. The current map is
intentionally broad: all Flutter source changes also invalidate seat checkout;
all SQL/Edge changes invalidate ticket and image contracts. Narrowing a component
requires checking cross-component file reads and adding invalidation coverage.

The selector hashes Git tree records (path, mode and object ID) for every lane
input. Content edits, renames, executable modes, additions, deletions and submodule
pins count. It compares the actual checkout tree, including the PR merge result,
against ancestors on the first-parent main side. It does not use file modification
times, changed-file counts or a previous local development receipt.

## Evidence and failure behavior

Only successful push/manual workflow executions on main, from this workflow and
within seven days, qualify. The latest check attempt must pass and belong to that
run. The job API must also report the final `All lane tests executed` step as
successful. A job which only reused evidence cannot become an execution baseline
or renew its age. A newer failed or pending matching run/check prevents falling
back to an older success. A shallow/missing history, unavailable API, absent
permissions, expired evidence or malformed response runs tests instead.

All dependency/SDK installation and test steps share the selector's condition.
Checkout and selection still run for unchanged lanes. The summary links the
actual executed check and records its source SHA and input SHA-256. Existing
release admission still rejects missing, skipped, pending or failed current jobs,
including extra failed checks; there is no deploy bypass. The tenant cannot edit
the selector, its dependency map, the job contract or the release gate relative
to its canonical main source.

This is conservative selection, not a claim that external dependencies never
change: locked tool versions are inputs, reuse is bounded to seven days, and a
manual workflow dispatch forces fresh verification. Runtime savings depend on
which components changed and have not yet been measured on GitHub.
