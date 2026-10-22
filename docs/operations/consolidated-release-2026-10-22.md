# Consolidated vstupenky.online release - 2026-10-22

## Selected source and tenant

Shared source before this readiness PR: `418ff8b6587570d9f7471d69f8d0974992cbd663`.
Production target: `prod/festapptickets`, `vstupenky.online`, Cloudflare Pages
`vstupenkyonline`, canonical backend organization 3, activation generation 1.
Previous production tip: `722522d48f68282d2fbc776b3df18ef3bac784b2`, version
`0.20.319+812`. No other tenant is included.

## Integration inventory

No open pull requests remained at inspection. Finished work already on main:

- Occasion configuration copying, source access checks, form-link editing,
  independent form/layout selection, undo and confirmed editor return.
- Compact payment/communication settings, scheduled-sale initialization and
  a draft/revision-scoped confirmation-email preview.
- Standing-admission catalog metadata repair (`01bcb67e0`).
- Twelve ticket designs and coordinated QR palettes (PR #555).
- Earlier repository artifact cleanup, client-test consolidation, Blueprint
  fixes and occasion-card changes (including PRs #546-554).

Remaining references were checked against current content, not just ancestry:

- `fix/email-substitution-autolinks-20261019` is superseded by
  `e7200e59b` (supported plain-value styling); do not restore pointer-events CSS.
- `fix/ticket-editor-ui-20261003` is superseded by subsequent editor work.
- Local font fixture and authorized draft ticket-preview changes already match
  main. The alternate `send-custom-email/setupPreview` is replaced by the
  dedicated revision-scoped preview endpoint.
- `feat/agent-access-20261003` contains a blocked diagnostics-broker prototype;
  use the existing protected backend-access channel instead.
- `feat/plesuj-public-guide` is explicitly a WIP pilot and is excluded.
- Remaining local historical SQL cleanup has not been qualified against the
  current migration baseline and is excluded. Original worktrees are preserved.

The new endpoint brought the production Function inventory to 36. This PR
updates the coverage-contract assertion from 35; coverage completeness, unknown
Function detection, and executable smoke/behavior checks remain required.

## Validation and release order

The occasion UX implementation passed its targeted Flutter, Deno and rollback
SQL checks before main publication. This readiness check also runs the canonical
source-contract generator and the production Function coverage contract.

The verified live backend ledger currently ends at `20261022000000`.
Release `20261022013000_occasion_setup_ux.sql` from merged main, with exact SQL
digest, protected rollback evidence and an atomic ledger record. Deploy the
canonical reviewed Function bundle, preserving the host router and credential
boundaries, then verify unauthenticated requests cannot access the new preview.
The UI requires both backend changes before publication.

Prepare a fresh main-based tenant overlay retaining the previous production tip
as an ancestor, increment the selected tenant version, run apply_config and the
main-owned drift check. Build locally and deploy using `automation/deploy_direct.sh`;
its build/startup/legal/image and coherent live-version gates remain mandatory.
This document records prepared scope, not a receipt of deployment success.
