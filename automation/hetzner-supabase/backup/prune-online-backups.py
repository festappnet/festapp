#!/usr/bin/env python3
"""Prune complete daily backup sets, retaining daily and weekly recovery points."""
import argparse
import base64
import datetime as dt
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import socket
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

HOST = 'festapp-supabase-rehearsal-01'
BUCKET = 'festapp-supabase-backups'
PREFIX = f'backups/{HOST}/'
ARTIFACTS = {'postgres.dump.age', 'globals.sql.age', 'storage.tar.age', 'runtime.tar.age'}
NS = {'s': 'http://s3.amazonaws.com/doc/2006-03-01/'}


def choose_sets(complete_sets, now, daily_days=14, weekly_copies=4):
    """Keep recent daily sets, four completed calendar weeks and latest three."""
    if daily_days < 7 or weekly_copies < 4:
        raise ValueError('Retention must preserve at least 7 days and 4 weekly copies')
    keep = set()
    weekly = {}
    current_week = now.date().isocalendar()[:2]
    for prefix in complete_sets:
        if not re.fullmatch(re.escape(PREFIX) + r'\d{8}T\d{6}Z', prefix):
            raise ValueError('Unexpected backup prefix')
        stamp = dt.datetime.strptime(prefix.rsplit('/', 1)[-1], '%Y%m%dT%H%M%SZ').replace(tzinfo=dt.timezone.utc)
        if stamp >= now - dt.timedelta(days=daily_days):
            keep.add(prefix)
        week = stamp.date().isocalendar()[:2]
        if week < current_week:
            weekly[week] = max(weekly.get(week, prefix), prefix)
    keep.update(weekly[w] for w in sorted(weekly)[-weekly_copies:])
    keep.update(sorted(complete_sets)[-3:])
    return keep, sorted(set(complete_sets) - keep)


class Store:
    def __init__(self, config):
        if config.get('R2_BUCKET') != BUCKET:
            raise ValueError('Unexpected bucket')
        endpoint = urllib.parse.urlsplit(config['R2_ENDPOINT'])
        if endpoint.scheme != 'https' or not endpoint.hostname.endswith('.r2.cloudflarestorage.com'):
            raise ValueError('Unexpected R2 endpoint')
        self.host = endpoint.netloc
        self.access = config['AWS_ACCESS_KEY_ID']
        self.secret = config['AWS_SECRET_ACCESS_KEY']

    def request(self, method, key='', params=None, body=b'', md5=False):
        path = '/' + BUCKET + ('/' + urllib.parse.quote(key, safe='/') if key else '')
        query = urllib.parse.urlencode(sorted((params or {}).items()), quote_via=urllib.parse.quote)
        now = dt.datetime.now(dt.timezone.utc)
        stamp, day = now.strftime('%Y%m%dT%H%M%SZ'), now.strftime('%Y%m%d')
        payload_hash = hashlib.sha256(body).hexdigest()
        headers = {'host': self.host, 'x-amz-content-sha256': payload_hash, 'x-amz-date': stamp}
        if md5:
            headers['content-md5'] = base64.b64encode(hashlib.md5(body).digest()).decode()
        names = sorted(headers)
        signed = ';'.join(names)
        canonical_headers = ''.join(f'{name}:{headers[name]}\n' for name in names)
        canonical = '\n'.join([method, path, query, canonical_headers, signed, payload_hash])
        scope = day + '/auto/s3/aws4_request'
        to_sign = '\n'.join(['AWS4-HMAC-SHA256', stamp, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        signing_key = ('AWS4' + self.secret).encode()
        for part in [day, 'auto', 's3', 'aws4_request']:
            signing_key = hmac.new(signing_key, part.encode(), hashlib.sha256).digest()
        signature = hmac.new(signing_key, to_sign.encode(), hashlib.sha256).hexdigest()
        headers['Authorization'] = f'AWS4-HMAC-SHA256 Credential={self.access}/{scope}, SignedHeaders={signed}, Signature={signature}'
        req = urllib.request.Request('https://' + self.host + path + ('?' + query if params else ''),
                                     data=body if method == 'POST' else None, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            # Never include signed headers, URLs or provider response bodies in logs.
            raise RuntimeError(f'R2 request failed with HTTP {error.code}') from None

    def list(self):
        rows, token = [], None
        while True:
            params = {'list-type': '2', 'prefix': PREFIX, 'max-keys': '1000'}
            if token:
                params['continuation-token'] = token
            root = ET.fromstring(self.request('GET', params=params))
            for obj in root.findall('s:Contents', NS):
                rows.append({'Path': obj.findtext('s:Key', namespaces=NS),
                             'Size': int(obj.findtext('s:Size', namespaces=NS)),
                             'ModTime': obj.findtext('s:LastModified', namespaces=NS)})
            if root.findtext('s:IsTruncated', namespaces=NS) != 'true':
                return rows
            token = root.findtext('s:NextContinuationToken', namespaces=NS)
            if not token:
                raise RuntimeError('Truncated inventory lacks continuation token')

    def delete(self, keys):
        for offset in range(0, len(keys), 1000):
            batch = keys[offset:offset + 1000]
            if any(not key.startswith(PREFIX) for key in batch):
                raise ValueError('Delete outside backup prefix')
            root = ET.Element('Delete', xmlns=NS['s'])
            for key in batch:
                ET.SubElement(ET.SubElement(root, 'Object'), 'Key').text = key
            ET.SubElement(root, 'Quiet').text = 'true'
            result = ET.fromstring(self.request('POST', params={'delete': ''}, body=ET.tostring(root), md5=True))
            if result.findall('s:Error', NS):
                raise RuntimeError('R2 reported partial deletion; inspect the protected manifest')


def complete_sets(store, rows):
    grouped = {}
    for row in rows:
        prefix, _, name = row['Path'].rpartition('/')
        if re.fullmatch(re.escape(PREFIX) + r'\d{8}T\d{6}Z', prefix):
            grouped.setdefault(prefix, {})[name] = row
    complete = {}
    for prefix, objects in grouped.items():
        if set(objects) != ARTIFACTS | {'manifest.json'}:
            continue  # Preserve incomplete, unrecognized or extended sets.
        manifest = json.loads(store.request('GET', prefix + '/manifest.json'))
        if (manifest.get('source_host') != HOST or manifest.get('encrypted') is not True
                or manifest.get('consistency') != 'online-operational-backup-not-promotion-rpo0'
                or manifest.get('destination', {}).get('prefix') != prefix
                or manifest.get('destination', {}).get('bucket') != BUCKET):
            continue  # Preserve non-routine recovery evidence.
        facts = manifest.get('artifacts', {})
        if set(facts) != ARTIFACTS or any(
                objects[name]['Size'] != facts[name].get('bytes') or objects[name]['Size'] <= 0
                or not re.fullmatch(r'[0-9a-f]{64}', facts[name].get('sha256', ''))
                for name in ARTIFACTS):
            raise RuntimeError('Backup manifest and object inventory disagree')
        complete[prefix] = list(objects.values())
    if len(complete) < 3:
        raise RuntimeError('Fewer than three verified complete backup sets; refusing cleanup')
    return complete


def save(path, value):
    # The evidence directory is root-owned; create private files atomically.
    temporary = path.with_suffix(path.suffix + '.tmp')
    with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as handle:
        json.dump(value, handle, sort_keys=True)
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--config', default='/etc/festapp-backup/r2.env')
    parser.add_argument('--evidence-dir', required=True)
    parser.add_argument('--daily-days', type=int, default=14)
    parser.add_argument('--weekly-copies', type=int, default=4)
    args = parser.parse_args()
    if os.geteuid() != 0 or socket.gethostname().split('.')[0] != HOST:
        raise RuntimeError('Run as root on the verified Festapp backup host')
    config_path = Path(args.config)
    stat = config_path.stat()
    if stat.st_uid != 0 or stat.st_mode & 0o777 != 0o600:
        raise RuntimeError('Backup config must be root-owned mode 0600')
    config = {}
    for line in config_path.read_text().splitlines():
        key, sep, value = line.strip().partition('=')
        if sep:
            config[key] = value.strip('"').strip("'")
    store = Store(config)
    now = dt.datetime.now(dt.timezone.utc)
    rows = store.list()
    complete = complete_sets(store, rows)
    keep, remove = choose_sets(complete, now, args.daily_days, args.weekly_copies)
    selected = [row for prefix in remove for row in complete[prefix]]
    evidence = {'version': 1, 'created_at': now.isoformat(), 'bucket': BUCKET, 'scope_prefix': PREFIX,
                'daily_days': args.daily_days, 'weekly_copies': args.weekly_copies,
                'status': 'planned', 'selected': selected, 'preserved_sets': sorted(keep),
                'selected_bytes': sum(row['Size'] for row in selected), 'selected_sets': len(remove)}
    evidence_dir = Path(args.evidence_dir)
    if not evidence_dir.is_dir() or evidence_dir.stat().st_uid != 0:
        raise RuntimeError('Evidence directory must exist and be root-owned')
    evidence_path = evidence_dir / ('backup-retention-' + now.strftime('%Y%m%dT%H%M%S') + '-' + os.urandom(4).hex() + '.json')
    save(evidence_path, evidence)
    if args.apply and selected:
        # Recheck identities immediately before irreversible deletion. A backup
        # writer uploads immutable keys; unexpected change aborts this operation.
        current = {row['Path']: row for row in store.list()}
        if any(current.get(row['Path']) != row for row in selected):
            raise RuntimeError('Inventory changed before deletion')
        store.delete([row['Path'] for row in selected])
        after = {row['Path']: row for row in store.list()}
        if any(row['Path'] in after for row in selected):
            raise RuntimeError('Selected objects remain after deletion')
        if any(after.get(row['Path']) != row for prefix in keep for row in complete[prefix]):
            raise RuntimeError('Preserved recovery points changed during deletion')
        evidence['status'] = 'deleted_and_verified'
        save(evidence_path, evidence)
    elif args.apply:
        evidence['status'] = 'nothing_to_delete'
        save(evidence_path, evidence)
    print(json.dumps({'status': evidence['status'], 'selected_sets': len(remove), 'preserved_sets': len(keep),
                      'selected_objects': len(selected), 'selected_bytes': evidence['selected_bytes'],
                      'evidence_file': str(evidence_path)}))


if __name__ == '__main__':
    main()
