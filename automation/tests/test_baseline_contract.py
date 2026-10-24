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


if __name__ == '__main__':
    unittest.main()
