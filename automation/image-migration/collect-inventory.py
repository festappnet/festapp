#!/usr/bin/env python3
"""Read-only canonical inventory. Private row values never go to stdout/Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
DATABASE = 'festapp_rehearsal_20260909220601'
HOST = 'festapp-supabase-rehearsal-01'

DISK_SCRIPT = r'''
import hashlib,json,os
from pathlib import Path
root=Path('/opt/festapp-supabase/docker/volumes/storage')
assert os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'
for p in sorted(root.rglob('*')):
 if p.is_symlink():raise RuntimeError('storage_symlink_requires_review')
 if not p.is_file():continue
 before=p.stat()
 with p.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
 after=p.stat()
 assert (before.st_size,before.st_mtime_ns,before.st_ino)==(after.st_size,after.st_mtime_ns,after.st_ino),'source_changed_during_hash'
 print(json.dumps({'path':str(p.relative_to(root)),'size':after.st_size,'sha256':digest}))
'''


def capture(command, source, destination):
    # stderr can contain names/payloads on a query error; retain it protected too.
    with destination.open('xb') as out, destination.with_suffix('.stderr').open('xb') as err:
        result = subprocess.run(command, input=source.encode(), stdout=out, stderr=err)
    if result.returncode:
        raise RuntimeError('inventory_failed_see_protected_stderr')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    os.umask(0o077)
    a.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    identity = subprocess.check_output(['ssh', '-o', 'ConnectTimeout=20', 'festapp-backend-agent', 'hostname -s'], text=True).strip()
    assert identity == HOST, 'backend_host_mismatch'
    database = subprocess.check_output(['ssh', 'festapp-backend-agent', "sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' /opt/festapp-supabase/docker/.env"], text=True).strip()
    assert database == DATABASE, 'backend_database_mismatch'
    sql=(HERE/'inventory.sql').read_text()
    (a.output/'inventory.sql').write_text(sql)
    capture(['ssh', 'festapp-backend-agent', f'docker exec -i supabase-db psql -X -qAt -U postgres -d {DATABASE}'], sql, a.output/'database.ndjson')
    capture(['ssh', 'festapp-backend-agent', 'python3 -'], DISK_SCRIPT, a.output/'disk.ndjson')
    receipt = {name: hashlib.sha256((a.output/name).read_bytes()).hexdigest() for name in ('database.ndjson','disk.ndjson','inventory.sql')}
    (a.output/'capture.json').write_text(json.dumps({'version':1,'read_only':True,'sha256':receipt}, indent=2)+'\n')
    print(json.dumps({'read_only_inventory_captured':True,'sha256':receipt}))


if __name__ == '__main__':
    main()
