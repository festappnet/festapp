import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'hetzner-supabase/restore/backup_manifest.py'
spec = importlib.util.spec_from_file_location('asset_backup_manifest', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BackupManifest(unittest.TestCase):
    def fixture(self, version):
        files = ['postgres.dump.age', 'globals.sql.age', 'runtime.tar.age', 'r2-images.tar.age']
        if version == 1:
            files.append('storage.tar.age')
        return dict(version=version, format='festapp-assets' if version == 2 else 'legacy-storage',
                    encrypted=True, storage_extended_attributes=version == 1,
                    consistency='online-operational-backup-not-promotion-rpo0',
                    source_host='festapp-supabase-rehearsal-01', source_database='festapp_rehearsal_20260909220601',
                    artifacts={name: {} for name in files})

    def test_historical_and_canonical_sets_keep_distinct_required_artifacts(self):
        for version in (1, 2):
            self.assertEqual(module.validate_artifacts(self.fixture(version)), version)
        historical = self.fixture(1)
        historical['version'] = 2
        with self.assertRaises(AssertionError):
            module.validate_artifacts(historical)

    def test_canonical_set_rejects_missing_assets_storage_carryover_and_unknown_formats(self):
        for name in self.fixture(2)['artifacts']:
            manifest = self.fixture(2)
            del manifest['artifacts'][name]
            with self.assertRaises(AssertionError):
                module.validate_artifacts(manifest)
        manifest = self.fixture(2)
        manifest['artifacts']['storage.tar.age'] = {}
        with self.assertRaises(AssertionError):
            module.validate_artifacts(manifest)
        manifest = self.fixture(2)
        manifest['version'] = 3
        with self.assertRaises(ValueError):
            module.validate_artifacts(manifest)


if __name__ == '__main__':
    unittest.main()
