#!/usr/bin/env python3
"""Deterministic follow-up migrations; never rewrites abuse or baseline."""
from pathlib import Path
import argparse, hashlib, json
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
bundles={
 '20261016170000_server_security_containment.sql':['database/functions/security/server_security_containment.sql'],
 '20261016171000_server_security_authorization.sql':['database/functions/security/server_security_retirement.sql','database/functions/inventory/update_spots_assignments.sql','database/functions/security/external_sync_acl.sql','database/functions/synchronization/add_sync_map.sql'],
 '20261016172000_server_security_hygiene.sql':['database/functions/security/server_security_search_paths.sql','database/functions/security/server_security_hygiene.sql'],
}
for name,sources in bundles.items():
 content='-- Canonical sources: '+', '.join(sources)+'\n\n'+'\n'.join((root/f).read_text() for f in sources)
 target=root/'supabase/migrations'/name
 if args.check:
  if target.read_text()!=content: raise SystemExit(f'Migration drift: {name}')
 else: target.write_text(content)
# Small independently executable transactional phase drivers and a digest manifest.
manifest={'version':1,'base_main':'cf699e154bfb9d4f0ad5b1991d00e0dd0f055d89','production_applied':False,'phases':[]}
for name in bundles:
 version, phase=name.removesuffix('.sql').split('_server_security_')
 digest=hashlib.sha256((root/'supabase/migrations'/name).read_bytes()).hexdigest()
 account='supabase_admin' if phase=='hygiene' else 'postgres'
 driver=f"""\\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('festapp-server-security-remediation',0));
DO $$$$
BEGIN
  IF current_database()<>'festapp_rehearsal_20260909220601' OR
    NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=1) THEN
    RAISE EXCEPTION 'Canonical target mismatch';
  END IF;
  IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='{version}') THEN
    RAISE EXCEPTION 'Migration already recorded; use readback rather than replay';
  END IF;
END $$$$;
-- Embedded canonical migration {name}
{(root/'supabase/migrations'/name).read_text()}
-- End canonical migration
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('{version}','server_security_{phase}',ARRAY['-- sha256:{digest}']);
NOTIFY pgrst,'reload schema';
COMMIT;
""".replace('$$$$','$$')
 target=root/'automation/hetzner-supabase/runtime'/f'apply-server-security-{phase}.sql'
 if args.check:
  if target.read_text()!=driver: raise SystemExit(f'Driver drift: {phase}')
 else: target.write_text(driver)
 manifest['phases'].append({'version':version,'file':'supabase/migrations/'+name,'sha256':digest,'database_user':account,'driver':str(target.relative_to(root))})
manifest['runtime_files']={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [
 root/'automation/hetzner-supabase/runtime/Caddyfile',
 root/'automation/hetzner-supabase/runtime/prepare-asset-runtime.py',
 root/'automation/hetzner-supabase/runtime/pins.json',
 root/'automation/hetzner-supabase/runtime/bootstrap-host.sh',
 root/'automation/hetzner-supabase/runtime/deploy-rehearsal.sh',
 root/'automation/hetzner-supabase/runtime/promote-production-runtime.sh',
 root/'automation/hetzner-supabase/runtime/switch-rehearsal-runtime-database.sh',
 root/'automation/hetzner-supabase/runtime/finalize-canonical-database-operations.sh',
 root/'automation/hetzner-supabase/runtime/apply-security-config.sh',
 root/'automation/hetzner-supabase/runtime/audit-security-state.sql',
 root/'automation/hetzner-supabase/runtime/collect-resource-budget.sh',
 root/'automation/hetzner-supabase/monitoring/agent.mjs',
 root/'automation/hetzner-supabase/monitoring/metrics.mjs',
 root/'automation/hetzner-supabase/monitoring/runtime-evidence.py',
 root/'supabase/functions/_shared/runtime_resource_metrics.ts',
 root/'automation/hetzner-supabase/runtime/patch-function-resource-metrics.py',
 root/'automation/hetzner-supabase/runtime/apply-runtime-resource-metrics.py',
 root/'automation/hetzner-supabase/runtime/test-edge-resource-metrics-local.py',
 root/'automation/hetzner-supabase/runtime/install-production-function-bundle.sh',
 root/'automation/hetzner-supabase/runtime/upgrade-installed-production-runtime.sh',
 root/'automation/hetzner-supabase/monitoring/festapp-host-monitor.service',
 root/'automation/hetzner-supabase/monitoring/install.sh',
 root/'automation/hetzner-supabase/restore/drill-online-backup-local.py',
 root/'automation/hetzner-supabase/restore/service_smoke.py',
 root/'automation/hetzner-supabase/restore/gateway_smoke.py',
 root/'automation/hetzner-supabase/restore/edge_smoke.py',
 root/'automation/hetzner-supabase/restore/export-public-edge-sources.py',
 root/'automation/hetzner-supabase/restore/r2_archive.py',
 root/'automation/hetzner-supabase/restore/backup_manifest.py',
 root/'automation/hetzner-supabase/restore/current_asset_fields.sql',
 root/'automation/image-migration/storage_references.py',
 root/'automation/hetzner-supabase/merge/source-registry.json',
 root/'automation/hetzner-supabase/restore/verify-r2-dump-local.py',
 root/'automation/hetzner-supabase/restore/download-offhost-backup.py',
 root/'automation/hetzner-supabase/runtime/docker-compose.resource-budget.yml',
 root/'automation/hetzner-supabase/runtime/apply-admin-resource-budget.py',
 root/'automation/hetzner-supabase/backup/create-online-encrypted-backup.sh',
 root/'automation/hetzner-supabase/backup/create-r2-image-archive.py',
 root/'automation/hetzner-supabase/backup/archive-runtime.sh',
 root/'automation/hetzner-supabase/backup/install-online-backup.sh',
 root/'automation/hetzner-supabase/backup/prune-online-backups.py',
 root/'automation/hetzner-supabase/backup/festapp-supabase-backup.timer']}
# Immutable 2026-10-16 receipt. Subsequent contracts are sealed by the data-security assembler.
manifest['contract_files']={'database/functions/security/server_security_acl_manifest.json': 'e977bebe9018d7b2d89070e651ce527d685c58fb9c13f48caf0188470878e7eb', 'database/functions/security/definer_contracts.json': '0a5448ecaf1a7deb6a715093df7de8210abe1a76a08eb8fd734bbc3748e6fa35'}
manifest_file=root/'automation/hetzner-supabase/runtime/server-security-release.json' 
content=json.dumps(manifest,indent=2)+'\n'
if args.check:
 if manifest_file.read_text()!=content: raise SystemExit('Release manifest drift')
else: manifest_file.write_text(content)
print('Server security migrations: canonical')
