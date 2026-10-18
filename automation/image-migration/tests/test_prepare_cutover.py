import copy
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from storage_references import digest

spec = importlib.util.spec_from_file_location('prepare_cutover', ROOT / 'prepare-cutover.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Cutover(unittest.TestCase):
    def fixture(self):
        original = {'owner_id': 'original-owner', 'owner': 'original-owner', 'bucket_id': 'public-files', 'name': 'example.pdf'}
        obj = dict(identity={'bucket': 'public-files', 'key': 'example.pdf'},
                   destination={'bucket': 'festapp-images', 'key': 'assets/storage/example'},
                   source={'size': 3, 'sha256': 'a' * 64}, metadata={'mimetype': 'application/pdf'},
                   visibility='public', source_storage_record=original)
        value = {'html': '<p>Preserve</p><a href="https://api.festapp.net/storage/v1/object/public/public-files/example.pdf">PDF</a>'}
        field = dict(schema='eshop', table='products', key={'id': 12}, field='data', original=value,
                     original_digest=digest(value), issues=[], classification='current')
        manifest = dict(summary={'ready_for_copy': True, 'ready_for_reference_rewrite': True}, objects=[obj],
                        r2_objects=[], r2_inventory_sha256='b' * 64, owned_hosts=['api.festapp.net'], fields=[field])
        receipt = dict(version=1, identity=obj['identity'], destination=obj['destination'], size=3,
                       sha256='a' * 64, contentType='application/pdf', manifestSha256='c' * 64,
                       r2InventorySha256='b' * 64, sourceRevision='d' * 40, verifiedAt='2026-10-18T10:00:00Z')
        return manifest, {module.identity_hash(obj['identity']): receipt}

    def test_exact_edits_preserve_original_ownership_and_history(self):
        manifest, receipts = self.fixture()
        history = copy.deepcopy(manifest['fields'][0])
        history['classification'] = 'history'
        manifest['fields'].append(history)
        result = module.prepare(manifest, 'c' * 64, receipts)
        self.assertEqual(len(result['edits']), 1)
        self.assertEqual(result['registry'][0]['owner_id'], 'original-owner')
        self.assertEqual(result['registry'][0]['source_storage_record'], manifest['objects'][0]['source_storage_record'])
        edit = result['edits'][0]
        self.assertEqual(edit['original'], manifest['fields'][0]['original'])
        self.assertEqual(edit['replacement']['html'], '<p>Preserve</p><a href="https://img.festapp.net/assets/storage/example">PDF</a>')
        self.assertTrue(result['requires_atomic_client_sync_publication'])
        self.assertFalse(result['production_mutations'])

    def test_missing_or_wrong_receipts_and_stale_prestates_refuse_entire_bundle(self):
        manifest, receipts = self.fixture()
        with self.assertRaisesRegex(ValueError, 'receipt_missing'):
            module.prepare(manifest, 'c' * 64, {})
        for field, bad in [('size', 4), ('sha256', 'e' * 64), ('manifestSha256', 'e' * 64),
                           ('r2InventorySha256', 'e' * 64), ('contentType', 'image/png')]:
            changed = copy.deepcopy(receipts)
            next(iter(changed.values()))[field] = bad
            with self.assertRaisesRegex(ValueError, 'receipt_mismatch'):
                module.prepare(manifest, 'c' * 64, changed)
        manifest['fields'][0]['original']['html'] = 'a concurrent edit'
        with self.assertRaisesRegex(ValueError, 'prestate_digest'):
            module.prepare(manifest, 'c' * 64, receipts)

    def test_unresolved_private_or_duplicate_fields_are_not_silently_skipped(self):
        manifest, receipts = self.fixture()
        manifest['summary']['ready_for_reference_rewrite'] = False
        with self.assertRaisesRegex(ValueError, 'complete_reference_inventory'):
            module.prepare(manifest, 'c' * 64, receipts)
        manifest['summary']['ready_for_reference_rewrite'] = True
        manifest['objects'][0]['visibility'] = 'private'
        with self.assertRaisesRegex(ValueError, 'private_reference_boundary'):
            module.prepare(manifest, 'c' * 64, receipts)
        manifest['objects'][0]['visibility'] = 'public'
        manifest['fields'].append(copy.deepcopy(manifest['fields'][0]))
        with self.assertRaisesRegex(ValueError, 'duplicate_field'):
            module.prepare(manifest, 'c' * 64, receipts)

    def test_explicit_test_map_disposal_preserves_other_features_and_still_checks_every_copy(self):
        manifest, receipts = self.fixture()
        features = [{'code': 'map', 'missing': 'https://api.festapp.net/storage/v1/object/public/public-files/missing'},
                    {'code': 'ticket', 'layout': {'untouched': True}}]
        field = dict(schema='public', table='occasions', key={'id': 63}, field='features',
                     original=features, original_digest=digest(features), classification='current',
                     issues=['reference_source_not_in_storage'])
        manifest['fields'].append(field)
        manifest['summary']['ready_for_reference_rewrite'] = False
        with self.assertRaisesRegex(ValueError, 'complete_reference_inventory'):
            module.prepare(manifest, 'c' * 64, receipts)
        with patch.object(module, 'ROMA_TEST_FEATURES_SHA256', digest(features)):
            result = module.prepare(manifest, 'c' * 64, receipts, True)
            self.assertTrue(result['discarded_roma_test_map'])
            self.assertEqual(result['edits'][1]['replacement'], features[1:])
            self.assertEqual(result['edits'][1]['original'], features)
            with self.assertRaisesRegex(ValueError, 'receipt_missing'):
                module.prepare(manifest, 'c' * 64, {}, True)
            field['key']['id'] = 64
            with self.assertRaisesRegex(ValueError, 'unreviewed_test_map'):
                module.prepare(manifest, 'c' * 64, receipts, True)
            field['key']['id'] = 63
            features[1]['layout']['untouched'] = False
            with self.assertRaisesRegex(ValueError, 'test_map_prestate_changed'):
                module.prepare(manifest, 'c' * 64, receipts, True)


if __name__ == '__main__':
    unittest.main()
