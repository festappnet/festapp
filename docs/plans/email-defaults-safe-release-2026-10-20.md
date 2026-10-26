# Order email defaults and deferred blueprint rollout

The user authorized publishing the completed changes on 2026-10-20, explicitly
excluding blueprint V2. The fetched main `a94ec80f75e32cca06578ac986933a451a2ed124`
contains the pending native blueprint integration `08b924278`. This release
restores its executable source, dependencies and matching tests to
`e2a4649394ec490d9a0575ee584d263381486340`, the current festapptickets overlay's
recorded safe main. Existing V2 plans/evidence remain in the repository and the
implementation remains recoverable from the recorded main/integration commits.
A future V2 release must reapply the integration deliberately after this hold.

The release keeps the subsequent non-V2 changes: supported email-template editor
catalog, explicit email usage descriptions, one-line event creation helper and
blue compact organizer navigation. It adds the global order-default repair from
`20261020001500_restore_order_email_defaults.sql`. The live repair updates all
global copies of five order template codes, preserving IDs and scoped overrides.
There is no blueprint conversion, rollout activation, Image Worker deployment or
blueprint SQL migration in this release.

Validation before the rollout hold: isolated PostgreSQL repair/insertion,
resolver precedence, scoped-content preservation and idempotence passed; the
three canonical payment presentation/preview regressions passed. Executable
blueprint paths must match the recorded safe main before deployment. The local
Flutter/web build, main-owned tenant drift gate and coherent live-version probes
remain mandatory for the single authorized tenant `festapptickets`.
