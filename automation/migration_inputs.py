"""Read frozen migration inputs after baseline compaction; never reinstall them.

Ordinary files retain pathlib semantics. Missing covered SQL is recovered only
from the baseline's checksum-pinned history, independently of Git ancestry.
"""
from functools import lru_cache
from pathlib import Path
import json
from baseline import ROOT, load_manifest
from historical_inputs import read_source


@lru_cache(maxsize=1)
def history():
    config = load_manifest()
    value = json.loads((ROOT / config['historicalSources']['path']).read_text())
    return config, value, {entry['path']: entry for entry in value['files']}


def entry(path):
    path = Path(path).absolute()
    if path.parent != ROOT / 'supabase/migrations':
        return None
    config, value, entries = history()
    relative = path.relative_to(ROOT).as_posix()
    item = entries.get(relative)
    return (value, item) if item else None


def read_bytes(path):
    if Path(path).is_file():
        return Path(path).read_bytes()
    frozen = entry(path)
    if frozen is None:
        return Path(path).read_bytes()
    value, item = frozen
    return read_source(item.get('sourceCommit', value['sourceCommit']), item['path'])


def read_text(path, encoding=None, errors=None):
    if Path(path).is_file():
        return Path(path).read_text(encoding=encoding, errors=errors)
    return read_bytes(path).decode(encoding or 'utf-8', errors or 'strict').replace('\r\n', '\n').replace('\r', '\n')


def is_file(path):
    return Path(path).is_file() or entry(path) is not None


def exists(path):
    return Path(path).exists() or entry(path) is not None


def write_text(path, text, *args, **kwargs):
    if entry(path) is not None:
        raise ValueError('Covered migration is immutable; author a new forward migration: ' + str(path))
    return Path(path).write_text(text, *args, **kwargs)


def migration_paths(root=ROOT):
    """Logical former-forward history for predecessor/source checks, not installs."""
    paths = set((root / 'supabase/migrations').glob('*.sql'))
    if root.resolve() == ROOT:
        config, _, entries = history()
        lower = config.get('compactedForwardsAfter', config['coveredThrough'])
        paths.update(ROOT / name for name in entries
                     if name.startswith('supabase/migrations/') and Path(name).name[:14] > lower)
    return sorted(paths)
