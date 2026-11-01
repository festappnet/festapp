import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('baseline', Path(__file__).parents[1] / 'baseline.py')
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)


class BaselineContractTest(unittest.TestCase):
    def test_recovered_inputs_match_frozen_git_objects_after_active_source_removal(self):
        import hashlib
        import json
        config = baseline.load_manifest()
        history = json.loads((baseline.ROOT / config['historicalSources']['path']).read_text())
        with tempfile.TemporaryDirectory() as temporary:
            kit = baseline.materialize_history(Path(temporary), include_email=True)
            for entry in history['files'] + history['emailUpgradeFiles']:
                self.assertEqual(hashlib.sha256((kit / entry['path']).read_bytes()).hexdigest(), entry['sha256'])

    def test_recovery_refuses_to_clobber_existing_evidence(self):
        import json
        config = baseline.load_manifest()
        history = json.loads((baseline.ROOT / config['historicalSources']['path']).read_text())
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / history['files'][0]['path']
            path.parent.mkdir(parents=True)
            path.write_bytes(b'other evidence')
            with self.assertRaisesRegex(ValueError, 'Refusing to overwrite'):
                baseline.materialize_history(Path(temporary))
            self.assertEqual(path.read_bytes(), b'other evidence')

    def test_local_upgrade_rejects_remote_target_before_starting_any_command(self):
        with patch.object(baseline.subprocess, 'check_output') as command:
            with self.assertRaisesRegex(ValueError, 'loopback Docker'):
                baseline.upgrade_local('postgresql://postgres@example.com:5432/postgres')
            command.assert_not_called()

    def test_local_maintenance_context_is_limited_to_the_migration_child(self):
        import json
        import os
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'history.json').write_text(json.dumps({'originalBaselineVersion': '20260805230000'}))
            (root / 'supabase/migrations').mkdir(parents=True)
            (root / 'supabase/migrations/20261101190000_fixture.sql').write_text('SELECT 1;')
            kit = root / 'kit'
            (kit / 'supabase/migrations').mkdir(parents=True)
            config = {'historicalSources': {'path': 'history.json'}}
            with patch.object(baseline, 'load_manifest', return_value=config), \
                 patch.object(baseline, 'covered_migrations', return_value=[{'version': '20260805230000'}]), \
                 patch.object(baseline, 'materialize_history', return_value=kit), \
                 patch.object(baseline.subprocess, 'check_output', side_effect=[
                     'supabase_db_festapp-fixture 127.0.0.1:55432->5432/tcp', '20260805230000\n']), \
                 patch.object(baseline.subprocess, 'run') as command, \
                 patch.dict(os.environ, {'PGOPTIONS': '-c statement_timeout=5000'}):
                baseline.upgrade_local('postgresql://supabase_admin:postgres@127.0.0.1:55432/postgres', root)
                command.assert_called_once()
                self.assertEqual(command.call_args.kwargs['env']['PGOPTIONS'],
                                 '-c statement_timeout=5000 -c request.jwt.claim.role=service_role')
                self.assertEqual(os.environ['PGOPTIONS'], '-c statement_timeout=5000')


if __name__ == '__main__':
    unittest.main()
