#!/usr/bin/env python3
"""Provision exactly one retained, closed synthetic Make reviewer dataset.

Reuse the canonical reviewer SQL seed, with guarded product-specific substitutions.
No existing reviewer memberships, events, accounts or grants are modified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import uuid

TEMPLATE_SHA256 = '06b7694665863923b62911740aa12a38158d3a0ab8d1dd29dffd7078f26ec1ef'
MARKER = 'make-review-20261028'
ROOT = Path(__file__).resolve().parents[3]

def render():
    source = (ROOT / 'integrations/chatgpt/review/provision-demo.sql').read_bytes()
    if hashlib.sha256(source).hexdigest() != TEMPLATE_SHA256:
        raise SystemExit('Canonical retained-demo seed changed; review before generating SQL')
    text = source.decode()
    replacements = {
        'FROM unnest(ARRAY[v_actor,v_owner]) actor_id;': 'FROM unnest(ARRAY[v_actor]) actor_id;',
        'FOR j IN 1..4 LOOP': 'FOR j IN 1..52 LOOP',
        "(ARRAY['ordered','paid','storno','waitlisted'])[j]": "(ARRAY['ordered','paid','storno','waitlisted'])[((j-1)%4)+1]",
        "CASE WHEN j=2 THEN v_price ELSE 0 END": "CASE WHEN v_state='paid' THEN v_price ELSE 0 END",
        'IF j<>4 THEN': "IF v_state<>'waitlisted' THEN",
        'CASE WHEN i=1 AND j=1 THEN': "CASE WHEN i=1 AND v_state='ordered' THEN",
        "'MCP demo - Testovací ples (leden)'": "'Make demo - Testovací ples'",
        "'MCP demo - Testovací ples (únor)'": "'Make demo - Testovací ples'",
    }
    for before, after in replacements.items():
        if text.count(before) != 1:
            raise SystemExit('Reviewed seed substitution changed: ' + before)
        text = text.replace(before, after)
    assert text.count('WHEN j=4 THEN') == 4
    text = text.replace('WHEN j=4 THEN', "WHEN v_state='waitlisted' THEN")
    text = text.replace('mcp-review-20261027', MARKER).replace('mcp-review@demo.vstupenky.online', 'make-review@demo.vstupenky.online')
    text = text.replace('MCP review - pouze syntetická data', 'Make review - pouze syntetická data')
    text = text.replace('MCP demo -', 'Make demo -').replace("'MCP','Reviewer'", "'Make','Reviewer'")
    assert 'ARRAY[v_actor,v_owner]' not in text
    assert 'FOR j IN 1..52 LOOP' in text
    return text.encode()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--private-dir', required=True, type=Path)
parser.add_argument('--owner', type=uuid.UUID)
parser.add_argument('--apply-revision')
parser.add_argument('--render-only', action='store_true')
args = parser.parse_args()
args.private_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
if args.private_dir.stat().st_mode & 0o077:
    raise SystemExit('Private directory must have mode 0700')
sql = render()
if args.render_only:
    out = args.private_dir / 'provision.sql'
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(sql)
    print(json.dumps({'status': 'rendered', 'sqlSha256': hashlib.sha256(sql).hexdigest(), 'ordersPerAccessibleEvent': 52, 'newActorOnly': True}))
    raise SystemExit(0)
if not args.owner or not args.apply_revision:
    raise SystemExit('--owner and exact canonical --apply-revision required')
relative = str(Path(__file__).resolve().relative_to(ROOT))
canonical = subprocess.check_output(['git', 'show', f'{args.apply_revision}:{relative}'], cwd=ROOT)
if canonical != Path(__file__).read_bytes():
    raise SystemExit('Provisioner differs from the exact canonical revision')
subprocess.run(['git', 'merge-base', '--is-ancestor', args.apply_revision, 'origin/main'], cwd=ROOT, check=True)
credentials_path = args.private_dir / 'credentials.json'
if credentials_path.exists():
    raise SystemExit('An attempt already exists: inspect private credentials/receipt and remote marker before retrying')
credentials = {'email': 'make-review@demo.vstupenky.online', 'password': secrets.token_urlsafe(36),
    'actor': str(uuid.uuid4()), 'organizationId': 3, 'sourceRevision': args.apply_revision, 'status': 'prepared'}
fd = os.open(credentials_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    json.dump(credentials, stream)
prelude = ('CREATE TEMP TABLE review_input(actor uuid,owner_id uuid,password text);\nCOPY review_input FROM STDIN;\n'
    + credentials['actor'] + '\t' + str(args.owner) + '\t' + credentials['password'] + '\n\\.\n')
remote = ('test "$(hostname -s)" = festapp-supabase-rehearsal-01 && '
    'docker exec -i supabase-db psql -X -qAt -U postgres -d festapp_rehearsal_20260909220601 -v ON_ERROR_STOP=1')
result = subprocess.run(['ssh', 'festapp-backend-agent', remote], input=prelude.encode() + sql, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if result.returncode:
    error = args.private_dir / 'provision-error.txt'
    fd = os.open(error, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(result.stderr)
    raise SystemExit('Provisioning failed; inspect private error and remote marker before any retry')
receipt = json.loads(result.stdout.decode().strip())
receipt.update(sourceRevision=args.apply_revision, sqlSha256=hashlib.sha256(sql).hexdigest(), newActorOnly=True, ordersPerAccessibleEvent=52)
assert len(receipt['orders']) == 104
receipt_path = args.private_dir / 'receipt.json'
fd = os.open(receipt_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    json.dump(receipt, stream, ensure_ascii=False, indent=2)
credentials['status'] = 'provisioned'
credentials_path.write_text(json.dumps(credentials))
print(json.dumps({'status': 'provisioned', 'occasionIds': receipt['occasionIds'], 'orders': len(receipt['orders']), 'credentials': 'protected file only'}))
