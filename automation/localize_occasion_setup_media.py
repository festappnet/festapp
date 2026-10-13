#!/usr/bin/env python3
"""Copy public source-plan backgrounds into the owned local Supabase storage."""
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

backend = Path(__file__).resolve().parents[2] / 'festapp-wizard-local'
snapshot_path = Path(sys.argv[1])
if not (backend / 'bootstrap-complete').exists():
    raise RuntimeError('Owned Wizard workspace is not initialized')
status = json.loads(subprocess.check_output(
    ['supabase', 'status', '--workdir', str(backend), '--output', 'json'],
    stderr=subprocess.DEVNULL))
origin = status['API_URL']
if origin != 'http://127.0.0.1:56821':
    raise RuntimeError('Expected local API is not running')
headers = {'Authorization': 'Bearer ' + status['SERVICE_ROLE_KEY'],
           'apikey': status['SERVICE_ROLE_KEY']}
bucket = 'wizard-source-assets'
request = urllib.request.Request(origin + '/storage/v1/bucket',
    data=json.dumps({'id': bucket, 'name': bucket, 'public': True}).encode(),
    headers={**headers, 'Content-Type': 'application/json'}, method='POST')
try:
    with urllib.request.urlopen(request) as response:
        response.read()
except urllib.error.HTTPError as error:
    if error.code not in (400, 409):
        raise
    # Accept only an already-existing owned bucket, not another failure.
    check = urllib.request.Request(origin + '/storage/v1/bucket/' + bucket, headers=headers)
    with urllib.request.urlopen(check) as response:
        if json.load(response)['id'] != bucket:
            raise RuntimeError('Unexpected local bucket identity')
snapshot = json.loads(snapshot_path.read_text())
copied = 0
for source in snapshot['sources']:
    for plan in source.get('blueprints', []):
        value = plan.get('background_svg') or ''
        if not value.startswith(('https://', 'http://')):
            continue
        parsed = urllib.parse.urlparse(value)
        if parsed.hostname == '127.0.0.1' and parsed.port == 56821:
            continue
        if parsed.scheme != 'https' or parsed.hostname not in {
            'api.festapp.net', 'images.festapp.net', 'kjdpmixlnhntmxjedpxh.supabase.co'}:
            raise RuntimeError('Unexpected source-media host')
        # No local credential is sent to the public source URL.
        media = subprocess.check_output(['curl', '--fail', '--silent', '--show-error',
            '--max-time', '30', '--max-filesize', str(12 * 1024 * 1024), value])
        content_type = 'image/png' if media.startswith(b'\x89PNG') else (
            'image/jpeg' if media.startswith(b'\xff\xd8') else 'image/webp')
        if len(media) > 12 * 1024 * 1024:
            raise RuntimeError('Source background exceeds local media limit')
        name = str(source['occasion']['id']) + '-' + str(plan['id'])
        upload = urllib.request.Request(origin + '/storage/v1/object/' + bucket + '/' + name,
            data=media, headers={**headers, 'Content-Type': content_type, 'x-upsert': 'true'}, method='POST')
        with urllib.request.urlopen(upload) as response:
            response.read()
        plan['background_svg'] = origin + '/storage/v1/object/public/' + bucket + '/' + name
        copied += 1
snapshot_path.write_text(json.dumps(snapshot, ensure_ascii=False))
os.chmod(snapshot_path, 0o600)
print(f'Copied {copied} public plan backgrounds into local storage.')
