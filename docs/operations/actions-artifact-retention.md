# Shared GitHub Actions storage

The festappnet allowance is shared by repositories. Actions cache is a separate
allowance; clearing dependency caches does not fix artifact storage usage.
The October 2026 incident was caused by historical Android candidates retained
for 30 days plus three large Plesy release archives. Plesy now retains its exact
verified live archive and notification receipts; Cloudflare versions own rollback.

`Actions artifact retention` in this repository runs daily and after Android
candidate/revalidation/production workflows. It deletes only recognized artifacts
with verified completed main-branch producer runs:

- Candidates after the existing seven-day promotion window, including historical
  uploads whose original expiry was 30 days. Rebuild after expiry.
- Raw AABs after their three-day recovery window, or immediately after a successful
  producer run stored the matching verified candidate. Failed verification keeps
  its raw recovery artifact for three days.

Current candidates and unrelated evidence stay untouched. Active/queued/waiting
Android operations block cleanup, with a second check before deletion. A 200 MiB
retained-storage budget fails visibly after safe cleanup; multiple pending large
candidates need an explicit promotion/expiry decision rather than silent eviction.
No tenant branches, builds, Play releases or billing settings are changed.

Inspect: `node automation/release/artifact_retention.mjs`.
Apply through the serialized workflow:
`gh workflow run artifact-retention.yml -R festappnet/festapp -f apply=true`.
Manual dispatch defaults to dry run. Deletion is irreversible and restricted to
this workflow. All artifact inventories are fully paginated. Monthly accrued
GB-hours remain even after deletion; the billing display can lag by 6-12 hours.
