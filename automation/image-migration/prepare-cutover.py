#!/usr/bin/env python3
"""Prepare private, exact registry/reference inputs from a verified copy set.

No database connection or production mutations. SQL execution and client-sync
publication are a separate gate; the edit bundle preserves exact prestates.
"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
from urllib.parse import quote

from storage_references import digest, inspect_value, rewrite_value


def identity_hash(identity):
    # The copy driver's JSON.stringify preserves the declared bucket/key order.
    value = {'bucket': identity['bucket'], 'key': identity['key']}
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def prepare(manifest, manifest_sha256, receipts):
    if not manifest['summary'].get('ready_for_reference_rewrite'):
        raise ValueError('complete_reference_inventory_required')
    if not manifest['summary'].get('ready_for_copy'):
        raise ValueError('complete_source_inventory_required')
    expected = list(manifest['objects']) + list(manifest.get('orphan_objects', []))
    expected += [dict(identity={'bucket': o['source_bucket'], 'key': o['key']},
                      destination={'bucket': o['destination_bucket'], 'key': o['destination_key']},
                      source={'size': o['size'], 'sha256': o['sha256']},
                      metadata={'mimetype': o['source_metadata'].get('Metadata', {}).get('content-type')
                                or o['source_metadata'].get('MimeType')})
                 for o in manifest['r2_objects']]
    verified = {}
    revisions = set()
    for obj in expected:
        key = identity_hash(obj['identity'])
        if key in verified:
            raise ValueError('duplicate_source_identity')
        r = receipts.get(key)
        if not r:
            raise ValueError('copy_receipt_missing')
        if (r.get('version') != 1 or r.get('identity') != obj['identity']
                or r.get('destination') != obj['destination']
                or r.get('sha256') != obj['source']['sha256']
                or r.get('size') != obj['source']['size']
                or r.get('contentType') != obj['metadata']['mimetype']
                or r.get('manifestSha256') != manifest_sha256
                or r.get('r2InventorySha256') != manifest['r2_inventory_sha256']):
            raise ValueError('copy_receipt_mismatch')
        revision = r.get('sourceRevision', '')
        if len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
            raise ValueError('copy_source_revision_required')
        at = datetime.fromisoformat(r.get('verifiedAt', '').replace('Z', '+00:00'))
        if at.tzinfo is None:
            raise ValueError('copy_timestamp_timezone_required')
        revisions.add(revision)
        verified[key] = r
    if len(revisions) != 1:
        raise ValueError('mixed_copy_source_revisions')

    mapping, registry = {}, []
    for obj in manifest['objects']:
        original = obj['source_storage_record']
        receipt = verified[identity_hash(obj['identity'])]
        registry.append(dict(bucket=obj['destination']['bucket'], object_key=obj['destination']['key'],
                             sha256=receipt['sha256'], bytes=receipt['size'], content_type=receipt['contentType'],
                             visibility=obj['visibility'], owner_id=original.get('owner_id'),
                             source_bucket=obj['identity']['bucket'], source_key=obj['identity']['key'],
                             source_storage_record=original, verified_at=receipt['verifiedAt']))
        # There is deliberately no invented public URL for a private object.
        # A consumed private reference needs its reviewed authorization boundary.
        if obj['visibility'] == 'public':
            mapping[(obj['identity']['bucket'], obj['identity']['key'])] = {
                'visibility': 'public',
                'url': 'https://img.festapp.net/' + quote(obj['destination']['key'], safe='/')}
    edits = []
    identities = set()
    for field in manifest['fields']:
        if field['classification'] != 'current':
            continue
        if field['issues'] or not field['key'] or field['schema'] not in ('public', 'eshop'):
            raise ValueError('unresolved_current_field')
        if digest(field['original']) != field['original_digest']:
            raise ValueError('field_prestate_digest_mismatch')
        identity = (field['schema'], field['table'], digest(field['key']), field['field'])
        if identity in identities:
            raise ValueError('duplicate_field_identity')
        identities.add(identity)
        try:
            after = rewrite_value(field['original'], set(manifest['owned_hosts']), mapping)
        except KeyError:
            raise ValueError('private_reference_boundary_or_source_missing') from None
        if after == field['original'] or list(inspect_value(after, set(manifest['owned_hosts']))):
            raise ValueError('incomplete_field_rewrite')
        edits.append({k: field[k] for k in ('schema', 'table', 'key', 'field', 'original', 'original_digest')}
                     | {'replacement': after, 'replacement_digest': digest(after)})
    return dict(version=1, manifest_sha256=manifest_sha256,
                r2_inventory_sha256=manifest['r2_inventory_sha256'], copy_source_revision=revisions.pop(),
                verified_objects=len(verified), registry=registry, edits=edits,
                retained_orphan_objects=manifest.get('orphan_objects', []),
                requires_atomic_client_sync_publication=True, production_mutations=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--receipts', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    body = args.manifest.read_bytes()
    manifest = json.loads(body)
    receipt_files = list(args.receipts.glob('*.json'))
    if any(p.is_symlink() or p.stat().st_uid != os.getuid() or p.stat().st_mode & 0o077 for p in receipt_files):
        raise ValueError('private_owned_receipt_files_required')
    result = prepare(manifest, hashlib.sha256(body).hexdigest(),
                     {p.stem: json.loads(p.read_bytes()) for p in receipt_files})
    # Exclusive creation: a prepared predecessor must remain independently auditable.
    with args.output.open('x') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({'verified_objects': result['verified_objects'], 'registry_rows': len(result['registry']),
                      'current_field_edits': len(result['edits']), 'production_mutations': False}))


if __name__ == '__main__':
    main()
