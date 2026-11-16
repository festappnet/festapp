# Platform integrations

`integrations/<platform>/` is the canonical home of each installable integration.
Keep its source, package manifest, lockfile, tests, build scripts and platform
setup instructions together. Shared Festapp checkout behavior stays in
`web_client/` and the backend; integrations adapt that existing contract.

| Platform | Products | Recorded state | Start here |
| --- | --- | --- | --- |
| WordPress | vstupenky.online; Festapp Tickets | Czech plugin is public on WordPress.org and mirrored in GitHub Releases. Global ZIP remains a separate prepared distribution. | [Directory](https://wordpress.org/plugins/vstupenky-online/), [development](wordpress/README.md) |
| Joomla | vstupenky.online; Festapp Tickets | Czech module is public in GitHub Releases and JED; the canonical update feed owns its version and checksum. Global packages are not part of the regional release. | [Update feed](joomla/updates/vstupenky-online.xml), [development](joomla/README.md) |
| Wix | vstupenky.online | Existing App Market app uses hosted widget/settings assets. The live manifest owns runtime version and file hashes. Native app registration and hosted runtime are separate releases. | [Live manifest](https://festapp-wix.pages.dev/manifest.json), [development](wix/README.md) |
| Make | vstupenky.online | Five read-only modules deployed; one verified-app review and follow-up form submitted on 2026-10-28. Approval and catalogue release pending in the dated evidence. | [Connector and status](make/README.md), [setup](make/SETUP.md), [submission receipt](make/evidence/submission-20261028.json) |

These are recorded states, not a live marketplace monitor. Record dated external
receipts in the platform directory when the state changes.

## Layout

- `src/` or the platform's native plugin directories: distributable code.
- `tests/` and `scripts/`: platform-specific verification and packaging.
- `README.md`: entry point, commands and links to the detailed state.
- `SETUP.md` / `SUBMISSION.md`: registration, installation and publishing steps.
- `evidence/` or `VALIDATION.json`: dated results and exact artifact hashes.
- `dist/`, `artifacts/`, `node_modules/`: generated locally, never source authority.
- `.private/`: ignored account/session/release inputs; never include in a package.

WordPress has its established `shared/` + product-directory layout; do not move
it merely to force the same source layout as Wix. Each JavaScript package owns
its pnpm 11.24.0 manifest and lockfile. Do not copy dependencies between worktrees.

Future Shoptet/Shopify integrations belong here when implemented. General
HTML and Webnode embed guides belong in public help, not in empty plugin folders.
Plans under `docs/plans/` describe decisions; they are not another source copy.

## Publisher cost constraint

The owner requires **zero fixed fees for registering, listing or retaining an
integration**. A sales/revenue commission is acceptable. Development/test sites
must not start a paid subscription. This constraint concerns our publisher
costs, separately from an organizer's ordinary website plan and ticket-service
pricing. Record actual terms; never infer zero cost from “free to install”.

For Wix, [billing review](wix/BILLING-APPROVAL.md) and the release check enforce
this constraint. No paid plan or marketplace fee is authorized by developing the
widget. An individual agreement must confirm the treatment of ticket face value
and our service revenue before commercial publication.

## Canonical service homepage

The service presentation lives at the product origin root: `https://vstupenky.online/`
(or `https://tickets.festapp.net/` for the international product). Plugin builders
derive offer links from that existing origin; do not add a separate marketing URL
to product configuration or proposals. Historical receipts and immutable released
ZIPs retain their original bytes; the retired public URL has only a permanent
redirect to the homepage. Prepared package versions require their normal release
gates before publishing or replacing marketplace metadata.
