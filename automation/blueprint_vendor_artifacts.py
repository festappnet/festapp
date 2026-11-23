#!/usr/bin/env python3
"""Import the verified Blueprint npm distribution and its paired archive receipt."""
import argparse
import re
import hashlib
import json
import pathlib
import shutil
import tarfile

HOST = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('artifacts', type=pathlib.Path)
args = parser.parse_args()
artifacts = args.artifacts.resolve()

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
manifest = {'documentVersion': 2, 'resourceProtocol': 2, 'archives': {}}
if receipt.get('sourceCommit'):
    if not re.fullmatch(r'[0-9a-f]{40}', receipt['sourceCommit']):
        raise SystemExit('Invalid archive source commit')
    manifest['sourceCommit'] = receipt['sourceCommit']
manifest['archiveGateReceiptSha256'] = digest(artifacts / 'archive-result.json')
for package in ('venue_layout_core', 'venue_seat_picker'):
    archive = artifacts / f'{package}.tar.gz'
    with tarfile.open(archive) as source:
        pubspec = source.extractfile('pubspec.yaml').read().decode()
    version = {'venue_layout_core': '0.2.8', 'venue_seat_picker': '0.4.10'}[package]
    if f'version: {version}' not in pubspec.splitlines():
        raise SystemExit(f'Unexpected {package} artifact version')
    manifest['archives'][archive.name] = digest(archive)

pack = json.loads((artifacts / 'npm-pack.json').read_text())[0]['filename']
archive = artifacts / pack
with tarfile.open(archive) as source:
    package = json.load(source.extractfile('package/package.json'))
if package['name'] != '@festapp/venue-layout' or package['version'] != '0.3.13':
    raise SystemExit('Unexpected npm artifact')
for name, expected in receipt['requiredNpmFiles'].items():
    if digest(artifacts / 'npm' / name) != expected:
        raise SystemExit(f'Extracted npm receipt mismatch: {name}')
immutable_pack = f'festapp-venue-layout-0.3.13-{digest(archive)[:12]}.tgz'
target_pack = HOST / 'web_client' / 'vendor' / immutable_pack
if target_pack.exists() and digest(target_pack) != digest(archive):
    raise SystemExit('Immutable npm artifact collision')
shutil.copyfile(archive, target_pack)
manifest['archives'][immutable_pack] = digest(archive)
(vendor / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
shutil.copyfile(artifacts / 'archive-result.json', vendor / 'archive-result.json')
print(f'Imported verified Blueprint npm archive: {immutable_pack}.')
