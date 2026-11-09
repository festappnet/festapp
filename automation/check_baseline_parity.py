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
    return normalize_schema_dump(dump)


def normalize_schema_dump(dump):
    # Policy role arrays are unordered sets represented in OID order by pg_dump.
    dump = re.sub(r'(?m)^(CREATE POLICY [^\n]*? TO )([\w\" ,]+)(?= USING | WITH CHECK |;)',
                  lambda match: match[1] + ', '.join(sorted(role.strip() for role in match[2].split(','))), dump)
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
    unresolved = {}
    for table in load_manifest()['referenceTables']:
        if not re.fullmatch(r'(public|eshop|storage)\.[a-z_][a-z_0-9]*', table):
            raise ValueError('Invalid reference table')
        # regclass values in JSON are OIDs, which differ across equivalent
        # restores. Resolve typed relation identities; never ignore the column.
        columns = json.loads(sql(left, f"SELECT coalesce(json_agg(attname ORDER BY attnum),'[]'::json) FROM pg_attribute WHERE attrelid='{table}'::regclass AND atttypid='regclass'::regtype AND NOT attisdropped"))
        projection = 'to_jsonb(t)'
        for column in columns:
            if not re.fullmatch(r'[a-z_][a-z_0-9]*', column):
                raise ValueError('Unsupported reference column name')
            projection += f" || jsonb_build_object('{column}',t.{column}::text)"
            query = f"SELECT count(*) FROM {table} t WHERE t.{column} IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=t.{column})"
            unresolved[table + '.' + column] = {side: int(sql(container, query)) for side, container in [('left',left),('right',right)]}
        query = f"SELECT coalesce(jsonb_agg(value ORDER BY value::text),'[]'::jsonb) FROM (SELECT {projection} value FROM {table} t) rows"
        references[table] = sql(left, query) == sql(right, query)
    sequences = sequence_values(left) == sequence_values(right)
    ledger = sql(left, 'SELECT json_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations') == sql(right, 'SELECT json_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations')
    extensions = sql(left, 'SELECT jsonb_agg(row ORDER BY row::text) FROM (SELECT extname,extversion,extnamespace::regnamespace::text AS schema FROM pg_extension) row') == sql(right, 'SELECT jsonb_agg(row ORDER BY row::text) FROM (SELECT extname,extversion,extnamespace::regnamespace::text AS schema FROM pg_extension) row')
    role_query = "SELECT jsonb_agg(row ORDER BY row::text) FROM (SELECT rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconnlimit,rolvaliduntil,rolconfig FROM pg_roles WHERE rolname !~ '^pg_') row"
    roles = sql(left,role_query) == sql(right,role_query)
    membership_query = "SELECT jsonb_agg(row ORDER BY row::text) FROM (SELECT (to_jsonb(m)-'roleid'-'member'-'grantor'-'oid') || jsonb_build_object('role',pg_get_userbyid(roleid),'member',pg_get_userbyid(member),'grantor',pg_get_userbyid(grantor)) row FROM pg_auth_members m) rows"
    memberships = sql(left,membership_query) == sql(right,membership_query)
    disabled_cron = all(sql(container,'SHOW cron.launch_active_jobs')=='off' for container in (left,right))
    report = {'roles_equal':roles,'role_memberships_equal':memberships,'cron_disabled_both':disabled_cron,'ledger_equal': ledger, 'extensions_equal': extensions, 'postgres_versions': versions, 'schema_equal': a == b,
              'schema_sha256': [hashlib.sha256(s.encode()).hexdigest() for s in [a,b]],
              'reference_rows_equal': references, 'unresolved_reference_counts': unresolved, 'sequence_values_equal': sequences,
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
    if any(count for sides in report['unresolved_reference_counts'].values() for count in sides.values()) or not report['roles_equal'] or not report['role_memberships_equal'] or not report['cron_disabled_both'] or not report['ledger_equal'] or not report['extensions_equal'] or not report['schema_equal'] or not report['sequence_values_equal'] or not all(report['reference_rows_equal'].values()):
        raise SystemExit('Baseline parity failed; see report')
    print('Baseline catalog, reference-data and sequence parity passed.')


if __name__ == '__main__':
    main()
