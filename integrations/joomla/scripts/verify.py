#!/usr/bin/env python3
"""Run the full bounded Joomla release gate once, tying every result to frozen inputs."""
import json
import subprocess
from datetime import datetime, timezone
from release_common import ROOT, EVIDENCE, source_hashes, evidence_hashes, sha

before = source_hashes()
(ROOT / 'evidence/verification.json').unlink(missing_ok=True)
for name in EVIDENCE:
    (ROOT / 'evidence' / name).unlink(missing_ok=True)
log = ROOT / '.private/release-verification.log'
with log.open('w') as stream:
    result = subprocess.run(['bash','scripts/verify.sh'],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
if result.returncode:
    print('\n'.join(log.read_text().splitlines()[-18:]))
    raise SystemExit(result.returncode)
assert source_hashes() == before, 'Source/tooling changed while verification ran'
release = json.loads((ROOT / 'dist/CANDIDATE.json').read_text())
for major in [5,6]:
    installed = json.loads((ROOT / 'evidence/installed-files.json').read_text())
    assert any(c['major']==major and c['sha256']==release['sha256'] for c in installed['cases'])
    assert json.loads((ROOT / f'evidence/updater-{major}.json').read_text())['sha256']==release['sha256']
receipt = {'state':'VERIFIED','verified_at':datetime.now(timezone.utc).isoformat(),'command':'python3 scripts/verify.py -> bash scripts/verify.sh','zip_sha256':release['sha256'],'source_sha256':before,'evidence_sha256':evidence_hashes(),'log_sha256':sha(log)}
(ROOT / 'evidence/verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS complete Joomla release gate; source, exact ZIP and every receipt bound by SHA-256')
