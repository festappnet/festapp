#!/usr/bin/env python3
"""Seal a private, main-sourced one-shot data + schema transaction (no network)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
VERSION = '20261101160000'
MIGRATION = f'supabase/migrations/{VERSION}_blueprint_canonical_storage_cutover.sql'
OPERATION = 'database/operations/blueprint-cutover/apply.sql'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--database', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.source_sha):
        parser.error('source-sha must be the complete published main commit')
    if not re.fullmatch(r'[A-Za-z0-9_]+', args.database):
        parser.error('invalid database assertion')
    subprocess.run(['git', 'merge-base', '--is-ancestor', args.source_sha,
                    'origin/main'], cwd=ROOT, check=True)
    directory = args.directory.resolve()
    if directory.stat().st_mode & 0o077:
        parser.error('input directory must be private (chmod 700)')
    source = directory / 'prepared-proposals.json'
    if source.stat().st_mode & 0o077:
        parser.error('prepared proposals must be private (chmod 600)')
    plans = json.loads(source.read_text())
    if not isinstance(plans, list) or not plans:
        parser.error('nonempty reviewed proposals required')
    ids = [p['source']['id'] for p in plans]
    if len(ids) != len(set(ids)):
        parser.error('duplicate blueprint proposals')
    organizations = sorted({p['source']['organization'] for p in plans})
    manifest = {'schemaVersion': 1, 'scopeOrganizationIds': organizations, 'plans': plans}
    payload = json.dumps(manifest, ensure_ascii=False, separators=(',', ':'))
    delimiter = '$reviewed_blueprint_cutover$'
    if delimiter in payload:
        parser.error('manifest contains reserved SQL delimiter')
    sources = {}
    for name in (OPERATION, MIGRATION, 'database/tests/canonical_mutation_source_parity_test.sql'):
        sources[name] = subprocess.check_output(
            ['git', 'show', f'{args.source_sha}:{name}'], cwd=ROOT, text=True)
    preamble = f"""\\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='5min';
SELECT pg_advisory_xact_lock(hashtextextended('festapp:blueprint:canonical-cutover',0));
DO $identity$ BEGIN
 IF current_database()<>'{args.database}' THEN RAISE EXCEPTION 'Wrong cutover database'; END IF;
 IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='{VERSION}') THEN
  RAISE EXCEPTION 'Cutover migration already applied'; END IF;
END $identity$;
SELECT set_config('request.jwt.claim.sub','',true),
 set_config('request.jwt.claim.role','service_role',true),
 set_config('request.jwt.claims','{{"role":"service_role"}}',true);
CREATE TEMP TABLE blueprint_cutover_manifest(payload jsonb) ON COMMIT DROP;
INSERT INTO blueprint_cutover_manifest VALUES({delimiter}{payload}{delimiter}::jsonb);
"""
    parity_source = sources['database/tests/canonical_mutation_source_parity_test.sql']
    # Reuse generated catalog expectations without installing test helpers in production.
    parity, assertions = re.subn(
        r" PERFORM assert_true\((.*),('(?:[^']|'')*')\);",
        lambda m: " IF NOT coalesce((" + m[1] + ") ,false) THEN RAISE EXCEPTION '%'," + m[2] + "; END IF;",
        parity_source)
    if not assertions or 'assert_true(' in parity:
        raise SystemExit('Unexpected generated parity assertion syntax')
    body = (preamble + sources[OPERATION] + '\nSELECT pg_temp.apply_blueprint_layout_cutover();\n'
            + sources[MIGRATION]
            + f"\nINSERT INTO supabase_migrations.schema_migrations(version,name) VALUES('{VERSION}','blueprint_canonical_storage_cutover');\n"
            + parity
            + "\nSELECT count(*) AS canonical_plans FROM eshop.blueprints WHERE layout->'schemaVersion'='2'::jsonb;\n")
    # The parity file is a read-only assertion, not a synthetic production fixture.
    if re.search(r'^\s*(BEGIN|COMMIT|ROLLBACK)\s*;',
                 sources['database/tests/canonical_mutation_source_parity_test.sql'], re.M | re.I):
        raise SystemExit('Parity assertion unexpectedly contains transaction control')
    evidence = {'sourceMainSha': args.source_sha, 'migrationVersion': VERSION,
                'database': args.database, 'scopeOrganizationIds': organizations,
                'blueprintIds': sorted(ids), 'plans': len(plans),
                'seatBindings': sum(len(p['seatBindings']) for p in plans),
                'inputSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'sources': {k: hashlib.sha256(v.encode()).hexdigest() for k, v in sources.items()}}
    for mode, ending in [('dry-run', 'ROLLBACK;'), ('apply', 'COMMIT;')]:
        data = (body + '\n' + ending + '\n').encode()
        target = directory / f'{mode}.sql'
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'wb') as output:
            output.write(data)
        os.chmod(target, 0o600)
        evidence[mode + 'Sha256'] = hashlib.sha256(data).hexdigest()
    receipt = directory / 'bundle.json'
    receipt.write_text(json.dumps(evidence, indent=2) + '\n')
    os.chmod(receipt, 0o600)
    print(f"Sealed {len(plans)} plans / {evidence['seatBindings']} bindings from {args.source_sha}")


if __name__ == '__main__':
    main()
