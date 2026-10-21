#!/usr/bin/env python3
"""Record reproducible source hashes and actual local gate evidence, including failures."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / 'docs/plans/evidence/canonical-authorization-20261020'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, value):
    (FOLDER / name).write_text(json.dumps(value, indent=2) + '\n')


paths = set(subprocess.check_output(['git', 'diff', '--name-only', 'origin/main'], cwd=ROOT, text=True).splitlines())
paths.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], cwd=ROOT, text=True).splitlines())
sources = {name: digest(ROOT / name) for name in sorted(paths)
           if (ROOT / name).is_file() and not (ROOT / name).is_symlink()
           and '/evidence/' not in name and 'node_modules' not in name}
artifacts = {str(p.relative_to(ROOT)): digest(p) for p in sorted(FOLDER.glob('*'))
             if p.is_file() and p.name not in ('source-hashes.json', 'validation.json')}
write('source-hashes.json', {
    'baseHead': subprocess.check_output(['git', 'rev-parse', 'origin/main'], cwd=ROOT, text=True).strip(),
    'scope': 'PR delta and evidence in the isolated worktree against recorded authoritative main; production remains unapplied.',
    'sources': sources, 'artifacts': artifacts,
})

# These are completed commands, not inferred test coverage or a full-plan pass.
gates = [
    ('sql-mcp', 'FESTAPP_AUTHORIZATION_DATABASE_URL=<owned-local-db> FESTAPP_MCP_TEST_DATABASE_URL=<owned-local-db> npm --prefix tools/festapp test',
     '/tmp/festapp-authz-full-final.log', 'passed', '66 passed, zero failed/skipped'),
    ('participant-notice-final', 'node --test --test-name-pattern="canonical truth table|app links enqueue" tools/festapp/test/canonical-authorization-postgres.test.mjs',
     '/tmp/festapp-authz-participant-notice-final.log', 'passed', '2 passed; final 2048-role management parity, recipient/template fences and revoked replay'),
    ('canonical-source-parity', 'node web_client/scripts/run_db_tests.js database/tests/canonical_mutation_source_parity_test.sql',
     '/tmp/festapp-authz-final-domain-batch.log', 'passed', '14 final SQL contracts pass, including actual database/source parity and retired signatures'),
    ('participant-notice-typecheck', 'deno check --allow-import=esm.sh supabase/functions/send-app-links/index.ts supabase/functions/send-sign-in-code/index.ts',
     '/tmp/festapp-authz-participant-notice-edge-check.log', 'passed', 'Both final entrypoints typechecked'),
    ('web', 'npm --prefix web_client test',
     '/tmp/festapp-authz-web-final.log', 'passed', '527 passed, 25 skipped, zero failed'),
    ('edge-domains', 'deno test <domain handlers; mocked providers, no runtime network>',
     '/tmp/festapp-authz-deno-domains.log', 'passed', '60 passed'),
    ('bank-fetch-edge', 'deno test --cached-only supabase/functions/fetch-transactions/handler_test.ts',
     '/tmp/festapp-authz-bank-pull-edge.log', 'passed', '3 passed'),
    ('bank-edge-typecheck', 'deno check --allow-import=esm.sh supabase/functions/bank-sync-manage/index.ts supabase/functions/fetch-transactions/index.ts',
     '/tmp/festapp-authz-bank-edge-final-check.log', 'passed', 'Both entrypoints typechecked'),
    ('app-links-edge-typecheck', 'deno check --allow-import=esm.sh supabase/functions/send-app-links/index.ts',
     '/tmp/festapp-authz-app-links-edge-check.log', 'passed', 'Entrypoint typechecked'),
    ('app-links-delivery', 'deno test --cached-only --allow-env=APP_LINKS_ORGANIZATION_ID supabase/functions/send-app-links/test_app_links_delivery.ts',
     '/tmp/festapp-authz-app-links-edge-test.log', 'passed', '3 passed; provider mocked'),
    ('reviewed-blueprint-sql', 'node --test --test-name-pattern="demo unit facts" tools/festapp/test/canonical-authorization-postgres.test.mjs',
     '/tmp/festapp-authz-reviewed-writer-fixed.log', 'passed', '1 passed; real SQL writer and receipt reject after role revocation'),
    ('organization-sql', 'node web_client/scripts/run_db_tests.js <organization, verification, communication and source-parity filters>',
     '/tmp/festapp-authz-org-context-contract.log', 'passed', '8 passed'),
    ('recovered-active-contracts', 'node web_client/scripts/run_db_tests.js <active recovered RPC and image-record contracts>',
     '/tmp/festapp-authz-recovered-active-contract.log', 'passed', '6 passed'),
    ('groups-sql', 'node web_client/scripts/run_db_tests.js <group contract filters>',
     '/tmp/festapp-authz-groups-contract.log', 'passed', '3 passed'),
    ('adapter-fixtures', 'node web_client/scripts/run_db_tests.js <adapter contract filters>',
     '/tmp/festapp-authz-adapters-contract.log', 'superseded-fixture-failure', '3 passed, 2 duplicate-occasion legacy Blueprint fixtures failed; reproduced with before definitions in before-blueprint-fixture-failures.json'),
    ('image-record-scope-fixed', 'node web_client/scripts/run_db_tests.js database/tests/abuse/image_records_test.sql',
     '/tmp/festapp-authz-directory-image-scope-fixed.log', 'passed', '1 passed after rejecting mixed unit/occasion owner'),
    ('remaining-ui', 'fvm flutter test --concurrency=1 --dart-define=FESTAPP_OCCASION_SETUP=true test/components/unit/app_landing_screen_test.dart test/components/organization/authorization_projection_test.dart',
     '/tmp/festapp-authz-remaining-ui-flutter.log', 'passed', '3 passed'),
    ('remaining-ui-analyzer', 'fvm dart analyze <changed organization/unit UI and tests>',
     '/tmp/festapp-authz-remaining-ui-analyze.log', 'passed-with-infos', 'Zero errors/warnings; 4 existing style/deprecation infos'),
    ('role-denial-original-batch', 'fvm flutter test --concurrency=1 <role-denial and command test files>',
     '/tmp/festapp-authz-role-denial-flutter.log', 'superseded-fixture-failure', '56 passed, 4 fixture failures; affected files fixed and rerun below'),
    ('role-denial-fixed-files', 'fvm flutter test --concurrency=1 test/data_services/rights_explicit_occasion_test.dart test/components/unit/unit_commands_cases.dart',
     '/tmp/festapp-authz-role-denial-flutter-fix.log', 'passed', '14 passed; other 46 unchanged tests passed in the original batch'),
    ('bank-sql-contracts', 'node web_client/scripts/run_db_tests.js <nine bank/source-parity/demo/internal filters>',
     '/tmp/festapp-authz-bank-two-roles-contract-final.log', 'passed', '9 passed'),
    ('bank-lifecycle', 'fvm flutter test --concurrency=1 <Rights, bank warning/card/add cases>',
     '/tmp/festapp-authz-bank-lifecycle-flutter.log', 'passed', '41 passed'),
    ('bank-provider-cases', 'fvm flutter test --concurrency=1 <bank *_cases.dart files>',
     '/tmp/festapp-authz-flutter-bank-cases.log', 'superseded-fixture-failure', '42 passed, 2 stale unsupported-0800 expectations failed'),
]
gates.extend([
 ('final-domains', 'DATABASE_URL=<owned-local-db> node web_client/scripts/run_db_tests.js <source parity, scanning, duplication and feature choices>',
  '/tmp/festapp-authz-final-domain-batch.log','passed','14 passed; supersedes all earlier scanning/duplication/feature fixture failures'),
 ('remaining-domains', 'node web_client/scripts/run_db_tests.js <speakers, cleaning, activities, reception, feedback, event grid, layout and places>',
  '/tmp/festapp-authz-remaining-domains-contract.log','passed','11 passed'),
 ('actor-order', 'node web_client/scripts/run_db_tests.js <waitlist, overview, email queue and parity>',
  '/tmp/festapp-authz-actor-order-contract.log','passed','5 passed'),
 ('capacity-contraction', 'node web_client/scripts/run_db_tests.js <capacity, retired writers and parity>',
  '/tmp/festapp-authz-capacity-contraction-contract.log','passed','5 passed'),
 ('direct-write-contraction', 'node --test --test-name-pattern=<gallery deletion|all roles ACL|direct table-write> tools/festapp/test/canonical-authorization-postgres.test.mjs',
  '/tmp/festapp-authz-direct-write-contraction-final.log','passed','3 passed; latest table/column reachability assertion also passes in full66'),
 ('legacy-scanner-proof-red', 'node web_client/scripts/run_db_tests.js database/tests/scanning/legacy_scan_proof_test.sql',
  '/tmp/festapp-authz-legacy-scan-proof-before.log','expected-red-before-fix','Actual legacy NULL-proof bypass reproduced before the fix; superseded by final10 scanning passes'),
 ('scanner-shared-proof', 'node web_client/scripts/run_db_tests.js database/tests/scanning/',
  '/tmp/festapp-authz-scanning-shared-proof-final.log','passed','10 passed; unchanged final scanning cases also pass in final14'),
 ('bank-provider-corrected', 'fvm flutter test --concurrency=1 <bank *_cases.dart>',
  '/tmp/festapp-authz-bank-cases-corrected.log','passed','46 passed; supersedes old0800 expectations'),
 ('navigation-rights', 'fvm flutter test --concurrency=1 test/data_services/rights_explicit_occasion_test.dart test/components/cleaning/cleaning_gating_cases.dart test/components/reception/reception_gating_cases.dart',
  '/tmp/festapp-authz-nav-flutter-final.log','passed','23 passed'),
 ('navigation-analyzer', 'fvm dart analyze lib/components/scan/check_page.dart lib/components/cleaning/cleaning_page.dart lib/data_services/rights_service.dart',
  '/tmp/festapp-authz-nav-analyze-final.log','passed-with-infos','No errors/warnings; 3 original style infos'),
 ('context-final-serial', 'AUTHZ_PERF_WORKLOADS=context node automation/authorization/compare.mjs performance-context-navigation-final.json',
  '/tmp/festapp-authz-performance-nav-final.log','passed','16 alternating paired blocks, final context projection'),
 ('context-final-concurrent', 'AUTHZ_PERF_WORKLOADS=context AUTHZ_PERF_SAMPLES=30 node automation/authorization/concurrent.mjs',
  '/tmp/festapp-authz-concurrent-nav-final.log','passed','12 alternating paired blocks, four clients, final context projection'),
 ('context-final-first-request', 'node automation/authorization/cold.mjs performance-first-request-navigation-final.json',
  '/tmp/festapp-authz-cold-nav-final.log','passed','24 alternating blocks; sequential and four-way fresh connections, all four p95 gates pass'),
])

gates.extend([
 ('pr-rebased-sql-mcp','pnpm --dir tools/festapp test with both owned-local database variables',
 '/tmp/festapp-authz-pr-full.log','passed','66 passed, zero skipped after rebase and upstream migration application'),
 ('pr-rebased-web','pnpm --dir web_client test',
 '/tmp/festapp-authz-pr-web.log','passed','531 passed,25 skipped; current pnpm lockfiles'),
 ('pr-rebased-generators','eight generator/immutable-migration checks; Python source-contract tests; Node canonical-operation source tests',
 '/tmp/festapp-authz-pr-generators-fixed.log','passed','8 Node source-contract tests passed; 9 Python tests and generator checks also passed'),
 ('pr-rebased-flutter','fvm flutter test --concurrency=1 --dart-define=FESTAPP_OCCASION_SETUP=true <organization/Rights/ticket editor/ticket saver cases>',
 '/tmp/festapp-authz-pr-ui-final.log','passed','120 passed; includes current image-drop lifecycle and SQL-projection admission'),
 ('pr-upstream-domain-selection','node web_client/scripts/run_db_tests.js <six selected upstream/current source contracts>',
 '/tmp/festapp-authz-pr-rebase-domains.log','superseded-runner-selection','5 pass; public_hold_availability requires psql variables and a different owned fixture project, so it was not an executable selection for this runner. It remains outside these local PR gates.'),
])

receipts = []
for gate, command, filename, state, result in gates:
    path = Path(filename)
    receipts.append(dict(gate=gate, command=command, state=state if path.exists() else 'evidence-missing',
                         result=result, logPath=filename, logSha256=digest(path) if path.exists() else None,
                         logTail=path.read_text(errors='replace')[-1800:] if path.exists() else None))
write('validation.json', {
    'state': 'local-implementation-complete', 'verification': 'standard',
    'notice': 'Local closure combines domain-ledger.json, boundary-ledger.json, transport-resolution.json, performance-summary.json and executed receipts. No production application or exhaustive per-function test claim.',
    'sourceManifestSha256': digest(FOLDER / 'source-hashes.json'),
    'gates': receipts,
    'notPerformed': ['production migration', 'deployment', 'commit/push/publication', 'real email delivery'],
})
print(f'Recorded {len(sources)} source hashes, {len(artifacts)} artifacts and {len(receipts)} receipts; production remains unapplied.')
