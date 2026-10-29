# Wix BI verification - independent audit, 2026-10-29

The independent critic approves publication of the dormant preparation. No
P0-P2 issue was found in the actions taken or in the completed sender. This is
not approval to send an unaccepted synthetic event or activate normal billing.

## Verified actions

The critic independently read Erel's BI request (`1a186cc331d539c7`) and the sent
clarification (`1a186f14ad37be72`) in thread `1a18198a75444077`. The clarification
truthfully proposes zero-only qualification and does not claim delivery. No newer
Wix reply was found at audit time. Sanitized saved OAuth evidence supports token
and token-info HTTP200 with active APP and the correct app/installation; it does
not prove billing permission or BI ingestion. No secrets or repeated live OAuth
requests were needed for this review.

## Finding fixed

WIX-BI-C01 (P3): the preparation receipt originally marked timestamp assignment
and persistence as completed, although only a candidate existed. The field was
removed and replaced with explicit future send requirements. A dormant sender
now actually assigns and persists the event before provider I/O.

## Completed preparation

`integrations/wix/billing/qualification.mjs` reuses the existing strict dispatcher
and provider for one fixed owned QA installation and zero-only CHARGE. It has no
SQL, activation or financial-source write path. An exclusive mode600 journal and
file/parent-directory sync precede OAuth. Every existing attempt blocks replay,
including rejected authorization, process death, uncertain response and corrupt
state. Worktrees share the repository git common directory fence; independent
clones do not share it and must never be used as a retry workaround.

The CLI requires an operator-reviewed approval receipt identifying Wix's actual
acceptance of the exact zero-only protocol. This receipt is an operator assertion,
not automated vendor-consent verification. No such receipt currently exists.
The pending preparation receipt fails this gate.

The critic independently reran qualification and reporting tests: 20/20 passed,
no skips. Tests use actual filesystem journals, the production executor and fake
provider responses, including concurrent callers, child-process death, restart,
wrong-instance/nonzero response, explicit rejection and lost response. Read-only
CLI inspection of the real shared attempt location reports `not-attempted`.

## Remaining boundary

Wix's documented API reports charges/refunds and does not establish a synthetic
zero-event test mode. Waiting for its confirmation is the review's judgment about
truthful reporting, not a quoted Wix rule requiring another approval. Once Wix
confirms the procedure, retain its actual reference, perform one documented
attempt and notify Erel of the result. His BI-ingestion confirmation and actual
Partner Billed activation remain separate steps. Normal billing stays disabled.

The wider marketplace work still includes current Editor/Studio/Harmony and store
qualification, resolving native external-billing/payout blockers, and the existing
release gates. That work is not itself blocked by waiting for zero-event consent.
No claim of completed marketplace submission or publication is made.
