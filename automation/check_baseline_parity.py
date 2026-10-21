#!/usr/bin/env python3
"""Compare complete same-major disposable Supabase catalogs and baseline reference data."""
import argparse
import difflib
import hashlib
import json
import re
import subprocess
from pathlib import Path
from baseline import load_manifest, ROOT


def command(container, executable, *args):
    if not re.fullmatch(r'supabase_db_festapp[a-zA-Z0-9_-]*', container):
        raise ValueError('Only explicitly named local Festapp Supabase containers are accepted')
    return subprocess.check_output(['docker', 'exec', '-e', 'PGPASSWORD=postgres', container,
                                    executable, '-U', 'postgres', '-d', 'postgres', *args], text=True)


def sql(container, query):
    result = command(container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-Atqc',
                     "BEGIN READ ONLY; SET LOCAL statement_timeout='30s'; " + query + '; COMMIT;')
    return result.strip()


def schema(container):
    dump = command(container, 'pg_dump', '--schema-only', '--exclude-schema=supabase_migrations')
    # Only pg_dump session delimiters/version metadata are environment-specific.
    return '\n'.join(line for line in dump.splitlines() if not line.startswith(
        ('\\restrict', '\\unrestrict', '-- Dumped', '-- Started', '-- Completed'))) + '\n'


def sequence_values(container):
    names = json.loads(sql(container, "SELECT coalesce(json_agg(format('%I.%I',n.nspname,c.relname) ORDER BY n.nspname,c.relname),'[]'::json) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='S' AND n.nspname IN ('public','eshop')"))
    return {name: sql(container, f'SELECT last_value,is_called FROM {name}') for name in names}


def compare(left, right):
    versions = [sql(c, 'SHOW server_version_num') for c in [left, right]]
    if versions[0][:2] != versions[1][:2]:
        raise ValueError('Compare catalogs within the same PostgreSQL major')
    a, b = schema(left), schema(right)
    references = {}
    for table in load_manifest()['referenceTables']:
        if not re.fullmatch(r'(public|eshop|storage)\.[a-z_][a-z_0-9]*', table):
            raise ValueError('Invalid reference table')
        query = f"SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM {table} t"
        references[table] = sql(left, query) == sql(right, query)
    sequences = sequence_values(left) == sequence_values(right)
    report = {'postgres_versions': versions, 'schema_equal': a == b,
              'schema_sha256': [hashlib.sha256(s.encode()).hexdigest() for s in [a,b]],
              'reference_rows_equal': references, 'sequence_values_equal': sequences,
              'ignored_catalog_schema': 'supabase_migrations (ledger verified separately)'}
    return report, ''.join(difflib.unified_diff(a.splitlines(True), b.splitlines(True), fromfile=left, tofile=right))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--left', required=True)
    parser.add_argument('--right', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    report, diff = compare(args.left, args.right)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    if diff:
        args.report.with_suffix('.diff').write_text(diff)
    if not report['schema_equal'] or not report['sequence_values_equal'] or not all(report['reference_rows_equal'].values()):
        raise SystemExit('Baseline parity failed; see report')
    print('Baseline catalog, reference-data and sequence parity passed.')


if __name__ == '__main__':
    main()
