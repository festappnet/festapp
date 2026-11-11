#!/usr/bin/env python3
"""Assemble the feed forward migration. Historical migrations are immutable inputs."""
import migration_inputs
from pathlib import Path
import argparse
import json
import hashlib

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
manifest = json.loads(migration_inputs.read_text(root / 'automation/notification-center-feed-manifest.json'))
canonical = root / manifest['output']
out = args.output.resolve() if args.output else canonical
historical = root / 'supabase/migrations/20261023210000_organization_notification_center.sql'
if out == historical or out.name in manifest['prerequisites']:
    raise SystemExit('Refusing to overwrite historical prerequisite migration')
for prerequisite in manifest['prerequisites']:
    if not migration_inputs.is_file(root / 'supabase/migrations' / prerequisite):
        raise SystemExit('Missing prerequisite: ' + prerequisite)
    if hashlib.sha256(migration_inputs.read_bytes(root / 'supabase/migrations' / prerequisite)).hexdigest() != manifest['prerequisiteSha256'][prerequisite]:
        raise SystemExit('Historical prerequisite digest differs: ' + prerequisite)
text = '-- Generated forward migration: ' + manifest['name'] + '\n'
text += '-- Prerequisites: ' + ', '.join(manifest['prerequisites']) + '\nBEGIN;\n'
text += "DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regclass('public.notification_center_view_members') IS NULL OR to_regprocedure('public.notification_center_prepared_scope(bigint,jsonb)') IS NULL OR to_regprocedure('public.mark_notification_center_view_item_read(bigint,jsonb)') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;\n"
for source in manifest['sources']:
    content = migration_inputs.read_text(root / 'database/functions' / source)
    if source == 'notification_center/maintenance.sql':
        # Its table prefix belongs to the immutable prerequisite, functions to this delta.
        content = 'CREATE OR REPLACE FUNCTION' + content.split('CREATE OR REPLACE FUNCTION', 1)[1]
    text += '\n-- SOURCE: ' + source + '\n' + content + '\n'
text += 'COMMIT;\n'
tables = root / 'database/tables/tables.sql'
start = '\n-- Organization notification center private projections.\n'
end = '-- End organization notification center private projections.\n'
block = start + migration_inputs.read_text(root/'database/functions/notification_center/schema.sql') + migration_inputs.read_text(root/'database/functions/notification_center/prepared_schema.sql') + migration_inputs.read_text(root/'database/functions/notification_center/maintenance.sql').split('CREATE OR REPLACE FUNCTION')[0] + end
current = migration_inputs.read_text(tables)
before, tail = current.split(start, 1)
canonical_tables = before + block + tail.split(end, 1)[1]
if args.check:
    if current != canonical_tables:
        raise SystemExit('Notification table definitions differ from canonical schema')
    if not migration_inputs.is_file(out) or migration_inputs.read_text(out) != text:
        raise SystemExit('Notification forward migration differs from manifest sources')
    print('Notification feed migration and canonical tables match')
else:
    if migration_inputs.exists(out) and migration_inputs.read_text(out) != text:
        raise SystemExit('Refusing to overwrite an existing different output')
    migration_inputs.write_text(out, text)
    migration_inputs.write_text(tables, canonical_tables)
    print(out)
