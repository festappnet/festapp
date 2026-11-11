"""Read exact historical fixture bytes independently of Git ancestry."""
import argparse
from functools import lru_cache
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


@lru_cache(maxsize=None)
def _manifest(root):
    value = json.loads((root / 'automation/historical-inputs/manifest.json').read_text())
    if value['schemaVersion'] != 1:
        raise ValueError('Unsupported historical input manifest')
    return value['snapshots']


def source_paths(revision, prefix='', *, root=ROOT):
    return tuple(p for p in _manifest(Path(root))[revision] if p.startswith(prefix))


def read_source(revision, relative, *, root=ROOT):
    root = Path(root)
    sha = _manifest(root)[revision][relative]
    if not re.fullmatch(r'[0-9a-f]{64}', sha):
        raise ValueError('Invalid historical input digest')
    blob = root / 'automation/historical-inputs/objects' / sha
    data = blob.read_bytes() if blob.is_file() else gzip.decompress(blob.with_suffix('.gz').read_bytes())
    if hashlib.sha256(data).hexdigest() != sha:
        raise ValueError(f'Historical input checksum mismatch: {revision}:{relative}')
    return data


def materialize(revision, prefix, destination, *, root=ROOT):
    # Validate every input before creating output; never substitute current bytes.
    files = []
    for name in source_paths(revision, prefix, root=root):
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name:
            raise ValueError('Unsafe historical input path')
        target = Path(destination) / path
        data = read_source(revision, name, root=root)
        if target.exists() and target.read_bytes() != data:
            raise ValueError(f'Refusing to overwrite historical evidence: {name}')
        if not target.resolve().is_relative_to(Path(destination).resolve()):
            raise ValueError('Historical output escapes destination')
        files.append((target, data))
    if not files:
        raise ValueError('No registered historical inputs match prefix')
    for target, data in files:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['list', 'read', 'materialize'])
    parser.add_argument('revision')
    parser.add_argument('path')
    parser.add_argument('destination', nargs='?', type=Path)
    args = parser.parse_args()
    if args.command == 'list':
        print('\n'.join(source_paths(args.revision, args.path)))
    elif args.command == 'read':
        sys.stdout.buffer.write(read_source(args.revision, args.path))
    else:
        if args.destination is None:
            parser.error('materialize requires a destination')
        materialize(args.revision, args.path, args.destination)
