#!/usr/bin/env python3
"""Install checked Blueprint distribution archives as immutable host snapshots."""
import hashlib
import json
import pathlib
import shutil
import sys
import tarfile

HOST = pathlib.Path(__file__).resolve().parent.parent
artifacts = pathlib.Path(sys.argv[1]).resolve()
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
for package in ('venue_layout_core', 'venue_seat_picker'):
    archive = artifacts / f'{package}.tar.gz'
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
            if existing != expected:
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
if package['name'] != '@festapp/venue-layout' or package['version'] != '0.3.0':
    raise SystemExit('Unexpected npm artifact')
for name, expected in receipt['requiredNpmFiles'].items():
    if digest(artifacts / 'npm' / name) != expected:
        raise SystemExit(f'Extracted npm receipt mismatch: {name}')
immutable_pack = f'festapp-venue-layout-0.3.0-{digest(archive)[:12]}.tgz'
target_pack = HOST / 'web_client' / 'vendor' / immutable_pack
if target_pack.exists() and digest(target_pack) != digest(archive):
    raise SystemExit('Immutable npm artifact collision')
shutil.copyfile(archive, target_pack)
manifest['archives'][immutable_pack] = digest(archive)
(vendor / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(vendor / 'README.md').write_text('''# Blueprint distribution snapshot

These are the exact pub-selected 0.3.0 wrapper and 0.2.0 core archives,
verified with the npm 0.3.0 archive by the package archive gate.
They are dependency artifacts. Edit the canonical `festappnet/venue_seat_picker`
package, then rebuild and verify its distributions before updating this snapshot.
Do not patch these copies or add another rendering implementation here.
`manifest.json` records the archive and every extracted file SHA-256.
The host uses repository-relative paths and needs no workstation checkout,
unpublished Git revision or dependency override file.

The old npm 0.2.3 archive is retained as immutable historical evidence;
no active dependency points to it.
''')
print(f'Installed Blueprint archives: {len(manifest["files"])} verified files.')
