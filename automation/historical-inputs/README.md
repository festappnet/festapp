# Historical tooling inputs

These are exact original input bytes for baseline recovery, immutable migration
assembly, predecessor/security regression tests and capture-reference checks.
They are fixtures, never current installable migrations or application sources.

`manifest.json` maps the original full revision and path to a SHA256-addressed
file in `objects/`. The Python and Node readers verify that digest before use.
Runtime readers never consult Git history or fall back to current source.
Repeated bytes share one file. Original revision IDs remain provenance only.

Inputs were verified against the external recovery bundle before history
compaction. Adding a fixture requires the exact reviewed original bytes and
matching digest; changing current source must never update these snapshots.
