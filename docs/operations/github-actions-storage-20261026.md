# GitHub Actions storage investigation - 2026-10-26

## Verified state

Read-only GitHub REST inventory covered all 11 repositories visible to the
current credential in `festappnet`, including archived repositories. Artifacts
were fully paginated (including both pages for `plesuj`). Snapshot sizes exclude
expired artifacts. Other organizations, inaccessible repositories and GitHub
Packages were not inventoried.

| Repository | Active artifacts | Bytes | GiB |
| --- | ---: | ---: | ---: |
| `festapp` | 27 | 1,581,731,045 | 1.473 |
| `venue_seat_picker` | 26 | 142,099,125 | 0.132 |
| `plesuj` | 142 | 7,106,228,123 | 6.618 |

Organization plan is Free. Its existing organization-wide Actions product budget
is **USD 0**, with `prevent_further_usage: true`. No budget or billing settings
were changed. The October usage API returned **USD 0 net** for all reported
Actions entries, including storage. This is a delayed usage snapshot, not a
final invoice or proof that every current workflow can upload artifacts.

The email's 0.46/0.5 GB cycle allowance is not today's physical stored bytes.
The API reports 1,018.692 accumulated GiB-hours for Actions storage in October
at inspection. Do not reconcile these asynchronously updated snapshots as if
they were measured at the same time. Storage accrues hourly; deleting an
artifact prevents further accumulation but does not reverse past usage.

Cache inventory is separate: `festapp` 11,088,407,698 bytes,
`venue_seat_picker` 10,429,172,306, `banksync` 678,535,169,
`invoicesync` 139,914,579 and `plesuj` 2,686,733,438. Cache storage has its own
10 GiB allowance per repository. It is not the artifact allowance in the email.

## Producers and consumers

- Festapp: ten encrypted Android candidates total 1,425,966,474 bytes; one raw
  encrypted AAB adds 155,735,121 bytes. Tiny dispatch inputs and Play receipts
  account for only 29,450 bytes. `android-production.yml` downloads a candidate
  by exact run ID and tenant/source name, then verifies its recorded identity,
  hash and signature. `android-candidate-revalidate.yml` consumes the raw AAB
  during its 3-day recovery window. No Play API or Android build was run.
- Plesuj: 65 `release-*` artifacts total 7,050,662,812 bytes, with an explicit
  90-day retention in `.github/workflows/release.yml`. Another 77 `receipt-*`
  artifacts total 55,565,311 bytes. Its workflow recovers `indexnow-state` from
  the newest receipt before notifications. Preserve that receipt and confirm
  release/rollback consumers before any cleanup. No changes made in this repo.
- Venue seat picker: 123,664,626 bytes are transient `github-pages` artifacts;
  verified npm archives account for another 18,424,657 bytes. No changes made.

## Prepared repository change

New Android candidate and revalidation uploads retain artifacts for **7 days**
instead of 30. Raw recovery stays at 3 days and Play reports at 30 days. This
reduces candidate byte-days by about 77% for the same upload rate. Production
still uses the exact candidate run/digest; expiry requires a new verified build
and authorization for that identity. Existing artifacts keep their old expiry.
No builds, tenant releases or production operations are part of this change.

## Concrete cleanup proposal - NOT executed

These four candidates have newer candidates for the same tenant. Their source
SHAs also differ from the current tenant branch heads, so the production
workflow's current-head guard rejects their promotion. This does not prove
there is an independent archival copy or no historical recovery need.

| Artifact ID | Name | Bytes |
| --- | --- | ---: |
| `11608613509` | `android-candidate-csmostrava2026-82219e6cb8d8c3ee4eabc41eee092c40229accdf` | 141,321,963 |
| `11607971169` | `android-candidate-festivalslunovrat-51141b4dd8c815416523d8a2919ce86e349b34f5` | 141,317,101 |
| `11544586471` | `android-candidate-festivalslunovrat-83e79d71320d236f51b680066dbd084eb134c710` | 141,274,831 |
| `11543658271` | `android-candidate-csmostrava2026-f0d8e4f5a80985ceaaf09d4eff11a4027ef101cc` | 141,277,550 |

Combined removal would free **565,191,445 bytes (0.526 GiB)**.
Keep all other candidates, the raw recovery AAB, operation receipts and dispatch
inputs. Confirm that these four superseded candidates may be discarded before
irreversible deletion. No archival copy was created or claimed.

Observed branch heads:

- `prod/csmostrava2026`: `b8599d06cd281879d98a99af89af747c470680de`
- `prod/festivalslunovrat`: `8cb508f76558e589c3de48239676a69bec939e7d`

## Recommended next steps

1. Publish the validated Festapp retention change. It only affects future
   uploads and does not alone resolve the organization's existing storage.
2. In `plesuj`, inspect the rollback contract and prepare a policy retaining
   the current release and a small explicit rollback set. A time limit alone
   still stores many 100 MB archives when releases run frequently. Preserve
   notification receipts separately; do not remove the newest receipt.
3. After approval, remove only the four exact superseded artifact IDs above,
   re-reading their identities immediately beforehand. Reinventory afterward;
   billing display can lag 6-12 hours, and accumulated usage remains.
4. Keep the existing USD 0 spending guard unless paid usage is explicitly
   requested. Purchasing Team solely for storage is unnecessary; any decision
   to allow small overage must separately consider runner usage and budget scope.

## Sources

- [Actions billing and hourly storage accounting](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [Retention changes affect only new artifacts](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)
- [Artifact deletion is irreversible](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/remove-workflow-artifacts)

Evidence commands: `gh api orgs/festappnet/repos --paginate`, fully paginated
`repos/<org>/<repo>/actions/artifacts`, `repos/<org>/<repo>/actions/cache/usage`,
`organizations/festappnet/settings/billing/budgets`, and
`organizations/festappnet/settings/billing/usage?year=2026&month=10`.
