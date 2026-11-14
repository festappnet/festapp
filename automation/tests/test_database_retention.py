"""Actual PostgreSQL17 retention and encrypted dump/restore in an isolated clone."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).parents[1] / 'hetzner-supabase/maintenance'


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


retention = load('test_db_retention', 'database-retention.py')
cleanup = load('test_db_cleanup', 'database-cleanup.py')
IMAGE = 'public.ecr.aws/supabase/postgres:17.6.1.156'


class DatabaseMaintenanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.container = 'festapp-maintenance-test-' + uuid.uuid4().hex[:10]
        try:
            cls.command('docker', 'run', '-d', '--name', cls.container, '--network', 'none',
                        '--memory', '512m', '--cpus', '1', '--user', 'postgres', '--entrypoint', 'sh',
                        IMAGE, '-c', 'sleep 1800')
            cls.command('docker', 'exec', cls.container, 'initdb', '-D', '/tmp/test-pg',
                        '-U', 'postgres', '--auth=trust', '--no-locale', '--encoding=UTF8')
            cls.command('docker', 'exec', cls.container, 'pg_ctl', '-D', '/tmp/test-pg',
                        '-l', '/tmp/test-pg.log', '-o',
                        "-c listen_addresses='' -c unix_socket_directories=/tmp -c port=55439 "
                        "-c shared_preload_libraries=pg_net,pgaudit,pg_stat_statements,supabase_vault "
                        "-c pg_net.database_name=retirement_network_disabled", '-w', 'start')
            cls.query('CREATE ROLE retirement_restore_admin SUPERUSER LOGIN;')
        except Exception:
            subprocess.run(['docker', 'rm', '-f', '-v', cls.container], capture_output=True)
            raise

    @classmethod
    def tearDownClass(cls):
        cls.command('docker', 'rm', '-f', '-v', cls.container)

    @staticmethod
    def command(*args, input=None):
        return subprocess.run(args, input=input, text=True, capture_output=True, check=True).stdout.strip()

    @classmethod
    def query(cls, statement, database='postgres'):
        return cls.command('docker', 'exec', '-i', cls.container, 'psql', '-X', '-h', '/tmp',
                           '-p', '55439', '-U', 'postgres', '-d', database, '-Atq',
                           '-v', 'ON_ERROR_STOP=1', input=statement)

    def setUp(self):
        self.database = 'maintenance_case_' + uuid.uuid4().hex[:8]
        self.query('CREATE DATABASE ' + self.database + ';')
        self.addCleanup(lambda: self.query('DROP DATABASE ' + self.database + ';'))

    def test_required_supabase_extension_installs_with_network_worker_fenced(self):
        self.query('CREATE EXTENSION pg_net;', self.database)
        self.assertEqual(self.query("SELECT current_setting('pg_net.database_name')", self.database), 'retirement_network_disabled')
        self.assertEqual(self.query("SELECT count(*) FROM pg_database WHERE datname='retirement_network_disabled'"), '0')
        self.assertEqual(self.query("SELECT count(*) FROM pg_stat_activity WHERE backend_type LIKE 'pg_net%' AND datname='" + self.database + "'"), '0')

    def test_clone_roles_restore_names_without_login_or_membership_privileges(self):
        name = 'clone_role_' + uuid.uuid4().hex[:8]
        original = (f'CREATE ROLE {name};\nALTER ROLE {name} WITH SUPERUSER LOGIN;\n'
                    f'GRANT postgres TO {name} GRANTED BY missing_grantor;\n').encode()
        self.query(cleanup.clone_roles(original).decode())
        self.addCleanup(lambda: self.query('DROP ROLE ' + name))
        self.assertEqual(self.query("SELECT rolcanlogin::text||'|'||rolsuper::text FROM pg_roles WHERE rolname='" + name + "'"), 'false|false')
        self.assertEqual(self.query("SELECT pg_has_role('" + name + "','postgres','MEMBER')"), 'f')

    def test_retirement_inventory_query_is_valid_on_real_catalogs(self):
        def execute(database, statement, **kwargs):
            return self.query(statement, self.database)
        expected = int(self.query("SELECT oid FROM pg_database WHERE datname='" + self.database + "'"))
        with patch.object(cleanup, 'sql', side_effect=execute), patch.object(cleanup, 'OLD', {self.database: expected}):
            facts = cleanup.retirement_inventory()
            self.assertEqual(len(facts), 1)
            self.assertEqual(facts[0]['datname'], self.database)
            self.assertIsInstance(facts[0]['oid'], int)
            self.assertEqual(facts[0]['oid'], expected)

    def test_real_sql_retains_recent_security_failures_and_inflight_rows(self):
        self.query("""
CREATE SCHEMA cron; CREATE SCHEMA auth;
CREATE TABLE cron.job_run_details(id int,status text,end_time timestamptz);
INSERT INTO cron.job_run_details VALUES
(1,'succeeded',now()-interval '8 days'),(2,'failed',now()-interval '8 days'),
(3,'failed',now()-interval '91 days'),(4,'succeeded',now()-interval '1 day'),
(5,'running',now()-interval '100 days'),(6,'succeeded',NULL);
CREATE TABLE public.log_app_config(id int,created_at timestamptz);
INSERT INTO public.log_app_config VALUES(1,now()-interval '100 days'),(2,now());
CREATE TABLE auth.audit_log_entries(id int,created_at timestamptz);
INSERT INTO auth.audit_log_entries VALUES(1,now()-interval '400 days'),(2,now()-interval '100 days');
""", self.database)
        for relation in ('events','information','news','email_messages','client_commit_components','client_sync_private_scopes'):
            self.query('CREATE TABLE public.' + relation + '(id int)', self.database)
        self.query('CREATE TABLE auth.refresh_tokens(id int)', self.database)
        def execute(database, statement, **kwargs):
            return self.query(statement, self.database)
        results = retention.prune(execute)
        self.assertEqual([r['removed'] for r in results], [1, 1, 1, 1])
        self.assertEqual(self.query('SELECT string_agg(id::text,\',\' ORDER BY id) FROM cron.job_run_details', self.database), '2,4,5,6')
        self.assertEqual(self.query('SELECT id FROM public.log_app_config', self.database), '2')
        self.assertEqual(self.query('SELECT id FROM auth.audit_log_entries', self.database), '2')

    def test_live_row_lock_is_skipped_without_terminating_other_session(self):
        self.query('CREATE TABLE public.log_app_config(id int,created_at timestamptz); '
                   "INSERT INTO public.log_app_config VALUES(1,now()-interval '100 days'),(2,now()-interval '100 days');", self.database)
        args = ['docker','exec','-i',self.container,'psql','-X','-h','/tmp','-p','55439','-U','postgres',
                '-d',self.database,'-Atq','-v','ON_ERROR_STOP=1']
        locked = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            locked.stdin.write('BEGIN; SELECT id FROM public.log_app_config WHERE id=1 FOR UPDATE;\n')
            locked.stdin.flush()
            self.assertEqual(locked.stdout.readline().strip(), '1')
            deleted = self.query(retention.delete_sql('public.log_app_config', "created_at<now()-interval '90 days'"), self.database)
            self.assertEqual(deleted, '1')
            self.assertIsNone(locked.poll())
        finally:
            locked.stdin.write('ROLLBACK;\n')
            locked.stdin.close()
            locked.wait(timeout=10)
            locked.stdout.close()
            locked.stderr.close()
        self.assertEqual(self.query('SELECT id FROM public.log_app_config', self.database), '1')

    @unittest.skipUnless(shutil.which('age') and shutil.which('age-keygen'), 'age required')
    def test_identical_dump_stream_is_encrypted_and_really_restored(self):
        self.query("CREATE TABLE proof(id int PRIMARY KEY,body text); INSERT INTO proof VALUES (1,'restore proof');", self.database)
        self.query('CREATE DATABASE verify_retired;')
        self.addCleanup(lambda: self.query('DROP DATABASE verify_retired;'))
        with tempfile.TemporaryDirectory() as tmp:
            key = Path(tmp) / 'identity'
            subprocess.run(['age-keygen', '-o', str(key)], capture_output=True, check=True)
            recipient = subprocess.check_output(['age-keygen', '-y', str(key)], text=True).strip()
            archive = Path(tmp) / 'backup.age'
            # Source uses its own isolated socket/port via normal libpq env.
            original_popen = subprocess.Popen
            def popen(args, **kwargs):
                if args[:3] == ['docker', 'exec', self.container] and 'pg_dump' in args:
                    args = args[:2] + ['-e', 'PGHOST=/tmp', '-e', 'PGPORT=55439'] + args[2:]
                return original_popen(args, **kwargs)
            with patch.object(cleanup.subprocess, 'Popen', side_effect=popen), patch.object(cleanup, 'STATE', Path(tmp)):
                cleanup.dump_and_restore(self.database, self.container, archive, recipient, source_container=self.container, source_user='postgres')
            self.assertEqual(self.query('SELECT body FROM proof', 'verify_retired'), 'restore proof')
            decoded = subprocess.run(['age','-d','-i',str(key),str(archive)], capture_output=True, check=True).stdout
            self.assertTrue(decoded.startswith(b'PGDMP'))


if __name__ == '__main__':
    unittest.main()
