# CLAUDE.md

Read `docs/architecture/ai_context.md` first — it has the architecture, critical rules, and gotchas.

## Quick Reference

```bash
fvm flutter run -d chrome                                          # Always use fvm prefix
fvm dart run build_runner build --delete-conflicting-outputs       # Regenerate AutoRoute, JSON models
./automation/test_all.sh                                           # Broad wrapper; lane caveats in CONTRIBUTING.md
./automation/test_client.sh                                        # All client roots (Dart + Flutter)
./automation/apply_config.sh                                       # Propagate project.conf changes
node web_client/scripts/run_db_tests.js database/tests/my_test.sql # Specific DB test
```

## Other Docs

- `docs/architecture/database.md` — Schema, SQL function inventory, RPC call map
- `docs/architecture/SERVICES.md` — RightsService, OfflineDataService, SynchroService
- `docs/backend/edge_functions.md` — Edge function auth patterns, deployment
- `CONTRIBUTING.md` — Testing workflow, security checklist, commit rules

## Czech action wording

Use “Zrušit” for cancel/dismiss actions in Czech UI, never “Stornovat” or “Storno”.
This is UI wording; existing backend command names and accounting states stay unchanged.

Address users formally in Czech UI copy (for example, “Vyberte”, “Klikněte”,
“Zadejte”). Apply the same wording to editor hints and validation messages.
