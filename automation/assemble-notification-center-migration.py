#!/usr/bin/env python3
"""Generate the forward-only notification availability cutover from canonical owners.

The installed additive rollout migration remains immutable history.
"""
from pathlib import Path
import argparse
root=Path(__file__).resolve().parents[1]
SOURCES=['notification_center/capacity.sql', 'notification_center/app_activity.sql', 'notification_center/core.sql', 'notification_center/email.sql', 'notification_center/bank.sql', 'notification_center/maintenance.sql', 'users/occasion_enrolment_internal.sql', 'events/save_event_domain_command_internal_v1.sql', 'events/set_event_attendance_client_sync_v1.sql', 'seed/seed_org_with_admin.sql']
PREFIX="-- Notification availability follows administration permissions, never tenant rollout.\n-- Preserve personal history and active source snapshots. Inactive organizations\n-- baseline once at this cutover; future creation initializes through its owner.\nLOCK TABLE public.notification_center_activation IN ACCESS EXCLUSIVE MODE;\nCREATE TEMP TABLE notification_center_initialization_timezones ON COMMIT DROP AS\n SELECT o.id organization,coalesce(a.timezone,'Europe/Prague') timezone\n FROM public.organizations o LEFT JOIN public.notification_center_activation a ON a.organization=o.id\n WHERE a.organization IS NULL OR NOT a.enabled;\nDELETE FROM public.notification_center_activation WHERE NOT enabled;\nALTER TABLE public.notification_center_activation RENAME TO notification_center_organizations;\nALTER TABLE public.notification_center_organizations RENAME COLUMN activated_at TO initialized_at;\nALTER TABLE public.notification_center_organizations DROP COLUMN enabled;\nDROP FUNCTION public.set_notification_center_activation(bigint,boolean,text);\n"
SUFFIX="\nDROP FUNCTION public.notification_center_active_internal(bigint);\nDO $$DECLARE item record; BEGIN\n FOR item IN SELECT * FROM notification_center_initialization_timezones ORDER BY organization LOOP\n  PERFORM public.initialize_notification_center_internal(item.organization,item.timezone);\n END LOOP;\nEND $$;\nNOTIFY pgrst, 'reload schema';\n"
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
out=root/'supabase/migrations/20261024235000_notification_center_canonical_availability.sql'
parts=[]
for source in SOURCES:
    text=(root/'database/functions'/source).read_text()
    if source=='notification_center/maintenance.sql':
        text=text[text.index('CREATE OR REPLACE FUNCTION'):]
    parts.append('-- Canonical source: database/functions/'+source+'\n'+text)
text=PREFIX+'\n'.join(parts)+SUFFIX
tables=root/'database/tables/tables.sql'
start='\n-- Organization notification center private projections.\n'
end='-- End organization notification center private projections.\n'
block=start+(root/'database/functions/notification_center/schema.sql').read_text()+(root/'database/functions/notification_center/maintenance.sql').read_text().split('CREATE OR REPLACE FUNCTION')[0]+end
current=tables.read_text()
before,tail=current.split(start,1)
canonical_tables=before+block+tail.split(end,1)[1]
if args.check:
    if current!=canonical_tables: raise SystemExit('Notification table definitions differ from canonical schema')
    if out.read_text()!=text: raise SystemExit('Notification cutover differs from canonical sources')
    print('Notification cutover matches canonical sources')
else:
    out.write_text(text)
    tables.write_text(canonical_tables)
    print(out.relative_to(root))
