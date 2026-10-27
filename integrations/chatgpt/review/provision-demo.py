#!/usr/bin/env python3
"""Provision the one explicitly authorized regional reviewer dataset.

Credentials go only to a private operator directory. No service key, delivery
API or public registration endpoint is used. Existing business data is untouched.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--owner', required=True, type=uuid.UUID)
parser.add_argument('--private-dir', required=True, type=Path)
parser.add_argument('--apply-revision', required=True)
args = parser.parse_args()
source = Path(__file__).with_suffix('.sql')
root = source.parents[3]
relative = str(source.relative_to(root))
canonical = subprocess.check_output(['git', 'show', f'{args.apply_revision}:{relative}'], cwd=root)
subprocess.run(['git', 'merge-base', '--is-ancestor', args.apply_revision, 'origin/main'], cwd=root, check=True)
if canonical != source.read_bytes():
    raise SystemExit('SQL differs from the exact approved revision')
args.private_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
if args.private_dir.stat().st_mode & 0o077:
    raise SystemExit('Private directory permissions must be 0700')
credential_path = args.private_dir / 'credentials.json'
if credential_path.exists():
    raise SystemExit('Private credentials already exist; inspect the attempt before any retry')
credentials = {'email': 'mcp-review@demo.vstupenky.online', 'password': secrets.token_urlsafe(36),
               'actor': str(uuid.uuid4()), 'organizationId': 3, 'sourceRevision': args.apply_revision,
               'status': 'prepared'}
fd = os.open(credential_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    json.dump(credentials, stream)
prelude = ('CREATE TEMP TABLE review_input(actor uuid,owner_id uuid,password text);\n'
           'COPY review_input FROM STDIN;\n' + credentials['actor'] + '\t' + str(args.owner) +
           '\t' + credentials['password'] + '\n\\.\n')
remote = ("test \"$(hostname -s)\" = festapp-supabase-rehearsal-01 && "
          "docker exec -i supabase-db psql -X -qAt -U postgres "
          "-d festapp_rehearsal_20260909220601 -v ON_ERROR_STOP=1")
result = subprocess.run(['ssh', 'festapp-backend-agent', remote], input=prelude.encode() + canonical,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if result.returncode:
    # SQL errors cannot contain private COPY data, but still retain diagnostics
    # privately instead of echoing arbitrary database output.
    error_path = args.private_dir / 'provision-error.txt'
    fd = os.open(error_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(result.stderr)
    raise SystemExit('Provisioning failed; inspect private provision-error.txt before retrying')
receipt = json.loads(result.stdout.decode().strip())
receipt['sourceRevision'] = args.apply_revision
receipt['sqlSha256'] = hashlib.sha256(canonical).hexdigest()
receipt_path = args.private_dir / 'receipt.json'
fd = os.open(receipt_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    json.dump(receipt, stream, ensure_ascii=False, indent=2)
credentials['status'] = 'provisioned'
credential_path.write_text(json.dumps(credentials))
print(json.dumps({'status': 'provisioned', 'occasionIds': receipt['occasionIds'],
                  'orders': len(receipt['orders']), 'credentials': 'private file only'}))
