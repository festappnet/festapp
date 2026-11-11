"""Recovery and populated-upgrade invariants at the baseline compaction boundary."""
import gzip
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1]))
import baseline
from historical_inputs import read_source
import migration_inputs


class MigrationCompactionTest(unittest.TestCase):
    def test_compressed_history_preserves_bytes_and_rejects_corruption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / 'automation/historical-inputs'
            (directory / 'objects').mkdir(parents=True)
            content = 'SELECT \'Příliš\';\r\n'.encode()
            digest = hashlib.sha256(content).hexdigest()
            (directory / 'manifest.json').write_text(json.dumps({
                'schemaVersion': 1, 'snapshots': {'revision': {'old.sql': digest}}}))
            blob = directory / 'objects' / (digest + '.gz')
            blob.write_bytes(gzip.compress(content, mtime=0))
            self.assertEqual(read_source('revision', 'old.sql', root=root), content)
            blob.write_bytes(gzip.compress(b'SELECT changed;', mtime=0))
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                read_source('revision', 'old.sql', root=root)

    def test_covered_migration_cannot_be_regenerated(self):
        path = baseline.ROOT / 'supabase/migrations/20261106120000_payment_provider_connectors.sql'
        with self.assertRaisesRegex(ValueError, 'immutable'):
            migration_inputs.write_text(path, 'SELECT changed;')

    def test_compacted_forward_restores_its_recorded_execution_role(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/'history.json').write_text(json.dumps({'originalBaselineVersion':'20260805230000'}))
            active=root/'supabase/migrations';active.mkdir(parents=True)
            first=active/'20261109121500_first.sql';first.write_text('SELECT 1;')
            second=active/'20261110040000_second.sql';second.write_text('SELECT 2;')
            kit=root/'kit';(kit/'supabase/migrations').mkdir(parents=True)
            config={'coveredThrough':'20261107170000','forwardMigrationRole':'supabase_admin',
                    'historicalSources':{'path':'history.json'}}
            executions=[]
            def execute(*args,**kwargs):
                executions.append([(kit/'supabase/migrations'/p.name).read_text() for p in [first,second]])
            with patch.object(baseline,'load_manifest',return_value=config), \
                 patch.object(baseline,'covered_migrations',return_value=[{'version':'20260805230000'}]), \
                 patch.object(baseline,'materialize_history',return_value=kit), \
                 patch.object(baseline.subprocess,'check_output',side_effect=[
                     'supabase_db_festapp-fixture 127.0.0.1:55432->5432/tcp','20260805230000\n']), \
                 patch.object(baseline.subprocess,'run',side_effect=execute):
                baseline.upgrade_local('postgresql://supabase_admin:postgres@127.0.0.1:55432/postgres',root)
            self.assertEqual(executions,[['SET ROLE supabase_admin;\nSELECT 1;','SELECT 2;']])
            self.assertEqual(first.read_text(),'SELECT 1;')

    def test_populated_upgrade_stages_covered_contract_after_backfill(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'history.json').write_text(json.dumps({'originalBaselineVersion': '20260805230000'}))
            (root / 'supabase/migrations').mkdir(parents=True)
            kit = root / 'kit'
            historical = kit / 'supabase/migrations'
            historical.mkdir(parents=True)
            prerequisite = '20261006130000_prepare.sql'
            contract = '20261006131000_contract.sql'
            for name in [prerequisite, contract]:
                (historical / name).write_text('SELECT 1;')
            config = {'coveredThrough': '20261107170000',
                      'historicalSources': {'path': 'history.json'},
                      'upgradeStages': [{'beforeVersion': '20261006131000',
                                         'remainingQuery': 'SELECT remaining',
                                         'backfill': {'path': 'backfill.sql'}}]}
            events = []
            def execute(command, **kwargs):
                events.append(('backfill' if command[0] == 'psql' else 'migrate',
                               sorted(p.name for p in (kit / 'supabase/migrations').glob('*.sql'))))
            with patch.object(baseline, 'load_manifest', return_value=config), \
                 patch.object(baseline, 'covered_migrations', return_value=[{'version': '20260805230000'}]), \
                 patch.object(baseline, 'materialize_history', return_value=kit), \
                 patch.object(baseline.subprocess, 'check_output', side_effect=[
                     'supabase_db_festapp-fixture 127.0.0.1:55432->5432/tcp',
                     '20260805230000\n', '1', '0']), \
                 patch.object(baseline.subprocess, 'run', side_effect=execute):
                baseline.upgrade_local('postgresql://supabase_admin:postgres@127.0.0.1:55432/postgres', root)
            self.assertEqual(events, [('migrate', [prerequisite]),
                                      ('backfill', [prerequisite]),
                                      ('migrate', [prerequisite, contract])])


if __name__ == '__main__':
    unittest.main()
