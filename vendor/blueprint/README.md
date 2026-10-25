# Blueprint distribution snapshot

These are the exact pub-selected 0.4.0 wrapper and 0.2.2 core archives,
verified with the npm 0.3.7 archive by the package archive gate.
They are dependency artifacts. Edit the canonical `festappnet/venue_seat_picker`
package, then rebuild and verify its distributions before updating this snapshot.
Do not patch these copies or add another rendering implementation here.
`manifest.json` records the archive and every extracted file SHA-256.
The host uses repository-relative paths and needs no workstation checkout,
unpublished Git revision or dependency override file.

Pub-selected means file selection by local `pub publish --dry-run`, not a prior
publication to pub.dev. Import verified archives built directly from canonical
source through `tool/archive_check.sh`; registry publication is a separate step.

Only the npm archive selected by `web_client/package.json` and its lockfile is
retained. Older host archives are recoverable from Git revision
`a4296c57687294b34826e59c7b232eef582c9748`; they are not installation inputs.
