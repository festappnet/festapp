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

## Retained consumers

- `automation/baseline.py` materializes predecessor migration inputs for offline
  install/upgrade; `source_paths` and `materialize` enumerate exact snapshot paths.
- Authorization and ticketing-profile assemblers compare their canonical sources
  against those frozen predecessors using `automation/historical_inputs.py`.
- Node security/predecessor and capture-reference checks use the digest-verifying
  `automation/lib/historical_inputs.mjs` reader.

Current installable SQL lives in `database/functions`, the baseline and forward
`supabase/migrations`; objects here remain immutable test/recovery inputs. No
snapshot has a proven retired recovery contract in the 2026-11-06 reduction, so
all mappings and raw objects are retained. Moving or compressing them is not a
runtime code reduction.
