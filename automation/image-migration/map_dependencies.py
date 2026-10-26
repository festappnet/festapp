#!/usr/bin/env python3
"""Audit retained map styles against a hash-pinned R2 sprite bundle.

Read-only preparation: never replaces missing symbols or changes a live style.
Unknown expressions and incomplete/mismatched atlases prevent approval.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct


def icon_outputs(value):
    if isinstance(value, str):
        return {value} if value else set()
    if not isinstance(value, list) or not value:
        raise ValueError('unsupported_icon_expression')
    operator = value[0]
    if operator == 'literal' and len(value) == 2 and isinstance(value[1], str):
        return icon_outputs(value[1])
    if operator == 'match' and len(value) >= 5 and len(value) % 2 == 1:
        outputs = value[3:-1:2] + value[-1:]
    elif operator == 'case' and len(value) >= 4 and len(value) % 2 == 0:
        outputs = value[2:-1:2] + value[-1:]
    elif operator == 'coalesce' and len(value) >= 2:
        outputs = value[1:]
    else:
        raise ValueError('dynamic_icon_expression_requires_tile_audit')
    return set().union(*(icon_outputs(item) for item in outputs))


def audit(style_bytes, manifest, directory):
    style = json.loads(style_bytes)
    required, issues = set(), []
    for layer in style.get('layers', []):
        icon = layer.get('layout', {}).get('icon-image')
        if icon is None:
            continue
        try:
            required.update(icon_outputs(icon))
        except ValueError as error:
            issues.append(str(error))
    entries = {}
    roles = {'sprite_json_1x', 'sprite_png_1x', 'sprite_json_2x', 'sprite_png_2x'}
    root = directory.resolve()
    for asset in manifest['assets']:
        role = asset['role']
        if role not in roles:
            continue
        if role in entries:
            raise ValueError('duplicate_sprite_role')
        target = (root / asset['path']).resolve()
        if not target.is_relative_to(root):
            raise ValueError('unsafe_sprite_path')
        data = target.read_bytes()
        if len(data) != asset['bytes'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
            raise ValueError('sprite_manifest_hash_mismatch')
        entries[role] = data
    missing_by_scale = {}
    for scale in ('1x', '2x'):
        if not all('sprite_' + kind + '_' + scale in entries for kind in ('json', 'png')):
            issues.append('sprite_pair_missing_' + scale)
            continue
        png = entries['sprite_png_' + scale]
        if len(png) < 33 or png[:8] != b'\x89PNG\r\n\x1a\n' or png[12:16] != b'IHDR':
            raise ValueError('invalid_sprite_png')
        width, height = struct.unpack('>II', png[16:24])
        atlas = json.loads(entries['sprite_json_' + scale])
        missing_by_scale[scale] = sorted(required - atlas.keys())
        if missing_by_scale[scale]:
            issues.append('required_sprite_missing_' + scale)
        for region in atlas.values():
            x, y, w, h = (region[key] for key in ('x', 'y', 'width', 'height'))
            if not all(isinstance(n, (int, float)) and not isinstance(n, bool) for n in (x, y, w, h)):
                raise ValueError('invalid_sprite_region')
            if not (0 <= x < width and 0 <= y < height and 0 < w <= width-x and 0 < h <= height-y):
                raise ValueError('sprite_region_outside_png')
    return {
        'version': 1, 'source_style_sha256': hashlib.sha256(style_bytes).hexdigest(),
        'required_icons': sorted(required), 'missing_icons': missing_by_scale,
        'verified_sprite_assets': len(entries), 'issues': sorted(set(issues)),
        'ready_for_sprite_rewrite': not issues, 'production_mutations': False,
        'network_dependencies': {key: style.get(key) for key in ('sprite', 'glyphs')},
        'scope': 'Sprite compatibility only; not proof of a complete offline map or migration.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--style', type=Path, required=True)
    parser.add_argument('--sprite-manifest', type=Path, required=True)
    parser.add_argument('--bundle-directory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest_bytes = args.sprite_manifest.read_bytes()
    result = audit(args.style.read_bytes(), json.loads(manifest_bytes), args.bundle_directory)
    result['sprite_manifest_sha256'] = hashlib.sha256(manifest_bytes).hexdigest()
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps({key: result[key] for key in ('verified_sprite_assets', 'issues', 'ready_for_sprite_rewrite')}))
    return 0 if result['ready_for_sprite_rewrite'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
