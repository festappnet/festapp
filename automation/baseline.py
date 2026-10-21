#!/usr/bin/env python3
"""Single baseline contract, covered ledger and checksum-verified historical SQL recovery."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'supabase/baseline/manifest.json'


def repository_path(root, value):
    path = root / value
    if not path.resolve().is_relative_to(root.resolve()) or path.is_symlink():
        raise ValueError(f'Input outside repository or symlink: {value}')
    return path


def checked_file(root, entry):
    path = repository_path(root, entry['path'])
    if hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        raise ValueError(f'Baseline input checksum mismatch: {entry["path"]}')
    return path


def load_manifest(root=ROOT):
    data = json.loads((root / MANIFEST).read_text())
    if data['formatVersion'] != 1 or not re.fullmatch(r'\d{14}', data['coveredThrough']):
        raise ValueError('Unsupported baseline manifest')
    for key in ['schema', 'bootstrap', 'referenceSeed', 'historicalSources']:
        checked_file(root, data[key])
    for stage in data.get('upgradeStages', []):
        if not re.fullmatch(r'\d{14}', stage['beforeVersion']) or stage['beforeVersion'] <= data['coveredThrough']:
            raise ValueError('Invalid forward upgrade stage')
        checked_file(root, stage['backfill'])
    history = json.loads((root / data['historicalSources']['path']).read_text())
    if history['coveredThrough'] != data['coveredThrough']:
        raise ValueError('Historical coverage and baseline differ')
    return data


def covered_migrations(root=ROOT):
    data = load_manifest(root)
    history = json.loads((root / data['historicalSources']['path']).read_text())
    rows = []
    for entry in history['files']:
        path = Path(entry['path'])
        if path.parent.as_posix() != 'supabase/migrations':
            continue
        version, name = path.stem.split('_', 1)
        if not re.fullmatch(r'\d{14}', version) or version > data['coveredThrough']:
            raise ValueError('Invalid covered migration')
        rows.append(dict(entry, version=version, name=name))
    if not rows or len({x['version'] for x in rows}) != len(rows):
        raise ValueError('Empty or duplicate baseline coverage')
    return sorted(rows, key=lambda x: x['version'])


def ledger_sql(root=ROOT):
    rows = covered_migrations(root)
    values = ',\n'.join("('%s','%s',ARRAY[]::text[])" % (x['version'], x['name'].replace("'", "''")) for x in rows)
    return ('CREATE SCHEMA IF NOT EXISTS supabase_migrations;\n'
            'CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations(version text PRIMARY KEY, statements text[], name text);\n'
            'INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES\n' + values +
            '\nON CONFLICT(version) DO NOTHING;\n')


def materialize_history(destination, root=ROOT, include_email=False):
    data = load_manifest(root)
    history = json.loads((root / data['historicalSources']['path']).read_text())
    commit = history['sourceCommit']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Historical source must pin a full Git commit')
    # Git is the sole recovery authority. Never substitute current source bytes.
    # Verify every blob before creating files; recovery works without a network.
    blobs = []
    for entry in history['files'] + (history['emailUpgradeFiles'] if include_email else []):
        repository_path(root, entry['path'])
        source_commit = entry.get('sourceCommit', commit)
        if not re.fullmatch(r'[0-9a-f]{40}', source_commit):
            raise ValueError('Historical input must pin a full Git commit')
        content = subprocess.check_output(['git', '-C', str(root), 'show', source_commit + ':' + entry['path']], stderr=subprocess.PIPE)
        if hashlib.sha256(content).hexdigest() != entry['sha256']:
            raise ValueError(f'Historical Git checksum mismatch: {entry["path"]}')
        path = repository_path(destination, entry['path'])
        if path.exists() and path.read_bytes() != content:
            raise ValueError(f'Refusing to overwrite historical kit file: {path}')
        blobs.append((path, content))
    for path, content in blobs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    return destination


def upgrade_local(database_url, root=ROOT):
    """Run the existing migration engine with recovered history; never install a snapshot over data."""
    from urllib.parse import urlsplit
    import tempfile
    import shutil
    target = urlsplit(database_url)
    if target.scheme not in ('postgres', 'postgresql') or target.hostname != '127.0.0.1' or not target.port:
        raise ValueError('Upgrade command accepts an explicit loopback Docker database only')
    # A loopback URL alone could point at a production tunnel. Require a local
    # Supabase Docker container with an actual published PostgreSQL port.
    containers = subprocess.check_output(['docker', 'ps', '--format', '{{.Names}} {{.Ports}}'], text=True)
    if not any(line.startswith('supabase_db_festapp') and f'127.0.0.1:{target.port}->5432/' in line
               or line.startswith('supabase_db_festapp') and f'0.0.0.0:{target.port}->5432/' in line
               for line in containers.splitlines()):
        raise ValueError('No local Festapp Docker PostgreSQL owns that port')
    history = json.loads((root / load_manifest(root)['historicalSources']['path']).read_text())
    required = [x['version'] for x in covered_migrations(root) if x['version'] <= history['originalBaselineVersion']]
    recorded = subprocess.check_output(['psql', database_url, '-X', '-v', 'ON_ERROR_STOP=1', '-Atqc',
                                       'SELECT version FROM supabase_migrations.schema_migrations'], text=True).splitlines()
    if not set(required).issubset(recorded):
        raise ValueError('Database is older than the supported original baseline ledger; refusing upgrade')
    with tempfile.TemporaryDirectory(prefix='festapp-upgrade-') as temporary:
        kit = materialize_history(Path(temporary), root)
        forward = sorted((root / 'supabase/migrations').glob('*.sql'))
        (kit / 'supabase/config.toml').write_text('project_id = "festapp-local-upgrade"\n')
        added = set()

        def migrate(before=None):
            for path in forward:
                if path.name in added or (before and path.name[:14] >= before):
                    continue
                destination = kit / 'supabase/migrations' / path.name
                if destination.exists():
                    raise ValueError('Forward SQL overlaps recovered history')
                shutil.copy2(path, destination)
                added.add(path.name)
            subprocess.run(['supabase', 'migration', 'up', '--workdir', str(kit), '--db-url', database_url, '--include-all'], check=True)

        for stage in sorted(load_manifest(root).get('upgradeStages', []), key=lambda stage: stage['beforeVersion']):
            if stage['beforeVersion'] in recorded:
                continue
            migrate(stage['beforeVersion'])
            previous = None
            while True:
                remaining = int(subprocess.check_output(['psql', database_url, '-X', '-v', 'ON_ERROR_STOP=1', '-Atqc', stage['remainingQuery']], text=True).strip())
                if remaining == 0:
                    break
                if previous is not None and remaining >= previous:
                    raise ValueError('Upgrade backfill made no progress; inspect the disposable target')
                subprocess.run(['psql', database_url, '-X', '-v', 'ON_ERROR_STOP=1', '-q', '-f', str(root / stage['backfill']['path'])], check=True, stdout=subprocess.DEVNULL)
                previous = remaining
        migrate()



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    field = sub.add_parser('field')
    field.add_argument('name', choices=['coveredThrough', 'schema', 'bootstrap', 'referenceSeed'])
    sub.add_parser('ledger-sql')
    sub.add_parser('check')
    upgrade = sub.add_parser('upgrade-local')
    upgrade.add_argument('--database-url', required=True)
    history = sub.add_parser('historical-kit')
    history.add_argument('destination', type=Path)
    history.add_argument('--email', action='store_true', help='Include the pinned legacy email upgrade chain and fixtures')
    args = parser.parse_args()
    data = load_manifest()
    if args.command == 'field':
        value = data[args.name]
        print(value if isinstance(value, str) else ROOT / value['path'])
    elif args.command == 'ledger-sql':
        print(ledger_sql(), end='')
    elif args.command == 'upgrade-local':
        upgrade_local(args.database_url)
    elif args.command == 'historical-kit':
        print(materialize_history(args.destination.resolve(), include_email=args.email))
    else:
        covered_migrations()
        versions = []
        for path in (ROOT / 'supabase/migrations').glob('*.sql'):
            version = path.name[:14]
            if not re.fullmatch(r'\d{14}', version) or version <= data['coveredThrough']:
                raise ValueError(f'Non-forward active migration: {path.name}')
            versions.append(version)
        if len(set(versions)) != len(versions):
            raise ValueError('Duplicate forward migration version')
        print('Baseline manifest and migration coverage passed.')


if __name__ == '__main__':
    main()
