"""Verify the selected sealed ZIP, source, SVN stage and review evidence.

--submit-ready additionally rejects unresolved pre-submission gates.
"""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from metadata_contract import validate_minimum_wordpress

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--product', required=True, choices=[p['slug'] for p in json.loads((root / 'products.json').read_text())])
parser.add_argument('--submit-ready', action='store_true')
args = parser.parse_args()
digest = lambda data: hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit('FAIL: ' + message)


approval = json.loads((root / 'dist/APPROVAL.json').read_text())
products = [p for p in approval['products'] if p['plugin'] == args.product]
require(len(products) == 1, 'product is not sealed exactly once')
product = products[0]
archive = root / product['zip']
require(digest(archive.read_bytes()) == product['zip_sha256'], 'ZIP differs from sealed review')
require(archive.with_suffix('.zip.sha256').read_text().split()[0] == product['zip_sha256'], 'ZIP checksum sidecar differs')
stage = root / product['offline_submission']
release_path = stage / 'RELEASE.json'
require(digest(release_path.read_bytes()) == product['release_manifest_sha256'], 'SVN manifest differs from sealed review')
release = json.loads(release_path.read_text())
require(release['zip_sha256'] == product['zip_sha256'], 'SVN stage refers to another ZIP')
require(release['plugin'] == args.product and release['version'] == product['version'], 'SVN identity/version differs')
inputs = json.loads((root / 'evidence' / (args.product + '-package-inputs.json')).read_text())
with zipfile.ZipFile(archive) as package:
    validate_minimum_wordpress(
        package.read(args.product + '/' + args.product + '.php').decode('utf-8'),
        package.read(args.product + '/readme.txt').decode('utf-8'))
    entries = package.infolist()
    require(len(entries) == len(inputs) == product['files'], 'ZIP entry count differs')
    seen = set()
    for entry in entries:
        path = Path(entry.filename)
        require(not path.is_absolute() and '..' not in path.parts and path.parts[0] == args.product and len(path.parts) > 1, 'unsafe ZIP path')
        name = path.relative_to(args.product).as_posix()
        require(name not in seen, 'duplicate ZIP entry')
        seen.add(name)
        data = package.read(entry)
        require(inputs.get(name) == digest(data), 'ZIP input differs: ' + name)
        for location in [root / args.product / name, stage / 'trunk' / name, stage / 'tags' / product['version'] / name]:
            require(location.is_file() and location.read_bytes() == data, 'distributed source or SVN tree differs: ' + str(location))
actual = {p.relative_to(stage).as_posix(): digest(p.read_bytes()) for p in stage.rglob('*') if p.is_file() and p != release_path}
require(actual == release['files_sha256'], 'SVN files/assets differ from manifest')
build = json.loads((root / 'evidence/shared-build.json').read_text())
require(build[args.product]['files'] == inputs, 'shared build and package inputs differ')
for name, expected in build['shared_inputs'].items():
    require(digest((root / name).read_bytes()) == expected, 'canonical build input changed: ' + name)
for name, expected in approval.get('evidence_sha256', {}).items():
    require(digest((root / 'evidence' / name).read_bytes()) == expected, 'review evidence changed: ' + name)
for name, expected in approval.get('documentation_sha256', {}).items():
    require(digest((root / name).read_bytes()) == expected, 'review documentation changed: ' + name)
if args.submit_ready:
    require(not approval.get('remaining_external_gates'), 'unresolved gates: ' + '; '.join(approval['remaining_external_gates']))
    require(approval.get('production_service_fixes_deployed') is True, 'production service parity is unverified')
    require(approval['state'] == 'READY_TO_SUBMIT', 'submission is not marked ready')
print('PASS: selected ZIP, source, SVN stage, assets and evidence agree' + ('; submission gates clear' if args.submit_ready else ' (submission gates are checked separately)'))
