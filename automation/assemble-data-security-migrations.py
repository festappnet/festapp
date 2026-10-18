#!/usr/bin/env python3
"""Only new 2026-10-18 phases. --check never writes any artifact."""
from pathlib import Path
import argparse, hashlib, json
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
phases={
 '20261018100000_data_security_auth.sql':['database/functions/users/create_user_from_registration.sql','database/functions/users/create_user_in_organization_with_data_ws.sql','database/functions/security/data_security_auth.sql'],
 '20261018101000_data_security_readers.sql':['database/functions/others/get_occasion_for_context.sql','database/functions/others/get_news_with_views.sql','database/functions/others/get_news_read_state.sql','database/functions/groups/group_member_read.sql','database/functions/security/news_read_marker.sql','database/functions/security/public_map_projection.sql'],
 '20261018102000_data_security_reads.sql':['database/functions/security/data_security_reads.sql'],
 '20261018103000_data_security_defaults.sql':['database/functions/security/data_security_defaults.sql'],
}
manifest={'base_main':'8b1420ea1da7349db68b4a293bb37da049fb9047','production_applied':False,'phases':[]}
def output(path,content):
 target=root/path
 if args.check:
  if not target.exists() or target.read_text()!=content:raise SystemExit(f'Drift: {path}')
 else:target.write_text(content)
for name,sources in phases.items():
 content='-- Canonical sources: '+', '.join(sources)+'\n\n'+'\n'.join((root/s).read_text() for s in sources)
 output('supabase/migrations/'+name,content)
 digest=hashlib.sha256(content.encode()).hexdigest()
 version=name.split('_')[0]
 phase=name.removesuffix('.sql').split('_data_security_')[1]
 previous_version={'readers':'20261018100000','reads':'20261018101000','defaults':'20261018102000'}.get(phase)
 dependency=(f"IF NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='{previous_version}') THEN RAISE EXCEPTION 'Previous data-security phase missing'; END IF;" if previous_version else '')
 compatibility=("\\if :{?data_security_compatibility_verified}\n\\else\n\\echo 'Compatibility evidence required before the read ACL phase'\nDO $$ BEGIN RAISE EXCEPTION 'Compatibility evidence required before the read ACL phase'; END $$;\n\\endif\n\\if :data_security_compatibility_verified\n\\else\nDO $$ BEGIN RAISE EXCEPTION 'Compatibility evidence required before the read ACL phase'; END $$;\n\\endif\n" if phase=='reads' else '')
 driver=f"""\\set ON_ERROR_STOP on
-- Apply only after explicit authorization of the shared database impact.
{compatibility}BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('festapp-data-security-20261018',0));
DO $$$$
BEGIN
 IF current_database()<>'festapp_rehearsal_20260909220601'
 OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=1) THEN
   RAISE EXCEPTION 'Canonical target mismatch';
 END IF;
{dependency}
 IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='{version}') THEN
   RAISE EXCEPTION 'Already recorded; read back rather than replay';
 END IF;
END $$$$;
{content}
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
 VALUES('{version}','data_security_{phase}',ARRAY['-- sha256:{digest}']);
NOTIFY pgrst,'reload schema';
COMMIT;
""".replace('$$$$','$$')
 driver_path='automation/hetzner-supabase/runtime/apply-data-security-'+phase+'.sql'
 output(driver_path,driver)
 manifest['phases'].append({'file':'supabase/migrations/'+name,'sha256':digest,'sources':sources,'database_user':'supabase_admin' if 'defaults' in name else 'postgres','driver':driver_path,'driver_sha256':hashlib.sha256(driver.encode()).hexdigest()})
manifest['contracts']={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'database/functions/security/data_security_contracts.json',root/'database/functions/security/server_security_acl_manifest.json',root/'database/functions/security/definer_contracts.json',root/'automation/hetzner-supabase/runtime/audit-data-security-state.sql',root/'automation/hetzner-supabase/runtime/data-security-preflight.sql']}
manifest['client_sources']={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['lib/components/news/db_news.dart','lib/components/occasion/db_occasions.dart','lib/components/users/db_users.dart','lib/components/users/user_info_model.dart','lib/data_services/offline_data_service.dart','lib/components/map/map_page.dart','lib/components/map/map_page_helper.dart']}
output('automation/hetzner-supabase/runtime/data-security-release.json',json.dumps(manifest,indent=2)+'\n')
print('Data security migrations: canonical (4 phases)')
