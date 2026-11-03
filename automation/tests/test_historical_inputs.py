import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).parents[1]))
from historical_inputs import read_source, materialize


class HistoricalInputsTest(unittest.TestCase):
    def fixture(self, root):
        directory = root / 'automation/historical-inputs'
        (directory / 'objects').mkdir(parents=True)
        data = b'SELECT 1;\r\n'
        sha = hashlib.sha256(data).hexdigest()
        blob = directory / 'objects' / sha
        blob.write_bytes(data)
        (directory / 'manifest.json').write_text(json.dumps({'schemaVersion': 1, 'snapshots': {'revision': {'historical.sql': sha}}}))
        return data, blob

    def test_exact_original_line_endings_survive_without_git(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data, _ = self.fixture(root)
            self.assertEqual(read_source('revision', 'historical.sql', root=root), data)

    def test_tampered_input_fails_before_output_is_written(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _, blob = self.fixture(root)
            blob.write_bytes(b'SELECT changed;')
            output = root / 'output'
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                materialize('revision', '', output, root=root)
            self.assertFalse(output.exists())

    def test_unregistered_input_has_no_current_source_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            (root / 'current.sql').write_text('SELECT 2;')
            with self.assertRaises(KeyError):
                read_source('revision', 'current.sql', root=root)


if __name__ == '__main__':
    unittest.main()
