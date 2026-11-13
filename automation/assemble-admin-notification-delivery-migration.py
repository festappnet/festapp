#!/usr/bin/env python3
"""Forward-only admin notification expansion over the canonical queue."""
import argparse
import json
import hashlib
from pathlib import Path
import migration_inputs
from migration_forward_owners import forward_sources, historical_source, check_effective_sources

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
manifest = json.loads((root / 'automation/admin-notification-delivery-manifest.json').read_text())
canonical = root / manifest['output']
output = args.output.resolve() if args.output else canonical
if output.name != canonical.name:
    raise SystemExit('Refusing to overwrite any other migration identity')
for prerequisite in manifest['prerequisites']:
    if hashlib.sha256(migration_inputs.read_bytes(root / 'supabase/migrations' / prerequisite)).hexdigest() != manifest['prerequisiteSha256'][prerequisite]:
        raise SystemExit('Historical prerequisite digest differs: ' + prerequisite)
text = '-- Generated forward migration: ' + manifest['name'] + '\nBEGIN;\n'
text += "DO $$ BEGIN IF to_regclass('public.notification_center_view_members') IS NULL OR to_regclass('public.abuse_policy_rules') IS NULL OR to_regprocedure('public.notification_center_prepared_scope(bigint,jsonb)') IS NULL THEN RAISE EXCEPTION 'admin_notification_prerequisites_missing'; END IF; END $$;\n"
later = forward_sources(root, after=canonical.name)
for source in manifest['sources']:
    if source in later:
        # Installed bytes are immutable. A declared later migration owns the
        # current body, whose effective parity is checked independently below.
        content = historical_source(root, canonical.name, source) + '\n'
    else:
        content = migration_inputs.read_text(root / 'database/functions' / source)
    if source == 'notification_center/maintenance.sql':
        content = content[content.index('CREATE OR REPLACE FUNCTION'):]
    text += '\n-- SOURCE: ' + source + '\n' + content + '\n'
seeds = migration_inputs.read_text(root / 'database/functions/abuse/seeds.sql')
text += seeds[seeds.index('-- Notification budgets share'):]
text += '\nCOMMIT;\n'
registry_path = root / 'automation/migration-forward-owners.json'
registry = json.loads(registry_path.read_text())
entry = next((entry for entry in registry['migrations'] if entry['migration'] == canonical.name), None)
digest = hashlib.sha256(text.encode()).hexdigest()
if args.check:
    check_effective_sources(root, set(manifest['sources']) & later)
    if not output.is_file() or output.read_text() != text:
        raise SystemExit('Admin notification migration differs from canonical sources')
    if entry is None or entry.get('manifest') != 'admin-notification-delivery-manifest.json' or entry.get('sha256') != digest:
        raise SystemExit('Admin notification forward ownership differs')
    print('Admin notification forward migration matches')
else:
    if output.exists() and output.read_text() != text:
        raise SystemExit('Refusing to overwrite a different migration; remove only your unpublished output first')
    output.write_text(text)
    if output == canonical:
        if entry is None:
            entry = {'migration': canonical.name, 'manifest': 'admin-notification-delivery-manifest.json'}
            registry['migrations'].append(entry)
        entry['sha256'] = digest
        registry_path.write_text(json.dumps(registry, indent=2) + '\n')
    print(output)
