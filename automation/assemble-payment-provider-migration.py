#!/usr/bin/env python3
"""Verify immutable connector migration and its archived exact source inputs."""
import migration_inputs
from pathlib import Path
import argparse, hashlib, json, re
ROOT = Path(__file__).resolve().parents[1]
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    if not parser.parse_args().check:
        raise SystemExit('Connector migration is frozen. Use assemble-payment-provider-hardening-migration.py.')
    archive = ROOT / 'docs/plans/payment-provider-hardening'
    frozen = json.loads(migration_inputs.read_text(archive/'frozen-inputs.json'))['files']
    manifest_path = 'automation/payment-provider-migration.json'
    manifest_bytes = migration_inputs.read_bytes(archive/'history'/manifest_path)
    manifest = json.loads(manifest_bytes)
    migration_path = 'supabase/migrations/' + manifest['migration']
    migration_bytes = migration_inputs.read_bytes(ROOT/migration_path)
    if hashlib.sha256(migration_bytes).hexdigest() != frozen[migration_path]:
        raise SystemExit('Changed frozen connector migration: ' + migration_path)

    # The immutable migration already contains every historical source verbatim.
    # Recover those bytes in memory instead of retaining a second SQL archive.
    sections = re.split(r'^-- SOURCE: (.+)\n', migration_bytes.decode(), flags=re.M)
    if sections[1::2] != manifest['sources']:
        raise SystemExit('Historical connector source order changed')
    recovered = {manifest_path: manifest_bytes, migration_path: migration_bytes}
    for source, body in zip(sections[1::2], sections[2::2]):
        body = body.rstrip()
        if source.startswith(('payment_providers/', 'eshop_stripe/')):
            prefix, suffix = 'SET LOCAL ROLE postgres;\n', '\nRESET ROLE;'
            if not body.startswith(prefix) or not body.endswith(suffix):
                raise SystemExit('Historical connector role boundary changed: ' + source)
            body = body[len(prefix):-len(suffix)]
        recovered['database/functions/' + source] = (body + '\n').encode()
    if recovered.keys() != frozen.keys():
        raise SystemExit('Historical connector input inventory changed')
    for name, content in recovered.items():
        if hashlib.sha256(content).hexdigest() != frozen[name]:
            raise SystemExit('Changed archived connector input: ' + name)
    parts = ['-- Payment provider connectors. Forward-only; no provider activation or production application.']
    for source in manifest['sources']:
        body = recovered['database/functions/' + source].decode().rstrip()
        if source.startswith(('payment_providers/', 'eshop_stripe/')):
            body = 'SET LOCAL ROLE postgres;\n' + body + '\nRESET ROLE;'
        parts.append('-- SOURCE: ' + source + '\n' + body)
    if '\n\n'.join(parts) + '\n' != migration_bytes.decode():
        raise SystemExit('Historical connector inputs do not reproduce the frozen migration')
    print('Connector migration and exact reproducible historical inputs unchanged')
if __name__ == '__main__': main()
