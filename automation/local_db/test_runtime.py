"""Unit and opt-in real PostgreSQL lifecycle contracts."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import runtime


class RuntimeIdentityTest(unittest.TestCase):
    def test_seed_includes_and_validation_policy_invalidate_the_base(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve()
            for source in runtime.core_sources(runtime.ROOT):
                target=root/source.relative_to(runtime.ROOT)
                target.parent.mkdir(parents=True,exist_ok=True)
                # Preserve the two declarations that resolve other inputs;
                # all other fixture bytes are sufficient for fingerprinting.
                target.write_bytes(source.read_bytes() if source.name in ('seed_demo_occasions.sql','canonical-source-contract.json') else b'fixture')
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

    def test_remote_environment_never_selects_the_runtime_target(self):
        with patch.dict(os.environ,{'DATABASE_URL':'postgresql://invalid:invalid@production.invalid/postgres'}):
            self.assertIn('@127.0.0.1:',runtime.Runtime().url())


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
            tail.write_text('CREATE TABLE public.runtime_checkpoint_probe(id bigint);\n')
            with self.db.locked(): result=self.db.prepare()
            self.assertEqual(result['mode'],'checkpoint-tail')
            self.assertEqual(self.db.sql("SELECT to_regclass('public.runtime_checkpoint_probe') IS NOT NULL",capture=True).strip(),b't')
            ledger=self.db.sql("SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='29991231235959'",capture=True)
            self.assertEqual(ledger.strip(),b'1')
        finally: tail.unlink(missing_ok=True)
        with self.db.locked(): self.assertEqual(self.db.prepare()['fingerprint'],original[0])


if __name__=='__main__': unittest.main()
