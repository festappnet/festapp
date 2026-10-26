#!/usr/bin/env python3
"""Reject stale evidence/critique/artifacts; seal a reviewed Czech release or check publication."""
import argparse
import json
import subprocess
import zipfile
import xml.etree.ElementTree as ET
from release_common import ROOT, sha, source_hashes, evidence_hashes

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--seal',action='store_true')
parser.add_argument('--public',action='store_true')
args = parser.parse_args()
release = json.loads((ROOT / 'dist/CANDIDATE.json').read_text())
verification = json.loads((ROOT / 'evidence/verification.json').read_text())
assert verification['state']=='VERIFIED' and verification['zip_sha256']==release['sha256'], 'Wrong/unverified ZIP'
assert verification['source_sha256']==source_hashes(), 'Verified source/tooling changed'
assert verification['evidence_sha256']==evidence_hashes(), 'Verification evidence changed'
for path in [release['zip'],'dist/vstupenky.online.zip']:
    assert sha(ROOT / path)==release['sha256'], 'Release ZIP differs from verified artifact'
assert sha(ROOT / 'updates/vstupenky-online.xml')==release['update_feed_sha256'], 'Update feed differs'
product = next(p for p in json.loads((ROOT / 'products.json').read_text()) if p['element']=='mod_vstupenky_online')
assert release['element']==product['element'] and release['version']==product['version'], 'Candidate product identity drift'
expected_tag = 'joomla-vstupenky-online-v' + product['version']
expected_download = 'https://github.com/festappnet/festapp/releases/download/' + expected_tag + '/vstupenky.online.zip'
assert release['tag']==expected_tag and release['download_url']==expected_download, 'Candidate release URL/tag drift'
assert release['update_url']==product['update_url'], 'Candidate update URL drift'
with zipfile.ZipFile(ROOT / release['zip']) as archive:
    manifest = ET.fromstring(archive.read(product['element']+'.xml'))
assert manifest.findtext('name')==product['element'] and manifest.findtext('version')==product['version'], 'Packaged identity drift'
assert manifest.findtext('./updateservers/server')==release['update_url'], 'Packaged update URL drift'
feed = ET.parse(ROOT / 'updates/vstupenky-online.xml').getroot()
assert len(feed.findall('update'))==1, 'Unexpected update entries'
for node,value in [('element',release['element']),('version',release['version']),('downloads/downloadurl',release['download_url']),('sha256',release['sha256'])]:
    assert feed.findtext('./update/'+node)==value, 'Feed/candidate drift: '+node
review = json.loads((ROOT / 'evidence/critic.json').read_text())
assert review['status']=='APPROVED' and review['zip_sha256']==release['sha256'], 'Critic has not approved this exact ZIP'
assert review['verification_sha256']==sha(ROOT / 'evidence/verification.json'), 'Critic reviewed a different verification result'
assert not review['unresolved_release_blockers'], 'Unresolved critic blockers'
proof = {**release,'verification_sha256':sha(ROOT / 'evidence/verification.json'),'critic_sha256':sha(ROOT / 'evidence/critic.json'),'documentation_sha256':{name:sha(ROOT / name) for name in ['README.md','SUBMISSION.md','dist/RELEASE-NOTES.md']}}
if args.seal:
    (ROOT / 'dist/RELEASE.json').write_text(json.dumps({'state':'READY_TO_PUBLISH',**proof},indent=2)+'\n')
else:
    sealed = json.loads((ROOT / 'dist/RELEASE.json').read_text())
    assert sealed=={'state':'READY_TO_PUBLISH',**proof}, 'Seal changed or does not cover current release'
if args.public:
    public = {}
    for key in ['download_url','update_url']:
        response = subprocess.run(['curl','--fail','--silent','--show-error','--location','--max-time','40',release[key]],check=True,capture_output=True)
        import hashlib
        expected = release['sha256'] if key=='download_url' else release['update_feed_sha256']
        actual = hashlib.sha256(response.stdout).hexdigest()
        assert actual==expected, 'Public response differs: '+key
        public[key]={'url':release[key],'sha256':actual}
    (ROOT / 'evidence/public-release.json').write_text(json.dumps(public,indent=2)+'\n')
print('PASS reviewed Czech release seal' + (' and exact public ZIP/update feed' if args.public else ' (publication is a separate recorded effect)'))
