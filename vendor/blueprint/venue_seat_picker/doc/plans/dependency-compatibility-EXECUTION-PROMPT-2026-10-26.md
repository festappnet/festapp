# Execute Venue Layout dependency compatibility work

Work in the canonical `festappnet/venue_seat_picker` repository checkout.
Read applicable repository instructions and the complete authoritative plan:
`doc/plans/dependency-compatibility-plan-2026-10-26.md`.

Implement its waves in order using standard verification. Remove only redundant
direct declarations, relax only tested dependency/SDK bounds, preserve all public
widgets, backdrops, color/localization behavior and the single shared core.
Prove the minimum actual SDK and low/high resolution graphs; add enduring CI
coverage and update the plan's execution record. Keep one Flutter task active
at a time, tests `--concurrency=1`, and use FVM/pnpm 11.24.0 as documented.

If evidence contradicts the planned SDK floor or dependency compatibility,
update the authoritative plan and use the narrowest proven contract. Do not add
forks, shims, speculative SDK branches or shipped dependency overrides. Preserve
all unrelated working changes. Do not overwrite published versions or deploy
Festapp; registry publication and production rollout are separate actions.
