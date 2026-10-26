# Consolidated release readiness - 2026-10-26

Status update 2026-10-27: deployed and verified at 0.20.427+929.
See [the release receipt](releases/festapptickets-2026-10-27.json).
The following original readiness snapshot is retained as dated preflight evidence.

Candidate implementation: `b1ac7e53025b45b731cd9d88f62cdd2d63f62539`. It contains PR #617 and #618 histories and the preserved workspace snapshot. Main remains `3988bb7cbaf8766068a84f49f759d5544269e325` until the protected merge succeeds.

The selected release is only `prod/festapptickets`, tenant festapptickets, https://vstupenky.online, canonical backend https://api.festapp.net, organization 3. Other production branches and Android publication are outside this rollout.

## Reconciliation

- Preserved the complete original dirty workspace in a protected external backup and a recoverable source snapshot; private browser artifacts were excluded from Git.
- Retained main's reviewed notification cursor/security/count fixes and the immutable already-installed `20261026150000` migration.
- Completed the remaining unread watermark/dot feature as a new forward-only `20261026230000` migration; no historical migration was regenerated.
- Included PR #618 maintenance, retention and finished research without partner submissions or additional infrastructure changes.
- Preserved the current canonical marketing generator's retired-page deletion. Private browser scratch output is now ignored.

## Validation

- Web: 785 cases, 755 passed, 30 existing skips, zero failures.
- Canonical/notification/organizer/infrastructure/Android contracts: 27 passed; nested Python source-contract cases also passed.
- Targeted notification Flutter controller/widget cases: 22 passed, concurrency 1.
- Real disposable PostgreSQL presentation and temporal-feed SQL files: both passed. Pre-ack watermark, subsequent acknowledgement and aggregated snapshot sequences are asserted. The test loader used the marked loopback disposable project; no production fixtures.
- Previously sealed stage 3-5 evidence remains tied to its implementation commits. Merge resolution changes no MCP/Edge command code; translation changes add only the notification label.
- Canonical production identity, migration prerequisites, live activation and the existing protected canonical web release manifest passed read-only preflight. Cloudflare Pages OAuth is authenticated.

## Remaining execution

GitHub main requires one approving review. The authenticated account is also the PR author, so it cannot supply the independent review; repository auto-merge is disabled. No protection changes or administrator bypass were performed. After authorized main merge: prepare the canonical tenant overlay from its current production tip, increment version, preserve ancestry/drift gates, take a fresh encrypted backup, apply missing reviewed SQL plus ledger atomically, promote reviewed Edge and MCP artifacts, then build/deploy locally with `automation/deploy_direct.sh` and verify coherent live version/legal/assets.

The five PR #617 migration versions 20261026170000, 20261026190000, 20261026200000, 20261026210000 and 20261026220000 are absent from the verified ledger. The new unread migration follows them. Version 20261026150000 is already installed. Recheck the ledger immediately before applying. The notification file has its own top-level transaction wrappers; an atomic migration+ledger executor must account for those wrappers, rather than nesting a helper that commits the body early.

Production source tip at preflight: `eaea5375e6d6487fd817e8c46102f0c5f6c78df4`, version `0.20.426+928`. Production has not been changed by this integration.

## Candidate source digests

- `database/functions/notification_center/core.sql`: `acf413f9a88e8e6391ab244dea37d3864d8d1df734207898a6c22e2ed70c4de8`
- `database/functions/notification_center/temporal_feed.sql`: `afea334bd834a415a0fd75265231e3996c1a2fbf5ea83a2589bbb7d6d7e54ee4`
- `lib/components/notification_center/notification_center_controller.dart`: `6ef2f7e3b2b9af831c34cae5e6e89f8dec3ad640b7e222c7c54fa0a97ed6c6c7`
- `lib/components/notification_center/notification_center_panel.dart`: `4526bb3001e38f17c999754e3b43eebd36e1c4c56073693dc116436d21b3cad2`
- `supabase/migrations/20261026230000_notification_center_unread_snapshot.sql`: `27c74f26c8e61d53ec1ec8d51b26e58cbda6bf080990f0001ba6aa654d489b78`
