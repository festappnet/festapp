"""Actual PG17 transaction contract on an exact task-owned network-none clone.

Run explicitly with FESTAPP_ASSET_CUTOVER_PG17_TEST=1. No remote DB URL accepted.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'automation/image-migration'))
from storage_references import digest
spec = importlib.util.spec_from_file_location('sql_renderer', ROOT / 'automation/image-migration/render-cutover.py')
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)
DB = 'festapp_rehearsal_20260909220601'


@unittest.skipUnless(os.environ.get('FESTAPP_ASSET_CUTOVER_PG17_TEST') == '1', 'explicit isolated PG17 contract')
class PostgreSQLCutover(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pins = json.loads((ROOT / 'automation/hetzner-supabase/runtime/pins.json').read_text())
        image = pins['supabase']['images']['postgres']
        assert image.startswith('supabase/postgres:17.') and '@sha256:' in image
        cls.name = 'festapp-asset-cutover-test-' + uuid.uuid4().hex[:12]
        subprocess.run(['docker', 'run', '-d', '--name', cls.name, '--network', 'none', '--memory', '1g',
                        '--cpus', '1', '--pids-limit', '256', '--label', 'festapp.isolated-restore=true',
                        '-e', 'POSTGRES_PASSWORD=isolated-fixture-only', image], check=True, capture_output=True)
        cls.addClassCleanup(lambda: subprocess.run(['docker', 'rm', '-f', '-v', cls.name], capture_output=True))
        for _ in range(90):
            result = subprocess.run(['docker', 'exec', cls.name, 'psql', '-X', '-U', 'supabase_admin',
                                     '-d', 'postgres', '-Atqc', 'SELECT 1'], capture_output=True)
            logs = subprocess.check_output(['docker', 'logs', cls.name], stderr=subprocess.STDOUT)
            if result.returncode == 0 and b'PostgreSQL init process complete' in logs:
                break
            time.sleep(1)
        else:
            raise RuntimeError('isolated PostgreSQL did not initialize')
        actual = json.loads(subprocess.check_output(['docker', 'inspect', cls.name]))[0]
        assert actual['HostConfig']['NetworkMode'] == 'none' and not actual['HostConfig']['PortBindings']
        assert not any(m['Type'] == 'bind' for m in actual['Mounts'])

    def sql(self, source, check=True, database=DB):
        result = subprocess.run(['docker', 'exec', '-i', self.name, 'psql', '-X', '-U', 'postgres',
                                 '-d', database, '-qAtv', 'ON_ERROR_STOP=1'], input=source,
                                text=True, capture_output=True)
        if check and result.returncode:
            self.fail('Isolated SQL fixture failed: ' + result.stderr[-1200:])
        return result

    def setUp(self):
        self.sql('DROP DATABASE IF EXISTS ' + DB + '; CREATE DATABASE ' + DB + ';', database='postgres')
        # Restore the actual canonical commit owner and its table contracts.
        source = (ROOT / 'supabase/migrations/20260802234000_client_sync_v1_expansion.sql').read_text()
        foundation = (ROOT / 'automation/hetzner-supabase/rehearsal/prepare-source-staging-databases.sh').read_text()
        uid = re.search(r'CREATE FUNCTION auth\.uid\(\)[\s\S]*?;', foundation)
        assert uid, 'managed Auth foundation definition missing'
        tables = []
        for name in ['client_commits', 'client_sync_scopes', 'client_sync_private_scopes',
                     'client_commit_items', 'client_commit_components', 'client_projection_dirty_keys']:
            match = re.search(r'CREATE TABLE public\.' + name + r' \([\s\S]*?\n\);', source)
            assert match, name
            tables.append(match[0])
        functions = []
        for name in ['is_service_role', 'require_service_role', 'require_client_sync_service_role_v1', 'record_client_sync_commit_v1']:
            match = re.search(r'CREATE OR REPLACE FUNCTION public\.' + name + r'\([\s\S]*?\bAS\s+(\$\w*\$)[\s\S]*?\1\s*;', source)
            assert match, name
            functions.append(match[0])
        self.sql('''CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS extensions; CREATE SCHEMA storage; CREATE SCHEMA eshop;
CREATE TABLE public.organizations(id bigint PRIMARY KEY,title text); INSERT INTO public.organizations VALUES(3,'vstupenky.online');
CREATE TABLE public.occasions(id bigint PRIMARY KEY); INSERT INTO public.occasions VALUES(10);
CREATE TABLE public.user_info(id uuid PRIMARY KEY,name text,surname text);
CREATE TABLE public.occasion_users(occasion bigint,"user" uuid);
CREATE TABLE public.account_deletion_requests(id uuid PRIMARY KEY);
CREATE TABLE storage.objects(id uuid,bucket_id text,name text,owner_id text,metadata jsonb);
CREATE TABLE eshop.products(id bigint PRIMARY KEY,description text,data jsonb,icons text[],price numeric);
INSERT INTO eshop.products VALUES(1,'before','{"html":"before"}',ARRAY['before'],42);
''' + uid[0] + '\n' + '\n'.join(tables) + '\n' + '\n'.join(functions)
                 + '\n' + (ROOT / 'database/tables/canonical_assets.sql').read_text())
        self.sql("INSERT INTO public.client_sync_scopes(component,scope_type,scope_id) VALUES('content_catalog','occasion',10);")
        original = dict(id='11111111-1111-4111-8111-111111111111', bucket_id='public-files', name='fixture.pdf', owner_id=None, metadata={})
        self.sql("INSERT INTO storage.objects SELECT * FROM jsonb_populate_record(NULL::storage.objects,'" + json.dumps(original) + "'::jsonb);")
        self.bundle = dict(version=1, manifest_sha256='a' * 64, production_mutations=False,
                           requires_atomic_client_sync_publication=True,
                           registry=[dict(bucket='festapp-images', object_key='assets/storage/public-files/' + 'a' * 20 + '/' + 'b' * 64 + '/' + 'c' * 64,
                                          sha256='c' * 64, bytes=3, content_type='application/pdf', visibility='public', owner_id=None,
                                          source_bucket='public-files', source_key='fixture.pdf', source_storage_record=original,
                                          verified_at='2026-10-18T10:00:00Z')], edits=[])
        for field, before, after in [('description', 'before', "after'; COMMIT; --"), ('data', {'html': 'before'}, {'html': 'after'}),
                                     ('icons', ['before'], ['after', 'retained'])]:
            self.bundle['edits'].append(dict(schema='eshop', table='products', key={'id': 1}, field=field,
                                             original=before, original_digest=digest(before), replacement=after, replacement_digest=digest(after)))

    def apply(self, bundle=None):
        sql = renderer.render(bundle or self.bundle, (ROOT / 'automation/image-migration/apply-cutover.sql').read_text(), 'b' * 40)
        return self.sql(sql, check=False)

    def test_real_types_and_canonical_sync_commit_share_the_transaction(self):
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        row = json.loads(self.sql('SELECT row_to_json(t) FROM eshop.products t;').stdout)
        self.assertEqual(row['price'], 42)
        self.assertEqual(row['icons'], ['after', 'retained'])
        self.assertEqual(row['description'], "after'; COMMIT; --")
        self.assertEqual(self.sql('SELECT count(*) FROM public.canonical_assets;').stdout.strip(), '1')
        self.assertEqual(self.sql('SELECT count(*) FROM public.client_commits;').stdout.strip(), '1')
        self.assertEqual(self.sql('SELECT source_revision FROM public.client_sync_scopes;').stdout.strip(), '1')
        self.assertNotEqual(self.apply().returncode, 0, 'replaying a completed cutover must fail')

    def test_a_concurrent_field_edit_rolls_back_other_fields_registry_and_sync(self):
        self.sql("UPDATE eshop.products SET description='concurrent';")
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual(self.sql('SELECT count(*) FROM public.canonical_assets;').stdout.strip(), '0')
        self.assertEqual(self.sql('SELECT count(*) FROM public.client_commits;').stdout.strip(), '0')
        self.assertEqual(self.sql("SELECT data->>'html' FROM eshop.products;").stdout.strip(), 'before')

    def test_new_source_or_unknown_scope_refuses_the_whole_cutover(self):
        self.sql("INSERT INTO storage.objects(bucket_id,name) VALUES('public-files','newly-uploaded');")
        self.assertNotEqual(self.apply().returncode, 0)
        self.sql("DELETE FROM storage.objects WHERE name='newly-uploaded'; INSERT INTO public.client_sync_scopes(component,scope_type,scope_id) VALUES('unit_catalog','unit',99);")
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual(self.sql('SELECT count(*) FROM public.canonical_assets;').stdout.strip(), '0')
        self.assertEqual(self.sql('SELECT description FROM eshop.products;').stdout.strip(), 'before')

    def test_changed_source_ownership_refuses_every_mutation(self):
        self.sql("UPDATE storage.objects SET owner_id='22222222-2222-4222-8222-222222222222';")
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual(self.sql('SELECT count(*) FROM public.canonical_assets;').stdout.strip(), '0')
        self.assertEqual(self.sql('SELECT count(*) FROM public.client_commits;').stdout.strip(), '0')
        self.assertEqual(self.sql('SELECT description FROM eshop.products;').stdout.strip(), 'before')

    def test_private_revision_and_sync_failure_obey_same_transaction(self):
        user = '22222222-2222-4222-8222-222222222222'
        self.sql(f"INSERT INTO public.user_info(id) VALUES('{user}'); INSERT INTO public.occasion_users VALUES(10,'{user}'); "
                 f"INSERT INTO public.client_sync_private_scopes(component,occasion,user_id) VALUES('private_profile',10,'{user}');")
        self.assertEqual(self.apply().returncode, 0)
        self.assertEqual(self.sql('SELECT source_revision FROM public.client_sync_private_scopes;').stdout.strip(), '1')
        self.assertEqual(self.sql('SELECT count(*) FROM public.client_commit_components WHERE user_id IS NOT NULL;').stdout.strip(), '1')
        # Exercise a real failure from the canonical commit owner, after edits.
        self.setUp()
        self.sql("ALTER TABLE public.client_commits ADD CHECK(source<>'storage.r2.retirement');")
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual(self.sql('SELECT count(*) FROM public.canonical_assets;').stdout.strip(), '0')
        self.assertEqual(self.sql('SELECT count(*) FROM public.client_commits;').stdout.strip(), '0')
        self.assertEqual(self.sql('SELECT description FROM eshop.products;').stdout.strip(), 'before')


if __name__ == '__main__':
    unittest.main()
