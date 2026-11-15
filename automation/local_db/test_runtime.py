"""Unit and opt-in real PostgreSQL lifecycle contracts."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import runtime
from local_db import images


class ImageResolutionTest(unittest.TestCase):
    image = 'public.ecr.aws/supabase/postgres:15.8.1.085@sha256:' + 'a' * 64

    def test_cached_pin_needs_no_registry_download(self):
        with patch.object(images.subprocess,'check_output',return_value=b'[{"Id":"same-content"}]'), \
             patch.object(images.subprocess,'run') as pull:
            self.assertEqual(images.resolve(self.image)[0],self.image)
            pull.assert_not_called()

    def test_cached_mirror_needs_no_registry_download(self):
        mirror=self.image.replace('public.ecr.aws/','docker.io/',1)
        def inspect(command,**kwargs):
            if command[-1]==self.image:raise subprocess.CalledProcessError(1,command)
            return b'[{"Id":"same-content"}]'
        with patch.object(images.subprocess,'check_output',side_effect=inspect), \
             patch.object(images.subprocess,'run') as pull:
            self.assertEqual(images.resolve(self.image)[0],mirror)
            pull.assert_not_called()

    def test_quota_failure_uses_only_the_identical_pinned_official_mirror(self):
        mirror=self.image.replace('public.ecr.aws/','docker.io/',1)
        downloaded=set()
        def inspect(command,**kwargs):
            if command[-1] not in downloaded:
                raise subprocess.CalledProcessError(1,command)
            return b'[{"Id":"same-content"}]'
        def pull(command,**kwargs):
            if command[-1]==self.image:
                return subprocess.CompletedProcess(command,1,stderr='Data limit exceeded')
            downloaded.add(command[-1])
            return subprocess.CompletedProcess(command,0)
        with patch.object(images.subprocess,'check_output',side_effect=inspect), \
             patch.object(images.subprocess,'run',side_effect=pull) as calls:
            self.assertEqual(images.resolve(self.image),(mirror,{'Id':'same-content'}))
            self.assertEqual([c.args[0] for c in calls.call_args_list],
                             [['docker','pull',self.image],['docker','pull',mirror]])

    def test_both_registries_unavailable_remains_a_failure(self):
        with patch.object(images.subprocess,'check_output',side_effect=subprocess.CalledProcessError(1,'inspect')), \
             patch.object(images.subprocess,'run',return_value=subprocess.CompletedProcess([],1)):
            with self.assertRaisesRegex(RuntimeError,'approved registries'):
                images.resolve(self.image)

    def test_mutable_tags_and_unapproved_registry_mirrors_are_rejected(self):
        with self.assertRaisesRegex(ValueError,'pinned by digest'):
            images.references('public.ecr.aws/supabase/postgres:latest')
        foreign='registry.invalid/postgres:15@sha256:'+'a'*64
        self.assertEqual(images.references(foreign),[foreign])


class RuntimeIdentityTest(unittest.TestCase):
    def test_seed_includes_and_validation_policy_invalidate_the_base(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve()
            for source in runtime.core_sources(runtime.ROOT):
                target=root/source.relative_to(runtime.ROOT)
                target.parent.mkdir(parents=True,exist_ok=True)
                # Preserve the two declarations that resolve other inputs;
                # all other fixture bytes are sufficient for fingerprinting.
                target.write_bytes(source.read_bytes() if (source.name in ('seed_demo_occasions.sql','canonical-source-contract.json') or source.name.endswith('_reference_seed.sql')) else b'fixture')
            artwork=root/'database/fixtures/demo_occasions/artwork.sql'
            artwork.write_text('\\ir nested.sql\n')
            nested=artwork.with_name('nested.sql');nested.write_text('SELECT 1;')
            instance=object.__new__(runtime.Runtime);instance.profile='demo'
            def tool(command,**kwargs):
                if command[:3]==['docker','image','inspect']:
                    return b'[{"Id":"fixture-image","Os":"linux","Architecture":"arm64"}]'
                return 'fixture-tool'
            with patch.object(runtime,'ROOT',root),patch.object(runtime.subprocess,'check_output',side_effect=tool):
                for relative in ('database/fixtures/demo_occasions/nested.sql',
                                 'automation/generate_canonical_source_contract.py',
                                 'automation/canonical-source-contract.json',
                                 'database/tests/helpers/assertions.sql',
                                 'database/tests/canonical_mutation_source_parity_test.sql'):
                    with self.subTest(input=relative):
                        path=root/relative;original=path.read_bytes();before=instance.identity()
                        try:
                            path.write_bytes(original+b'\n ')
                            changed=instance.identity()
                            self.assertNotEqual(before[0],changed[0])
                            self.assertNotEqual(before[1],changed[1])
                        finally:path.write_bytes(original)

    def test_nested_sql_include_streams_exact_content_and_rejects_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve()
            (root/'seed').mkdir()
            seed=root/'seed/main.sql';nested=root/'seed/nested.sql'
            seed.write_text("SELECT 1;\n\\ir nested.sql\nSELECT 3;\n")
            nested.write_text('SELECT 2;\n')
            self.assertEqual(runtime.sql_content(root,seed),'SELECT 1;\nSELECT 2;\nSELECT 3;\n')
            nested.write_text('\\ir ../../outside.sql\n')
            with self.assertRaises(ValueError):runtime.sql_content(root,seed)

    def test_same_name_content_rewrite_invalidates_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'migration.sql';source.write_text('SELECT 1;')
            before=runtime.content_digest([source],root)
            source.write_text('SELECT 2;')
            self.assertNotEqual(before,runtime.content_digest([source],root))

    def test_unowned_container_and_loopback_tunnel_are_rejected(self):
        instance=runtime.Runtime()
        data={'Config':{'Labels':{}},'HostConfig':{'PortBindings':{'5432/tcp':[{'HostIp':'127.0.0.1','HostPort':str(instance.port)}]}}}
        result=subprocess.CompletedProcess([],0,json.dumps([data]))
        with patch.object(runtime.subprocess,'run',return_value=result):
            with self.assertRaisesRegex(ValueError,'not owned'): instance.inspect()
        data['Config']['Labels']={runtime.LABEL:runtime.VERSION}
        data['HostConfig']['PortBindings']['5432/tcp'][0]['HostPort']='54321'
        result.stdout=json.dumps([data])
        with patch.object(runtime.subprocess,'run',return_value=result):
            with self.assertRaisesRegex(ValueError,'exact loopback'): instance.inspect()

    def test_mirror_container_requires_the_same_pinned_provider_digest(self):
        instance=runtime.Runtime()
        mirror=images.references(runtime.CONFIG['image'])[1]
        command=['postgres','-D','/etc/postgresql',
                 *[arg for k,v in runtime.CONFIG['settings'].items() for arg in ('-c',k+'='+v)]]
        data={'Config':{'Labels':{runtime.LABEL:runtime.VERSION},'Image':mirror,'Cmd':command},
              'HostConfig':{'PortBindings':{'5432/tcp':[{'HostIp':'127.0.0.1','HostPort':str(instance.port)}]}}}
        result=subprocess.CompletedProcess([],0,json.dumps([data]))
        with patch.object(runtime.subprocess,'run',return_value=result):
            self.assertEqual(instance.inspect()['Config']['Image'],mirror)
            data['Config']['Image']=mirror.split('@')[0]+'@sha256:'+'0'*64
            result.stdout=json.dumps([data])
            with self.assertRaisesRegex(ValueError,'image/provider major mismatch'):
                instance.inspect()

    def test_remote_environment_never_selects_the_runtime_target(self):
        with patch.dict(os.environ,{'DATABASE_URL':'postgresql://invalid:invalid@production.invalid/postgres'}):
            self.assertIn('@127.0.0.1:',runtime.Runtime().url())


    def test_incremental_upgrade_restores_role_on_first_pending_migration(self):
        baseline = runtime.baseline
        for resumed in [False, True]:
            with self.subTest(resumed=resumed), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / 'history.json').write_text(json.dumps({'originalBaselineVersion': '20260805230000'}))
                migrations = root / 'supabase/migrations'
                migrations.mkdir(parents=True)
                names = ['20261108000000_first.sql', '20261109000000_tail.sql']
                for name in names:
                    (migrations / name).write_text('SELECT current_user;')
                kit = root / 'kit'
                (kit / 'supabase/migrations').mkdir(parents=True)
                config = {'historicalSources': {'path': 'history.json'},
                          'coveredThrough': '20261107170000',
                          'forwardMigrationRole': 'supabase_admin'}
                recorded = '20260805230000\n' + ('20261108000000\n' if resumed else '')
                def migrate(*args, **kwargs):
                    staged = kit / 'supabase/migrations'
                    pending = names[1] if resumed else names[0]
                    self.assertEqual((staged / pending).read_text(),
                                     'SET ROLE supabase_admin;\nSELECT current_user;')
                    if resumed:
                        self.assertEqual((staged / names[0]).read_text(), 'SELECT current_user;')
                with patch.object(baseline, 'load_manifest', return_value=config), \
                     patch.object(baseline, 'covered_migrations', return_value=[{'version': '20260805230000'}]), \
                     patch.object(baseline, 'materialize_history', return_value=kit), \
                     patch.object(baseline.subprocess, 'check_output', side_effect=[
                         'supabase_db_festapp-fixture 127.0.0.1:55432->5432/tcp', recorded]), \
                     patch.object(baseline.subprocess, 'run', side_effect=migrate):
                    baseline.upgrade_local('postgresql://supabase_admin:postgres@127.0.0.1:55432/postgres', root)

@unittest.skipUnless(os.environ.get('FESTAPP_RUNTIME_INTEGRATION')=='1','explicit disposable runtime required')
class RuntimeLifecycleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db=runtime.Runtime()
        with cls.db.locked(): cls.db.prepare()

    def test_two_leases_are_isolated_and_released_without_stopping_foreign_sessions(self):
        with self.db.workspace() as first,self.db.workspace() as second:
            self.assertNotEqual(first['database'],second['database'])
            self.db.sql('CREATE TABLE festapp_test_support.lease_probe(value int); INSERT INTO festapp_test_support.lease_probe VALUES(42);',database=first['database'])
            self.assertEqual(self.db.sql("SELECT to_regclass('festapp_test_support.lease_probe') IS NULL",database=second['database'],capture=True).strip(),b't')
            with self.assertRaisesRegex(ValueError,'Leased'): self.db.stop()
        with self.db.workspace() as clean:
            self.assertEqual(self.db.sql("SELECT to_regclass('festapp_test_support.lease_probe') IS NULL",database=clean['database'],capture=True).strip(),b't')

    def test_live_connection_blocks_release_and_marker_corruption_fails_closed(self):
        with self.db.workspace() as lease:
            client=subprocess.Popen(['psql',lease['databaseUrl'],'-X','-Atq'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
            client.stdin.write("SELECT 'ready';\n");client.stdin.flush()
            self.assertEqual(client.stdout.readline().strip(),'ready')
            try:
                with self.assertRaisesRegex(ValueError,'Active client'): self.db.release(lease['runId'])
            finally: client.communicate('\\q\n',timeout=10)
            self.db.sql('COMMENT ON DATABASE '+lease['database']+" IS 'wrong-marker';",database='template1')
            try:
                with self.assertRaisesRegex(ValueError,'marker mismatch'): self.db.release(lease['runId'])
            finally:
                self.db.sql('COMMENT ON DATABASE '+lease['database']+" IS '"+lease['runId']+':'+lease['fingerprint']+"';",database='template1')

    def test_dead_owner_clone_is_pruned_but_live_owner_is_retained(self):
        dead=subprocess.Popen(['sleep','30'])
        with self.db.locked(): lease=self.db.acquire(dead.pid)
        self.db.prune(0)
        self.assertTrue((self.db.cache/('lease-'+lease['runId']+'.json')).exists())
        dead.terminate();dead.wait()
        with self.db.locked(): self.db.prune(0)
        self.assertFalse((self.db.cache/('lease-'+lease['runId']+'.json')).exists())

    def test_publication_crash_never_publishes_a_usable_template(self):
        name='festapp_base_'+'f'*40;marker=runtime.VERSION+':'+'f'*64
        original=self.db.sql
        def fail_comment(sql=None,**kwargs):
            if sql and sql.startswith('COMMENT ON DATABASE '+name): raise RuntimeError('injected publication crash')
            return original(sql,**kwargs)
        with patch.object(self.db,'sql',side_effect=fail_comment):
            with self.assertRaisesRegex(RuntimeError,'injected'): self.db.publish(name,marker)
        with self.assertRaisesRegex(ValueError,'marker/fence'): self.db.template_exists(name,marker)
        self.db.recover_publications()
        self.assertFalse(self.db.template_exists(name,marker))

    def test_append_only_checkpoint_applies_real_tail_and_old_migration_edit_invalidates(self):
        original=self.db.identity()
        older=runtime.ROOT/'supabase/migrations'/original[2][0]['name']
        content=older.read_bytes()
        try:
            older.write_bytes(content+b'\n-- fingerprint invalidation probe\n')
            changed=self.db.identity()
            self.assertNotEqual(original[0],changed[0])
            self.assertNotEqual(original[2][0],changed[2][0])
        finally: older.write_bytes(content)
        tail=runtime.ROOT/'supabase/migrations/29991231235959_runtime_checkpoint_probe.sql'
        self.assertFalse(tail.exists())
        try:
            tail.write_text(
                "DO $$ BEGIN EXECUTE pg_get_functiondef("
                "'public.get_or_create_scan_code(text,boolean)'::regprocedure); END $$;\n"
                'CREATE TABLE public.runtime_checkpoint_probe(id bigint);\n')
            with self.db.locked(): result=self.db.prepare()
            self.assertEqual(result['mode'],'checkpoint-tail')
            self.assertEqual(self.db.sql("SELECT to_regclass('public.runtime_checkpoint_probe') IS NOT NULL",capture=True).strip(),b't')
            ledger=self.db.sql("SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='29991231235959'",capture=True)
            self.assertEqual(ledger.strip(),b'1')
        finally: tail.unlink(missing_ok=True)
        with self.db.locked(): self.assertEqual(self.db.prepare()['fingerprint'],original[0])


if __name__=='__main__': unittest.main()
