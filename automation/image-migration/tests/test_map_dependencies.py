import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from map_dependencies import audit, icon_outputs


class MapDependencies(unittest.TestCase):
    def fixture(self, directory, available=('icon-shop',)):
        atlas = {key: {'x': 0, 'y': 0, 'width': 1, 'height': 1} for key in available}
        # Geometry fixture only; the audit does not claim PNG decoding/rendering.
        png = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 1, 1) + b'\x08\x06\x00\x00\x00' + b'\x00' * 4
        assets = []
        for scale in ('1x', '2x'):
            for kind, content in [('json', json.dumps(atlas).encode()), ('png', png)]:
                name = scale + '.' + kind
                (directory / name).write_bytes(content)
                assets.append({'role': f'sprite_{kind}_{scale}', 'path': name, 'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()})
        return {'assets': assets}

    def test_match_reads_outputs_without_confusing_condition_labels(self):
        self.assertEqual(icon_outputs(['match', ['get', 'kind'], 'icon-condition', ['case', True, 'icon-shop', ''], 'icon-default']), {'icon-shop', 'icon-default'})

    def test_missing_symbol_and_dynamic_expression_block_rewrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = self.fixture(root)
            style = {'layers': [{'layout': {'icon-image': 'icon-church'}}, {'layout': {'icon-image': ['get', 'icon']}}]}
            result = audit(json.dumps(style).encode(), manifest, root)
            self.assertFalse(result['ready_for_sprite_rewrite'])
            self.assertEqual(result['missing_icons'], {'1x': ['icon-church'], '2x': ['icon-church']})
            self.assertIn('dynamic_icon_expression_requires_tile_audit', result['issues'])

    def test_verified_pair_accepts_matching_style_and_rejects_changed_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = self.fixture(root)
            style = json.dumps({'layers': [{'layout': {'icon-image': 'icon-shop'}}]}).encode()
            self.assertTrue(audit(style, manifest, root)['ready_for_sprite_rewrite'])
            (root / '2x.png').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'hash_mismatch'):
                audit(style, manifest, root)

    def test_outside_atlas_and_path_escape_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = self.fixture(root)
            path = root / '1x.json'
            path.write_text(json.dumps({'icon-shop': {'x': 1, 'y': 0, 'width': 1, 'height': 1}}))
            entry = manifest['assets'][0]
            entry.update(bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            with self.assertRaisesRegex(ValueError, 'outside_png'):
                audit(b'{}', manifest, root)
            entry['path'] = '../escape'
            with self.assertRaisesRegex(ValueError, 'unsafe_sprite_path'):
                audit(b'{}', manifest, root)
