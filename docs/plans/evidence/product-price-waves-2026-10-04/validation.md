# Validation

Full automation/test_all.sh passed: 114 SQL files, 1085 Flutter tests (one skip),
242 Deno tests, web and automation contracts, three local worker integration tests
(27 external credential-dependent cases skipped). Disposable database port 56722.
Targeted 13 Flutter tests passed after adding due-visibility refresh tracking.
Real PostgreSQL concurrency harness passed worker/cancel/move races for both
individual plans and shared price/visibility waves. Targeted wave SQL passed.
Dart analysis has no errors or warnings; five informational brace-style notices.
Translations unified and reordered; apply_config and git diff --check passed.

Headless screenshots use real widgets with synthetic data, not production edits.
No production fixtures or order/price/visibility mutations were created.
