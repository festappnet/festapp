# Festapp compaction: optional ref scope expansion

Date: 2026-11-03. Read-only/disposable experiments only; no publication or
ref deletion is authorized by the user's question about dropping refs.

The current main/12-tenant candidate packs all 24 retained remote refs into
499.70 MiB (523,971,083 bytes). These independently fetched full repositories
use the same repack settings as the original compaction measurements and pass
fsck. All original refs remain unchanged on GitHub and in the shared checkout.

| Option relative to the prepared candidate | Packed MiB | Saving MiB | Missing active pinned commits |
| --- | ---: | ---: | ---: |
| Remove six feature/fix refs and Joomla tag | 483.31 | 16.38 | 8 |
| Retain gh-pages current tree in one root commit | 204.37 | 295.33 | 0 |
| Combine both options | 188.23 | 311.46 | 8 |

## Recommended additional scope

Rewrite only `refs/heads/gh-pages` from 600 commits to one root commit that
retains its exact current tree. This saves approximately
295.33 MiB (59.1%)
in the full remote-ref clone, without dropping any active pinned-history input.
Its current content and all file modes compare exactly. GitHub Pages is
configured for `live.festapp.net`; this experiment preserves its published
source snapshot instead of deleting the hosting ref. No website deployment ran.

- Frozen gh-pages: `8f31f880a899b5a2db5548cdf9d20775a360e62b`
- Proposed snapshot: `b50d910009b9df2f64595925e9b8f377c32a9e04`
- Source tree equality: PASS; new commit has no parent.

This would expand the proposed atomic ref set from 13 to 14 branches. It is
not yet in `publication-manifest.json`; obtain the owner's scope choice before
updating that publication contract. Existing main protection/admin-review and
write-freeze gates still apply. Retain all recovery bundles and original refs
until the approved transaction and readback complete.

## Deletion-only alternatives

The seven refs proposed for measurement-only exclusion are:

- `refs/heads/feat/admin-mcp-seat-holds-release-20261023`
- `refs/heads/feat/agent-access-20261003`
- `refs/heads/fix/blueprint-majority-label-defaults-20261022`
- `refs/heads/fix/email-substitution-autolinks-20261019`
- `refs/heads/fix/tenant-startup-test-config-20261103`
- `refs/heads/fix/ticket-editor-ui-20261003`
- `refs/tags/joomla-vstupenky-online-v1.0.1`

They account for only about 16 MiB of further savings once the hosting history
is compacted. Removing them loses eight active historical commit inputs used
by baseline SQL recovery, migration assembly and other tooling. A full clone
without these refs was explicitly checked and lacks all eight IDs. Replace
those historical-input contracts with exact preserved fixtures before such a
deletion/remapping wave. Simply substituting arbitrary new group endpoints
would change historical input bytes. Some feature branches also contain unique
patch candidates; the external bundle preserves them, but deletion needs an
explicit owner disposition.

Local archive/backup refs do not exist in the advertised remote ref set and
therefore do not account for the measured remote clone size. They remain in
the original workspace and verified external bundle. GitHub PR refs and server
caches may retain objects independently of ordinary branch/tag publication.

Detailed bytes, removed-ref sets, pinned-input checks and proposed gh-pages
snapshot are in:

`/Users/miakh/festapp-history-compaction-20261103/ref-option-measurements.json`

## Follow-up: resolved versus unfinished feature branches

The owner clarified that deletion is conditional on the work being resolved.
Detailed PR discussions, source blobs and replacement commits were checked;
patch uniqueness alone was insufficient. Four refs are eligible for retirement:
seat-hold MCP integration, superseded ticket editor UI, withdrawn email auto-link
experiment, and merged startup-branding test. The diagnostics broker is an
explicitly disabled unfinished draft, not a merged implementation. The two
AKH label SQL repair scripts are not merged and have no located execution
receipt; retain their ref pending a concrete disposition. No remote deletion
was performed. The repository has automatic deletion after merge disabled;
closed unmerged PR refs also remained after cleanup.

Authoritative detailed evidence: external `feature-final-dispositions.json`,
`pr-229-discussion.json`, `pr-252-discussion.json`,
`pr-519-discussion.json` and `pr-571-discussion.json`.

## Final executed choice

Both scope expansions were completed with consumer preservation. The six
working branches were retired after their final audit. gh-pages history was
collapsed. The Joomla tag's old history was removed while retaining the tag
name, exact release source tree, release object and ZIP because the real CMS
updater depends on its public URL. Historical tooling now uses verified
fixture bytes instead of old Git commits. Final clone: approximately 190 MiB.
Publication, protections, fresh GitHub clone, public ZIP equality and all six CI
workflows are verified. See the final execution result for exact measurements.
