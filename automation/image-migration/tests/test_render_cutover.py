import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from storage_references import digest
spec = importlib.util.spec_from_file_location('render_cutover', ROOT / 'render-cutover.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Render(unittest.TestCase):
    def bundle(self):
        before = 'literal quote\'; COMMIT; -- and \\ backslash'
        after = '<p>Preserved content</p>'
        return dict(version=1, production_mutations=False, requires_atomic_client_sync_publication=True,
                    manifest_sha256='a' * 64, edits=[dict(original=before, original_digest=digest(before),
                    replacement=after, replacement_digest=digest(after))])

    def test_values_remain_literal_and_all_mutations_share_the_operator_transaction(self):
        sql = module.render(self.bundle(), 'SELECT 1;', 'b' * 40)
        self.assertIn('ON_ERROR_STOP on', sql)
        self.assertIn('ON COMMIT DROP', sql)
        self.assertTrue(sql.endswith('SELECT 1;\nCOMMIT;\n'))
        self.assertIn('SET LOCAL standard_conforming_strings=on;', sql)

    def test_stale_digests_and_unsealed_comment_fields_fail_before_rendering(self):
        bundle = self.bundle()
        bundle['edits'][0]['replacement'] = 'changed'
        with self.assertRaisesRegex(ValueError, 'field_digest'):
            module.render(bundle, '', 'b' * 40)
        bundle = self.bundle()
        bundle['manifest_sha256'] = 'a\nCOMMIT;'
        with self.assertRaisesRegex(ValueError, 'sealed_source'):
            module.render(bundle, '', 'b' * 40)


if __name__ == '__main__':
    unittest.main()
