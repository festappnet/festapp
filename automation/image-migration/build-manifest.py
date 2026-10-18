#!/usr/bin/env python3
"""Seal a protected candidate manifest; unresolved rows prevent cutover.

This does not mutate the database or assume that a public bucket makes a signed
reference public. Unowned/orphaned sources remain inventoried, never discarded.
"""
import argparse
import hashlib
from collections import Counter, defaultdict
import json
import os
from pathlib import Path
from urllib.parse import quote
from storage_references import digest, inspect_value, storage_identity

HERE = Path(__file__).resolve().parent
HISTORY = {'log_app_config', 'log_emails', 'log_notifications', 'email_messages',
           'email_delivery_attempts', 'email_provider_events'}


def private_storage_closed(records):
    """Recognize the audited closed client boundary, never interpret arbitrary SQL.

    Original null ownership can be preserved under service custody only when
    we know that private client access will not be silently narrowed or widened.
    Changed/unrecognized permissive policies require a fresh explicit decision.
    """
    security = [r for r in records if r['kind'] == 'storage_security']
    if len(security) != 1 or security[0].get('rls') is not True:
        return False
    roles = security[0].get('client_roles') or []
    if {r['name'] for r in roles} != {'anon', 'authenticated'} or any(r['bypass'] or r['superuser'] for r in roles):
        return False
    policies = [r['value'] for r in records if r['kind'] == 'storage_policy']
    if not policies:
        return False
    return all(p['cmd'] not in ('SELECT', 'ALL') or p['permissive'] != 'PERMISSIVE' or
        (p['roles'] == ['authenticated'] and p['cmd'] == 'SELECT' and
         p['qual'] == "((bucket_id = 'public-files'::text) AND can_delete_legacy_image_v1(name))")
        for p in policies)


def build(records, disk, hosts, *, retain_ownerless=False, retain_orphan_bytes=False):
    closed_private_boundary = private_storage_closed(records) if retain_ownerless else False
    objects, buckets, relations, rows, failures = {}, {}, {}, [], []
    for item in records:
        kind = item['kind']
        if kind == 'schema' and item['classification']=='unclassified':
            failures.append('application_schema_classification_required')
        if kind == 'object':
            obj = item['value']; objects[(obj['bucket_id'], obj['name'])] = obj
        elif kind == 'bucket':
            buckets[item['value']['id']] = item['value']
        elif kind == 'relation':
            relations[(item['schema'], item['table'])] = item
        elif kind == 'row':
            rows.append(item)
    files = {item['path']: item for item in disk}
    linked_files, manifests, mutations = set(), [], []
    image_owners = defaultdict(set)
    for row in rows:
        if row['schema'] == 'public' and row['table'] == 'images':
            value = row['value']
            try: identity = storage_identity(value.get('link', ''), hosts)
            except ValueError: continue
            if identity:
                for field in ('occasion', 'unit'):
                    if value.get(field) is not None:
                        image_owners[(identity['bucket'], identity['key'])].add(f'{field}:{value[field]}')
    for identity, obj in objects.items():
        bucket, key = identity
        prefix = f'stub/stub/{bucket}/{key}'
        version = obj.get('version')
        candidates = [prefix+'/'+version, prefix+'-$v-'+version] if version else [prefix]
        matches = [x for x in candidates if x in files]
        issues = []
        if len(matches) != 1:
            issues.append('source_locator_missing_or_ambiguous')
        source = files[matches[0]] if len(matches) == 1 else None
        if source:
            linked_files.add(source['path'])
            expected = obj.get('metadata', {}).get('size')
            if expected is not None and int(expected) != source['size']:
                issues.append('source_metadata_size_mismatch')
        owners = sorted(image_owners[identity])
        if obj.get('owner_id'):
            owners.append('user:'+obj['owner_id'])
        if bucket == 'ticket-fonts':
            owners.append('service:ticket-fonts')
        custody = None
        if not owners:
            # A proven original absence is not an invented user assignment.
            # Keep owner/owner_id verbatim, deny application mutation, and keep
            # private objects service-only. Default remains fail-closed.
            if retain_ownerless and 'owner' in obj and 'owner_id' in obj and obj['owner'] is None and obj['owner_id'] is None and closed_private_boundary:
                custody = {'kind':'unassigned-legacy-retention','application_write_grant':False,
                           'source_record_sha256':digest(obj)}
            else:
                issues.append('ownership_unresolved')
        public = buckets[bucket]['public']
        if bucket == 'ticket-fonts' and public:
            issues.append('font_bucket_unexpectedly_public')
        visibility = 'public' if public else 'private'
        sha = source['sha256'] if source else None
        if bucket == 'ticket-fonts':
            destination_key = 'ticket-fonts/'+key
            if not key.startswith('sha256/') or key.split('/')[-1].split('.')[0] != sha:
                issues.append('font_key_hash_mismatch')
        else:
            owner_hash = digest(owners)[:20] if owners else digest({'custody':custody['kind'],'bucket':bucket})[:20] if custody else 'unresolved'
            # Registry images retain the path contract understood by released
            # clients. Other binary assets use the approved assets namespace.
            purpose = 'images' if image_owners[identity] else 'assets'
            destination_key = f'{purpose}/storage/{bucket}/{owner_hash}/{digest(identity)}/{sha or "unresolved"}'
        destination_bucket = 'festapp-images' if public else 'festapp-images-private'
        item = {'identity': {'bucket':bucket,'key':key}, 'source':source,
                'owners':owners,'custody':custody,'visibility':visibility, 'metadata':obj.get('metadata'),
                'source_storage_record':obj,
                'destination':{'bucket':destination_bucket,'key':destination_key},'issues':issues}
        manifests.append(item)
    indexed = {(item['identity']['bucket'],item['identity']['key']):item for item in manifests}
    copy_failures = list(failures) + [issue for obj in manifests for issue in obj['issues']]
    for row in rows:
        schema, table, value = row['schema'], row['table'], row['value']
        relation = relations[(schema,table)]
        history = table in HISTORY or table.startswith('log_')
        pk = {column:value[column] for column in relation['primary_key']}
        columns = {column['name']:column for column in relation['columns']}
        for field, original in value.items():
            # Stored generated search documents normalize/lowercase HTML URLs.
            # They are refreshed by their owning source fields, never treated
            # as independent byte-preserving source locators or writable fields.
            if columns[field]['generated']:
                continue
            refs = list(inspect_value(original, hosts))
            if not refs: continue
            issues = []
            for ref in refs:
                if 'error' in ref: issues.append(ref['error']); continue
                source = indexed.get((ref['identity']['bucket'],ref['identity']['key']))
                if not source: issues.append('reference_source_not_in_storage'); continue
                if source['issues']: issues.append('reference_source_unresolved')
                if ref['identity']['route'] != 'public' and source['visibility']=='public':
                    issues.append('signed_public_reference_requires_review')
                if source['visibility']=='private' and ref['identity']['bucket']!='ticket-fonts':
                    issues.append('private_permission_boundary_required')
            if not pk: issues.append('durable_row_key_missing')
            if relation['relation_kind']=='m': issues.append('materialized_view_refresh_required')
            record = {'schema':schema,'table':table,'key':pk,'field':field,
                      'original':original,'original_digest':digest(original),'references':refs,
                      'classification':'history' if history else 'current','issues':sorted(set(issues))}
            mutations.append(record)
            if not history:
                failures.extend(record['issues'])
    orphan_files = [item for name,item in files.items() if name not in linked_files]
    orphan_objects = []
    if retain_orphan_bytes:
        # No registry metadata means no evidence of a public read or a human
        # owner. Retain exact bytes privately, without inventing either. These
        # objects are not destinations for any current application reference.
        for source in orphan_files:
            identity = {'bucket':'orphan-files','key':source['path']}
            custody = {'kind':'unregistered-disk-retention','application_write_grant':False}
            key = f'assets/storage/orphan-files/{digest(custody)[:20]}/{digest(identity)}/{source["sha256"]}'
            orphan_objects.append({'identity':identity,'source':source,'owners':[],
                'custody':custody,'visibility':'private','source_kind':'unregistered-disk-file',
                'metadata':{'mimetype':'application/octet-stream'},'source_storage_record':None,
                'destination':{'bucket':'festapp-images-private','key':key},'issues':[]})
    failures.extend(issue for obj in manifests for issue in obj['issues'])
    if orphan_files and not retain_orphan_bytes:
        failures.append('disk_orphan_disposition_required')
        copy_failures.append('disk_orphan_disposition_required')
    summary = {'storage_objects':len(objects),'disk_files':len(files),'matched_disk_files':len(linked_files),
               'unreferenced_disk_files':len(orphan_files),'relations_scanned':len(relations),
               'privately_retained_orphan_objects':len(orphan_objects),
               'current_fields':sum(x['classification']=='current' for x in mutations),
               'history_fields':sum(x['classification']=='history' for x in mutations),
               'current_references':sum(len(x['references']) for x in mutations if x['classification']=='current'),
               'objects_with_issues':sum(bool(x['issues']) for x in manifests),
               'blockers':dict(Counter(failures)),'copy_blockers':dict(Counter(copy_failures)),
               'ready_for_copy':not copy_failures,'ready_for_reference_rewrite':not failures,
               'production_mutations':False}
    return {'version':1,'objects':manifests,'orphan_objects':orphan_objects,'fields':mutations,'unreferenced_disk_files':orphan_files,
            'relations':list(relations.values()),'summary':summary}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--capture',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--r2-inventory',type=Path)
    parser.add_argument('--retain-ownerless',action='store_true',help='Preserve proven null ownership under service custody; requires captured closed private policies.')
    parser.add_argument('--retain-orphan-bytes',action='store_true',help='Retain every unregistered disk file in private R2 custody; never expose it through application references.')
    args = parser.parse_args()
    os.umask(0o077)
    args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    registry = json.loads((HERE.parent/'hetzner-supabase/merge/source-registry.json').read_text())
    hosts = {'api.festapp.net'} | {source['project_ref']+'.supabase.co' for source in registry['sources']}
    def records(name):
        return [json.loads(line) for line in (args.capture/name).read_text().splitlines() if line.strip()]
    manifest = build(records('database.ndjson'),records('disk.ndjson'),hosts,
                     retain_ownerless=args.retain_ownerless,retain_orphan_bytes=args.retain_orphan_bytes)
    manifest['owned_hosts']=sorted(hosts)
    manifest['capture']=json.loads((args.capture/'capture.json').read_text())
    if args.r2_inventory:
        body=args.r2_inventory.read_bytes()
        r2=json.loads(body)
        assert r2['version']==1 and r2['read_only'] is True
        assert all(obj['source_bucket'] in ('festapp-images','festapp-images-a','festapp-images-private','festapp-images-a-private') for obj in r2['objects'])
        manifest['r2_inventory_sha256']=hashlib.sha256(body).hexdigest()
        manifest['r2_objects']=r2['objects']
        manifest['summary']['r2_objects']=len(r2['objects'])
        manifest['summary']['r2_bytes']=sum(obj['size'] for obj in r2['objects'])
    else:
        manifest['summary']['blockers']['r2_inventory_required']=1
        manifest['summary']['ready_for_copy']=False
        manifest['summary']['ready_for_reference_rewrite']=False
    (args.output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    (args.output/'summary.json').write_text(json.dumps(manifest['summary'],indent=2)+'\n')
    print(json.dumps(manifest['summary']))


if __name__=='__main__': main()
