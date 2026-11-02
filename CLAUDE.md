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

Use “Stornovat” for Czech business cancellation of orders, tickets and
applications, and “storno” for their cancellation state. Use “Zrušit” for
dismissing dialogs, abandoning edits or cancelling scheduled changes.
Existing backend command names and accounting states stay unchanged.

Address users formally in Czech UI copy (for example, “Vyberte”, “Klikněte”,
“Zadejte”). Apply the same wording to editor hints and validation messages.

## Platform brand

Always spell the platform brand **Festapp**. Use **Festapp Tickets** for the
global ticketing product and **vstupenky.online** for the regional portal. Keep
this exact spelling in UI, connector metadata, descriptions and documentation;
do not invent another spelling or infer a brand name from speech transcription.
