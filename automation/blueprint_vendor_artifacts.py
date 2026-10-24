#!/usr/bin/env python3
"""Install checked Blueprint distribution archives as immutable host snapshots."""
import argparse
import re
import subprocess
import hashlib
import json
import pathlib
import shutil
import sys
import tarfile

HOST = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('artifacts', type=pathlib.Path)
parser.add_argument('--restore-from-commit', help='Replace a historical drifted snapshot only when every current file matches this committed host snapshot')
args = parser.parse_args()
artifacts = args.artifacts.resolve()
restoration_commit = None
if args.restore_from_commit:
    if not re.fullmatch(r'[0-9a-f]{40}', args.restore_from_commit):
        raise SystemExit('--restore-from-commit requires a full 40-character commit SHA')
    restoration_commit = subprocess.check_output(
        ['git', '-C', str(HOST), 'rev-parse', '--verify',
         args.restore_from_commit + '^{commit}'], text=True).strip()

def committed_snapshot(package):
    prefix = f'vendor/blueprint/{package}/'
    names = subprocess.check_output(
        ['git', '-C', str(HOST), 'ls-tree', '-r', '--name-only',
         restoration_commit, '--', prefix], text=True).splitlines()
    if not names:
        raise SystemExit(f'No committed snapshot for {package}')
    return {name[len(prefix):]: hashlib.sha256(subprocess.check_output(
        ['git', '-C', str(HOST), 'show', f'{restoration_commit}:{name}'])).hexdigest()
        for name in names}

receipt = json.loads((artifacts / 'archive-result.json').read_text())
if not all(receipt.get(key) for key in (
    'passed', 'coreSourceByteEquivalent', 'pubSelectedCoreAndWrapper',
    'actualNpmPack', 'archivedExampleBuilt', 'archivedExampleBrowser',
)):
    raise SystemExit('Archive gate has not passed')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

vendor = HOST / 'vendor' / 'blueprint'
vendor.mkdir(parents=True, exist_ok=True)
manifest = {'documentVersion': 2, 'resourceProtocol': 2, 'archives': {}, 'files': {}}
if restoration_commit:
    manifest['restoredSnapshotCommit'] = restoration_commit
    for package in ('venue_layout_core', 'venue_seat_picker'):
        target = vendor / package
        existing = {str(path.relative_to(target)): digest(path)
                    for path in target.rglob('*') if path.is_file()}
        if existing != committed_snapshot(package):
            raise SystemExit(f'Current dependency differs from restoration commit: {package}')
if receipt.get('sourceCommit'):
    if not re.fullmatch(r'[0-9a-f]{40}', receipt['sourceCommit']):
        raise SystemExit('Invalid archive source commit')
    manifest['sourceCommit'] = receipt['sourceCommit']
manifest['archiveGateReceiptSha256'] = digest(artifacts / 'archive-result.json')
for package in ('venue_layout_core', 'venue_seat_picker'):
    archive = artifacts / f'{package}.tar.gz'
    with tarfile.open(archive) as source:
        pubspec = source.extractfile('pubspec.yaml').read().decode()
    version = {'venue_layout_core': '0.2.2', 'venue_seat_picker': '0.3.7'}[package]
    if f'version: {version}' not in pubspec.splitlines():
        raise SystemExit(f'Unexpected {package} artifact version')
    target = vendor / package
    if target.exists():
        # A JS-only reseal can reuse byte-identical selected Dart snapshots.
        with tarfile.open(archive) as source:
            selected = {member.name: hashlib.sha256(source.extractfile(member).read()).hexdigest()
                        for member in source.getmembers() if member.isfile()}
        existing = {str(path.relative_to(target)): digest(path)
                    for path in target.rglob('*') if path.is_file()}
        if existing != selected:
            previous = json.loads((vendor / 'manifest.json').read_text())['files']
            prefix = package + '/'
            expected = {key[len(prefix):]: value for key, value in previous.items() if key.startswith(prefix)}
            if existing != expected and (not restoration_commit or existing != committed_snapshot(package)):
                raise SystemExit(f'Modified dependency snapshot: {target}. Preserve local changes before updating.')
            shutil.rmtree(target)
            target.mkdir()
            with tarfile.open(archive) as source:
                source.extractall(target, filter='data')
    else:
        target.mkdir()
        with tarfile.open(archive) as source:
            source.extractall(target, filter='data')
    manifest['archives'][archive.name] = digest(archive)
    manifest['files'].update({str(path.relative_to(vendor)): digest(path)
                              for path in sorted(target.rglob('*')) if path.is_file()})

pack = json.loads((artifacts / 'npm-pack.json').read_text())[0]['filename']
archive = artifacts / pack
with tarfile.open(archive) as source:
    package = json.load(source.extractfile('package/package.json'))
if package['name'] != '@festapp/venue-layout' or package['version'] != '0.3.6':
    raise SystemExit('Unexpected npm artifact')
for name, expected in receipt['requiredNpmFiles'].items():
    if digest(artifacts / 'npm' / name) != expected:
        raise SystemExit(f'Extracted npm receipt mismatch: {name}')
immutable_pack = f'festapp-venue-layout-0.3.6-{digest(archive)[:12]}.tgz'
target_pack = HOST / 'web_client' / 'vendor' / immutable_pack
if target_pack.exists() and digest(target_pack) != digest(archive):
    raise SystemExit('Immutable npm artifact collision')
shutil.copyfile(archive, target_pack)
manifest['archives'][immutable_pack] = digest(archive)
(vendor / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
shutil.copyfile(artifacts / 'archive-result.json', vendor / 'archive-result.json')
(vendor / 'README.md').write_text('''# Blueprint distribution snapshot

These are the exact pub-selected 0.3.7 wrapper and 0.2.2 core archives,
verified with the npm 0.3.6 archive by the package archive gate.
They are dependency artifacts. Edit the canonical `festappnet/venue_seat_picker`
package, then rebuild and verify its distributions before updating this snapshot.
Do not patch these copies or add another rendering implementation here.
`manifest.json` records the archive and every extracted file SHA-256.
The host uses repository-relative paths and needs no workstation checkout,
unpublished Git revision or dependency override file.

Pub-selected means file selection by local `pub publish --dry-run`, not a prior
publication to pub.dev. Import verified archives built directly from canonical
source through `tool/archive_check.sh`; registry publication is a separate step.

Only the npm archive selected by `web_client/package.json` and its lockfile is
retained. Older host archives are recoverable from Git revision
`a4296c57687294b34826e59c7b232eef582c9748`; they are not installation inputs.
''')
print(f'Installed Blueprint archives: {len(manifest["files"])} verified files.')
