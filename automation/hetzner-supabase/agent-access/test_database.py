"""Explicit opt-in; synthetic database on the documented local test cluster only."""
import os
from pathlib import Path
import subprocess
import unittest

BASE = 'postgresql://postgres:postgres@127.0.0.1:55432/'
DATABASE = 'festapp_rehearsal_20260909220601'
ROLE = 'festapp_agent_diagnostics'


def sql(database, statement, as_agent=False):
    return subprocess.run(['psql', (BASE.replace('postgres:postgres@', ROLE + ':synthetic-local-password@') if as_agent else BASE) + database + '?sslmode=disable', '-XqAt',
                           '-v', 'ON_ERROR_STOP=1', '-c', statement],
                          capture_output=True, text=True, timeout=10)


@unittest.skipUnless(os.environ.get('FESTAPP_AGENT_LOCAL_DB_TEST') == '1', 'local database opt-in required')
class DatabaseTests(unittest.TestCase):
    def test_isolated_role_and_bounded_views(self):
        absent = sql('postgres', f"SELECT (SELECT count(*) FROM pg_database WHERE datname='{DATABASE}') + (SELECT count(*) FROM pg_roles WHERE rolname='{ROLE}')")
        self.assertEqual(absent.returncode, 0, 'local cluster unavailable')
        self.assertEqual(absent.stdout.strip(), '0', 'refusing to touch existing database or role')
        self.assertEqual(sql('postgres', f'CREATE DATABASE {DATABASE}').returncode, 0)
        try:
            fixture = '''CREATE TABLE public.organizations(id bigint PRIMARY KEY);
              INSERT INTO public.organizations VALUES(1),(2);
              CREATE TABLE public.agent_test_private(secret text);
              CREATE SCHEMA supabase_migrations;
              CREATE TABLE supabase_migrations.schema_migrations(version text);
              INSERT INTO supabase_migrations.schema_migrations SELECT n::text FROM generate_series(1,60) n;'''
            self.assertEqual(sql(DATABASE, fixture).returncode, 0)
            installation = Path(__file__).with_name('diagnostics.sql').read_text()
            self.assertNotEqual(sql('postgres', 'BEGIN; ' + installation + ' COMMIT;').returncode, 0)
            applied = sql(DATABASE, 'BEGIN; ' + installation + ' COMMIT;')
            self.assertEqual(applied.returncode, 0, applied.stderr)
            self.assertEqual(sql(DATABASE, f"ALTER ROLE {ROLE} PASSWORD 'synthetic-local-password'").returncode, 0)
            probe = sql(DATABASE, 'SELECT organization FROM agent_operations.identity; SELECT count(*) FROM agent_operations.migrations;', as_agent=True)
            self.assertEqual(probe.returncode, 0, probe.stderr)
            self.assertEqual(probe.stdout.strip(), '1\n50')
            for denied in ['SELECT * FROM public.agent_test_private',
                           'SELECT * FROM public.organizations',
                           'INSERT INTO public.organizations VALUES(3)',
                           'UPDATE agent_operations.identity SET organization=2',
                           'CREATE TABLE public.agent_test_illegal(id int)']:
                self.assertNotEqual(sql(DATABASE, denied, as_agent=True).returncode, 0)
        finally:
            sql('postgres', f'DROP DATABASE {DATABASE}')
            sql('postgres', f'DROP ROLE IF EXISTS {ROLE}')


if __name__ == '__main__':
    unittest.main()
