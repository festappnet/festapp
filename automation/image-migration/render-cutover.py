#!/usr/bin/env python3
"""Render an exact private operator transaction; never connect to a database."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess

from storage_references import digest


def render(bundle, template, source_revision):
    if bundle.get('version') != 1 or bundle.get('production_mutations') is not False:
        raise ValueError('verified_private_bundle_required')
    if not bundle.get('requires_atomic_client_sync_publication'):
        raise ValueError('atomic_publication_required')
    if not re.fullmatch('[a-f0-9]{64}', bundle.get('manifest_sha256', '')) or not re.fullmatch('[a-f0-9]{40}', source_revision):
        raise ValueError('sealed_source_identity_required')
    for field in bundle['edits']:
        if digest(field['original']) != field['original_digest'] or digest(field['replacement']) != field['replacement_digest']:
            raise ValueError('field_digest_mismatch')
    body = json.dumps(bundle, ensure_ascii=False, separators=(',', ':'))
    # A random dollar delimiter keeps all customer content literal SQL data,
    # including quotes, semicolons, backslashes and apparent SQL statements.
    delimiter = '$asset_' + secrets.token_hex(24) + '$'
    while delimiter in body:
        delimiter = '$asset_' + secrets.token_hex(24) + '$'
    return ('\\set ON_ERROR_STOP on\n'
            f'-- Canonical source: {source_revision}\n'
            f'-- Template SHA-256: {hashlib.sha256(template.encode()).hexdigest()}\n'
            f'-- Verified manifest SHA-256: {bundle["manifest_sha256"]}\n'
            'BEGIN;\nSET LOCAL standard_conforming_strings=on;\n'
            'CREATE TEMP TABLE asset_cutover_input(payload jsonb NOT NULL) ON COMMIT DROP;\n'
            f'INSERT INTO asset_cutover_input VALUES({delimiter}{body}{delimiter}::jsonb);\n'
            + template + '\nCOMMIT;\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--custody-output', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    root = Path(__file__).resolve().parents[2]
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    source = git('rev-parse', 'HEAD')
    if source != git('rev-parse', 'origin/main') or git('status', '--porcelain'):
        raise ValueError('reviewed_clean_canonical_main_required')
    stat = args.bundle.stat()
    if args.bundle.is_symlink() or stat.st_uid != os.getuid() or stat.st_mode & 0o077:
        raise ValueError('private_owned_bundle_required')
    bundle = json.loads(args.bundle.read_bytes())
    sql = render(bundle, (Path(__file__).parent / 'apply-cutover.sql').read_text(), source)
    custody = {'version': 1, 'source_manifest_sha256': bundle['manifest_sha256'],
               'objects': bundle['retained_orphan_objects']}
    for obj in custody['objects']:
        if (obj['source_storage_record'] is not None or obj['visibility'] != 'private'
                or obj['destination']['bucket'] != 'festapp-images-private'
                or obj['custody'].get('application_write_grant') is not False):
            raise ValueError('private_unassigned_custody_required')
    if args.output.exists() or args.custody_output.exists():
        raise ValueError('prepared_predecessor_must_be_preserved')
    with args.custody_output.open('x') as output:
        json.dump(custody, output, ensure_ascii=False, indent=2)
        output.write('\n')
    with args.output.open('x') as output:
        output.write(sql)
    print(json.dumps({'transaction_sha256': hashlib.sha256(sql.encode()).hexdigest(),
                      'source_revision': source, 'retained_orphan_objects': len(custody['objects']),
                      'production_mutations': False}))


if __name__ == '__main__':
    main()
