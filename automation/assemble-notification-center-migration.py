#!/usr/bin/env python3
"""Assemble the feed forward migration. Historical migrations are immutable inputs."""
from pathlib import Path
import argparse
import json
import hashlib

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
manifest = json.loads((root / 'automation/notification-center-feed-manifest.json').read_text())
canonical = root / manifest['output']
out = args.output.resolve() if args.output else canonical
historical = root / 'supabase/migrations/20261023210000_organization_notification_center.sql'
if out == historical or out.name in manifest['prerequisites']:
    raise SystemExit('Refusing to overwrite historical prerequisite migration')
for prerequisite in manifest['prerequisites']:
    if not (root / 'supabase/migrations' / prerequisite).is_file():
        raise SystemExit('Missing prerequisite: ' + prerequisite)
    if hashlib.sha256((root / 'supabase/migrations' / prerequisite).read_bytes()).hexdigest() != manifest['prerequisiteSha256'][prerequisite]:
        raise SystemExit('Historical prerequisite digest differs: ' + prerequisite)
text = '-- Generated forward migration: ' + manifest['name'] + '\n'
text += '-- Prerequisites: ' + ', '.join(manifest['prerequisites']) + '\nBEGIN;\n'
text += "DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;\n"
for source in manifest['sources']:
    content = (root / 'database/functions' / source).read_text()
    if source == 'notification_center/maintenance.sql':
        # Its table prefix belongs to the immutable prerequisite, functions to this delta.
        content = 'CREATE OR REPLACE FUNCTION' + content.split('CREATE OR REPLACE FUNCTION', 1)[1]
    text += '\n-- SOURCE: ' + source + '\n' + content + '\n'
text += 'COMMIT;\n'
tables = root / 'database/tables/tables.sql'
start = '\n-- Organization notification center private projections.\n'
end = '-- End organization notification center private projections.\n'
block = start + (root/'database/functions/notification_center/schema.sql').read_text() + (root/'database/functions/notification_center/maintenance.sql').read_text().split('CREATE OR REPLACE FUNCTION')[0] + end
current = tables.read_text()
before, tail = current.split(start, 1)
canonical_tables = before + block + tail.split(end, 1)[1]
if args.check:
    if current != canonical_tables:
        raise SystemExit('Notification table definitions differ from canonical schema')
    if not out.is_file() or out.read_text() != text:
        raise SystemExit('Notification forward migration differs from manifest sources')
    print('Notification feed migration and canonical tables match')
else:
    if out.exists() and out.read_text() != text:
        raise SystemExit('Refusing to overwrite an existing different output')
    out.write_text(text)
    tables.write_text(canonical_tables)
    print(out)
