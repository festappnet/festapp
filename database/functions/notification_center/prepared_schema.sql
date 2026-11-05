-- Rebuildable private read model; canonical deliveries and receipts remain owners.
ALTER TABLE public.notification_center_events ADD COLUMN IF NOT EXISTS view_revision bigint NOT NULL DEFAULT 1;
ALTER TABLE public.notification_center_recipients
 ADD COLUMN IF NOT EXISTS view_required_revision bigint NOT NULL DEFAULT 1,
 ADD COLUMN IF NOT EXISTS view_applied_revision bigint NOT NULL DEFAULT 0;
ALTER TABLE public.notification_center_user_state ADD COLUMN IF NOT EXISTS view_read_revision bigint NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS notification_center_repair_work ON public.notification_center_recipients(event_id,recipient)
 WHERE view_required_revision>view_applied_revision;
CREATE INDEX IF NOT EXISTS notification_center_hidden_subjects ON public.organization_users(organization,"user") WHERE is_hidden;
CREATE TABLE IF NOT EXISTS public.notification_center_projection_scopes (
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE, recipient uuid NOT NULL,
 revision bigint NOT NULL DEFAULT 1, build_revision bigint NOT NULL DEFAULT 0,
 phase text NOT NULL DEFAULT 'clear_members' CHECK(phase IN ('clear_members','clear_summaries','backfill','ready')),
 cursor_sequence bigint NOT NULL DEFAULT 0, prepared_sequence bigint NOT NULL DEFAULT 0,
 applied_read_revision bigint NOT NULL DEFAULT 0, pending_events integer NOT NULL DEFAULT 0,
 pending_groups integer NOT NULL DEFAULT 0, privacy jsonb NOT NULL DEFAULT '[]',
 privacy_pending boolean NOT NULL DEFAULT false, repair_privacy jsonb NOT NULL DEFAULT '[]',
 privacy_keys text[] NOT NULL DEFAULT '{}', privacy_cursor uuid,
 next_expiry timestamptz, next_check_at timestamptz NOT NULL DEFAULT '-infinity',
 last_ready_at timestamptz, PRIMARY KEY(organization,recipient),
 CHECK(pending_events>=0 AND pending_groups>=0)
);
CREATE INDEX IF NOT EXISTS notification_center_scope_work ON public.notification_center_projection_scopes(next_check_at,organization,recipient);
CREATE TABLE IF NOT EXISTS public.notification_center_view_members (
 organization bigint NOT NULL, recipient uuid NOT NULL,
 event_id uuid NOT NULL REFERENCES public.notification_center_events(id) ON DELETE CASCADE,
 sequence bigint NOT NULL, attention_revision bigint NOT NULL, source_revision bigint NOT NULL,
 group_key text NOT NULL, batch_id text NOT NULL, is_read boolean NOT NULL,
 after_sequence bigint NOT NULL, through_sequence bigint NOT NULL,
 eligible boolean NOT NULL, occurred_at timestamptz NOT NULL, expires_at timestamptz,
 places bigint, multiple boolean NOT NULL DEFAULT false,
 PRIMARY KEY(organization,recipient,event_id),
 FOREIGN KEY(organization,recipient) REFERENCES public.notification_center_projection_scopes(organization,recipient) ON DELETE CASCADE
);
-- Event purge must not scan every personal membership for each deleted fact.
CREATE INDEX IF NOT EXISTS notification_center_member_event ON public.notification_center_view_members(event_id);
CREATE INDEX IF NOT EXISTS notification_center_member_preview ON public.notification_center_view_members(organization,recipient,batch_id,occurred_at DESC,event_id DESC) WHERE eligible;
CREATE INDEX IF NOT EXISTS notification_center_member_group ON public.notification_center_view_members(organization,recipient,group_key,event_id);
CREATE INDEX IF NOT EXISTS notification_center_member_expiry ON public.notification_center_view_members(organization,recipient,expires_at,event_id) WHERE eligible AND expires_at IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.notification_center_member_subjects (
 organization bigint NOT NULL,recipient uuid NOT NULL,subject text NOT NULL,event_id uuid NOT NULL,
 PRIMARY KEY(organization,recipient,subject,event_id),
 FOREIGN KEY(organization,recipient,event_id) REFERENCES public.notification_center_view_members(organization,recipient,event_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS notification_center_subject_event ON public.notification_center_member_subjects(organization,recipient,event_id);
CREATE TABLE IF NOT EXISTS public.notification_center_batch_summaries (
 organization bigint NOT NULL,recipient uuid NOT NULL,id text NOT NULL,group_key text NOT NULL,
 kind text NOT NULL,occasion bigint,is_read boolean NOT NULL,after_sequence bigint NOT NULL,
 through_sequence bigint NOT NULL,activity_count bigint NOT NULL,known_count bigint NOT NULL,
 places bigint NOT NULL,multiple_count bigint NOT NULL,
 latest_at timestamptz NOT NULL,latest_event uuid NOT NULL,preview_events uuid[] NOT NULL DEFAULT '{}',
 PRIMARY KEY(organization,recipient,id),
 FOREIGN KEY(organization,recipient) REFERENCES public.notification_center_projection_scopes(organization,recipient) ON DELETE CASCADE,
 CHECK(activity_count>=0 AND known_count>=0 AND known_count<=activity_count AND multiple_count>=0)
);
-- Scope aliases duplicate only indexed sort metadata, never event membership.
CREATE TABLE IF NOT EXISTS public.notification_center_summary_scopes (
 organization bigint NOT NULL,recipient uuid NOT NULL,scope text NOT NULL,id text NOT NULL,
 latest_at timestamptz NOT NULL,sequence bigint NOT NULL,is_read boolean NOT NULL,
 PRIMARY KEY(organization,recipient,scope,id),
 FOREIGN KEY(organization,recipient,id) REFERENCES public.notification_center_batch_summaries(organization,recipient,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS notification_center_summary_member ON public.notification_center_summary_scopes(organization,recipient,id);
CREATE INDEX IF NOT EXISTS notification_center_summary_top ON public.notification_center_summary_scopes(organization,recipient,scope,latest_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS notification_center_summary_unseen ON public.notification_center_summary_scopes(organization,recipient,scope,sequence DESC) WHERE NOT is_read;
CREATE TABLE IF NOT EXISTS public.notification_center_group_repairs (
 organization bigint NOT NULL,recipient uuid NOT NULL,group_key text NOT NULL,cursor uuid,
 PRIMARY KEY(organization,recipient,group_key),
 FOREIGN KEY(organization,recipient) REFERENCES public.notification_center_projection_scopes(organization,recipient) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS public.notification_center_views (
 token uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization bigint NOT NULL,recipient uuid NOT NULL,
 current_occasion bigint,timezone text NOT NULL,snapshot bigint NOT NULL,anchor timestamptz NOT NULL,
 previous_seen bigint NOT NULL,source_revision bigint NOT NULL,read_revision bigint NOT NULL,
 privacy_key text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '30 minutes',
 acknowledged boolean NOT NULL DEFAULT false,truncated boolean NOT NULL DEFAULT false,
 FOREIGN KEY(organization,recipient) REFERENCES public.notification_center_projection_scopes(organization,recipient) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS notification_center_view_owner ON public.notification_center_views(organization,recipient,expires_at);
CREATE TABLE IF NOT EXISTS public.notification_center_view_rows (
 token uuid NOT NULL REFERENCES public.notification_center_views(token) ON DELETE CASCADE,
 position integer NOT NULL CHECK(position BETWEEN 1 AND 100),id text NOT NULL,group_key text NOT NULL,
 after_sequence bigint NOT NULL,through_sequence bigint NOT NULL,kind text NOT NULL,occasion bigint,
 latest_at timestamptz NOT NULL,latest_event uuid,preview_events uuid[] NOT NULL DEFAULT '{}',
 activity_count bigint NOT NULL,known_count bigint NOT NULL,places bigint NOT NULL,multiple_count bigint NOT NULL,
 is_read boolean NOT NULL,state text NOT NULL DEFAULT 'ready' CHECK(state IN ('ready','preparing','removed')),
 revision bigint NOT NULL,read_revision bigint NOT NULL,privacy_key text NOT NULL,
 repair_cursor uuid,repair_revision bigint,repair_read_revision bigint,repair_privacy_key text,
 repair_count bigint NOT NULL DEFAULT 0,repair_known bigint NOT NULL DEFAULT 0,
 repair_places bigint NOT NULL DEFAULT 0,repair_multiple bigint NOT NULL DEFAULT 0,
 repair_unread bigint NOT NULL DEFAULT 0,repair_previews uuid[] NOT NULL DEFAULT '{}',
 PRIMARY KEY(token,position),UNIQUE(token,id)
);
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['projection_scopes','view_members','member_subjects','batch_summaries','summary_scopes','group_repairs','views','view_rows'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY','notification_center_'||name);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role','notification_center_'||name);
 END LOOP;
END $$;
ALTER TABLE public.notification_center_projection_scopes
 ADD COLUMN IF NOT EXISTS pending_delivery integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS delivery_initialized boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS notification_center_personal_source_repairs ON public.notification_center_recipients(recipient,event_id)
 WHERE view_required_revision>view_applied_revision;
CREATE INDEX IF NOT EXISTS notification_center_personal_pending_delivery ON public.notification_center_recipients(recipient,event_id)
 WHERE processed_revision<eligible_revision;
ALTER TABLE public.notification_center_projection_scopes
 ADD COLUMN IF NOT EXISTS retry_count integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_error_code text,
 ADD COLUMN IF NOT EXISTS quarantined boolean NOT NULL DEFAULT false;
ALTER TABLE public.notification_center_view_rows
 ADD COLUMN IF NOT EXISTS retry_count integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_error_code text,
 ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz NOT NULL DEFAULT '-infinity',
 ADD COLUMN IF NOT EXISTS quarantined boolean NOT NULL DEFAULT false;
ALTER TABLE public.notification_center_batch_summaries ADD COLUMN IF NOT EXISTS first_sequence bigint NOT NULL DEFAULT 0;
ALTER TABLE public.notification_center_view_rows ADD COLUMN IF NOT EXISTS capture_is_read boolean NOT NULL DEFAULT false;
-- Different captured prefixes can legitimately close different ranges at the
-- same upper sequence. Receipts remain immutable; never widen an old receipt.
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT pc.conname FROM pg_constraint pc WHERE pc.conrelid='public.notification_center_read_batches'::regclass AND pc.contype='u'
  AND (SELECT array_agg(a.attname::text ORDER BY x.position) FROM unnest(pc.conkey) WITH ORDINALITY x(attnum,position)
   JOIN pg_attribute a ON a.attrelid=pc.conrelid AND a.attnum=x.attnum)=ARRAY['organization','recipient','group_key','through_sequence'] LOOP
  EXECUTE format('ALTER TABLE public.notification_center_read_batches DROP CONSTRAINT %I',c.conname);
 END LOOP;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS notification_center_read_receipt_range ON public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence);
CREATE INDEX IF NOT EXISTS notification_center_read_through ON public.notification_center_read_batches(organization,recipient,group_key,through_sequence) INCLUDE(after_sequence,read_at,id);

DROP INDEX IF EXISTS public.notification_center_order_projection;
CREATE INDEX notification_center_order_projection ON public.notification_center_events(occasion,(data->>'orderId'),id)
 WHERE kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted','offer_declined','offer_expired');
CREATE INDEX IF NOT EXISTS notification_center_participant_dependency ON public.notification_center_events((data->>'userId'),occasion,id) WHERE kind='occasion_joined';
ALTER TABLE public.notification_center_projection_scopes
 ADD COLUMN IF NOT EXISTS work_requested boolean NOT NULL DEFAULT true,
 ADD COLUMN IF NOT EXISTS requested_at timestamptz DEFAULT clock_timestamp();
ALTER TABLE public.notification_center_maintenance
 ADD COLUMN IF NOT EXISTS worker_url text,
 ADD COLUMN IF NOT EXISTS wake_error text;
CREATE INDEX IF NOT EXISTS notification_center_requested_work ON public.notification_center_projection_scopes(work_requested DESC,next_check_at,organization,recipient);
ALTER TABLE public.notification_center_organizations ADD COLUMN IF NOT EXISTS prepared_paused boolean NOT NULL DEFAULT false;
ALTER TABLE public.notification_center_projection_scopes ADD COLUMN IF NOT EXISTS failed_event uuid;
