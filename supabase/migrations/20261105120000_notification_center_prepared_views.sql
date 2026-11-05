-- Generated forward migration: notification-center-prepared-views-2026-11-05
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql, 20261026120000_notification_center_feed.sql, 20261026150000_notification_center_order_periods.sql, 20261026230000_notification_center_unread_snapshot.sql, 20261027210000_notification_center_overview.sql, 20261027220000_notification_center_daily_overview.sql, 20261027234500_notification_group_order_selection.sql, 20261028010000_notification_legacy_place_totals.sql, 20261028013000_notification_category_rollups.sql, 20261028020000_notification_center_lifecycle.sql, 20261028030000_notification_new_orders_exclude_cancelled.sql, 20261028120000_notification_center_current_rollups.sql, 20261028130000_notification_personal_read_batches.sql, 20261030093000_notification_deleted_entities.sql, 20261031110000_notification_current_participants.sql, 20261031120000_notification_center_source_alignment.sql, 20261101170000_hidden_participant_notifications.sql, 20261105070000_notification_subject_lookup_performance.sql, 20261105110000_notification_center_delivery_draining.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

-- SOURCE: notification_center/delivery_schema_delta.sql
-- Delivery retry state belongs to the existing durable recipient work owner.
ALTER TABLE public.notification_center_recipients
 ADD COLUMN IF NOT EXISTS pending_since timestamptz NOT NULL DEFAULT clock_timestamp(),
 ADD COLUMN IF NOT EXISTS retry_revision bigint NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS retry_count integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz NOT NULL DEFAULT '-infinity',
 ADD COLUMN IF NOT EXISTS last_error_code text,
 ADD COLUMN IF NOT EXISTS quarantined boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS notification_center_recipient_retry
 ON public.notification_center_recipients(event_id,next_attempt_at,recipient)
 WHERE processed_revision<eligible_revision;

-- Include the deterministic tie-breaker, avoiding a backlog-sized sort per call.
DROP INDEX IF EXISTS public.notification_center_pending;
CREATE INDEX notification_center_pending ON public.notification_center_events(organization,occurred_at,id)
 WHERE projected_revision<attention_revision;

ALTER TABLE public.notification_center_maintenance
 ADD COLUMN IF NOT EXISTS last_scanned integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_processed integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_deferred integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_failed integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_elapsed_ms numeric,
 ADD COLUMN IF NOT EXISTS last_run_at timestamptz;


-- SOURCE: notification_center/prepared_schema.sql
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


-- SOURCE: notification_center/prepared_wake.sql
-- pg_net publishes only after the surrounding domain transaction commits.
-- This is a coalesced synchronization hint, never a second business queue.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_wake()
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE url text;
BEGIN
 IF current_setting('festapp.notification_wake',true)='scheduled' THEN RETURN; END IF;
 UPDATE public.notification_center_maintenance SET next_at=clock_timestamp()+interval '1 second',wake_error=NULL
 WHERE name='delivery-wake' AND worker_url IS NOT NULL AND next_at<=clock_timestamp()
  AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED)
 RETURNING worker_url INTO url;
 IF url IS NULL THEN RETURN; END IF;
 PERFORM set_config('festapp.notification_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  UPDATE public.notification_center_maintenance SET wake_error='wake_failed' WHERE name='delivery-wake'
   AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED);
 END;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_prepared_wake() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.wake_notification_center()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.notification_center_require_service();PERFORM public.notification_center_prepared_wake();END $$;
REVOKE ALL ON FUNCTION public.wake_notification_center() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_notification_center() TO service_role;
CREATE OR REPLACE FUNCTION public.configure_notification_center_worker(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 IF p_project_url IS NULL OR p_project_url !~ '^https?://[^/?#[:space:]]+/?$' THEN RAISE invalid_parameter_value USING MESSAGE='notification_worker_origin_required'; END IF;
 INSERT INTO public.notification_center_maintenance(name,worker_url) VALUES('delivery-wake',rtrim(p_project_url,'/')||'/functions/v1/process-notification-center')
 ON CONFLICT(name) DO UPDATE SET worker_url=excluded.worker_url,next_at='-infinity',wake_error=NULL;
END $$;
REVOKE ALL ON FUNCTION public.configure_notification_center_worker(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_notification_center_worker(text) TO service_role;


-- SOURCE: notification_center/read_state.sql
-- Personal attention state: opening sees a snapshot; following reads one batch.
ALTER TABLE public.notification_center_user_state ADD COLUMN IF NOT EXISTS seen_through_sequence bigint NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS public.notification_center_read_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 recipient uuid NOT NULL, group_key text NOT NULL,
 after_sequence bigint NOT NULL, through_sequence bigint NOT NULL,
 read_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(after_sequence>=0 AND through_sequence>after_sequence),
 CONSTRAINT notification_center_read_receipt_range UNIQUE(organization,recipient,group_key,after_sequence,through_sequence)
);
ALTER TABLE public.notification_center_read_batches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_center_read_batches FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.notification_center_batch_internal(
 e public.notification_center_events,d public.notification_center_deliveries)
RETURNS TABLE(batch_id text,is_read boolean,after_sequence bigint,through_sequence bigint,group_key text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH state AS (
  SELECT coalesce((SELECT read_through_sequence FROM public.notification_center_user_state
   WHERE organization=d.organization AND recipient=d.recipient),0) baseline,
   CASE WHEN e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem')
    THEN 'occasion-kind:'||e.occasion||':'||e.kind ELSE 'event:'||e.id END key),
 receipt AS (
  SELECT b.* FROM public.notification_center_read_batches b,state s
  WHERE b.organization=d.organization AND b.recipient=d.recipient AND b.group_key=s.key
   AND d.sequence>b.after_sequence AND d.sequence<=b.through_sequence
  ORDER BY b.through_sequence,b.read_at,b.id LIMIT 1),
 bounds AS (
  SELECT s.*,greatest(s.baseline,coalesce((SELECT max(b.through_sequence)
   FROM public.notification_center_read_batches b WHERE b.organization=d.organization
    AND b.recipient=d.recipient AND b.group_key=s.key),0)) last_read,
   e.actor=d.recipient AND e.kind IN ('order_created','order_cancelled') own_action FROM state s)
 SELECT CASE WHEN coalesce(s.own_action,false) THEN s.key||':self'
   WHEN d.sequence<=s.baseline THEN s.key||':legacy'
   WHEN r.id IS NOT NULL THEN s.key||':batch:'||r.after_sequence
   ELSE s.key||':batch:'||s.last_read END,
  coalesce(s.own_action,false) OR d.sequence<=s.baseline OR r.id IS NOT NULL,
  CASE WHEN coalesce(s.own_action,false) OR d.sequence<=s.baseline THEN 0
   WHEN r.id IS NOT NULL THEN r.after_sequence ELSE s.last_read END,
  CASE WHEN coalesce(s.own_action,false) THEN d.sequence WHEN d.sequence<=s.baseline THEN s.baseline
   WHEN r.id IS NOT NULL THEN r.through_sequence ELSE d.sequence END,s.key
 FROM bounds s LEFT JOIN receipt r ON true;
$$;
REVOKE ALL ON FUNCTION public.notification_center_batch_internal(public.notification_center_events,public.notification_center_deliveries) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.mark_notification_center_item_read(p_organization bigint,p_scope jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE id text:=p_scope->>'id'; base text; lower_bound bigint; upper_bound bigint;
 actual_upper bigint; baseline bigint; last_read bigint; occ bigint; snap bigint;
BEGIN
 IF p_scope ? 'viewToken' THEN RETURN public.mark_notification_center_view_item_read(p_organization,p_scope); END IF;
 PERFORM public.notification_center_check_context(p_organization);
 IF coalesce(p_scope->>'snapshot','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 SELECT read_through_sequence,least((p_scope->>'snapshot')::bigint,last_delivery_sequence)
  INTO baseline,snap FROM public.notification_center_user_state
  WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF id ~ '^occasion-kind:[0-9]{1,18}:[a-z_]+:batch:[0-9]{1,18}$' THEN
  base:=regexp_replace(id,':batch:[0-9]+$','');
  lower_bound:=substring(id from ':batch:([0-9]+)$')::bigint;
  occ:=split_part(id,':',2)::bigint;
  PERFORM public.notification_center_check_context(p_organization,occ);
 ELSIF id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
  base:='event:'||id; lower_bound:=0;
 ELSE
  RETURN false;
 END IF;
 IF p_scope ? 'throughSequence' AND coalesce(p_scope->>'throughSequence','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 upper_bound:=least(coalesce((p_scope->>'throughSequence')::bigint,snap),snap);
 SELECT max((v.delivery).sequence) INTO actual_upper
 FROM public.notification_center_visible_internal(p_organization,snap,occ) v
 WHERE (v.delivery).sequence>lower_bound AND (v.delivery).sequence<=upper_bound
  AND public.notification_center_in_center_internal(v.event,clock_timestamp())
  AND CASE WHEN occ IS NOT NULL THEN
   'occasion-kind:'||(v.event).occasion||':'||(v.event).kind=base
   ELSE 'event:'||(v.event).id=base END
  AND NOT coalesce((v.event).actor=auth.uid() AND (v.event).kind IN ('order_created','order_cancelled'),false);
 IF actual_upper IS NULL THEN RETURN false; END IF;
 RETURN public.notification_center_prepared_seal(p_organization,base,lower_bound,actual_upper);
END $$;
REVOKE ALL ON FUNCTION public.mark_notification_center_item_read(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_notification_center_item_read(bigint,jsonb) TO authenticated;


-- SOURCE: notification_center/core.sql
-- Called by trusted domain owners only. Never accept an actor in a public RPC.
CREATE OR REPLACE FUNCTION public.notification_center_require_service() RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF session_user<>'postgres' AND coalesce(auth.role(),'')<>'service_role' THEN
  RAISE insufficient_privilege USING MESSAGE='notification_service_required'; END IF;
END $$;
-- Match the canonical account write policy: account admin AND linked-unit manager.
CREATE OR REPLACE FUNCTION public.notification_center_bank_admin(p_bank bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.bank_account_write_rule(
  EXISTS(SELECT 1 FROM eshop.bank_account_users m WHERE m.bank_account=p_bank AND m."user"=p_user AND m.is_admin),
  EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN public.unit_users m ON m.unit=l.unit AND m."user"=p_user AND m.is_manager
   WHERE l.bank_account=p_bank AND NOT EXISTS(SELECT 1 FROM public.demo_unit_ids_internal() d WHERE d.unit_id=m.unit)),
  public.is_demo_bank_account(p_bank));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_admin(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_allowed(p_event public.notification_center_events,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_user IS NOT NULL
 AND public.notification_center_subject_visible_internal(p_event.organization,p_event.kind,p_event.data)
 AND (
 CASE WHEN p_event.kind IN ('event_capacity_full','occasion_joined') THEN
 public.notification_center_app_admin_internal(p_event.organization,p_event.occasion,p_user)
 WHEN p_event.kind='email_problem' THEN
 EXISTS(SELECT 1 FROM public.organization_users WHERE organization=p_event.organization AND "user"=p_user AND is_admin) OR (p_event.occasion IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion WHERE oc.organization=p_event.organization AND oc.id=p_event.occasion AND ou."user"=p_user AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id)))
 WHEN p_event.kind='bank_problem' THEN (EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 WHERE c.id=(p_event.data->>'bankConnectionId')::bigint AND bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user)
 AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit WHERE u.organization=p_event.organization AND uba.bank_account=bu.bank_account))
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id WHERE oc.organization=p_event.organization AND oc.id=ANY(p_event.affected_occasions) AND ou."user"=p_user AND ou.is_editor_order_view))
 ELSE EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_event.organization AND ou."user"=p_user AND ou.is_editor_order_view
 AND NOT public.is_demo_occasion(oc.id)
 AND (oc.id=p_event.occasion OR oc.id=ANY(p_event.affected_occasions))) END
 );
$$;
-- Shared administration capability controls availability, never item access.
CREATE OR REPLACE FUNCTION public.notification_center_administration_internal(p_org bigint,p_occ bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_user IS NOT NULL AND (p_occ IS NULL OR EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occ AND organization=p_org)) AND (
 EXISTS(SELECT 1 FROM public.organization_users WHERE organization=p_org AND "user"=p_user AND is_admin)
 OR EXISTS(SELECT 1 FROM public.units un JOIN public.unit_users um ON um.unit=un.id
 WHERE un.organization=p_org AND um."user"=p_user AND (um.is_manager OR um.is_editor OR um.is_editor_view)
 AND (p_occ IS NULL OR EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occ AND unit=un.id)))
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_org AND ou."user"=p_user AND NOT public.is_demo_occasion(oc.id)
 AND (p_occ IS NULL OR oc.id=p_occ)
 AND (public.administration_navigation_rule(false,ou.is_editor,ou.is_manager,false,false) OR ou.is_editor_view)));
$$;
REVOKE ALL ON FUNCTION public.notification_center_administration_internal(bigint,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_check_context(p_org bigint,p_occ bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (
 public.notification_center_administration_internal(p_org,NULL,auth.uid()) OR
 EXISTS(SELECT 1 FROM eshop.bank_account_users bu JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account
 JOIN public.units u ON u.id=uba.unit WHERE bu."user"=auth.uid() AND public.notification_center_bank_admin(bu.bank_account,auth.uid()) AND u.organization=p_org)
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_org AND ou."user"=auth.uid() AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id))) THEN
 RAISE insufficient_privilege USING MESSAGE='notification_read_denied'; END IF;
 IF p_occ IS NOT NULL AND NOT public.notification_center_administration_internal(p_org,p_occ,auth.uid()) AND NOT EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.id=p_occ AND oc.organization=p_org AND ou."user"=auth.uid() AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id)) THEN
 RAISE insufficient_privilege USING MESSAGE='notification_context_denied'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_capture_recipients_internal(p_event uuid,p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; u uuid; was_pending boolean;
BEGIN
 SELECT * INTO e FROM public.notification_center_events WHERE id=p_event;
 IF NOT FOUND THEN RETURN; END IF;
 FOR u IN SELECT "user" FROM public.organization_users WHERE organization=e.organization AND is_admin
 UNION SELECT ou."user" FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion WHERE oc.organization=e.organization AND (ou.is_editor_order_view OR public.participant_contacts_read_rule(ou.is_editor,ou.is_manager,false))
 UNION SELECT bu."user" FROM eshop.bank_account_users bu JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account
 JOIN public.units un ON un.id=uba.unit WHERE un.organization=e.organization AND bu.is_admin LOOP
  IF public.notification_center_allowed(e,u) AND (e.kind IN ('order_created','order_cancelled') OR u IS DISTINCT FROM p_actor OR
   CASE WHEN e.kind IN ('event_capacity_full','occasion_joined') THEN
     NOT public.notification_center_app_admin_internal(e.organization,e.occasion,p_actor)
   ELSE NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=e.occasion AND "user"=p_actor AND is_editor_order)
     AND NOT EXISTS(SELECT 1 FROM public.organization_users WHERE organization=e.organization AND "user"=p_actor AND is_admin) END) THEN
   SELECT coalesce(bool_or(processed_revision<eligible_revision),false) INTO was_pending FROM public.notification_center_recipients WHERE event_id=e.id AND recipient=u;
   INSERT INTO public.notification_center_recipients(event_id,recipient,eligible_revision) VALUES(e.id,u,e.attention_revision)
   ON CONFLICT(event_id,recipient) DO UPDATE SET eligible_revision=excluded.eligible_revision,
    pending_since=CASE WHEN notification_center_recipients.eligible_revision<>excluded.eligible_revision
     THEN clock_timestamp() ELSE notification_center_recipients.pending_since END;
   IF NOT was_pending THEN UPDATE public.notification_center_projection_scopes SET pending_delivery=pending_delivery+1,requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END
    WHERE organization=e.organization AND recipient=u AND delivery_initialized; END IF;
  END IF;
 END LOOP;
 -- A source revision with no captured work is complete immediately. It must
 -- not occupy the delivery candidate index or delay a drain's idle decision.
 UPDATE public.notification_center_events ev SET projected_revision=attention_revision
 WHERE ev.id=p_event AND NOT EXISTS(SELECT 1 FROM public.notification_center_recipients r
  WHERE r.event_id=ev.id AND r.eligible_revision=ev.attention_revision AND r.processed_revision<r.eligible_revision);
 PERFORM public.notification_center_prepared_wake();
END $$;
REVOKE ALL ON FUNCTION public.notification_center_capture_recipients_internal(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_publish_internal(p_org bigint,p_occ bigint,p_kind text,p_key text,
 p_data jsonb DEFAULT '{}',p_actor uuid DEFAULT NULL,p_at timestamptz DEFAULT NULL,p_affected bigint[] DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a public.notification_center_organizations; e public.notification_center_events; u uuid;
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||p_org,0));
 p_at:=coalesce(p_at,clock_timestamp());
 -- Source initialization and domain commits share one organization boundary.
 SELECT * INTO a FROM public.notification_center_organizations WHERE organization=p_org FOR SHARE;
 IF NOT FOUND OR p_at<coalesce(a.collection_started_at,a.initialized_at) THEN RETURN NULL; END IF;
 IF NOT public.notification_center_subject_visible_internal(p_org,p_kind,p_data) THEN RETURN NULL; END IF;
 IF p_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occ AND organization=p_org) THEN
 RAISE EXCEPTION 'notification_scope_mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_affected) x WHERE NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=x AND organization=p_org)) THEN
 RAISE EXCEPTION 'notification_scope_mismatch'; END IF;
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,actor,occurred_at,data,affected_occasions)
 VALUES(p_org,p_occ,p_kind,p_key,p_actor,p_at,p_data,p_affected) ON CONFLICT DO NOTHING RETURNING * INTO e;
 IF NOT FOUND THEN RETURN (SELECT id FROM public.notification_center_events WHERE organization=p_org AND source_key=p_key); END IF;
 PERFORM public.notification_center_capture_recipients_internal(e.id,p_actor);
 RETURN e.id;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_unmuted(p_event public.notification_center_events,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_event.occasion IS NOT NULL THEN NOT EXISTS(SELECT 1 FROM public.notification_center_preferences
 WHERE organization=p_event.organization AND recipient=p_user AND occasion=p_event.occasion AND muted)
 WHEN cardinality(p_event.affected_occasions)=0 THEN true
 ELSE EXISTS(SELECT 1 FROM unnest(p_event.affected_occasions) oc JOIN public.occasion_users ou ON ou.occasion=oc AND ou."user"=p_user AND ou.is_editor_order_view
 WHERE NOT EXISTS(SELECT 1 FROM public.notification_center_preferences p WHERE p.organization=p_event.organization AND p.recipient=p_user AND p.occasion=oc AND p.muted))
 OR (p_event.kind='bank_problem' AND EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON
 bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 WHERE c.id=(p_event.data->>'bankConnectionId')::bigint AND bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user))) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_unmuted(public.notification_center_events,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.project_notification_center(p_limit integer DEFAULT 100) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; work record; tenant record; tz text; seq bigint;
 n integer:=0; scanned integer:=0; deferred integer:=0; failed integer:=0; tenant_work integer;
 budget integer:=greatest(1,least(coalesce(p_limit,100),500)); after_org bigint; last_org bigint; tenant_budget integer;
 started_at timestamptz:=clock_timestamp();
 deadline timestamptz:=clock_timestamp()+interval '250 milliseconds'; error_code text;
 previous_lock_timeout text:=current_setting('lock_timeout');
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 INSERT INTO public.notification_center_maintenance(name) VALUES('delivery') ON CONFLICT DO NOTHING;
 SELECT cursor INTO after_org FROM public.notification_center_maintenance WHERE name='delivery' FOR UPDATE;
 SELECT greatest(1,budget/least(4,greatest(1,count(*)))) INTO tenant_budget
 FROM public.notification_center_organizations a WHERE EXISTS(SELECT 1 FROM public.notification_center_events pending
 WHERE pending.organization=a.organization AND pending.projected_revision<pending.attention_revision);
 -- Rotate across tenants, with separate work/scan budgets. A busy personal row
 -- never makes a recipient revision processed and never stalls another tenant.
 FOR tenant IN
  SELECT a.organization,a.timezone FROM public.notification_center_organizations a
  WHERE EXISTS(SELECT 1 FROM public.notification_center_events ev
   WHERE ev.organization=a.organization AND ev.projected_revision<ev.attention_revision)
  ORDER BY (a.organization>after_org) DESC,a.organization LIMIT 32
 LOOP
  last_org:=tenant.organization; tz:=tenant.timezone; tenant_work:=0;
  FOR work IN
   SELECT ev.id event_id,r.recipient,r.eligible_revision FROM public.notification_center_events ev
   JOIN public.notification_center_recipients r ON r.event_id=ev.id
   WHERE ev.organization=tenant.organization AND ev.projected_revision<ev.attention_revision
    AND r.eligible_revision=ev.attention_revision AND r.processed_revision<r.eligible_revision
    AND (r.retry_revision<>r.eligible_revision OR (NOT r.quarantined AND r.next_attempt_at<=clock_timestamp()))
   ORDER BY ev.occurred_at,ev.id,r.recipient LIMIT least(500,budget*4)
  LOOP
   EXIT WHEN n>=budget OR tenant_work>=tenant_budget OR scanned>=budget*4 OR clock_timestamp()>=deadline;
   scanned:=scanned+1; tenant_work:=tenant_work+1;
   BEGIN
    -- Bound the first-insert race with an opening client too. Restore the
    -- caller's setting on every return; all successful sequence writes are atomic.
    PERFORM set_config('lock_timeout','5ms',true);
    INSERT INTO public.notification_center_user_state(organization,recipient)
     VALUES(tenant.organization,work.recipient) ON CONFLICT DO NOTHING;
    PERFORM 1 FROM public.notification_center_user_state
     WHERE organization=tenant.organization AND recipient=work.recipient FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN deferred:=deferred+1; PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision); CONTINUE; END IF;
    -- Domain writers own event -> recipient. We acquire personal state first,
    -- then SKIP LOCKED on both, so there is no wait edge back to a producer.
    SELECT * INTO e FROM public.notification_center_events WHERE id=work.event_id FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN deferred:=deferred+1; PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision); CONTINUE; END IF;
    PERFORM 1 FROM public.notification_center_recipients
     WHERE event_id=e.id AND recipient=work.recipient AND eligible_revision=e.attention_revision
      AND processed_revision<eligible_revision FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN deferred:=deferred+1; PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision); CONTINUE; END IF;
    IF public.notification_center_allowed(e,work.recipient)
      AND public.notification_center_unmuted(e,work.recipient)
      AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries
       WHERE event_id=e.id AND recipient=work.recipient AND attention_revision=e.attention_revision) THEN
     UPDATE public.notification_center_user_state SET last_delivery_sequence=last_delivery_sequence+1
      WHERE organization=e.organization AND recipient=work.recipient RETURNING last_delivery_sequence INTO seq;
     INSERT INTO public.notification_center_deliveries(event_id,recipient,organization,attention_revision,sequence,group_key)
     VALUES(e.id,work.recipient,e.organization,e.attention_revision,seq,
      CASE WHEN e.kind='email_problem' THEN coalesce(e.occasion::text,'shared')||':email_problem:'||coalesce(e.data->>'reason','problem')||':'||(e.occurred_at AT TIME ZONE tz)::date::text
       WHEN e.kind IN ('order_created','waitlist_registered','order_cancelled','occasion_joined') THEN
        coalesce(e.occasion::text,'shared')||':'||e.kind||':'||(e.occurred_at AT TIME ZONE tz)::date::text ELSE e.id::text END);
     PERFORM public.notification_center_prepared_on_delivery(e,(SELECT d FROM public.notification_center_deliveries d WHERE d.event_id=e.id AND d.recipient=work.recipient AND d.attention_revision=e.attention_revision));
    END IF;
    UPDATE public.notification_center_recipients SET processed_revision=e.attention_revision,
     retry_revision=e.attention_revision,retry_count=0,next_attempt_at='-infinity',last_error_code=NULL,quarantined=false
     WHERE event_id=e.id AND recipient=work.recipient;
    IF NOT EXISTS(SELECT 1 FROM public.notification_center_recipients
     WHERE event_id=e.id AND eligible_revision=e.attention_revision AND processed_revision<e.attention_revision) THEN
     UPDATE public.notification_center_events SET projected_revision=e.attention_revision WHERE id=e.id;
    END IF;
    UPDATE public.notification_center_projection_scopes SET pending_delivery=greatest(0,pending_delivery-1)
     WHERE organization=e.organization AND recipient=work.recipient AND delivery_initialized;
    n:=n+1;
   EXCEPTION
    WHEN lock_not_available THEN deferred:=deferred+1;PERFORM public.notification_center_prepared_defer(work.event_id,work.recipient,work.eligible_revision);
    WHEN OTHERS THEN
     GET STACKED DIAGNOSTICS error_code=RETURNED_SQLSTATE;
     -- The subtransaction rolled back delivery and sequence allocation together.
     -- Store only SQLSTATE, never private payload or exception message.
     UPDATE public.notification_center_recipients r SET
      retry_count=CASE WHEN retry_revision=eligible_revision THEN retry_count+1 ELSE 1 END,
      next_attempt_at=clock_timestamp()+make_interval(secs=>least(300,power(2,least(CASE WHEN retry_revision=eligible_revision THEN retry_count ELSE 0 END,8))*(0.9+random()*0.2))),
      quarantined=retry_revision=eligible_revision AND retry_count>=4,
      retry_revision=eligible_revision,last_error_code=error_code
     WHERE r.event_id=work.event_id AND r.recipient=work.recipient
      AND r.eligible_revision=e.attention_revision;
     failed:=failed+1;
   END;
  END LOOP;
  -- Events with no eligible candidate must also leave the pending index.
  UPDATE public.notification_center_events ev SET projected_revision=attention_revision
   WHERE ev.id IN(SELECT z.id FROM (
    SELECT pending.id,pending.attention_revision FROM public.notification_center_events pending
    WHERE pending.organization=tenant.organization AND pending.projected_revision<pending.attention_revision
    ORDER BY pending.occurred_at,pending.id LIMIT 25 FOR UPDATE SKIP LOCKED) z
    WHERE NOT EXISTS(SELECT 1 FROM public.notification_center_recipients r WHERE r.event_id=z.id
      AND r.eligible_revision=z.attention_revision AND r.processed_revision<z.attention_revision));
  EXIT WHEN n>=budget OR scanned>=budget*4 OR clock_timestamp()>=deadline;
 END LOOP;
 UPDATE public.notification_center_maintenance SET cursor=coalesce(last_org,after_org),
  last_scanned=scanned,last_processed=n,last_deferred=deferred,last_failed=failed,
  last_elapsed_ms=extract(epoch FROM clock_timestamp()-started_at)*1000,last_run_at=clock_timestamp()
  WHERE name='delivery';
 PERFORM set_config('lock_timeout',previous_lock_timeout,true);
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_dto(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=e.data-'bankConnectionId'; account bigint; un bigint; impacts jsonb; customer text; actual_state text; contact jsonb; actual_context jsonb; actual_count bigint;
BEGIN
 IF NOT public.notification_center_allowed(e,auth.uid()) THEN RETURN NULL; END IF;
 IF e.kind='email_problem' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT payload||jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'recipient',m.recipient,'customerName',coalesce(
    nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),
    nullif(trim(concat_ws(' ',u.name,u.surname)),''))) INTO payload
  FROM public.email_messages m
  LEFT JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
    AND coalesce(public.can_read_orders(o.occasion),false)
    AND EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=o.occasion AND oc.organization=m.organization)
  LEFT JOIN public.user_info u ON u.id=m.recipient_user AND u.organization=m.organization
  WHERE m.message_id=(e.data->>'messageId')::uuid AND m.organization=e.organization
    AND m.occasion IS NOT DISTINCT FROM e.occasion;
  payload:=coalesce(payload,e.data-'bankConnectionId');
 END IF;
 IF e.kind='occasion_joined' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT nullif(trim(concat_ws(' ',u.name,u.surname)),'') INTO customer
  FROM public.user_info u JOIN public.occasion_users m ON m."user"=u.id
  WHERE m.occasion=e.occasion AND u.organization=e.organization AND u.id=(e.data->>'userId')::uuid;
  payload:=payload||jsonb_build_object('customerName',customer,'state',CASE WHEN EXISTS(
   SELECT 1 FROM public.occasion_users m WHERE m.occasion=e.occasion AND m."user"=(e.data->>'userId')::uuid) THEN 'membership_active' ELSE 'membership_left' END);
 END IF;
 IF e.data ? 'orderId' AND e.occasion IS NOT NULL AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),o.state,public.notification_center_order_form_context_internal(o.form),
    (SELECT count(DISTINCT x.ticket) FROM eshop.order_product_ticket x WHERE x."order"=o.id)
   INTO contact,actual_state,actual_context,actual_count
   FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
   WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('contact',coalesce(contact,'{}'),'customerName',nullif(trim(concat_ws(' ',contact->>'name',contact->>'surname')),''),'state',coalesce(actual_state,e.data->>'state'));
  -- Legacy events have no captured form context/count; use the authorized live
  -- order only for absent fields. Captured historical facts always win.
  IF public.notification_center_order_activity_internal(e.kind) THEN
   payload:=payload||jsonb_build_object('formContext',coalesce(nullif(e.data->'formContext','null'::jsonb),actual_context),
    'count',coalesce(nullif(e.data->'count','null'::jsonb),CASE WHEN actual_count>0 THEN to_jsonb(actual_count) END));
  END IF;
 END IF;
 IF e.kind='bank_problem' THEN
  SELECT bu.bank_account,u.id INTO account,un FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu
   ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   WHERE c.id=(e.data->>'bankConnectionId')::bigint AND bu."user"=auth.uid() AND public.notification_center_bank_admin(bu.bank_account,auth.uid()) AND u.organization=e.organization AND EXISTS(SELECT 1 FROM public.unit_users um WHERE um.unit=u.id AND um."user"=auth.uid() AND um.is_manager) ORDER BY u.id LIMIT 1;
  IF account IS NOT NULL THEN payload:=payload||jsonb_build_object('bankAccountId',account,'unitId',un); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'link',oc.link)),'[]') INTO impacts
   FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid() AND ou.is_editor_order_view
   WHERE oc.organization=e.organization AND oc.id=ANY(e.affected_occasions);
  payload:=payload||jsonb_build_object('affectedOccasions',impacts);
 END IF;
 RETURN (SELECT jsonb_build_object('id',e.id,'sequence',d.sequence,'kind',e.kind,'occurredAt',e.occurred_at,
 'status',e.status,'data',payload,'occasionId',e.occasion,'occasionLink',oc.link,'occasionTitle',oc.title)
 FROM (SELECT 1) seed LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=e.organization);
END $$;
-- One authorized snapshot selector shared by feed, hydration and external legacy serializers.
CREATE OR REPLACE FUNCTION public.notification_center_visible_internal(p_org bigint,p_snapshot bigint,p_current bigint DEFAULT NULL)
RETURNS TABLE(event public.notification_center_events,delivery public.notification_center_deliveries,section integer)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT e,d,CASE WHEN e.occasion IS NULL AND (p_current IS NULL OR cardinality(e.affected_occasions)=0 OR p_current=ANY(e.affected_occasions)) THEN 0
 WHEN e.occasion=p_current THEN 1 ELSE 2 END
 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=p_org AND d.recipient=auth.uid() AND d.sequence<=p_snapshot AND public.notification_center_allowed(e,auth.uid())
 AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries newer WHERE newer.event_id=d.event_id AND newer.recipient=d.recipient
 AND newer.sequence<=p_snapshot AND newer.sequence>d.sequence);
$$;
REVOKE ALL ON FUNCTION public.notification_center_visible_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_notification_center_feed(p_organization bigint,p_current_occasion bigint DEFAULT NULL,
 p_snapshot bigint DEFAULT NULL,p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; tuple jsonb; items jsonb; tail jsonb; more boolean; lim integer:=greatest(1,least(p_limit,100));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 SELECT least(coalesce(p_snapshot,last_delivery_sequence),last_delivery_sequence) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 IF p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb THEN
  BEGIN
   IF jsonb_typeof(p_cursor)<>'string' THEN RAISE EXCEPTION 'invalid cursor'; END IF;
   tuple:=convert_from(decode(p_cursor#>>'{}','base64'),'UTF8')::jsonb;
   IF jsonb_typeof(tuple)<>'object' OR NOT tuple ?& ARRAY['organization','snapshot','occasion','section','time','id']
    OR (tuple->>'organization')::bigint IS DISTINCT FROM p_organization OR (tuple->>'snapshot')::bigint IS DISTINCT FROM snap
    OR (tuple->>'occasion')::bigint IS DISTINCT FROM p_current_occasion OR (tuple->>'section')::int NOT BETWEEN 0 AND 2
    OR (tuple->>'time')::timestamptz IS NULL OR (tuple->>'id')::uuid IS NULL THEN RAISE EXCEPTION 'invalid cursor'; END IF;
  EXCEPTION WHEN OTHERS THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_cursor'; END;
 END IF;
 WITH rows AS (SELECT v.*,row_number() OVER(ORDER BY section,(event).occurred_at DESC,(event).id DESC) position
 FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v
 WHERE tuple IS NULL OR section>(tuple->>'section')::int OR (section=(tuple->>'section')::int
 AND ((event).occurred_at,(event).id)<((tuple->>'time')::timestamptz,(tuple->>'id')::uuid))
 ORDER BY section,(event).occurred_at DESC,(event).id DESC LIMIT lim+1), page AS (SELECT * FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(public.notification_center_dto(event,delivery)||jsonb_build_object('section',section) ORDER BY position) FROM page),'[]'),
 (SELECT jsonb_build_object('organization',p_organization,'snapshot',snap,'occasion',p_current_occasion,'section',section,'time',(event).occurred_at,'id',(event).id) FROM page ORDER BY position DESC LIMIT 1),
 (SELECT count(*)>lim FROM rows) INTO items,tail,more;
 RETURN jsonb_build_object('snapshot',snap,'items',items,'nextCursor',CASE WHEN more THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_feed(bigint,bigint,bigint,jsonb,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_feed(bigint,bigint,bigint,jsonb,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_group(p_organization bigint,p_group_key text,p_snapshot bigint,
 p_cursor bigint DEFAULT NULL,p_limit integer DEFAULT 5) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE items jsonb; next_cursor bigint;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 -- External legacy serializer for previously shipped clients only.
 WITH rows AS (SELECT public.notification_center_dto(event,delivery) item,(delivery).sequence FROM
 public.notification_center_visible_internal(p_organization,p_snapshot) WHERE (delivery).group_key=p_group_key
 AND (p_cursor IS NULL OR (delivery).sequence<p_cursor) ORDER BY (delivery).sequence DESC LIMIT greatest(1,least(p_limit,50)))
 SELECT coalesce(jsonb_agg(item ORDER BY sequence DESC),'[]'),CASE WHEN count(*)=greatest(1,least(p_limit,50)) THEN min(sequence) END INTO items,next_cursor FROM rows;
 RETURN jsonb_build_object('items',items,'nextCursor',next_cursor);
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_page(p_organization bigint,p_current_occasion bigint DEFAULT NULL,
 p_limit integer DEFAULT 30,p_snapshot bigint DEFAULT NULL,p_cursor jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE groups jsonb; choices jsonb; snap bigint; tail jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 SELECT least(coalesce(p_snapshot,last_delivery_sequence),last_delivery_sequence) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 -- External legacy grouped page; authorization and revision selection share the feed owner.
 WITH available AS (SELECT (delivery).*,(event).kind,(event).occasion,oc.title,v.section
 FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v
 LEFT JOIN public.occasions oc ON oc.id=(event).occasion AND oc.organization=p_organization), grouped AS (
 SELECT group_key,kind,occasion,title,section,count(*) n,max(sequence) latest FROM available GROUP BY group_key,kind,occasion,title,section
 ), page AS (SELECT * FROM grouped WHERE p_cursor IS NULL OR section>(p_cursor->>'section')::int OR
 (section=(p_cursor->>'section')::int AND (latest,group_key)<((p_cursor->>'sequence')::bigint,p_cursor->>'key'))
 ORDER BY section,latest DESC,group_key DESC LIMIT greatest(1,least(p_limit,100)))
 SELECT coalesce(jsonb_agg(jsonb_build_object('key',group_key,'section',section,'occasionId',occasion,'occasionTitle',title,'kind',kind,'day',CASE WHEN kind IN ('order_created','waitlist_registered','order_cancelled','occasion_joined','email_problem') THEN right(group_key,10) END,'count',n,
 'lastSequence',latest,'items',public.get_notification_center_group(p_organization,group_key,snap,NULL,5)->'items') ORDER BY section,latest DESC,group_key DESC),'[]'),
 (jsonb_agg(jsonb_build_object('section',section,'sequence',latest,'key',group_key) ORDER BY section DESC,latest,group_key)->0) INTO groups,tail FROM page;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'muted',coalesce(p.muted,false)) ORDER BY oc.title),'[]') INTO choices
 FROM public.occasions oc LEFT JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid()
 LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
 WHERE oc.organization=p_organization AND NOT public.is_demo_occasion(oc.id)
 AND (coalesce(ou.is_editor_order_view,false) OR public.notification_center_app_admin_internal(p_organization,oc.id,auth.uid()));
 RETURN jsonb_build_object('snapshot',snap,'groups',groups,'nextCursor',CASE WHEN jsonb_array_length(groups)=greatest(1,least(p_limit,100)) THEN tail END,'occasions',choices);
END $$;
CREATE OR REPLACE FUNCTION public.open_notification_center(p_organization bigint,p_current_occasion bigint DEFAULT NULL,p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state; result jsonb; feed jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
 UPDATE public.notification_center_user_state SET seen_through_sequence=greatest(seen_through_sequence,s.last_delivery_sequence)
 WHERE organization=p_organization AND recipient=auth.uid();
 result:=public.get_notification_center_page(p_organization,p_current_occasion,p_limit,s.last_delivery_sequence,NULL);
 feed:=public.get_notification_center_feed(p_organization,p_current_occasion,s.last_delivery_sequence,NULL,p_limit);
 RETURN result||jsonb_build_object('readThrough',s.last_delivery_sequence,'previousReadThrough',greatest(s.read_through_sequence,s.seen_through_sequence),'feedSupported',true,
 'feedItems',feed->'items',
 'feedNextCursor',feed->'nextCursor','timelineSupported',true,'snapshotAt',clock_timestamp(),
 'oldestOrderAt',(SELECT min((event).occurred_at) FROM public.notification_center_visible_internal(p_organization,s.last_delivery_sequence,p_current_occasion)
 WHERE (event).occasion IS NOT NULL AND public.notification_center_order_activity_internal((event).kind)));
END $$;
CREATE OR REPLACE FUNCTION public.set_notification_center_muted(p_organization bigint,p_occasion bigint,p_muted boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_occasion);
 IF p_occasion IS NULL OR p_muted IS NULL THEN RAISE EXCEPTION 'notification_invalid_preference'; END IF;
 INSERT INTO public.notification_center_preferences VALUES(p_organization,auth.uid(),p_occasion,p_muted)
 ON CONFLICT(organization,recipient,occasion) DO UPDATE SET muted=excluded.muted;
END $$;
-- Explicitly close every helper; PostgREST cannot publish or project as a user.
REVOKE ALL ON FUNCTION public.notification_center_require_service(),public.notification_center_allowed(public.notification_center_events,uuid),
 public.notification_center_check_context(bigint,bigint),public.notification_center_publish_internal(bigint,bigint,text,text,jsonb,uuid,timestamptz,bigint[]),
 public.notification_center_dto(public.notification_center_events,public.notification_center_deliveries),public.project_notification_center(integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.project_notification_center(integer) TO service_role;
REVOKE ALL ON FUNCTION public.get_notification_center_badge(bigint),public.open_notification_center(bigint,bigint,integer),
 public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb),public.get_notification_center_group(bigint,text,bigint,bigint,integer),
 public.set_notification_center_muted(bigint,bigint,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_badge(bigint),public.open_notification_center(bigint,bigint,integer),
 public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb),public.get_notification_center_group(bigint,text,bigint,bigint,integer),
 public.set_notification_center_muted(bigint,bigint,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_updates(p_organization bigint,p_snapshot bigint,p_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 IF coalesce(cardinality(p_ids),0)>200 THEN RAISE EXCEPTION 'notification_update_limit'; END IF;
 SELECT coalesce(jsonb_agg(public.notification_center_dto(event,delivery) ORDER BY (delivery).sequence DESC),'[]') INTO result
 FROM public.notification_center_visible_internal(p_organization,p_snapshot) WHERE (event).id=ANY(p_ids);
 RETURN jsonb_build_object('items',result);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_updates(bigint,bigint,uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_updates(bigint,bigint,uuid[]) TO authenticated;


-- SOURCE: notification_center/center_policy.sql
-- Only the current incident for a connection remains actionable. Historical
-- episodes can retain deliveries/read receipts, but must not duplicate alerts.
CREATE OR REPLACE FUNCTION public.notification_center_bank_episode_current(e public.notification_center_events)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT e.kind<>'bank_problem' OR NOT EXISTS(
  SELECT 1 FROM public.notification_center_source_state s
  WHERE s.organization=e.organization AND s.source_key='bank:'||(e.data->>'bankConnectionId')
   AND s.state->>'eventId' IS NOT NULL
   AND (s.state->>'eventId'<>e.id::text OR NOT coalesce((s.state->>'problem')::boolean,false)));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_episode_current(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

-- New-order activity follows the current order state, including older panel snapshots.
-- Participant joins remain relevant only while that person belongs to the occasion.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.notification_center_subject_visible_internal(e.organization,e.kind,e.data) AND CASE WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved') AND public.notification_center_bank_episode_current(e)
  ELSE e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno')
   AND (e.kind<>'occasion_joined' OR EXISTS(
    SELECT 1 FROM public.occasion_users m
    JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
    WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId'
     AND NOT EXISTS(SELECT 1 FROM public.organization_users hidden
      WHERE hidden.organization=e.organization AND hidden."user"=m."user" AND hidden.is_hidden))) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_in_center_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_notification_center_badge(p_organization bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state; anchor timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 RETURN jsonb_build_object('feedSupported',true,'timelineSupported',true,'enabled',true,'lastSequence',coalesce(s.last_delivery_sequence,0),'readThrough',coalesce(s.read_through_sequence,0),
 'unread',EXISTS(SELECT 1 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=p_organization AND d.recipient=auth.uid() AND d.sequence>greatest(coalesce(s.seen_through_sequence,0),coalesce(s.read_through_sequence,0))
 AND NOT (SELECT is_read FROM public.notification_center_batch_internal(e,d))
 AND public.notification_center_in_center_internal(e,anchor)
 AND public.notification_center_allowed(e,auth.uid()) AND public.notification_center_unmuted(e,auth.uid())));
END $$;

REVOKE ALL ON FUNCTION public.get_notification_center_badge(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_badge(bigint) TO authenticated;


-- SOURCE: notification_center/daily_overview.sql
-- Normalize opaque IDs sent by already-open clients during this migration.
-- This accepts an old identifier, never recreates a daily grouping.
CREATE OR REPLACE FUNCTION public.notification_center_rollup_id_internal(p_id text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=public,extensions AS $$
 SELECT regexp_replace(p_id,'^order-day:([0-9]+):([a-z_]+):[0-9]{4}-[0-9]{2}-[0-9]{2}$','occasion-kind:\1:\2');
$$;
REVOKE ALL ON FUNCTION public.notification_center_rollup_id_internal(text) FROM PUBLIC,anon,authenticated,service_role;

-- One client RPC opens/acknowledges, pages or refreshes category rollups.
-- Keep the existing RPC signature for installed clients; there is one grouping path.
-- Counts, historical place totals, bounded contact previews and badge state are
-- computed together. Calendar dates use one validated IANA display timezone.
CREATE OR REPLACE FUNCTION public.get_notification_center_daily_overview(
 p_organization bigint,p_current_occasion bigint,p_snapshot bigint DEFAULT NULL,
 p_snapshot_at timestamptz DEFAULT NULL,p_timezone text DEFAULT 'UTC',p_cursor jsonb DEFAULT NULL,
 p_limit integer DEFAULT 30,p_ids text[] DEFAULT NULL,p_open boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; context text; cursor jsonb; items jsonb; tail jsonb; more boolean; truncated boolean;
 anchor timestamptz:=coalesce(p_snapshot_at,clock_timestamp()); previous_read bigint;
 choices jsonb; badge jsonb; lim integer:=greatest(1,least(p_limit,200));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_timezone'; END IF;
 IF cardinality(p_ids)>10000 OR (p_ids IS NOT NULL AND p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb)
  OR (p_open AND (p_ids IS NOT NULL OR (p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb))) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_update_limit'; END IF;
 IF p_ids IS NOT NULL THEN lim:=greatest(1,cardinality(p_ids)); END IF;
 IF p_open THEN
  INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
  SELECT last_delivery_sequence,greatest(read_through_sequence,seen_through_sequence) INTO snap,previous_read
   FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
  anchor:=clock_timestamp();
 ELSE
  SELECT greatest(0,least(p_snapshot,last_delivery_sequence)) INTO snap
   FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 END IF;
 snap:=coalesce(snap,0);
 context:=md5(jsonb_build_array('occasion-kind-overview',auth.uid(),p_organization,p_current_occasion,snap,extract(epoch FROM anchor),p_timezone)::text);
 cursor:=public.notification_center_time_cursor_internal(p_cursor,context);
 WITH visible AS MATERIALIZED (
  SELECT v.*,b.batch_id,b.is_read,b.after_sequence,b.through_sequence,(event).kind NOT IN ('email_problem','bank_problem') AND (event).occasion IS NOT NULL grouped
  FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v
  CROSS JOIN LATERAL public.notification_center_batch_internal(v.event,v.delivery) b
  WHERE public.notification_center_in_center_internal(v.event,anchor)),
 -- Resolve absent legacy facts in batches, never one client request per row.
 legacy_orders AS MATERIALIZED (
  SELECT DISTINCT o.id,o.form FROM visible v
  JOIN eshop.orders o ON o.id=CASE WHEN (v.event).data->>'orderId' ~ '^[0-9]{1,18}$'
   THEN ((v.event).data->>'orderId')::bigint END AND o.occasion=(v.event).occasion
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=p_organization
  WHERE v.grouped AND public.notification_center_order_activity_internal((v.event).kind) AND ((v.event).data->>'count' IS NULL
   OR (v.event).data->>'formContext' IS NULL)),
 legacy_counts AS MATERIALIZED (
  SELECT o.id,nullif(count(DISTINCT x.ticket),0) places FROM legacy_orders o
  LEFT JOIN eshop.order_product_ticket x ON x."order"=o.id GROUP BY o.id),
 legacy_forms AS MATERIALIZED (
  SELECT form,public.notification_center_order_form_context_internal(form) context
  FROM (SELECT DISTINCT form FROM legacy_orders) f),
 classified AS MATERIALIZED (
  SELECT v.*,((event).occurred_at AT TIME ZONE p_timezone)::date calendar_day,
   coalesce(CASE WHEN (event).data->>'count' ~ '^[0-9]{1,9}$'
    THEN nullif(greatest(((event).data->>'count')::bigint,0),0) END,c.places) captured_places,
   coalesce(nullif((event).data->'formContext','null'::jsonb),f.context) resolved_context
  FROM visible v LEFT JOIN legacy_orders o ON v.grouped AND o.id=
   CASE WHEN (v.event).data->>'orderId' ~ '^[0-9]{1,18}$' THEN ((v.event).data->>'orderId')::bigint END
  LEFT JOIN legacy_counts c ON c.id=o.id LEFT JOIN legacy_forms f ON f.form=o.form),
 ranked AS (
  SELECT *,row_number() OVER(bucket ORDER BY (event).occurred_at DESC,(event).id DESC) rank,
   count(*) OVER bucket n,count(captured_places) OVER bucket known_counts,sum(captured_places) OVER bucket total_places,
   bool_or(captured_places>1 OR resolved_context->'allowsMultiple'='true'::jsonb) OVER bucket has_multiple,
   max((delivery).sequence) OVER bucket latest FROM classified WHERE grouped
  WINDOW bucket AS(PARTITION BY batch_id)),
 combined AS (
  SELECT (event).id::text id,section,(event).occurred_at at,event,delivery,calendar_day,
   0::bigint activity_count,(delivery).sequence sequence,NULL::bigint place_count,false multiple_places,batch_id,is_read,after_sequence,through_sequence FROM classified WHERE NOT grouped
  UNION ALL
  SELECT batch_id,section,(event).occurred_at,event,delivery,
   calendar_day,n,latest,CASE WHEN has_multiple AND known_counts=n THEN total_places END,coalesce(has_multiple,false),batch_id,is_read,after_sequence,through_sequence FROM ranked WHERE rank=1),
 catalog AS MATERIALIZED (
  SELECT *,row_number() OVER(ORDER BY section,at DESC,id DESC) catalog_position FROM
   (SELECT * FROM combined ORDER BY section,at DESC,id DESC LIMIT 101) bounded),
 rows AS (
  SELECT *,row_number() OVER(ORDER BY section,at DESC,id DESC) position FROM catalog
  WHERE catalog_position<=100 AND (p_ids IS NULL OR EXISTS(SELECT 1 FROM unnest(p_ids) requested WHERE requested=id OR (requested ~ '^(occasion-kind:[0-9]+:[a-z_]+|order-day:)' AND requested !~ ':(pending|batch|self|legacy)(:|$)' AND public.notification_center_rollup_id_internal(requested)=regexp_replace(id,':(pending|batch):.*$|:(self|legacy)$','')))) AND (cursor IS NULL OR section>(cursor->>'section')::int
   OR (section=(cursor->>'section')::int AND (at,id)<((cursor->>'time')::timestamptz,cursor->>'id')))
  ORDER BY section,at DESC,id DESC LIMIT lim+1),
 page AS (SELECT *,public.notification_center_dto(event,delivery)||jsonb_build_object('isRead',is_read,'isSeen',is_read OR sequence<=greatest(coalesce((SELECT seen_through_sequence FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid()),0),coalesce(previous_read,0))) dto,
  coalesce((SELECT requested FROM unnest(p_ids) WITH ORDINALITY r(requested,position)
    WHERE requested=rows.id OR public.notification_center_rollup_id_internal(requested)=regexp_replace(rows.id,':(pending|batch):.*$|:(self|legacy)$','') ORDER BY r.position LIMIT 1),id) response_id
  FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(CASE WHEN activity_count=0 THEN dto||jsonb_build_object('section',section,'day',calendar_day)
  WHEN NOT public.notification_center_order_activity_internal((event).kind) THEN
   dto||jsonb_build_object('id',response_id,'section',section,'day',calendar_day,'sequence',sequence,
     'data',(dto->'data')||jsonb_build_object('eventCount',activity_count))
  ELSE dto||jsonb_build_object('id',response_id,'section',section,'day',calendar_day,'sequence',sequence,'data',
   (CASE WHEN activity_count=1 THEN dto->'data' ELSE jsonb_build_object('contact',dto#>'{data,contact}') END)-'orderId'-'orderSymbol'
   ||jsonb_build_object('activityCount',activity_count,'relatedOrders',true,'allowsMultiple',multiple_places,'afterSequence',after_sequence,'throughSequence',sequence)
   ||jsonb_strip_nulls(jsonb_build_object('placeCount',place_count))
   ||jsonb_build_object('previewContacts',(SELECT jsonb_agg(
    public.notification_center_dto(r.event,r.delivery)#>'{data,contact}' ORDER BY r.rank)
    FROM ranked r WHERE r.batch_id=page.batch_id
     AND r.rank<=3))) END ORDER BY position) FROM page),'[]'),
  (SELECT jsonb_build_object('context',context,'section',section,'time',at,'id',id) FROM page ORDER BY position DESC LIMIT 1),
  (SELECT count(*)>lim FROM rows),(SELECT count(*)>100 FROM catalog) INTO items,tail,more,truncated;
 IF p_open THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'muted',coalesce(p.muted,false)) ORDER BY oc.title),'[]') INTO choices
  FROM public.occasions oc LEFT JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid()
  LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
  WHERE oc.organization=p_organization AND NOT public.is_demo_occasion(oc.id)
   AND (coalesce(ou.is_editor_order_view,false) OR public.notification_center_app_admin_internal(p_organization,oc.id,auth.uid()));
  -- A failed overview never acknowledges: data and watermark commit together.
  UPDATE public.notification_center_user_state SET seen_through_sequence=greatest(seen_through_sequence,snap)
  WHERE organization=p_organization AND recipient=auth.uid();
 END IF;
 badge:=public.get_notification_center_badge(p_organization);
 RETURN badge||jsonb_build_object('dailySupported',true,'truncated',truncated,'snapshot',snap,'snapshotAt',anchor,
  'snapshotDay',(anchor AT TIME ZONE p_timezone)::date,'timezone',p_timezone,
  'previousReadThrough',previous_read,'occasions',choices,'items',items,
  'nextCursor',CASE WHEN more AND p_ids IS NULL THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamptz,text,jsonb,integer,text[],boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamptz,text,jsonb,integer,text[],boolean) TO authenticated;


-- SOURCE: notification_center/order_selection.sql
-- Resolve the frozen, authorized group only when the orders page is opened.
-- No target ID arrays are added to the notification feed or badge polling.
CREATE OR REPLACE FUNCTION public.notification_center_order_selection(
 p_occasion bigint,p_group jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE org bigint; snap bigint; zone text; anchor timestamptz; result jsonb; lower_bound bigint; upper_bound bigint; group_id text; selected_id text; capture_at timestamptz; capture_read boolean;
BEGIN
 IF p_group ? 'viewToken' THEN
  p_group:=public.notification_center_prepared_scope((p_group->>'organization')::bigint,p_group);
  capture_at:=(p_group->>'capturedAt')::timestamptz;capture_read:=(p_group->>'captureIsRead')::boolean;
  IF (p_group->>'occasion')::bigint IS DISTINCT FROM p_occasion THEN RAISE insufficient_privilege USING MESSAGE='notification_context_mismatch'; END IF;
 END IF;
 IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='orders_read_denied'; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=p_occasion;
 IF org IS DISTINCT FROM (p_group->>'organization')::bigint THEN
  RAISE insufficient_privilege USING MESSAGE='notification_context_mismatch'; END IF;
 PERFORM public.notification_center_check_context(org,p_occasion);
 IF coalesce(p_group->>'snapshot','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 anchor:=least(coalesce((p_group->>'snapshotAt')::timestamptz,clock_timestamp()),clock_timestamp());
 zone:=p_group->>'timezone';
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_timezone'; END IF;
 SELECT greatest(0,least((p_group->>'snapshot')::bigint,last_delivery_sequence)) INTO snap
 FROM public.notification_center_user_state WHERE organization=org AND recipient=auth.uid();
 group_id:=public.notification_center_rollup_id_internal(p_group->>'id');
 selected_id:=group_id;
 lower_bound:=coalesce((p_group->>'afterSequence')::bigint,substring(group_id from ':batch:([0-9]+)$')::bigint,0);
 upper_bound:=least(coalesce((p_group->>'throughSequence')::bigint,snap),snap);
 IF capture_at IS NOT NULL THEN group_id:=p_group->>'groupKey';
 ELSE group_id:=regexp_replace(group_id,':(pending|batch):.*$|:(self|legacy)$',''); END IF;
 IF lower_bound<0 OR upper_bound<lower_bound THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 SELECT coalesce(jsonb_agg(DISTINCT ((v.event).data->>'orderId')::bigint),'[]'::jsonb) INTO result
 FROM public.notification_center_visible_internal(org,coalesce(snap,0),p_occasion) v
 WHERE (v.event).occasion=p_occasion
  AND public.notification_center_in_center_internal(v.event,anchor)
  AND public.notification_center_order_activity_internal((v.event).kind)
  AND public.notification_center_prepared_scope_member(v.event,v.delivery,group_id,selected_id,lower_bound,upper_bound,capture_at,capture_read)
  AND (v.event).data->>'orderId' ~ '^[0-9]{1,18}$';
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_selection(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.notification_center_order_selection(bigint,jsonb) TO authenticated;


-- SOURCE: eshop_orders/get_orders_tab_data.sql
DROP FUNCTION IF EXISTS public.get_orders_tab_data(text);
CREATE OR REPLACE FUNCTION public.get_orders_tab_data(
    p_occasion_link TEXT,
    p_notification_group JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
    v_notification_ids JSONB := '[]'::jsonb;
BEGIN

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    v_orders_data:=jsonb_set(v_orders_data,'{data,orders}',coalesce((SELECT jsonb_agg(o) FROM jsonb_array_elements(v_orders_data#>'{data,orders}') o WHERE o->>'state' IS DISTINCT FROM 'stock'),'[]'));
    IF p_notification_group IS NOT NULL THEN
      SELECT public.notification_center_order_selection(
        (v_orders_data->>'occasion_id')::bigint,p_notification_group) INTO v_notification_ids;
      -- Keep only records in the independently authorized orders response.
      SELECT coalesce(jsonb_agg(o->'id'),'[]'::jsonb) INTO v_notification_ids
      FROM jsonb_array_elements(v_orders_data#>'{data,orders}') o
      WHERE (o->>'id')::bigint IN (SELECT value::bigint FROM jsonb_array_elements_text(v_notification_ids));
    END IF;
    IF p_notification_group->>'markRead'='true' THEN
      PERFORM public.mark_notification_center_item_read(
        (p_notification_group->>'organization')::bigint,p_notification_group);
    END IF;
    -- No orders means no delivery status. Do not resolve an ambiguous event slug.
    RETURN (v_orders_data->'data') || jsonb_build_object('notification_order_ids',v_notification_ids,'forms', v_forms_data->'data', 'email_delivery',
      CASE WHEN jsonb_array_length(v_orders_data#>'{data,orders}') = 0
        THEN '{}'::jsonb
        ELSE public.get_order_email_summaries(
          (v_orders_data->>'occasion_id')::bigint,
          ARRAY(SELECT (ord->>'id')::bigint
            FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord))
      END);
END;
$$;

REVOKE ALL ON FUNCTION public.get_orders_tab_data(text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_orders_tab_data(text,jsonb) TO anon,authenticated,service_role;


-- SOURCE: notification_center/delivery_operations.sql
-- Operator surfaces never expose contacts, source payloads or recipient IDs.
CREATE OR REPLACE FUNCTION public.get_notification_center_delivery_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_require_service();
 SELECT coalesce(jsonb_agg(to_jsonb(s)),'[]') INTO result FROM (
  SELECT e.organization,count(*) pending,
   count(*) FILTER(WHERE r.retry_revision=r.eligible_revision AND r.quarantined) quarantined,
   count(*) FILTER(WHERE r.retry_revision=r.eligible_revision AND r.next_attempt_at>clock_timestamp()) backing_off,
   min(r.pending_since) oldest_pending_at,max(r.retry_count) maximum_attempts
  FROM public.notification_center_recipients r JOIN public.notification_center_events e ON e.id=r.event_id
  WHERE r.processed_revision<r.eligible_revision AND r.eligible_revision=e.attention_revision
  GROUP BY e.organization ORDER BY e.organization LIMIT 100) s;
 RETURN jsonb_build_object('organizations',result,'organizationLimit',100,'lastRun',
  (SELECT jsonb_build_object('scanned',last_scanned,'processed',last_processed,'deferred',last_deferred,
   'failed',last_failed,'elapsedMs',last_elapsed_ms,'at',last_run_at)
   FROM public.notification_center_maintenance WHERE name='delivery'));
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_delivery_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_center_delivery_health() TO service_role;
CREATE OR REPLACE FUNCTION public.retry_notification_center_delivery(p_organization bigint,p_event uuid,p_recipient uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 UPDATE public.notification_center_recipients r SET retry_count=0,next_attempt_at='-infinity',quarantined=false,last_error_code=NULL
 FROM public.notification_center_events e WHERE e.id=r.event_id AND e.organization=p_organization
  AND r.event_id=p_event AND r.recipient=p_recipient AND r.processed_revision<r.eligible_revision;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.retry_notification_center_delivery(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.retry_notification_center_delivery(bigint,uuid,uuid) TO service_role;


-- SOURCE: notification_center/prepared_projection.sql
CREATE OR REPLACE FUNCTION public.notification_center_prepared_privacy(p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('user',m."user",'email',nullif(lower(btrim(u.email_readonly)),''),'profile',u.id IS NOT NULL) ORDER BY m."user"),'[]')
 FROM public.organization_users m LEFT JOIN public.user_info u ON u.id=m."user" AND u.organization=m.organization
 WHERE m.organization=p_org AND m.is_hidden;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_privacy_keys(p_state jsonb)
RETURNS SETOF text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT 'u:'||(x->>'user') FROM jsonb_array_elements(p_state) x WHERE x->>'profile'='true'
 UNION SELECT 'e:'||(x->>'email') FROM jsonb_array_elements(p_state) x WHERE x->>'email' IS NOT NULL;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_subjects(e public.notification_center_events)
RETURNS SETOF text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH orders AS(SELECT o.data->>'email' email FROM eshop.orders o
  WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END),
 messages AS(SELECT m.recipient,m.recipient_user,m.order_id FROM public.email_messages m
  WHERE e.kind='email_problem' AND m.organization=e.organization AND m.message_id=CASE WHEN e.data->>'messageId' ~* '^[0-9a-f-]{36}$' THEN (e.data->>'messageId')::uuid END),
 subjects AS(SELECT 'u:'||(e.data->>'userId') subject WHERE e.data->>'userId' IS NOT NULL
  UNION SELECT 'e:'||lower(btrim(email)) FROM orders WHERE nullif(btrim(email),'') IS NOT NULL
  UNION SELECT 'e:'||lower(btrim(recipient)) FROM messages WHERE nullif(btrim(recipient),'') IS NOT NULL
  UNION SELECT 'u:'||recipient_user FROM messages WHERE recipient_user IS NOT NULL
  UNION SELECT 'e:'||lower(btrim(o.data->>'email')) FROM messages m JOIN eshop.orders o ON o.id=m.order_id
   JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization WHERE nullif(btrim(o.data->>'email'),'') IS NOT NULL)
 SELECT subject FROM subjects;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_tags(e public.notification_center_events)
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN e.kind='bank_problem' THEN
  ARRAY['bank:'||(e.data->>'bankConnectionId')]||
  CASE WHEN cardinality(e.affected_occasions)=0 THEN ARRAY['bank-shared:'||(e.data->>'bankConnectionId')] ELSE '{}'::text[] END||
  ARRAY(SELECT 'bank-occasion:'||x FROM unnest(e.affected_occasions) x)||
  ARRAY(SELECT 'bank-current:'||(e.data->>'bankConnectionId')||':'||x FROM unnest(e.affected_occasions) x)
 WHEN e.kind='email_problem' THEN ARRAY['email-admin:'||coalesce(e.occasion::text,'shared')]||
  CASE WHEN e.occasion IS NOT NULL THEN ARRAY['orders:'||e.occasion] ELSE '{}'::text[] END
 WHEN e.kind IN ('occasion_joined','event_capacity_full') THEN ARRAY['app:'||e.occasion]
 ELSE ARRAY['orders:'||e.occasion] END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_allowed_scopes(p_org bigint,p_current bigint,p_user uuid)
RETURNS TABLE(scope text,section integer) LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH occasions AS MATERIALIZED(SELECT oc.id,CASE WHEN oc.id=p_current THEN 1 ELSE 2 END priority,
  public.notification_center_allowed(jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',p_org,'occasion',oc.id,'kind','order_created')),p_user) orders,
  public.notification_center_allowed(jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',p_org,'occasion',oc.id,'kind','occasion_joined')),p_user) app,
  public.notification_center_allowed(jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',p_org,'occasion',oc.id,'kind','email_problem')),p_user) email,
  EXISTS(SELECT 1 FROM public.occasion_users m WHERE m.occasion=oc.id AND m."user"=p_user AND m.is_editor_order_view) bank
  FROM public.occasions oc JOIN(SELECT m.occasion id FROM public.occasion_users m WHERE m."user"=p_user AND (m.is_editor_order_view OR m.is_editor OR m.is_manager)
   UNION SELECT o.id FROM public.occasions o WHERE o.organization=p_org AND EXISTS(SELECT 1 FROM public.organization_users m WHERE m.organization=p_org AND m."user"=p_user AND m.is_admin)) own ON own.id=oc.id
  WHERE oc.organization=p_org),
 banks AS MATERIALIZED(SELECT DISTINCT c.id FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts uba
  ON uba.bank_account=c.bank_account_id OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
  JOIN public.units u ON u.id=uba.unit AND u.organization=p_org
  WHERE public.notification_center_allowed(jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',p_org,'kind','bank_problem','data',jsonb_build_object('bankConnectionId',c.id),'affected_occasions','[]'::jsonb)),p_user))
 SELECT 'orders:'||id,priority FROM occasions WHERE orders
 UNION ALL SELECT 'app:'||id,priority FROM occasions WHERE app
 UNION ALL SELECT 'email-admin:'||id,priority FROM occasions WHERE email
 UNION ALL SELECT 'email-admin:shared',0 WHERE EXISTS(SELECT 1 FROM public.organization_users WHERE organization=p_org AND "user"=p_user AND is_admin)
 UNION ALL SELECT 'bank-occasion:'||id,CASE WHEN p_current IS NULL OR id=p_current THEN 0 ELSE 2 END FROM occasions WHERE bank
 UNION ALL SELECT 'bank:'||id,CASE WHEN p_current IS NULL THEN 0 ELSE 2 END FROM banks
 UNION ALL SELECT 'bank-shared:'||id,0 FROM banks
 UNION ALL SELECT 'bank-current:'||id||':'||p_current,0 FROM banks WHERE p_current IS NOT NULL;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_refresh_summary(p_org bigint,p_user uuid,p_id text)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE ids uuid[]; latest public.notification_center_events; upper_bound bigint; first_seq bigint; read_state boolean;
BEGIN
 DELETE FROM public.notification_center_batch_summaries WHERE organization=p_org AND recipient=p_user AND id=p_id AND activity_count=0;
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_batch_summaries WHERE organization=p_org AND recipient=p_user AND id=p_id) THEN RETURN; END IF;
 SELECT array_agg(event_id ORDER BY occurred_at DESC,event_id DESC) INTO ids FROM (
  SELECT event_id,occurred_at FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND batch_id=p_id AND eligible
  ORDER BY occurred_at DESC,event_id DESC LIMIT 3) x;
 SELECT * INTO STRICT latest FROM public.notification_center_events WHERE id=ids[1];
 SELECT sequence INTO upper_bound FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND batch_id=p_id AND eligible ORDER BY sequence DESC LIMIT 1;
 SELECT sequence INTO first_seq FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND batch_id=p_id AND eligible ORDER BY sequence LIMIT 1;
 UPDATE public.notification_center_batch_summaries SET first_sequence=first_seq,latest_event=latest.id,latest_at=latest.occurred_at,
  through_sequence=upper_bound,preview_events=ids WHERE organization=p_org AND recipient=p_user AND id=p_id RETURNING is_read INTO read_state;
 DELETE FROM public.notification_center_summary_scopes WHERE organization=p_org AND recipient=p_user AND id=p_id;
 INSERT INTO public.notification_center_summary_scopes(organization,recipient,scope,id,latest_at,sequence,is_read)
 SELECT p_org,p_user,tag,p_id,latest.occurred_at,upper_bound,read_state FROM unnest(public.notification_center_prepared_tags(latest)) tag WHERE tag IS NOT NULL;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_policy(e public.notification_center_events,p_anchor timestamptz,p_privacy jsonb)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(SELECT 1 FROM public.notification_center_prepared_subjects(e) subject
  JOIN (SELECT 'u:'||(x->>'user') subject FROM jsonb_array_elements(p_privacy) x WHERE x->>'profile'='true'
   UNION SELECT 'e:'||(x->>'email') FROM jsonb_array_elements(p_privacy) x WHERE x->>'email' IS NOT NULL) hidden USING(subject))
 AND CASE WHEN e.kind IN ('email_problem','bank_problem') THEN e.status NOT IN ('recovered','resolved') AND public.notification_center_bank_episode_current(e)
 ELSE e.occurred_at>=p_anchor-interval '30 days'
  AND (e.kind<>'order_created' OR coalesce((SELECT o.state FROM eshop.orders o WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),e.status,'')<>'storno')
  AND (e.kind<>'occasion_joined' OR EXISTS(SELECT 1 FROM public.occasion_users m JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
   WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId')) END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_apply(e public.notification_center_events,d public.notification_center_deliveries,p_anchor timestamptz DEFAULT clock_timestamp(),p_privacy jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
#variable_conflict use_column
DECLARE old public.notification_center_view_members; b record; id text; visible boolean; places bigint; context jsonb; multi boolean; legacy_count bigint;
BEGIN
 SELECT * INTO old FROM public.notification_center_view_members WHERE organization=d.organization AND recipient=d.recipient AND event_id=d.event_id;
 IF FOUND AND old.sequence>d.sequence THEN RETURN; END IF;
 SELECT * INTO b FROM public.notification_center_batch_internal(e,d);
 id:=CASE WHEN e.kind IN ('email_problem','bank_problem') OR e.occasion IS NULL THEN e.id::text ELSE b.batch_id||CASE WHEN b.is_read THEN ':read' ELSE ':unread' END END;
 visible:=public.notification_center_prepared_policy(e,p_anchor,coalesce(p_privacy,(SELECT privacy FROM public.notification_center_projection_scopes WHERE organization=d.organization AND recipient=d.recipient)));
 places:=CASE WHEN e.data->>'count' ~ '^[0-9]{1,9}$' THEN nullif((e.data->>'count')::bigint,0) END;
 context:=nullif(e.data->'formContext','null'::jsonb);
 IF public.notification_center_order_activity_internal(e.kind) AND (e.data->>'count' IS NULL OR context IS NULL) THEN
  SELECT nullif(count(DISTINCT x.ticket),0),public.notification_center_order_form_context_internal(o.form)
   INTO legacy_count,context FROM eshop.orders o LEFT JOIN eshop.order_product_ticket x ON x."order"=o.id
   WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END GROUP BY o.id;
  places:=coalesce(places,legacy_count);context:=coalesce(nullif(e.data->'formContext','null'::jsonb),context);
 END IF;
 multi:=coalesce(places>1 OR context->'allowsMultiple'='true'::jsonb,false);
 IF old.eligible THEN
  UPDATE public.notification_center_batch_summaries SET activity_count=activity_count-1,known_count=known_count-(old.places IS NOT NULL)::int,
   places=places-coalesce(old.places,0),multiple_count=multiple_count-old.multiple::int
   WHERE organization=d.organization AND recipient=d.recipient AND id=old.batch_id;
 END IF;
 INSERT INTO public.notification_center_view_members(organization,recipient,event_id,sequence,attention_revision,source_revision,group_key,batch_id,is_read,after_sequence,through_sequence,eligible,occurred_at,expires_at,places,multiple)
 VALUES(d.organization,d.recipient,e.id,d.sequence,d.attention_revision,e.view_revision,b.group_key,id,b.is_read,b.after_sequence,b.through_sequence,visible,e.occurred_at,
  CASE WHEN e.kind NOT IN ('email_problem','bank_problem') THEN e.occurred_at+interval '30 days' END,places,multi)
 ON CONFLICT(organization,recipient,event_id) DO UPDATE SET sequence=excluded.sequence,attention_revision=excluded.attention_revision,source_revision=excluded.source_revision,
 group_key=excluded.group_key,batch_id=excluded.batch_id,is_read=excluded.is_read,after_sequence=excluded.after_sequence,through_sequence=excluded.through_sequence,
 eligible=excluded.eligible,occurred_at=excluded.occurred_at,expires_at=excluded.expires_at,places=excluded.places,multiple=excluded.multiple;
 DELETE FROM public.notification_center_member_subjects WHERE organization=d.organization AND recipient=d.recipient AND event_id=e.id;
 INSERT INTO public.notification_center_member_subjects(organization,recipient,event_id,subject)
 SELECT d.organization,d.recipient,e.id,subject FROM public.notification_center_prepared_subjects(e) subject ON CONFLICT DO NOTHING;
 IF visible THEN
  INSERT INTO public.notification_center_batch_summaries(organization,recipient,id,group_key,kind,occasion,is_read,after_sequence,through_sequence,activity_count,known_count,places,multiple_count,latest_at,latest_event,preview_events)
  VALUES(d.organization,d.recipient,id,b.group_key,e.kind,e.occasion,b.is_read,b.after_sequence,d.sequence,1,(places IS NOT NULL)::int,coalesce(places,0),multi::int,e.occurred_at,e.id,ARRAY[e.id])
  ON CONFLICT(organization,recipient,id) DO UPDATE SET activity_count=notification_center_batch_summaries.activity_count+1,
   known_count=notification_center_batch_summaries.known_count+excluded.known_count,places=notification_center_batch_summaries.places+excluded.places,
   multiple_count=notification_center_batch_summaries.multiple_count+excluded.multiple_count,is_read=excluded.is_read;
 END IF;
 IF old.batch_id IS NOT NULL AND old.batch_id<>id THEN PERFORM public.notification_center_prepared_refresh_summary(d.organization,d.recipient,old.batch_id); END IF;
 PERFORM public.notification_center_prepared_refresh_summary(d.organization,d.recipient,id);
END $$;
CREATE INDEX IF NOT EXISTS notification_center_member_upper ON public.notification_center_view_members(organization,recipient,batch_id,sequence DESC) WHERE eligible;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_invalidate(p_event uuid)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE org bigint; rev bigint; r record;
BEGIN
 -- No delivery means no prepared contribution to retract or invalidate.
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries WHERE event_id=p_event) THEN RETURN; END IF;
 UPDATE public.notification_center_events SET view_revision=view_revision+1 WHERE id=p_event RETURNING organization,view_revision INTO org,rev;
 FOR r IN SELECT nr.recipient,nr.view_required_revision>nr.view_applied_revision dirty FROM public.notification_center_recipients nr
  JOIN public.notification_center_projection_scopes s ON s.organization=org AND s.recipient=nr.recipient
  WHERE nr.event_id=p_event AND EXISTS(SELECT 1 FROM public.notification_center_deliveries d WHERE d.event_id=p_event AND d.recipient=nr.recipient)
  FOR UPDATE OF nr LOOP
  UPDATE public.notification_center_recipients SET view_required_revision=rev WHERE event_id=p_event AND recipient=r.recipient;
  UPDATE public.notification_center_projection_scopes SET revision=revision+1,
   pending_events=pending_events+CASE WHEN phase='ready' AND NOT r.dirty THEN 1 ELSE 0 END,requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN failed_event=p_event OR retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END,
   quarantined=CASE WHEN failed_event=p_event THEN false ELSE quarantined END,retry_count=CASE WHEN failed_event=p_event THEN 0 ELSE retry_count END,
   last_error_code=CASE WHEN failed_event=p_event THEN NULL ELSE last_error_code END
   WHERE organization=org AND recipient=r.recipient;
 END LOOP;
 PERFORM public.notification_center_prepared_wake();
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_delete_member(p_org bigint,p_user uuid,p_event uuid)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE old public.notification_center_view_members;
BEGIN
 SELECT * INTO old FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND event_id=p_event;
 IF NOT FOUND THEN RETURN; END IF;
 IF old.eligible THEN
  UPDATE public.notification_center_batch_summaries b SET activity_count=b.activity_count-1,
   known_count=b.known_count-(old.places IS NOT NULL)::int,places=b.places-coalesce(old.places,0),multiple_count=b.multiple_count-old.multiple::int
   WHERE b.organization=p_org AND b.recipient=p_user AND b.id=old.batch_id;
 END IF;
 DELETE FROM public.notification_center_view_members WHERE organization=p_org AND recipient=p_user AND event_id=p_event;
 PERFORM public.notification_center_prepared_refresh_summary(p_org,p_user,old.batch_id);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_delete_events(p_events uuid[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE m record;
BEGIN
 FOR m IN SELECT ev.organization,r.recipient,r.event_id,r.view_required_revision>r.view_applied_revision dirty,
   r.processed_revision<r.eligible_revision delivery_dirty
  FROM public.notification_center_recipients r JOIN public.notification_center_events ev ON ev.id=r.event_id
  JOIN public.notification_center_projection_scopes ps ON ps.organization=ev.organization AND ps.recipient=r.recipient
  WHERE r.event_id=ANY(p_events) ORDER BY ev.organization,r.recipient,r.event_id FOR UPDATE OF ev,r LOOP
  PERFORM 1 FROM public.notification_center_projection_scopes WHERE organization=m.organization AND recipient=m.recipient FOR UPDATE;
  PERFORM public.notification_center_prepared_delete_member(m.organization,m.recipient,m.event_id);
  UPDATE public.notification_center_projection_scopes SET revision=revision+1,
   pending_events=greatest(0,pending_events-m.dirty::int),
   pending_delivery=greatest(0,pending_delivery-CASE WHEN delivery_initialized AND m.delivery_dirty THEN 1 ELSE 0 END)
   WHERE organization=m.organization AND recipient=m.recipient;
 END LOOP;
 PERFORM public.notification_center_prepared_wake();
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_on_delivery(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE s public.notification_center_projection_scopes; read_rev bigint;
BEGIN
 SELECT * INTO s FROM public.notification_center_projection_scopes WHERE organization=d.organization AND recipient=d.recipient FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN
  IF EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE organization=d.organization AND recipient=d.recipient) THEN
   RAISE lock_not_available USING MESSAGE='notification_projection_scope_busy';
  END IF;
  RETURN;
 END IF;
 SELECT view_read_revision INTO read_rev FROM public.notification_center_user_state WHERE organization=d.organization AND recipient=d.recipient;
 IF s.phase<>'ready' OR s.pending_events>0 OR s.pending_groups>0 OR s.privacy_pending
  OR s.applied_read_revision<>read_rev OR s.privacy<>public.notification_center_prepared_privacy(d.organization)
  OR s.prepared_sequence<>d.sequence-1 THEN
  UPDATE public.notification_center_projection_scopes SET requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=d.organization AND recipient=d.recipient;
  RETURN;
 END IF;
 PERFORM public.notification_center_prepared_apply(e,d);
 UPDATE public.notification_center_recipients SET view_required_revision=e.view_revision,view_applied_revision=e.view_revision WHERE event_id=e.id AND recipient=d.recipient;
 UPDATE public.notification_center_projection_scopes SET prepared_sequence=d.sequence,
  next_expiry=least(next_expiry,CASE WHEN e.kind NOT IN ('email_problem','bank_problem') AND public.notification_center_prepared_policy(e,clock_timestamp(),s.privacy) THEN e.occurred_at+interval '30 days' END)
  WHERE organization=d.organization AND recipient=d.recipient;
END $$;
-- One receipt owner serves both external serializers after their scope checks.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_record_read(p_org bigint,p_group text,p_after bigint,p_through bigint,p_captured boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE baseline bigint; last_read bigint; lower_bound bigint; inserted boolean;
BEGIN
 SELECT read_through_sequence INTO baseline FROM public.notification_center_user_state WHERE organization=p_org AND recipient=auth.uid() FOR UPDATE;
 SELECT coalesce(max(through_sequence),0) INTO last_read FROM public.notification_center_read_batches WHERE organization=p_org AND recipient=auth.uid() AND group_key=p_group;
 lower_bound:=CASE WHEN p_captured THEN greatest(p_after,baseline) ELSE greatest(p_after,baseline,last_read) END;
 IF p_through<=lower_bound THEN RETURN true; END IF;
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 VALUES(p_org,auth.uid(),p_group,lower_bound,p_through) ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN RETURN true; END IF;
 UPDATE public.notification_center_user_state SET view_read_revision=view_read_revision+1 WHERE organization=p_org AND recipient=auth.uid();
 INSERT INTO public.notification_center_group_repairs(organization,recipient,group_key)
 SELECT p_org,auth.uid(),p_group WHERE EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE organization=p_org AND recipient=auth.uid())
 ON CONFLICT DO NOTHING RETURNING true INTO inserted;
 IF inserted THEN
  UPDATE public.notification_center_projection_scopes SET pending_groups=pending_groups+1,requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=p_org AND recipient=auth.uid();
 ELSE
  UPDATE public.notification_center_group_repairs SET cursor=NULL WHERE organization=p_org AND recipient=auth.uid() AND group_key=p_group;
 END IF;
 PERFORM public.notification_center_prepared_wake();
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_seal(p_org bigint,p_group text,p_after bigint,p_through bigint)
RETURNS boolean LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.notification_center_prepared_record_read(p_org,p_group,p_after,p_through,false);
$$;

CREATE OR REPLACE FUNCTION public.notification_center_prepared_order_events(p_order bigint)
RETURNS SETOF uuid LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT e.id FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 JOIN public.notification_center_events e ON e.organization=oc.organization AND e.occasion=o.occasion
 WHERE o.id=p_order AND e.data->>'orderId'=p_order::text
  AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted','offer_declined','offer_expired')
 UNION
 SELECT e.id FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 JOIN public.email_messages m ON m.order_id=o.id AND m.occasion=o.occasion AND m.organization=oc.organization
 JOIN public.notification_center_events e ON e.organization=m.organization AND e.kind='email_problem' AND e.source_key='email:'||m.message_id
 WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_invalidate_order(p_order bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE event_id uuid;
BEGIN
 FOR event_id IN SELECT * FROM public.notification_center_prepared_order_events(p_order) LOOP
  PERFORM public.notification_center_prepared_invalidate(event_id);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_invalidate_user(p_user uuid,p_occasion bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE item record;
BEGIN
 FOR item IN SELECT e.id FROM public.notification_center_events e WHERE e.kind='occasion_joined' AND e.data->>'userId'=p_user::text
  AND (p_occasion IS NULL OR e.occasion=p_occasion) LOOP PERFORM public.notification_center_prepared_invalidate(item.id); END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_defer(p_event uuid,p_recipient uuid,p_revision bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 -- Only retry metadata changes. Never claim work or advance canonical progress.
 UPDATE public.notification_center_recipients r SET next_attempt_at=clock_timestamp()+interval '1 second',
  retry_count=CASE WHEN retry_revision=eligible_revision THEN retry_count ELSE 0 END,
  quarantined=CASE WHEN retry_revision=eligible_revision THEN quarantined ELSE false END,retry_revision=eligible_revision
 WHERE r.event_id=p_event AND r.recipient=p_recipient AND r.eligible_revision=p_revision
  AND r.ctid IN(SELECT ctid FROM public.notification_center_recipients WHERE event_id=p_event AND recipient=p_recipient FOR UPDATE SKIP LOCKED);
END $$;


-- SOURCE: notification_center/prepared_views.sql
CREATE OR REPLACE FUNCTION public.notification_center_prepared_batch_at(
 e public.notification_center_events,d public.notification_center_deliveries,p_anchor timestamptz)
RETURNS TABLE(batch_id text,is_read boolean,after_sequence bigint,through_sequence bigint,group_key text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH state AS (
  SELECT coalesce((SELECT read_through_sequence FROM public.notification_center_user_state
   WHERE organization=d.organization AND recipient=d.recipient),0) baseline,
   CASE WHEN e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem')
    THEN 'occasion-kind:'||e.occasion||':'||e.kind ELSE 'event:'||e.id END key),
 receipt AS (
  SELECT b.* FROM public.notification_center_read_batches b,state s
  WHERE b.organization=d.organization AND b.recipient=d.recipient AND b.group_key=s.key
   AND b.read_at<=p_anchor AND d.sequence>b.after_sequence AND d.sequence<=b.through_sequence
  ORDER BY b.through_sequence,b.read_at,b.id LIMIT 1),
 bounds AS (
  SELECT s.*,greatest(s.baseline,coalesce((SELECT max(b.through_sequence)
   FROM public.notification_center_read_batches b WHERE b.organization=d.organization
    AND b.recipient=d.recipient AND b.group_key=s.key AND b.read_at<=p_anchor),0)) last_read,
   e.actor=d.recipient AND e.kind IN ('order_created','order_cancelled') own_action FROM state s)
 SELECT CASE WHEN coalesce(s.own_action,false) THEN s.key||':self'
   WHEN d.sequence<=s.baseline THEN s.key||':legacy'
   WHEN r.id IS NOT NULL THEN s.key||':batch:'||r.after_sequence
   ELSE s.key||':batch:'||s.last_read END,
  coalesce(s.own_action,false) OR d.sequence<=s.baseline OR r.id IS NOT NULL,
  CASE WHEN coalesce(s.own_action,false) OR d.sequence<=s.baseline THEN 0
   WHEN r.id IS NOT NULL THEN r.after_sequence ELSE s.last_read END,
  CASE WHEN coalesce(s.own_action,false) THEN d.sequence WHEN d.sequence<=s.baseline THEN s.baseline
   WHEN r.id IS NOT NULL THEN r.through_sequence ELSE d.sequence END,s.key
 FROM bounds s LEFT JOIN receipt r ON true;
$$;

DROP FUNCTION IF EXISTS public.notification_center_prepared_scope_member(public.notification_center_events,public.notification_center_deliveries,text,text,bigint,bigint);
-- Shared membership predicate. External legacy and token contracts validate
-- their scopes separately before invoking this private owner.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_scope_member(e public.notification_center_events,d public.notification_center_deliveries,p_group text,p_id text,p_after bigint,p_through bigint,p_capture_at timestamptz DEFAULT NULL,p_capture_read boolean DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT d.sequence>p_after AND d.sequence<=p_through AND CASE WHEN p_capture_at IS NULL THEN true WHEN p_group LIKE 'event:%' THEN true ELSE
  EXISTS(SELECT 1 FROM public.notification_center_prepared_batch_at(e,d,p_capture_at) b WHERE b.batch_id=regexp_replace(p_id,':(read|unread)$','') AND b.is_read=p_capture_read) END
 AND CASE WHEN p_group LIKE 'event:%' THEN 'event:'||e.id=p_group
 ELSE 'occasion-kind:'||e.occasion||':'||e.kind=p_group END
 AND CASE WHEN p_id ~ ':self$' THEN coalesce(e.actor=d.recipient,false)
 WHEN p_id ~ ':(batch:[0-9]+|legacy)$' AND e.kind IN ('order_created','order_cancelled') THEN e.actor IS DISTINCT FROM d.recipient ELSE true END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_contact(e public.notification_center_events)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_strip_nulls(jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'))
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
 WHERE o.occasion=e.occasion AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END;
$$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_render(r public.notification_center_view_rows,v public.notification_center_views)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; d public.notification_center_deliveries; dto jsonb; contact jsonb; previews jsonb; payload jsonb; grouped boolean;
BEGIN
 IF r.state<>'ready' THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state',r.state); END IF;
 SELECT * INTO e FROM public.notification_center_events WHERE id=r.latest_event;
 IF NOT FOUND OR NOT public.notification_center_allowed(e,auth.uid()) THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state','removed'); END IF;
 SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=e.id AND recipient=v.recipient AND sequence<=v.snapshot ORDER BY sequence DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state','removed'); END IF;
 grouped:=e.occasion IS NOT NULL AND e.kind NOT IN ('email_problem','bank_problem');
 IF grouped AND public.notification_center_order_activity_internal(e.kind) THEN
  contact:=coalesce(public.notification_center_prepared_contact(e),'{}');
  SELECT coalesce(jsonb_agg(coalesce(public.notification_center_prepared_contact(ev),'{}') ORDER BY p.position),'[]') INTO previews
   FROM unnest(r.preview_events) WITH ORDINALITY p(id,position) JOIN public.notification_center_events ev ON ev.id=p.id;
  payload:=CASE WHEN r.activity_count=1 THEN e.data-'orderId'-'orderSymbol' ELSE '{}'::jsonb END||
   jsonb_build_object('contact',contact,'previewContacts',previews,'activityCount',r.activity_count,'relatedOrders',true,
    'allowsMultiple',r.multiple_count>0,'afterSequence',r.after_sequence,'throughSequence',r.through_sequence)||
   CASE WHEN r.multiple_count>0 AND r.known_count=r.activity_count THEN jsonb_build_object('placeCount',r.places) ELSE '{}'::jsonb END;
  dto:=(SELECT jsonb_build_object('kind',e.kind,'status',e.status,'data',payload,'occasionId',e.occasion,'occasionLink',oc.link,'occasionTitle',oc.title)
   FROM (SELECT 1) seed LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=e.organization);
 ELSE
  dto:=public.notification_center_dto(e,d);
  IF grouped THEN dto:=jsonb_set(dto,'{data}',coalesce(dto->'data','{}')||jsonb_build_object('eventCount',r.activity_count)); END IF;
 END IF;
 RETURN dto||jsonb_build_object('id',r.id,'position',r.position,'state','ready','sequence',r.through_sequence,
  'section',CASE WHEN e.occasion IS NULL AND (v.current_occasion IS NULL OR cardinality(e.affected_occasions)=0 OR v.current_occasion=ANY(e.affected_occasions)) THEN 0 WHEN e.occasion=v.current_occasion THEN 1 ELSE 2 END,'occurredAt',r.latest_at,'day',(r.latest_at AT TIME ZONE v.timezone)::date,'isRead',r.is_read,
  'isSeen',r.is_read OR r.through_sequence<=v.previous_seen);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_display_key(p_token uuid,p_cursor integer,p_limit integer)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH owned AS MATERIALIZED(SELECT * FROM public.notification_center_views WHERE token=p_token AND recipient=auth.uid()),
 rows AS MATERIALIZED(SELECT r.*,r.xmin::text row_xid,r.ctid::text row_tid FROM public.notification_center_view_rows r WHERE r.token=p_token AND r.position>p_cursor AND r.position<=p_cursor+p_limit),
 facts AS(SELECT r.position,p.position preview,ev.id,ev.event_xid,ev.event_tid,
  o.xmin::text order_xid,o.ctid::text order_tid,m.xmin::text mail_xid,m.ctid::text mail_tid,
  mo.xmin::text mail_order_xid,mo.ctid::text mail_order_tid,ui.xmin::text profile_xid,ui.ctid::text profile_tid,
  oc.xmin::text occasion_xid,oc.ctid::text occasion_tid,
  CASE WHEN ev.kind='bank_problem' THEN(SELECT jsonb_agg(jsonb_build_array(c.xmin::text,c.ctid::text,uba.unit,uba.bank_account,uba.xmin::text,uba.ctid::text,bu.xmin::text,bu.ctid::text,um.xmin::text,um.ctid::text,u.xmin::text,u.ctid::text) ORDER BY uba.unit,bu.bank_account)
   FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON bu."user"=auth.uid() AND (bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   LEFT JOIN public.unit_users um ON um.unit=u.id AND um."user"=auth.uid() WHERE c.id=(ev.data->>'bankConnectionId')::bigint) END bank_versions,
  CASE WHEN ev.kind='bank_problem' THEN(SELECT jsonb_agg(jsonb_build_array(impact.id,impact.xmin::text,impact.ctid::text) ORDER BY impact.id) FROM public.occasions impact
   WHERE impact.organization=ev.organization AND impact.id=ANY(ev.affected_occasions)) END impact_versions
  FROM rows r CROSS JOIN LATERAL unnest(r.preview_events) WITH ORDINALITY p(id,position)
  JOIN LATERAL(SELECT permitted.*,permitted.xmin::text event_xid,permitted.ctid::text event_tid FROM public.notification_center_events permitted WHERE permitted.id=p.id AND public.notification_center_allowed(permitted,auth.uid()) OFFSET 0) ev ON true
  LEFT JOIN eshop.orders o ON o.occasion=ev.occasion AND o.id=CASE WHEN ev.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (ev.data->>'orderId')::bigint END
  LEFT JOIN public.email_messages m ON m.organization=ev.organization AND m.message_id=CASE WHEN ev.data->>'messageId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (ev.data->>'messageId')::uuid END
  LEFT JOIN eshop.orders mo ON mo.id=m.order_id AND mo.occasion=m.occasion
  LEFT JOIN public.user_info ui ON ui.organization=ev.organization AND ui.id=coalesce(m.recipient_user,CASE WHEN ev.data->>'userId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (ev.data->>'userId')::uuid END)
  LEFT JOIN public.occasions oc ON oc.id=ev.occasion AND oc.organization=ev.organization)
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(jsonb_build_array(position,row_xid,row_tid) ORDER BY position) FROM rows),
  (SELECT jsonb_agg(to_jsonb(f) ORDER BY position,preview) FROM facts f),
  (SELECT jsonb_agg(jsonb_build_array(a.scope,a.section) ORDER BY a.scope,a.section) FROM owned v CROSS JOIN LATERAL public.notification_center_prepared_allowed_scopes(v.organization,v.current_occasion,v.recipient) a))::text);
$$;

-- One STABLE statement owns privacy/read checks and every payload read, avoiding
-- a generation preflight followed by a different READ COMMITTED snapshot.
DROP FUNCTION IF EXISTS public.notification_center_prepared_payload(uuid,integer,integer);
CREATE OR REPLACE FUNCTION public.notification_center_prepared_payload(p_token uuid,p_cursor integer,p_limit integer,p_revision text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH owned AS MATERIALIZED(SELECT v.*,s.revision current_revision,u.view_read_revision current_read_revision,
  md5(public.notification_center_prepared_privacy(v.organization)::text) current_privacy
  FROM public.notification_center_views v JOIN public.notification_center_projection_scopes s USING(organization,recipient)
  JOIN public.notification_center_user_state u USING(organization,recipient)
  WHERE v.token=p_token AND v.recipient=auth.uid()),
 status AS MATERIALIZED(SELECT o.*,EXISTS(SELECT 1 FROM public.notification_center_view_rows r WHERE r.token=o.token
  AND (r.revision<>o.current_revision OR r.read_revision<>o.current_read_revision OR r.privacy_key<>o.current_privacy OR r.state='preparing')) preparing FROM owned o),
 keyed AS(SELECT status.*,CASE WHEN preparing THEN NULL ELSE public.notification_center_prepared_display_key(token,p_cursor,p_limit) END display_key FROM status)
 SELECT jsonb_build_object('viewSupported',true,'state',CASE WHEN o.expires_at<=clock_timestamp() THEN 'expired' WHEN o.preparing THEN 'preparing' ELSE 'ready' END,
  'viewToken',o.token,'snapshot',o.snapshot,'snapshotAt',o.anchor,'snapshotDay',(o.anchor AT TIME ZONE o.timezone)::date,'timezone',o.timezone,
  'previousReadThrough',o.previous_seen,'acknowledged',o.acknowledged,'truncated',o.truncated,
  'revision',o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key,
  'unchanged',NOT o.preparing AND p_revision=(o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key),
  'items',CASE WHEN o.expires_at<=clock_timestamp() OR (NOT o.preparing AND p_revision=(o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key)) THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(
   CASE WHEN o.preparing THEN jsonb_build_object('id',r.id,'position',r.position,'state','preparing')
   ELSE public.notification_center_prepared_render(r,ROW(o.token,o.organization,o.recipient,o.current_occasion,o.timezone,o.snapshot,o.anchor,o.previous_seen,o.source_revision,o.read_revision,o.privacy_key,o.created_at,o.expires_at,o.acknowledged,o.truncated)::public.notification_center_views) END ORDER BY r.position)
   FROM public.notification_center_view_rows r WHERE r.token=o.token AND r.position>p_cursor AND r.position<=p_cursor+p_limit),'[]') END,
  'nextCursor',CASE WHEN EXISTS(SELECT 1 FROM public.notification_center_view_rows r WHERE r.token=o.token AND r.position>p_cursor+p_limit) THEN p_cursor+p_limit END,
  'retryAfterMs',CASE WHEN o.preparing THEN 1000 END)
 FROM keyed o;
$$;
DROP FUNCTION IF EXISTS public.get_notification_center_view(bigint,bigint,text,uuid,integer,integer,text);
CREATE OR REPLACE FUNCTION public.get_notification_center_view(p_organization bigint,p_current_occasion bigint DEFAULT NULL,
 p_mode text DEFAULT 'open',p_view uuid DEFAULT NULL,p_cursor integer DEFAULT 0,p_limit integer DEFAULT 30,p_timezone text DEFAULT 'UTC',p_revision text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
#variable_conflict use_variable
DECLARE s public.notification_center_projection_scopes; u public.notification_center_user_state; v public.notification_center_views;
 token uuid:=p_view; payload jsonb; anchor timestamptz:=clock_timestamp(); lim integer:=greatest(1,least(coalesce(p_limit,30),100));
 previous_timeout text:=current_setting('lock_timeout'); total integer;
BEGIN
 BEGIN PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('viewSupported',true,'state','denied','items','[]'::jsonb); END;
 IF p_mode IS NULL OR p_cursor IS NULL OR (p_mode IN ('preview','open') AND p_cursor<>0) OR p_mode NOT IN ('preview','open','page','refresh','close','close_all') OR p_cursor<0 OR p_cursor>100
  OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_view_request'; END IF;
 IF p_mode IN ('close','close_all') THEN
  DELETE FROM public.notification_center_views WHERE (p_mode='close_all' OR notification_center_views.token=p_view) AND organization=p_organization AND recipient=auth.uid();
  RETURN jsonb_build_object('viewSupported',true,'state','closed','items','[]'::jsonb);
 END IF;
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization AND prepared_paused) THEN RETURN jsonb_build_object('viewSupported',true,'state','preparing','items','[]'::jsonb,'retryAfterMs',1000); END IF;
 PERFORM set_config('lock_timeout','5ms',true);
 BEGIN
  INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
  INSERT INTO public.notification_center_projection_scopes(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
  SELECT * INTO s FROM public.notification_center_projection_scopes WHERE organization=p_organization AND recipient=auth.uid() FOR SHARE NOWAIT;
  IF token IS NOT NULL AND p_mode='open' THEN
   SELECT * INTO v FROM public.notification_center_views WHERE notification_center_views.token=token AND organization=p_organization AND recipient=auth.uid()
    AND current_occasion IS NOT DISTINCT FROM p_current_occasion AND timezone=p_timezone;
   SELECT * INTO u FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
   IF v.token IS NOT NULL AND NOT v.acknowledged AND (v.snapshot<>u.last_delivery_sequence OR s.pending_delivery>0
     OR v.source_revision<>s.revision OR v.read_revision<>u.view_read_revision OR v.privacy_key<>md5(public.notification_center_prepared_privacy(p_organization)::text)) THEN
    DELETE FROM public.notification_center_views WHERE notification_center_views.token=token;token:=NULL;
   END IF;
  END IF;
  IF token IS NOT NULL THEN
   SELECT * INTO v FROM public.notification_center_views WHERE notification_center_views.token=token AND organization=p_organization AND recipient=auth.uid()
    AND current_occasion IS NOT DISTINCT FROM p_current_occasion AND timezone=p_timezone;
   IF NOT FOUND OR v.expires_at<=anchor THEN payload:=jsonb_build_object('viewSupported',true,'state','expired','items','[]'::jsonb);
   ELSE payload:=public.notification_center_prepared_payload(token,p_cursor,lim,CASE WHEN p_mode='refresh' THEN p_revision END); END IF;
  ELSIF p_mode NOT IN ('preview','open') THEN payload:=jsonb_build_object('viewSupported',true,'state','expired','items','[]'::jsonb);
  ELSE
   SELECT * INTO u FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE NOWAIT;
   anchor:=clock_timestamp();
   -- No lease/catalog is allocated until all required preparation is ready.
   -- A preparing open has no bound to acknowledge and retries as a fresh intent.
   IF s.phase<>'ready' OR NOT s.delivery_initialized OR s.pending_delivery>0 OR s.pending_events>0 OR s.pending_groups>0 OR s.privacy_pending
    OR s.prepared_sequence<>u.last_delivery_sequence OR s.applied_read_revision<>u.view_read_revision OR s.next_expiry<anchor
    OR s.privacy<>public.notification_center_prepared_privacy(p_organization) THEN
    payload:=jsonb_build_object('viewSupported',true,'state','preparing','items','[]'::jsonb,'retryAfterMs',1000);
   ELSE
    DELETE FROM public.notification_center_views WHERE notification_center_views.token IN(SELECT expired.token FROM public.notification_center_views expired
     WHERE expired.organization=p_organization AND expired.recipient=auth.uid() AND expired.expires_at<=anchor LIMIT 100);
    IF (SELECT count(*) FROM public.notification_center_views WHERE organization=p_organization AND recipient=auth.uid())>=4 THEN
     payload:=jsonb_build_object('viewSupported',true,'state','view_limit','items','[]'::jsonb);
    ELSE
     INSERT INTO public.notification_center_views(organization,recipient,current_occasion,timezone,snapshot,anchor,previous_seen,source_revision,read_revision,privacy_key)
     VALUES(p_organization,auth.uid(),p_current_occasion,p_timezone,u.last_delivery_sequence,anchor,greatest(u.seen_through_sequence,u.read_through_sequence),s.revision,u.view_read_revision,md5(s.privacy::text)) RETURNING notification_center_views.token INTO token;
     WITH candidates AS MATERIALIZED(
      SELECT DISTINCT ON(x.id) x.id,a.section,x.latest_at FROM public.notification_center_prepared_allowed_scopes(p_organization,p_current_occasion,auth.uid()) a
      CROSS JOIN LATERAL(SELECT id,latest_at FROM public.notification_center_summary_scopes t WHERE t.organization=p_organization AND t.recipient=auth.uid() AND t.scope=a.scope
       ORDER BY latest_at DESC,id DESC LIMIT 101) x ORDER BY x.id,a.section),
     ranked AS(SELECT *,row_number() OVER(ORDER BY section,latest_at DESC,id DESC) position FROM candidates ORDER BY section,latest_at DESC,id DESC LIMIT 101)
     INSERT INTO public.notification_center_view_rows(token,position,id,group_key,after_sequence,through_sequence,kind,occasion,latest_at,latest_event,preview_events,capture_is_read,
      activity_count,known_count,places,multiple_count,is_read,revision,read_revision,privacy_key)
     SELECT token,r.position,r.id,b.group_key,least(b.after_sequence,b.first_sequence-1),b.through_sequence,b.kind,b.occasion,b.latest_at,b.latest_event,b.preview_events,b.is_read,
      b.activity_count,b.known_count,b.places,b.multiple_count,b.is_read,s.revision,u.view_read_revision,md5(s.privacy::text)
      FROM ranked r JOIN public.notification_center_batch_summaries b ON b.organization=p_organization AND b.recipient=auth.uid() AND b.id=r.id WHERE r.position<=100;
     -- Truncation requires only the same bounded scope candidates, never history.
     SELECT count(*) INTO total FROM (SELECT DISTINCT x.id FROM public.notification_center_prepared_allowed_scopes(p_organization,p_current_occasion,auth.uid()) a
      CROSS JOIN LATERAL(SELECT id FROM public.notification_center_summary_scopes t WHERE t.organization=p_organization AND t.recipient=auth.uid() AND t.scope=a.scope
       ORDER BY latest_at DESC,id DESC LIMIT 101) x LIMIT 101) bounded;
     UPDATE public.notification_center_views SET truncated=total>100 WHERE notification_center_views.token=token;
     payload:=public.notification_center_prepared_payload(token,p_cursor,lim,CASE WHEN p_mode='refresh' THEN p_revision END);
    END IF;
   END IF;
  END IF;
  IF p_mode='open' AND payload->>'state'='ready' THEN
   SELECT * INTO u FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE NOWAIT;
   UPDATE public.notification_center_user_state SET seen_through_sequence=greatest(seen_through_sequence,(payload->>'snapshot')::bigint) WHERE organization=p_organization AND recipient=auth.uid();
   UPDATE public.notification_center_views SET acknowledged=true WHERE notification_center_views.token=token;
   payload:=payload||jsonb_build_object('acknowledged',true);
  ELSIF payload->>'state'='preparing' THEN
   UPDATE public.notification_center_projection_scopes SET requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=p_organization AND recipient=auth.uid();
  END IF;
  IF payload->>'state'='preparing' THEN PERFORM public.notification_center_prepared_wake(); END IF;
  IF payload->>'state'='ready' THEN payload:=payload||jsonb_build_object('unread',public.get_notification_center_prepared_badge(p_organization)->'unread'); END IF;
 EXCEPTION WHEN lock_not_available THEN payload:=jsonb_build_object('viewSupported',true,'state','preparing','items','[]'::jsonb,'retryAfterMs',1000);
 END;
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_view(bigint,bigint,text,uuid,integer,integer,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_notification_center_view(bigint,bigint,text,uuid,integer,integer,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_prepared_badge(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE payload jsonb;
BEGIN
 BEGIN PERFORM public.notification_center_check_context(p_organization);
 EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('viewSupported',true,'state','denied','enabled',false); END;
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization AND prepared_paused) THEN RETURN jsonb_build_object('viewSupported',true,'enabled',true,'state','preparing','unread',NULL); END IF;
 INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
 INSERT INTO public.notification_center_projection_scopes(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
 -- A single statement provides the current privacy snapshot and all candidates.
 WITH current AS MATERIALIZED(SELECT s.*,u.last_delivery_sequence,greatest(u.seen_through_sequence,u.read_through_sequence) seen,u.view_read_revision,
   public.notification_center_prepared_privacy(p_organization) privacy_now FROM public.notification_center_projection_scopes s
   JOIN public.notification_center_user_state u USING(organization,recipient) WHERE s.organization=p_organization AND s.recipient=auth.uid()),
 status AS(SELECT *,phase<>'ready' OR NOT delivery_initialized OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending
   OR prepared_sequence<>last_delivery_sequence OR applied_read_revision<>view_read_revision OR next_expiry<clock_timestamp() OR privacy<>privacy_now preparing FROM current)
 SELECT jsonb_build_object('viewSupported',true,'timelineSupported',true,'enabled',true,'state',CASE WHEN preparing THEN 'preparing' ELSE 'ready' END,
  'lastSequence',last_delivery_sequence,'unread',CASE WHEN preparing THEN NULL ELSE EXISTS(
   SELECT 1 FROM public.notification_center_prepared_allowed_scopes(p_organization,NULL,auth.uid()) a
   CROSS JOIN LATERAL(SELECT t.id FROM public.notification_center_summary_scopes t WHERE t.organization=p_organization AND t.recipient=auth.uid()
    AND t.scope=a.scope AND NOT t.is_read AND t.sequence>status.seen ORDER BY t.sequence DESC LIMIT 1) t
   WHERE CASE WHEN a.scope ~ '^(orders|app|email-admin|bank-occasion):[0-9]+$' THEN NOT EXISTS(SELECT 1 FROM public.notification_center_preferences p
    WHERE p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=split_part(a.scope,':',2)::bigint AND p.muted)
    ELSE true END) END) INTO payload FROM status;
 IF payload->>'state'='preparing' THEN PERFORM public.notification_center_prepared_wake(); UPDATE public.notification_center_projection_scopes SET requested_at=CASE WHEN work_requested THEN requested_at ELSE clock_timestamp() END,work_requested=true,next_check_at=CASE WHEN retry_count=0 THEN least(next_check_at,clock_timestamp()) ELSE next_check_at END WHERE organization=p_organization AND recipient=auth.uid(); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_prepared_badge(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_notification_center_prepared_badge(bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.notification_center_prepared_scope(p_org bigint,p_scope jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE v public.notification_center_views;r public.notification_center_view_rows; source_revision bigint;read_revision bigint;privacy_key text;
BEGIN
 PERFORM public.notification_center_check_context(p_org);
 IF EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_org AND prepared_paused) THEN RAISE object_not_in_prerequisite_state USING MESSAGE='notification_view_preparing'; END IF;
 SELECT * INTO v FROM public.notification_center_views WHERE token=(p_scope->>'viewToken')::uuid AND organization=p_org AND recipient=auth.uid();
 IF NOT FOUND OR v.expires_at<=clock_timestamp() THEN RAISE object_not_in_prerequisite_state USING MESSAGE='notification_view_expired'; END IF;
 SELECT s.revision,u.view_read_revision,md5(public.notification_center_prepared_privacy(p_org)::text) INTO source_revision,read_revision,privacy_key
  FROM public.notification_center_projection_scopes s JOIN public.notification_center_user_state u USING(organization,recipient) WHERE s.organization=p_org AND s.recipient=auth.uid();
 SELECT * INTO r FROM public.notification_center_view_rows WHERE token=v.token AND id=p_scope->>'id';
 IF NOT FOUND OR r.state='removed' OR r.revision<>source_revision OR r.privacy_key<>privacy_key THEN
  RAISE object_not_in_prerequisite_state USING MESSAGE='notification_view_preparing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_events e WHERE e.id=r.latest_event AND public.notification_center_allowed(e,auth.uid())) THEN
  RAISE insufficient_privilege USING MESSAGE='notification_read_denied'; END IF;
 RETURN jsonb_build_object('id',r.id,'organization',p_org,'snapshot',v.snapshot,'snapshotAt',v.anchor,'timezone',v.timezone,
  'capturedAt',v.anchor,'captureIsRead',r.capture_is_read,'afterSequence',r.after_sequence,'throughSequence',r.through_sequence,'markRead',coalesce((p_scope->>'markRead')::boolean,false),'groupKey',r.group_key,'isRead',r.is_read,'occasion',r.occasion);
END $$;
CREATE OR REPLACE FUNCTION public.mark_notification_center_view_item_read(p_organization bigint,p_scope jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE scope jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 PERFORM 1 FROM public.notification_center_projection_scopes WHERE organization=p_organization AND recipient=auth.uid() FOR SHARE NOWAIT;
 PERFORM 1 FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE NOWAIT;
 scope:=public.notification_center_prepared_scope(p_organization,p_scope);
 IF scope->>'isRead'='true' THEN RETURN true; END IF;
 RETURN public.notification_center_prepared_record_read(p_organization,scope->>'groupKey',(scope->>'afterSequence')::bigint,(scope->>'throughSequence')::bigint,true);
EXCEPTION WHEN lock_not_available THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.mark_notification_center_view_item_read(bigint,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.mark_notification_center_view_item_read(bigint,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_settings(p_organization bigint,p_after bigint DEFAULT 0,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;lim integer:=greatest(1,least(coalesce(p_limit,50),100));
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 WITH rows AS(SELECT oc.id,oc.title,coalesce(p.muted,false) muted,row_number() OVER(ORDER BY oc.id) position FROM public.occasions oc
  LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
  WHERE oc.organization=p_organization AND oc.id>p_after AND NOT public.is_demo_occasion(oc.id)
   AND (public.notification_center_app_admin_internal(p_organization,oc.id,auth.uid()) OR EXISTS(SELECT 1 FROM public.occasion_users m WHERE m.occasion=oc.id AND m."user"=auth.uid() AND m.is_editor_order_view)) ORDER BY oc.id LIMIT lim+1)
 SELECT jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'muted',muted) ORDER BY id) FILTER(WHERE position<=lim),'[]'),
  'nextCursor',CASE WHEN count(*)>lim THEN max(id) FILTER(WHERE position<=lim) END) INTO result FROM rows;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_settings(bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_notification_center_settings(bigint,bigint,integer) TO authenticated;
-- Every helper is private, including default EXECUTE granted by PostgreSQL.
DO $$ DECLARE f regprocedure; BEGIN
 FOR f IN SELECT oid::regprocedure FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'notification_center_prepared_%' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f);
 END LOOP;
END $$;


-- SOURCE: notification_center/prepared_worker.sql
CREATE OR REPLACE FUNCTION public.prepare_notification_center(p_limit integer DEFAULT 500)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
#variable_conflict use_variable
DECLARE s public.notification_center_projection_scopes; personal public.notification_center_user_state;
 e public.notification_center_events; d public.notification_center_deliveries; item record; job record;
 privacy jsonb; keys text[]; maximum uuid; processed integer:=0; n integer; budget integer:=greatest(1,least(coalesce(p_limit,500),100));
 error_code text;deadline timestamptz:=clock_timestamp()+interval '250 milliseconds'; current_at timestamptz; previous_timeout text:=current_setting('lock_timeout');
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 PERFORM set_config('lock_timeout','5ms',true);
 FOR s IN SELECT * FROM public.notification_center_projection_scopes WHERE next_check_at<=clock_timestamp() AND NOT quarantined
  ORDER BY work_requested DESC,next_check_at,organization,recipient LIMIT 8 FOR UPDATE SKIP LOCKED LOOP
  BEGIN
   e:=NULL;
   budget:=greatest(1,least(coalesce(p_limit,500),100)-processed);
   SELECT * INTO personal FROM public.notification_center_user_state WHERE organization=s.organization AND recipient=s.recipient FOR UPDATE SKIP LOCKED;
   IF NOT FOUND THEN
    UPDATE public.notification_center_projection_scopes SET next_check_at=clock_timestamp()+interval '100 milliseconds' WHERE organization=s.organization AND recipient=s.recipient;
    CONTINUE;
   END IF;
   current_at:=clock_timestamp();privacy:=public.notification_center_prepared_privacy(s.organization);
   IF NOT s.delivery_initialized THEN
    SELECT count(*) INTO n FROM public.notification_center_recipients r JOIN public.notification_center_events ev ON ev.id=r.event_id
     WHERE r.recipient=s.recipient AND ev.organization=s.organization AND r.processed_revision<r.eligible_revision;
    UPDATE public.notification_center_projection_scopes SET pending_delivery=n,delivery_initialized=true WHERE organization=s.organization AND recipient=s.recipient;
   END IF;
   IF s.phase IN ('backfill','ready') AND s.phase='backfill' AND s.build_revision<>s.revision THEN
    UPDATE public.notification_center_projection_scopes SET phase='clear_members',build_revision=s.revision WHERE organization=s.organization AND recipient=s.recipient;
    processed:=processed+1;CONTINUE;
   END IF;
   IF s.phase='clear_members' THEN
    DELETE FROM public.notification_center_view_members WHERE (organization,recipient,event_id) IN(
     SELECT organization,recipient,event_id FROM public.notification_center_view_members WHERE organization=s.organization AND recipient=s.recipient ORDER BY event_id LIMIT budget);
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n<budget THEN UPDATE public.notification_center_projection_scopes SET phase='clear_summaries' WHERE organization=s.organization AND recipient=s.recipient; END IF;
    processed:=processed+greatest(n,1);
   ELSIF s.phase='clear_summaries' THEN
    DELETE FROM public.notification_center_batch_summaries WHERE (organization,recipient,id) IN(
     SELECT organization,recipient,id FROM public.notification_center_batch_summaries WHERE organization=s.organization AND recipient=s.recipient ORDER BY id LIMIT budget);
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n<budget THEN
     UPDATE public.notification_center_projection_scopes SET phase='backfill',cursor_sequence=0,prepared_sequence=0,
      build_revision=s.revision,privacy=privacy,pending_events=0,privacy_pending=false,privacy_keys='{}',privacy_cursor=NULL
      WHERE organization=s.organization AND recipient=s.recipient;
    END IF;
    processed:=processed+greatest(n,1);
   ELSIF s.phase='backfill' THEN
    n:=0;
    FOR d IN SELECT * FROM public.notification_center_deliveries WHERE organization=s.organization AND recipient=s.recipient
     AND sequence>s.cursor_sequence ORDER BY sequence LIMIT budget LOOP
     SELECT * INTO e FROM public.notification_center_events WHERE id=d.event_id;
     PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy);
     UPDATE public.notification_center_recipients SET view_applied_revision=e.view_revision,view_required_revision=e.view_revision WHERE event_id=e.id AND recipient=s.recipient;
     s.cursor_sequence:=d.sequence;n:=n+1;
    END LOOP;
    UPDATE public.notification_center_projection_scopes SET cursor_sequence=s.cursor_sequence,prepared_sequence=s.cursor_sequence,
     phase=CASE WHEN s.cursor_sequence>=personal.last_delivery_sequence THEN 'ready' ELSE 'backfill' END,
     applied_read_revision=CASE WHEN pending_groups=0 THEN personal.view_read_revision ELSE applied_read_revision END,
     last_ready_at=CASE WHEN s.cursor_sequence>=personal.last_delivery_sequence THEN clock_timestamp() ELSE last_ready_at END
     WHERE organization=s.organization AND recipient=s.recipient;
    processed:=processed+greatest(n,1);
   ELSE
    -- Hidden identity/email changes are detected from a bounded live subject
    -- snapshot. Every contribution is evaluated against an explicit snapshot,
    -- so a transient hide/unhide cannot contaminate a different generation.
    IF s.privacy<>privacy OR s.privacy_pending THEN
     WITH before_keys AS(SELECT key FROM public.notification_center_prepared_privacy_keys(s.privacy) key),
     after_keys AS(SELECT key FROM public.notification_center_prepared_privacy_keys(privacy) key),
     delta AS(SELECT coalesce(b.key,a.key) key FROM before_keys b FULL JOIN after_keys a USING(key) WHERE b.key IS NULL OR a.key IS NULL)
     SELECT array_agg(DISTINCT key) FILTER(WHERE key IS NOT NULL) INTO keys FROM(
      SELECT unnest(s.privacy_keys) key UNION SELECT key FROM delta) q;
     IF NOT s.privacy_pending OR s.repair_privacy<>privacy THEN s.privacy_cursor:=NULL; END IF;
     n:=0;maximum:=s.privacy_cursor;
     FOR item IN SELECT DISTINCT v.event_id FROM unnest(coalesce(keys,'{}')) key
      CROSS JOIN LATERAL(SELECT event_id FROM public.notification_center_member_subjects m
       WHERE m.organization=s.organization AND m.recipient=s.recipient AND m.subject=key
        AND (s.privacy_cursor IS NULL OR m.event_id>s.privacy_cursor) ORDER BY event_id LIMIT budget) v ORDER BY v.event_id LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id;
      SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=item.event_id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
      IF e.id IS NOT NULL AND d.event_id IS NOT NULL THEN PERFORM public.notification_center_prepared_apply(e,d,current_at,privacy); END IF;
      maximum:=item.event_id;n:=n+1;
     END LOOP;
     UPDATE public.notification_center_projection_scopes SET privacy_pending=n>=budget,
      privacy=CASE WHEN n<budget THEN privacy ELSE notification_center_projection_scopes.privacy END,
      repair_privacy=privacy,privacy_cursor=CASE WHEN n>=budget THEN maximum END,
      privacy_keys=CASE WHEN n>=budget THEN coalesce(keys,'{}') ELSE '{}'::text[] END,
      revision=revision+CASE WHEN NOT s.privacy_pending THEN 1 ELSE 0 END
      WHERE organization=s.organization AND recipient=s.recipient;
     processed:=processed+greatest(n,1);
    ELSIF s.pending_events>0 THEN
     n:=0;
     FOR item IN SELECT r.event_id FROM public.notification_center_recipients r JOIN public.notification_center_events ev ON ev.id=r.event_id
      WHERE r.recipient=s.recipient AND ev.organization=s.organization AND r.view_required_revision>r.view_applied_revision
      ORDER BY r.event_id LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id FOR UPDATE SKIP LOCKED;
      IF NOT FOUND THEN CONTINUE; END IF;
      PERFORM 1 FROM public.notification_center_recipients WHERE event_id=e.id AND recipient=s.recipient FOR UPDATE SKIP LOCKED;
      IF NOT FOUND THEN CONTINUE; END IF;
      SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=e.id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
      IF FOUND THEN PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy); END IF;
      UPDATE public.notification_center_recipients SET view_applied_revision=e.view_revision,view_required_revision=e.view_revision WHERE event_id=e.id AND recipient=s.recipient;
      n:=n+1;
     END LOOP;
     UPDATE public.notification_center_projection_scopes SET pending_events=greatest(0,pending_events-n) WHERE organization=s.organization AND recipient=s.recipient;
     processed:=processed+n;
    ELSIF s.pending_groups>0 THEN
     SELECT * INTO job FROM public.notification_center_group_repairs WHERE organization=s.organization AND recipient=s.recipient ORDER BY group_key LIMIT 1 FOR UPDATE SKIP LOCKED;
     IF FOUND THEN
      n:=0;maximum:=job.cursor;
      FOR item IN SELECT event_id FROM public.notification_center_view_members WHERE organization=s.organization AND recipient=s.recipient AND group_key=job.group_key
       AND (job.cursor IS NULL OR event_id>job.cursor) ORDER BY event_id LIMIT budget LOOP
       SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id;
       SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=item.event_id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
       IF e.id IS NOT NULL AND d.event_id IS NOT NULL THEN PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy); END IF;
       maximum:=item.event_id;n:=n+1;
      END LOOP;
      IF n<budget THEN
       DELETE FROM public.notification_center_group_repairs WHERE organization=s.organization AND recipient=s.recipient AND group_key=job.group_key;
       UPDATE public.notification_center_projection_scopes SET pending_groups=greatest(0,pending_groups-1),
        applied_read_revision=CASE WHEN pending_groups<=1 THEN personal.view_read_revision ELSE applied_read_revision END WHERE organization=s.organization AND recipient=s.recipient;
      ELSE UPDATE public.notification_center_group_repairs SET cursor=maximum WHERE organization=s.organization AND recipient=s.recipient AND group_key=job.group_key; END IF;
      processed:=processed+greatest(n,1);
     END IF;
    ELSIF s.prepared_sequence<personal.last_delivery_sequence THEN
     n:=0;
     FOR d IN SELECT * FROM public.notification_center_deliveries WHERE organization=s.organization AND recipient=s.recipient AND sequence>s.prepared_sequence ORDER BY sequence LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=d.event_id;
      PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy);
      UPDATE public.notification_center_recipients SET view_applied_revision=e.view_revision,view_required_revision=e.view_revision WHERE event_id=e.id AND recipient=s.recipient;
      s.prepared_sequence:=d.sequence;n:=n+1;
     END LOOP;
     UPDATE public.notification_center_projection_scopes SET prepared_sequence=s.prepared_sequence WHERE organization=s.organization AND recipient=s.recipient;
     processed:=processed+greatest(n,1);
    ELSE
     n:=0;
     FOR item IN SELECT event_id FROM public.notification_center_view_members WHERE organization=s.organization AND recipient=s.recipient AND eligible AND expires_at<current_at ORDER BY expires_at,event_id LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id;
      SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=e.id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
      PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy);n:=n+1;
     END LOOP;
     processed:=processed+n;
    END IF;
   END IF;
   SELECT expires_at INTO s.next_expiry FROM public.notification_center_view_members
    WHERE organization=s.organization AND recipient=s.recipient AND eligible AND expires_at IS NOT NULL ORDER BY expires_at,event_id LIMIT 1;
   UPDATE public.notification_center_projection_scopes SET retry_count=0,last_error_code=NULL,failed_event=NULL,
    work_requested=phase<>'ready' OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending OR prepared_sequence<personal.last_delivery_sequence OR coalesce(s.next_expiry<current_at,false),
    next_expiry=s.next_expiry,
    requested_at=CASE WHEN phase<>'ready' OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending OR prepared_sequence<personal.last_delivery_sequence OR coalesce(s.next_expiry<current_at,false)
     THEN coalesce(requested_at,current_at) END,
    next_check_at=CASE WHEN phase<>'ready' OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending OR prepared_sequence<personal.last_delivery_sequence OR coalesce(s.next_expiry<current_at,false)
     THEN clock_timestamp() ELSE coalesce(s.next_expiry,'infinity'::timestamptz) END
    WHERE organization=s.organization AND recipient=s.recipient;
  EXCEPTION WHEN lock_not_available THEN NULL;
   WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code=RETURNED_SQLSTATE;
    UPDATE public.notification_center_projection_scopes SET retry_count=retry_count+1,last_error_code=error_code,failed_event=e.id,
     quarantined=retry_count>=4,next_check_at=clock_timestamp()+make_interval(secs=>least(300,power(2,least(retry_count,8))*(0.9+random()*0.2)))
     WHERE organization=s.organization AND recipient=s.recipient;
    processed:=processed+1;
  END;
  EXIT WHEN processed>=budget OR clock_timestamp()>=deadline;
 END LOOP;
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN processed;
EXCEPTION WHEN lock_not_available THEN
 -- Relation locks (for example concurrent maintenance) can precede row-level
 -- SKIP LOCKED. This entire call rolls back; recovery retries durable work.
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN 0;
END $$;
REVOKE ALL ON FUNCTION public.prepare_notification_center(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_notification_center(integer) TO service_role;
CREATE OR REPLACE FUNCTION public.prepare_notification_center_views(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
#variable_conflict use_variable
DECLARE work record; s public.notification_center_projection_scopes; v public.notification_center_views;
 r public.notification_center_view_rows; e public.notification_center_events; d public.notification_center_deliveries; m public.notification_center_view_members;
 privacy jsonb; privacy_key text; read_rev bigint; last_id uuid; ids uuid[]; b record;
 n integer; processed integer:=0; budget integer:=greatest(1,least(coalesce(p_limit,100),100));
 error_code text;deadline timestamptz:=clock_timestamp()+interval '250 milliseconds'; previous_timeout text:=current_setting('lock_timeout');
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 PERFORM set_config('lock_timeout','5ms',true);
 DELETE FROM public.notification_center_views WHERE token IN(SELECT token FROM public.notification_center_views WHERE expires_at<=clock_timestamp() ORDER BY expires_at LIMIT 100);
 FOR work IN SELECT vr.token,vr.position FROM public.notification_center_view_rows vr JOIN public.notification_center_views vw ON vw.token=vr.token
  JOIN public.notification_center_projection_scopes ps ON ps.organization=vw.organization AND ps.recipient=vw.recipient
  JOIN public.notification_center_user_state us ON us.organization=vw.organization AND us.recipient=vw.recipient
  WHERE vw.expires_at>clock_timestamp() AND (vr.next_attempt_at<=clock_timestamp() OR vr.repair_revision IS DISTINCT FROM ps.revision)
   AND (NOT vr.quarantined OR vr.repair_revision IS DISTINCT FROM ps.revision) AND ps.phase='ready' AND ps.pending_events=0 AND ps.pending_groups=0 AND NOT ps.privacy_pending
   AND (vr.state='preparing' OR vr.revision<>ps.revision OR vr.read_revision<>us.view_read_revision
    OR vr.privacy_key<>md5(public.notification_center_prepared_privacy(vw.organization)::text))
  ORDER BY vw.created_at,vr.position LIMIT 8 FOR UPDATE OF vr SKIP LOCKED LOOP
  BEGIN
   budget:=greatest(1,least(coalesce(p_limit,100),100)-processed);
   SELECT * INTO v FROM public.notification_center_views WHERE token=work.token;
   SELECT * INTO s FROM public.notification_center_projection_scopes WHERE organization=v.organization AND recipient=v.recipient FOR SHARE NOWAIT;
   SELECT * INTO r FROM public.notification_center_view_rows WHERE token=work.token AND position=work.position;
   SELECT view_read_revision INTO read_rev FROM public.notification_center_user_state WHERE organization=v.organization AND recipient=v.recipient;
   privacy:=public.notification_center_prepared_privacy(v.organization);privacy_key:=md5(privacy::text);
   IF r.repair_revision IS DISTINCT FROM s.revision OR r.repair_read_revision IS DISTINCT FROM read_rev OR r.repair_privacy_key IS DISTINCT FROM privacy_key THEN
    r.repair_cursor:=NULL;r.repair_count:=0;r.repair_known:=0;r.repair_places:=0;r.repair_multiple:=0;r.repair_unread:=0;r.repair_previews:='{}';
   END IF;
   n:=0;last_id:=r.repair_cursor;ids:=r.repair_previews;
   FOR m IN SELECT * FROM public.notification_center_view_members WHERE organization=v.organization AND recipient=v.recipient AND group_key=r.group_key
    AND (r.repair_cursor IS NULL OR event_id>r.repair_cursor) ORDER BY event_id LIMIT budget LOOP
    last_id:=m.event_id;n:=n+1;
    SELECT * INTO e FROM public.notification_center_events WHERE id=m.event_id;
    SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=m.event_id AND recipient=v.recipient AND sequence<=v.snapshot ORDER BY sequence DESC LIMIT 1;
    IF e.id IS NULL OR d.event_id IS NULL OR NOT public.notification_center_prepared_scope_member(e,d,r.group_key,r.id,r.after_sequence,r.through_sequence,v.anchor,r.capture_is_read)
     OR NOT public.notification_center_prepared_policy(e,v.anchor,privacy) THEN CONTINUE; END IF;
    SELECT * INTO b FROM public.notification_center_batch_internal(e,d);
    r.repair_count:=r.repair_count+1;r.repair_known:=r.repair_known+(m.places IS NOT NULL)::int;
    r.repair_places:=r.repair_places+coalesce(m.places,0);r.repair_multiple:=r.repair_multiple+m.multiple::int;r.repair_unread:=r.repair_unread+(NOT b.is_read)::int;
    ids:=array_append(ids,e.id);
   END LOOP;
   SELECT coalesce(array_agg(id ORDER BY occurred_at DESC,id DESC),'{}') INTO ids FROM(SELECT DISTINCT ev.id,ev.occurred_at FROM unnest(ids) p(event_id) JOIN public.notification_center_events ev ON ev.id=p.event_id ORDER BY ev.occurred_at DESC,ev.id DESC LIMIT 3) q;
   UPDATE public.notification_center_view_rows SET state=CASE WHEN n>=budget THEN 'preparing' WHEN r.repair_count=0 THEN 'removed' ELSE 'ready' END,
    repair_cursor=CASE WHEN n>=budget THEN last_id END,repair_revision=s.revision,repair_read_revision=read_rev,repair_privacy_key=privacy_key,
    repair_count=r.repair_count,repair_known=r.repair_known,repair_places=r.repair_places,repair_multiple=r.repair_multiple,repair_unread=r.repair_unread,repair_previews=ids,
    revision=CASE WHEN n<budget THEN s.revision ELSE revision END,read_revision=CASE WHEN n<budget THEN read_rev ELSE read_revision END,
    privacy_key=CASE WHEN n<budget THEN privacy_key ELSE notification_center_view_rows.privacy_key END,
    activity_count=CASE WHEN n<budget THEN r.repair_count ELSE activity_count END,known_count=CASE WHEN n<budget THEN r.repair_known ELSE known_count END,
    places=CASE WHEN n<budget THEN r.repair_places ELSE places END,multiple_count=CASE WHEN n<budget THEN r.repair_multiple ELSE multiple_count END,
    is_read=CASE WHEN n<budget THEN r.repair_unread=0 ELSE is_read END,
    latest_event=CASE WHEN n<budget THEN ids[1] ELSE latest_event END,preview_events=CASE WHEN n<budget THEN ids ELSE preview_events END
    WHERE token=r.token AND position=r.position;
   processed:=processed+greatest(n,1);
  EXCEPTION WHEN lock_not_available THEN NULL;
   WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code=RETURNED_SQLSTATE;
    UPDATE public.notification_center_view_rows SET state='preparing',retry_count=retry_count+1,last_error_code=error_code,
     repair_revision=s.revision,repair_read_revision=read_rev,repair_privacy_key=privacy_key,repair_cursor=NULL,
     repair_count=0,repair_known=0,repair_places=0,repair_multiple=0,repair_unread=0,repair_previews='{}',
     quarantined=retry_count>=4,next_attempt_at=clock_timestamp()+make_interval(secs=>least(300,power(2,least(retry_count,8))*(0.9+random()*0.2)))
     WHERE token=work.token AND position=work.position;
    processed:=processed+1;
  END;
  EXIT WHEN processed>=budget OR clock_timestamp()>=deadline;
 END LOOP;
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN processed;
EXCEPTION WHEN lock_not_available THEN
 -- Relation locks (for example concurrent maintenance) can precede row-level
 -- SKIP LOCKED. This entire call rolls back; recovery retries durable work.
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN 0;
END $$;
REVOKE ALL ON FUNCTION public.prepare_notification_center_views(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_notification_center_views(integer) TO service_role;


-- SOURCE: notification_center/orders.sql
CREATE OR REPLACE FUNCTION public.notification_center_order_internal(p_order bigint,p_kind text,p_transition text,p_actor uuid DEFAULT auth.uid(),p_extra jsonb DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; org bigint; event uuid; ticket_count bigint; form_context jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF NOT FOUND OR o.state='stock' THEN RETURN; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 SELECT count(DISTINCT ticket) INTO ticket_count FROM eshop.order_product_ticket WHERE "order"=o.id;
 form_context:=public.notification_center_order_form_context_internal(o.form);
 event:=public.notification_center_publish_internal(org,o.occasion,p_kind,p_kind||':'||p_order||':'||p_transition,
 jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'state',o.state,'formContext',form_context,'count',ticket_count)||p_extra,p_actor);
 UPDATE public.notification_center_events SET status=o.state WHERE id=event;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_state_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.notification_center_events e JOIN eshop.orders o ON o.occasion=e.occasion
  WHERE o.id=p_order AND e.data->>'orderId'=p_order::text AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted') AND (e.status='storno') IS DISTINCT FROM (o.state='storno')) OR EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 JOIN public.email_messages m ON m.order_id=o.id AND m.occasion=o.occasion AND m.organization=oc.organization
 JOIN public.notification_center_events e ON e.organization=m.organization AND e.source_key='email:'||m.message_id AND e.kind='email_problem'
 WHERE o.id=p_order AND o.state='storno' AND m.message_kind<>'order_storno' AND e.status NOT IN ('recovered','resolved')) THEN
  PERFORM public.notification_center_prepared_invalidate_order(p_order);
 END IF;
 UPDATE public.notification_center_events e SET status=o.state,data=e.data||jsonb_build_object('state',o.state)
 FROM eshop.orders o WHERE o.id=p_order AND e.data->>'orderId'=p_order::text
 AND e.occasion=o.occasion AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted');
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_internal(bigint,text,text,uuid,jsonb),public.notification_center_order_state_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/email.sql
CREATE OR REPLACE FUNCTION public.notification_center_email_internal(p_message uuid,p_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; a public.notification_center_organizations; old public.notification_center_source_state;
 reason text; fact_at timestamptz; ev uuid; seen jsonb; key text:='email:'||p_message; due_at timestamptz;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF NOT FOUND THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||m.organization,0));
 p_at:=coalesce(p_at,clock_timestamp());
 SELECT * INTO a FROM public.notification_center_organizations WHERE organization=m.organization FOR SHARE;
 IF NOT FOUND THEN RETURN; END IF;
 -- Cancellation retires recovery of the original order messages. Provider
 -- callbacks can arrive later; preserve their audit facts without re-alerting.
 -- A failed cancellation notice is a separate, still relevant incident.
 IF m.order_id IS NOT NULL AND m.message_kind<>'order_storno' AND EXISTS(
  SELECT 1 FROM eshop.orders o WHERE o.id=m.order_id AND o.occasion=m.occasion AND o.state='storno') THEN
  PERFORM public.notification_center_prepared_invalidate(ev.id) FROM public.notification_center_events ev WHERE ev.organization=m.organization AND ev.source_key=key AND ev.status<>'recovered';
  UPDATE public.notification_center_events SET status='recovered'
   WHERE organization=m.organization AND source_key=key AND kind='email_problem';
  RETURN;
 END IF;
 reason:=public.email_reporting_state(m);
 -- A failed preparation/send is an incident now, even while the queue retries.
 -- Reserve the grace period for ordinary waiting and brief rate limiting.
 IF reason IN ('retry_wait','unknown') AND nullif(m.last_error,'') IS NOT NULL
    AND m.last_error<>'throttled' AND (m.expires_at IS NULL OR m.expires_at>p_at) THEN
  reason:=CASE WHEN m.last_error='preparation_failed' THEN 'rendering_failure' ELSE 'delayed' END;
 END IF;
 SELECT * INTO old FROM public.notification_center_source_state WHERE organization=m.organization AND source_key=key FOR UPDATE;
 due_at:=coalesce((old.state->>'dueAt')::timestamptz,m.target_time);
 IF reason IN ('unknown','retry_wait','pending','preparing','delay') THEN
  IF m.expires_at<=p_at OR m.workflow_state IN ('cancelled','expired') THEN reason:=NULL;
  ELSIF p_at<due_at+interval '30 minutes' AND NOT coalesce((m.message_kind='waitlist_offer' AND m.expires_at<=p_at+interval '5 minutes'),false) THEN reason:=NULL;
  ELSE reason:='delayed'; END IF;
 END IF;
 IF reason='suppressed' AND EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(m.recipient) AND created_at<m.created_at) THEN reason:=NULL; END IF;
 IF reason NOT IN ('complaint','bounce','reject','rendering_failure','dead','suppressed','delayed','post_action_failed') THEN reason:=NULL; END IF;
 fact_at:=CASE reason WHEN 'complaint' THEN m.complained_at WHEN 'bounce' THEN m.bounced_at
 WHEN 'reject' THEN (SELECT min(provider_time) FROM public.email_delivery_events WHERE message_id=m.message_id AND event_type='reject')
 WHEN 'rendering_failure' THEN (SELECT min(provider_time) FROM public.email_delivery_events WHERE message_id=m.message_id AND event_type='rendering_failure')
 WHEN 'delayed' THEN least(p_at,due_at+interval '30 minutes') ELSE p_at END;
 seen:=coalesce(old.state->'seen','[]');
 IF reason IS NOT NULL AND coalesce(fact_at,p_at)>=a.initialized_at AND NOT seen ? reason THEN
  ev:=public.notification_center_publish_internal(m.organization,m.occasion,'email_problem',key,
    jsonb_build_object('messageId',m.message_id,'messageKind',m.message_kind,'reason',reason),NULL,coalesce(fact_at,p_at));
  IF ev IS NOT NULL AND old.state->>'eventId'=ev::text THEN
   PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
   UPDATE public.notification_center_events SET attention_revision=attention_revision+1,status='active',
    data=data||jsonb_build_object('reason',reason) WHERE id=(old.state->>'eventId')::uuid;
   PERFORM public.notification_center_capture_recipients_internal((old.state->>'eventId')::uuid,NULL);
  END IF;
  seen:=seen||jsonb_build_array(reason);
 ELSIF reason IS NULL AND old.state->>'eventId' IS NOT NULL AND public.email_reporting_state(m) IN ('delivery','open','click','accepted') THEN
  PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
  UPDATE public.notification_center_events SET status='recovered' WHERE id=(old.state->>'eventId')::uuid;
 END IF;
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 VALUES(m.organization,key,jsonb_build_object('reason',reason,'seen',seen,'dueAt',due_at,'eventId',coalesce(ev::text,old.state->>'eventId')))
 ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=p_at;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_email_internal(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/bank.sql
CREATE OR REPLACE FUNCTION public.claim_notification_center_bank_health(p_limit integer DEFAULT 20) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_require_service();
 INSERT INTO public.notification_center_bank_health(connection_id)
 SELECT DISTINCT c.id FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts uba ON uba.bank_account=c.bank_account_id OR uba.bank_account IN
 (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 JOIN public.units u ON u.id=uba.unit JOIN public.notification_center_organizations a ON a.organization=u.organization
 WHERE c.mode='api' AND c.state IN ('connected','degraded') ON CONFLICT DO NOTHING;
 -- A newly connected source starts against the activation boundary, not its first failed refresh.
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 SELECT DISTINCT a.organization,'bank:'||c.id,jsonb_build_object('problem',c.created_at<a.initialized_at AND
  (c.last_error IS NOT NULL OR coalesce(c.bank_pull_at,c.created_at)<a.initialized_at-interval '30 minutes'))
 FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts uba ON uba.bank_account=c.bank_account_id OR uba.bank_account IN
  (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 JOIN public.units u ON u.id=uba.unit JOIN public.notification_center_organizations a ON a.organization=u.organization
 WHERE c.mode='api' AND c.state IN ('connected','degraded') ON CONFLICT DO NOTHING;
 WITH selected AS (SELECT h.connection_id FROM public.notification_center_bank_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
 WHERE h.next_at<=clock_timestamp() AND (h.lease_until IS NULL OR h.lease_until<clock_timestamp()) AND c.mode='api' AND c.state IN ('connected','degraded')
 AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
 JOIN public.notification_center_organizations a ON a.organization=u.organization WHERE uba.bank_account=c.bank_account_id
 OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))
 ORDER BY h.next_at,h.connection_id LIMIT greatest(1,least(p_limit,20)) FOR UPDATE OF h SKIP LOCKED), claimed AS (
 UPDATE public.notification_center_bank_health h SET lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes'
 FROM selected s WHERE s.connection_id=h.connection_id RETURNING h.*)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',h.connection_id,'token',h.lease_token,'remoteId',c.remote_bank_account_id)),'[]') INTO result
 FROM claimed h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.complete_notification_center_bank_health(p_connection bigint,p_token uuid,p_success_at timestamptz,p_reason text,p_at timestamptz DEFAULT clock_timestamp())
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE h public.notification_center_bank_health; c eshop.bank_sync_connections; scope record; old public.notification_center_source_state;
 nc_reason text; key text:='bank:'||p_connection; ev uuid; ep bigint; affected bigint[];
BEGIN
 PERFORM public.notification_center_require_service();
 SELECT * INTO h FROM public.notification_center_bank_health WHERE connection_id=p_connection AND lease_token=p_token AND lease_until>clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'notification_health_lease_lost'; END IF;
 SELECT * INTO STRICT c FROM eshop.bank_sync_connections WHERE id=p_connection;
 IF p_reason NOT IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch','bank_sync_retry_required','transport_unavailable') AND p_reason IS NOT NULL THEN RAISE EXCEPTION 'notification_health_reason_invalid'; END IF;
 nc_reason:=p_reason;
 IF c.state='suspended' THEN nc_reason:=NULL;
 ELSIF nc_reason IS NULL AND coalesce(p_success_at,h.last_success,c.bank_pull_at,c.created_at)<p_at-interval '30 minutes' THEN nc_reason:='stale_health'; END IF;
 h.failures:=CASE WHEN nc_reason IS NULL THEN 0 ELSE h.failures+1 END;
 h.failure_since:=CASE WHEN nc_reason IS NULL THEN NULL ELSE coalesce(h.failure_since,p_at) END;
 UPDATE public.notification_center_bank_health SET failures=h.failures,failure_since=h.failure_since,reason=nc_reason,last_success=greatest(last_success,p_success_at),
 lease_token=NULL,lease_until=NULL,next_at=p_at+CASE WHEN p_reason='transport_unavailable' THEN interval '10 minutes' ELSE interval '5 minutes' END WHERE connection_id=p_connection;
 FOR scope IN SELECT DISTINCT u.organization FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
 JOIN public.notification_center_organizations a ON a.organization=u.organization
 WHERE uba.bank_account=c.bank_account_id OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id) LOOP
  PERFORM 1 FROM public.notification_center_organizations WHERE organization=scope.organization FOR SHARE;
  SELECT array_agg(DISTINCT f.occasion) INTO affected FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion
  WHERE oc.organization=scope.organization AND (f.bank_account=c.bank_account_id OR f.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.form=f.id AND (pi.bank_account=c.bank_account_id OR pi.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))));
  SELECT * INTO old FROM public.notification_center_source_state WHERE organization=scope.organization AND source_key=key FOR UPDATE;
  IF NOT FOUND THEN
   INSERT INTO public.notification_center_source_state(organization,source_key,state) VALUES(scope.organization,key,jsonb_build_object('problem',nc_reason IS NOT NULL,'reason',nc_reason));
   CONTINUE;
  END IF;
  ep:=old.episode;
  IF nc_reason IS NOT NULL AND (nc_reason='fio_token_invalid_or_inactive' OR (h.failures>=2 AND h.failure_since<=p_at-interval '15 minutes')) THEN
   IF NOT coalesce((old.state->>'problem')::boolean,false) THEN
    PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
    ep:=ep+1;
    ev:=public.notification_center_publish_internal(scope.organization,NULL,'bank_problem',key||':episode:'||ep,
     jsonb_build_object('reason',nc_reason,'bankConnectionId',c.id),NULL,p_at,coalesce(affected,'{}'));
    old.state:=jsonb_build_object('problem',true,'reason',nc_reason,'eventId',ev);
   ELSE
    -- New confirmed evidence refines the same episode. A transport timeout does
    -- not erase a previously confirmed token/account failure before recovery.
    IF old.state->>'reason' IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch')
     AND nc_reason IN ('transport_unavailable','bank_sync_retry_required','stale_health') THEN nc_reason:=old.state->>'reason'; END IF;
    UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',nc_reason) WHERE id=(old.state->>'eventId')::uuid;
    old.state:=old.state||jsonb_build_object('reason',nc_reason);
   END IF;
  ELSIF nc_reason IS NULL AND p_success_at IS NOT NULL AND (old.observed_at<p_success_at OR NOT coalesce((old.state->>'problem')::boolean,false)) THEN
   PERFORM public.notification_center_prepared_invalidate((old.state->>'eventId')::uuid);
   UPDATE public.notification_center_events SET status='recovered' WHERE id=(old.state->>'eventId')::uuid;
   old.state:=old.state||jsonb_build_object('problem',false,'reason',NULL);
  END IF;
  UPDATE public.notification_center_source_state SET state=old.state,episode=ep,observed_at=p_at WHERE organization=scope.organization AND source_key=key;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.claim_notification_center_bank_health(integer),public.complete_notification_center_bank_health(bigint,uuid,timestamptz,text,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_center_bank_health(integer),public.complete_notification_center_bank_health(bigint,uuid,timestamptz,text,timestamptz) TO service_role;


-- SOURCE: notification_center/capacity.sql
CREATE OR REPLACE FUNCTION public.notification_center_initialized_internal(p_org bigint) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||p_org,0));
 RETURN EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_org);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_initialized_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
-- Runs under the existing form/product/inventory locks, never takes a recipient lock.
CREATE OR REPLACE FUNCTION public.notification_center_capacity_transition_internal(p_org bigint,p_occ bigint,p_key text,p_snapshot jsonb,p_actor uuid DEFAULT auth.uid(),p_cause uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE old public.notification_center_source_state; nc_episode bigint; next_state jsonb; crossing text; high boolean; remaining bigint; lim bigint; used bigint; event uuid;
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-organization:'||p_org,0));
 PERFORM 1 FROM public.notification_center_organizations WHERE organization=p_org FOR SHARE;
 IF NOT FOUND THEN RETURN; END IF;
 lim:=(p_snapshot->>'limit')::bigint; remaining:=(p_snapshot->>'remainingPublic')::bigint;
 IF lim IS NULL OR lim<=0 THEN
  SELECT * INTO old FROM public.notification_center_source_state WHERE organization=p_org AND source_key=p_key FOR UPDATE;
  IF FOUND THEN UPDATE public.notification_center_events SET status='recovered',data=data||p_snapshot WHERE organization=p_org AND source_key=p_key||':episode:'||old.episode; END IF;
  INSERT INTO public.notification_center_source_state(organization,source_key,state) VALUES(p_org,p_key,p_snapshot||jsonb_build_object('high',false))
  ON CONFLICT(organization,source_key) DO UPDATE SET state=excluded.state,observed_at=clock_timestamp();
  RETURN;
 END IF;
 used:=lim-coalesce(remaining,0);
 SELECT * INTO old FROM public.notification_center_source_state WHERE organization=p_org AND source_key=p_key FOR UPDATE;
 high:=CASE WHEN used::numeric/lim<0.85 THEN false WHEN used::numeric/lim>=0.9 THEN true ELSE coalesce((old.state->>'high')::boolean,false) END;
 next_state:=p_snapshot||jsonb_build_object('high',high);
 IF NOT FOUND THEN
  INSERT INTO public.notification_center_source_state(organization,source_key,state,episode,observed_at) VALUES(p_org,p_key,next_state,0,clock_timestamp()) ON CONFLICT DO NOTHING;
  RETURN;
 END IF;
 crossing:=CASE WHEN remaining=0 AND (coalesce((old.state->>'limit')::bigint,0)<=0 OR coalesce((old.state->>'remainingPublic')::bigint,1)>0) THEN 'capacity_full'
 WHEN remaining>0 AND (old.state->>'remainingPublic')::bigint=0 THEN 'capacity_reopened'
 WHEN high AND NOT coalesce((old.state->>'high')::boolean,false) THEN 'capacity_warning' END;
 IF NOT high AND coalesce((old.state->>'high')::boolean,false) THEN
  UPDATE public.notification_center_events SET status='recovered',data=data||next_state WHERE organization=p_org AND source_key=p_key||':episode:'||old.episode;
 END IF;
 nc_episode:=old.episode;
 IF crossing IS NOT NULL THEN
  -- Full/reopen is one episode. Reopen updates it without another unread event.
  IF crossing='capacity_reopened' THEN
   UPDATE public.notification_center_events SET status='recovered',data=data||next_state WHERE organization=p_org AND source_key=p_key||':episode:'||nc_episode;
  ELSIF crossing='capacity_full' AND old.state->>'episodeEvent' IS NOT NULL THEN
   PERFORM public.notification_center_prepared_invalidate((old.state->>'episodeEvent')::uuid);
   UPDATE public.notification_center_events SET kind='capacity_full',data=data||next_state,status='active',attention_revision=attention_revision+CASE WHEN created_xid=pg_current_xact_id() THEN 0 ELSE 1 END
    WHERE id=(old.state->>'episodeEvent')::uuid RETURNING id INTO event;
   IF event IS NOT NULL THEN PERFORM public.notification_center_capture_recipients_internal(event,p_actor);
   ELSE
    nc_episode:=nc_episode+1;
    event:=public.notification_center_publish_internal(p_org,p_occ,crossing,p_key||':episode:'||nc_episode,next_state,p_actor);
   END IF;
  ELSE
   nc_episode:=nc_episode+1;
   IF p_cause IS NULL THEN
    event:=public.notification_center_publish_internal(p_org,p_occ,crossing,p_key||':episode:'||nc_episode,next_state,p_actor);
   ELSE
    UPDATE public.notification_center_events SET data=data||jsonb_build_object('capacity',next_state) WHERE id=p_cause;
   END IF;
  END IF;
 END IF;
 IF p_cause IS NOT NULL AND crossing IS NOT NULL THEN UPDATE public.notification_center_events SET data=data||jsonb_build_object('capacity',next_state) WHERE id=p_cause; END IF;
 next_state:=next_state||jsonb_build_object('episodeEvent',coalesce(event::text,CASE WHEN remaining=0 OR high THEN old.state->>'episodeEvent' END));
 UPDATE public.notification_center_source_state SET state=next_state,episode=nc_episode,observed_at=clock_timestamp() WHERE organization=p_org AND source_key=p_key;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_form_capacity_internal(p_form bigint,p_actor uuid DEFAULT auth.uid(),p_cause uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; org bigint;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 SELECT organization INTO org FROM public.occasions WHERE id=f.occasion;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 PERFORM public.notification_center_capacity_transition_internal(org,f.occasion,'form:'||f.id,
 public.get_form_capacity_snapshot_internal(f.id)||jsonb_build_object('formId',f.id,'title',f.title),p_actor,p_cause);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_product_capacity_internal(p_product bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE p eshop.products; org bigint; used bigint;
BEGIN
 SELECT * INTO p FROM eshop.products WHERE id=p_product;
 SELECT organization INTO org FROM public.occasions WHERE id=p.occasion;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 -- The product materializer's canonical maximum counts the committed product links.
 SELECT count(*) INTO used FROM eshop.order_product_ticket WHERE product=p.id;
 PERFORM public.notification_center_capacity_transition_internal(org,p.occasion,'product:'||p.id,
 jsonb_build_object('productId',p.id,'title',p.title,'limit',p.maximum,'remainingPublic',greatest(p.maximum-used,0)),p_actor);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_capacity_transition_internal(bigint,bigint,text,jsonb,uuid,uuid),
 public.notification_center_form_capacity_internal(bigint,uuid,uuid),public.notification_center_product_capacity_internal(bigint,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_inventory_capacity_internal(p_context bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ctx public.inventory_contexts; pool public.inventory_pools; org bigint; lim bigint; occupied bigint;
BEGIN
 SELECT * INTO ctx FROM public.inventory_contexts WHERE id=p_context;
 SELECT * INTO pool FROM public.inventory_pools WHERE id=ctx.inventory_pool;
 SELECT organization INTO org FROM public.occasions WHERE id=pool.occasion;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 SELECT least(count(*),coalesce(pool.sellable_capacity,count(*))),count(*) FILTER(WHERE order_product_ticket IS NOT NULL)
 INTO lim,occupied FROM eshop.spots WHERE inventory_context=ctx.id;
 -- Same physical/commercial limits as apply_allocations. Temporary buyer holds are deliberately excluded.
 PERFORM public.notification_center_capacity_transition_internal(org,pool.occasion,'inventory:'||ctx.id,
 jsonb_build_object('inventoryContextId',ctx.id,'title',pool.title,'limit',lim,'remainingPublic',greatest(lim-occupied,0)),p_actor);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_blueprint_capacity_internal(p_blueprint bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE bp eshop.blueprints; lim bigint; occupied bigint;
BEGIN
 SELECT * INTO bp FROM eshop.blueprints WHERE id=p_blueprint;
 IF NOT public.notification_center_initialized_internal(bp.organization) THEN RETURN; END IF;
 SELECT count(*),count(*) FILTER(WHERE s.order_product_ticket IS NOT NULL) INTO lim,occupied
 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
 WHERE sb.blueprint=bp.id AND s.blueprint=bp.id AND s.occasion=bp.occasion AND NOT sb.blocked;
 PERFORM public.notification_center_capacity_transition_internal(bp.organization,bp.occasion,'blueprint:'||bp.id,
 jsonb_build_object('blueprintId',bp.id,'title',bp.title,'limit',lim,'remainingPublic',greatest(lim-occupied,0)),p_actor);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_capacity_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE item record; bp bigint; org bigint;
BEGIN
 SELECT oc.organization INTO org FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
 IF NOT public.notification_center_initialized_internal(org) THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.notification_center_events WHERE data->>'orderId'=p_order::text AND (data->>'count' IS NULL OR data->>'formContext' IS NULL)) THEN
  PERFORM public.notification_center_prepared_invalidate_order(p_order);
 END IF;
 PERFORM public.notification_center_form_capacity_internal((SELECT form FROM eshop.orders WHERE id=p_order));
 FOR item IN SELECT DISTINCT product FROM eshop.order_product_ticket WHERE "order"=p_order AND product IS NOT NULL LOOP
  PERFORM public.notification_center_product_capacity_internal(item.product);
 END LOOP;
 FOR item IN SELECT DISTINCT s.inventory_context FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
 WHERE x."order"=p_order AND s.inventory_context IS NOT NULL LOOP
  PERFORM public.notification_center_inventory_capacity_internal(item.inventory_context);
 END LOOP;
 SELECT f.blueprint INTO bp FROM public.forms f JOIN eshop.orders o ON o.form=f.id WHERE o.id=p_order;
 IF bp IS NOT NULL THEN PERFORM public.notification_center_blueprint_capacity_internal(bp); END IF;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_inventory_capacity_internal(bigint,uuid),public.notification_center_blueprint_capacity_internal(bigint,uuid),
 public.notification_center_order_capacity_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: notification_center/deleted_entities.sql
-- Explicit operator repair for historical hard deletions. No domain rows change.
CREATE OR REPLACE FUNCTION public.notification_center_purge_deleted_internal(p_organization bigint)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE removed integer; event_ids uuid[];
BEGIN
 PERFORM public.notification_center_require_service();
 IF p_organization IS NULL OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization) THEN
  RAISE EXCEPTION 'notification_organization_required';
 END IF;
 SELECT array_agg(e.id) INTO event_ids FROM public.notification_center_events e
 WHERE e.organization=p_organization AND (
  (e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted')
   AND e.data->>'orderId' IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    WHERE o.id::text=e.data->>'orderId' AND o.occasion=e.occasion AND oc.organization=e.organization))
  OR (e.kind='occasion_joined' AND e.data->>'userId' IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion
    WHERE ou."user"::text=e.data->>'userId' AND ou.occasion=e.occasion AND oc.organization=e.organization))
  OR (e.kind='email_problem' AND e.data->>'messageId' IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM public.email_messages m
    WHERE m.message_id::text=e.data->>'messageId' AND m.organization=e.organization))
 );
 PERFORM public.notification_center_prepared_delete_events(event_ids);
 DELETE FROM public.notification_center_events WHERE id=ANY(event_ids);
 GET DIAGNOSTICS removed=ROW_COUNT;
 DELETE FROM public.notification_center_source_state s
 WHERE s.organization=p_organization AND s.source_key LIKE 'email:%'
 AND NOT EXISTS(SELECT 1 FROM public.email_messages m
  WHERE m.organization=s.organization AND s.source_key='email:'||m.message_id);
 RETURN removed;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_purge_deleted_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: eshop_orders/repair_order_email_client_sync_v1.sql
-- Shared recipient validation. Preserve aliases and local-part spelling.
CREATE OR REPLACE FUNCTION public.normalize_order_email_contact(p_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,extensions AS $$
DECLARE v_email text:=btrim(p_email);
BEGIN
 IF NOT public.email_address_is_valid(v_email) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 RETURN v_email;
END $$;
REVOKE ALL ON FUNCTION public.normalize_order_email_contact(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_order_email_contact(text) TO service_role;

-- A read token over the existing payment facts, not a stored/global version.
CREATE OR REPLACE FUNCTION public.order_email_payment_fingerprint(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(jsonb_build_array(o.payment_info,p.payment_method,p.amount,p.paid,p.returned,
  p.currency_code,p.deadline,p.deposit_amount,p.deposit_deadline,p.variable_symbol,p.creditor_reference,
  p.bank_account,b.account_number,b.account_number_human_readable,b.creditor_name)::text,'sha256'),'hex')
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.order_email_payment_fingerprint(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_payment_fingerprint(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.repair_order_email_client_sync_v1(
 p_order bigint,p_expected_email text,p_expected_state text,p_expected_payment_version bigint,
 p_email text,p_source_message uuid,p_resend boolean,p_command_id uuid,p_expected_payment_fingerprint text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; src public.email_messages; active public.email_messages;
 v_begin jsonb; v_hash text; v_email text; v_form bigint; v_field bigint; v_fields jsonb;
 v_kind text; v_intent jsonb; v_users uuid[]; v_payload jsonb; v_details jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO oc FROM public.occasions WHERE id=o.occasion;
 IF auth.uid() IS NULL OR o.id IS NULL OR NOT coalesce(public.can_write_orders(o.occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 -- Re-authorize the object relationship even on receipt replay.
 IF p_source_message IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.email_messages m
  WHERE m.message_id=p_source_message AND m.order_id=o.id AND m.occasion=o.occasion
   AND m.organization=oc.organization AND public.email_report_allowed(m.organization,m.occasion,m.recipient_user)) THEN
  RAISE insufficient_privilege USING MESSAGE='order email unavailable'; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('order',p_order,'expectedEmail',p_expected_email,
  'expectedState',p_expected_state,'expectedVersion',p_expected_payment_version,'email',p_email,
  'source',p_source_message,'resend',p_resend,'paymentFingerprint',p_expected_payment_fingerprint)::text,'sha256'),'hex');
 v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.order.repair_email',o.occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
 v_form:=o.form;
 -- Same form -> order -> message order as response editing / send fencing.
 IF v_form IS NOT NULL THEN PERFORM 1 FROM public.forms WHERE id=v_form FOR SHARE; END IF;
 SELECT * INTO o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF o.id IS NULL OR o.form IS DISTINCT FROM v_form OR o.data->>'email' IS DISTINCT FROM p_expected_email
  OR o.state IS DISTINCT FROM p_expected_state OR o.email_payment_version IS DISTINCT FROM p_expected_payment_version
  OR p_expected_payment_fingerprint IS DISTINCT FROM public.order_email_payment_fingerprint(o.id) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','order_changed')); END IF;
 PERFORM public.check_occasion_writable(o.occasion);
 IF o.state NOT IN ('ordered','paid','sent') THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF p_resend IS NULL OR p_email IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 v_email:=public.normalize_order_email_contact(p_email);
 v_kind:=public.order_checkout_email_kind_internal(o.id);
 PERFORM 1 FROM public.email_messages WHERE order_id=o.id ORDER BY id FOR UPDATE;
 SELECT * INTO src FROM public.email_messages WHERE message_id=p_source_message;
 IF p_resend AND src.id IS NOT NULL AND (src.message_kind<>v_kind OR src.last_error='post_action_failed') THEN
  RAISE EXCEPTION 'source_not_resendable'; END IF;
 -- An issued permit or unknown outcome cannot be bypassed by changing contact.
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=o.id AND message_kind IN ('order_confirmation','order_tickets')
  AND workflow_state IN ('sending','unknown')) THEN RAISE EXCEPTION 'email_outcome_unresolved'; END IF;
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_email)) THEN
  RAISE EXCEPTION 'email_recipient_suppressed'; END IF;
 IF p_resend THEN
  SELECT * INTO active FROM public.email_messages WHERE order_id=o.id AND message_kind=v_kind
   AND workflow_state IN ('pending','preparing','retry_wait','blocked')
   AND recipient=o.data->>'email' AND source_version=o.email_payment_version
   AND (expires_at IS NULL OR expires_at>now())
   ORDER BY id DESC LIMIT 1;
  IF active.id IS NOT NULL THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
    jsonb_build_object('reason','active_email_intent','messageId',active.message_id)); END IF;
 END IF;
 -- Repair chains have one successor per source. A stale source cannot fork
 -- around a newer failed/waiting attempt, even after its active lease ended.
 IF p_resend AND src.id IS NOT NULL AND EXISTS(SELECT 1 FROM public.email_messages
  WHERE order_id=o.id AND data->>'repair_source_message_id'=src.message_id::text) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
   jsonb_build_object('reason','source_replaced')); END IF;
 -- Update only the existing contact projection, without invoking pricing/stock.
 SELECT min(id) INTO v_field FROM public.form_fields WHERE form=v_form AND type='email';
 IF (SELECT count(*) FROM public.form_fields WHERE form=v_form AND type='email')>1 THEN
  RAISE EXCEPTION 'ambiguous_contact_field'; END IF;
 IF v_field IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(e - v_field::text) FILTER (WHERE e - v_field::text<>'{}'::jsonb),'[]') INTO v_fields
   FROM jsonb_array_elements(coalesce(o.data->'fields','[]')) e;
  o.data:=jsonb_set(o.data,'{fields}',v_fields||jsonb_build_array(jsonb_build_object(v_field::text,v_email)));
 END IF;
 UPDATE eshop.orders SET data=jsonb_set(o.data,'{email}',to_jsonb(v_email)),updated_at=now()
  WHERE id=o.id RETURNING * INTO o;
 PERFORM public.notification_center_prepared_invalidate_order(o.id);
 INSERT INTO eshop.orders_history("order",state,price,currency_code,data,created_by)
  VALUES(o.id,o.state,o.price,o.currency_code,o.data,auth.uid());
 -- A prepared payload is a snapshot of its recipient; retire pre-permit old
 -- contacts explicitly, including legacy manual ticket snapshots.
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='contact_changed',lease_token=NULL,lease_until=NULL
  WHERE order_id=o.id AND recipient IS DISTINCT FROM v_email
   AND workflow_state IN ('pending','preparing','retry_wait','blocked');
 IF p_resend THEN
  v_payload:=jsonb_build_object('order_id',o.id,'requested_by',auth.uid(),'repair_source_message_id',p_source_message,'repair_payment_fingerprint',p_expected_payment_fingerprint);
  IF v_kind='order_confirmation' THEN
   -- The existing confirmation renderer consumes the canonical checkout shape,
   -- not an order ID. Rebuild it from current facts without a checkout mutation.
   v_details:=public.get_order_details_for_email(o.id)->'data';
   -- Each explicit resend owns its command identity. Reusing the checkout
   -- command collides with the unique confirmation-command index.
   v_payload:=v_payload||jsonb_build_object('command_id',p_command_id,
    'ticket_order',jsonb_build_object('order',v_details->'order'||jsonb_build_object(
     'occasion',v_details->'occasion','reply_to',v_details->'reply_to',
     'form',jsonb_build_object('id',o.form,'data',v_details->'form_data'),
     'payment_info',coalesce(v_details->'payment_info','{}')||jsonb_build_object(
      'account_number',v_details#>'{bank_account,account_number}',
      'account_number_human_readable',v_details#>'{bank_account,account_number_human_readable}',
      'creditor_name',v_details#>'{bank_account,creditor_name}'))));
  END IF;
  v_intent:=public.enqueue_order_email(CASE v_kind WHEN 'order_confirmation' THEN 'TICKET_ORDER_CONFIRMATION' ELSE 'ORDER_TICKETS' END,
   v_payload,
   oc.organization,oc.id,oc.unit,now(),'repair:'||p_command_id);
  IF v_intent->>'message_id' IS NULL OR coalesce((v_intent->>'replayed')::boolean,false) THEN
   RAISE EXCEPTION 'email_enqueue_rejected'; END IF;
 END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'inventory.order.repair_email',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
    'safeLabel','Order contact','changedFields',jsonb_build_array('data'))),v_users,
  jsonb_build_object('order',to_jsonb(o)||jsonb_build_object('email_payment_fingerprint',public.order_email_payment_fingerprint(o.id)),'intent',v_intent,'sendingRequested',p_resend));
END $$;
REVOKE ALL ON FUNCTION public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text) TO authenticated;

-- Extend the current registry row in place; no readiness/version transition.
UPDATE public.client_sync_component_sources SET canonical_writers=array_append(canonical_writers,'repair_order_email_client_sync_v1')
 WHERE source_relation='eshop.orders'::regclass AND NOT ('repair_order_email_client_sync_v1'=ANY(canonical_writers));


-- SOURCE: eshop_orders/update_order_responses.sql
CREATE OR REPLACE FUNCTION public.update_order_responses(
    p_order_id BIGINT,
    responses JSONB
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_order_form_id BIGINT;
    v_current_state text;
    v_current_data JSONB;
    v_new_data JSONB;
    v_field_definitions JSONB;
    v_current_fields_map JSONB;
    v_merged_fields_map JSONB;
    v_new_fields_array JSONB;

    v_field_id_text TEXT;
    v_field_type TEXT;
    v_new_value JSONB;

    v_updated_order_state TEXT;
    v_updated_order_price NUMERIC(10, 2);
    v_updated_order_data JSONB;
BEGIN
    -- Fetch the order's current data, occasion, and form ID
    SELECT
        o.data,
        o.occasion,
        o.form,
        o.state
    INTO
        v_current_data,
        v_occasion_id,
        v_order_form_id,
        v_current_state
    FROM eshop.orders o
    WHERE o.id = p_order_id;

    -- Raise an exception if the SELECT INTO returned no row
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    -- Check if the current user has order editing permissions for this occasion
    IF (SELECT can_write_orders(v_occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User does not have permission to edit this order.';
    END IF;

    -- Reject the terminal state before form validation, without reversing
    -- the form -> order lock order used by form-field removal.
    IF v_current_state='storno' THEN
        RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
    END IF;

    -- Raise an exception if the order is not linked to a form
    IF v_order_form_id IS NULL THEN
        RAISE EXCEPTION 'Order % has no associated form.', p_order_id;
    END IF;

    -- Coordinate response validation/writes with form saves and field removal.
    PERFORM 1 FROM public.forms WHERE id = v_order_form_id FOR SHARE;
    PERFORM public.check_order_is_mutable(p_order_id);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=p_order_id));
    SELECT data INTO v_current_data FROM eshop.orders WHERE id=p_order_id;

    -- Fetch all field definitions for this form into a JSONB map { "field_id": "field_type" }
    SELECT jsonb_object_agg(ff.id::text, ff.type)
    INTO v_field_definitions
    FROM public.form_fields ff
    WHERE ff.form = v_order_form_id;

    -- Raise an exception if the form has no fields
    IF v_field_definitions IS NULL THEN
        RAISE EXCEPTION 'No form fields found for form %', v_order_form_id;
    END IF;

    -- FIX: Use a LATERAL join to explicitly reference the columns from jsonb_each,
    -- resolving the "ambiguous column 'value'" error.
    SELECT jsonb_object_agg(je.key, je.value)
    INTO v_current_fields_map
    FROM jsonb_array_elements(v_current_data -> 'fields') AS jae(field_object),
         LATERAL jsonb_each(jae.field_object) AS je(key, value);

    -- Start with the current order data
    v_new_data := v_current_data;

    -- Merge the existing fields map with the new responses. New responses overwrite old ones.
    v_merged_fields_map := COALESCE(v_current_fields_map, '{}'::jsonb) || responses;

    -- Iterate through only the *incoming* responses to handle updates and nulls
    FOR v_field_id_text, v_new_value IN SELECT * FROM jsonb_each(responses)
    LOOP
        -- Get the type of the field being updated
        v_field_type := v_field_definitions ->> v_field_id_text;

        -- Validate that the field ID exists on this order's form
        IF v_field_type IS NULL THEN
            RAISE EXCEPTION 'Field ID % not found on form %', v_field_id_text, v_order_form_id;
        END IF;

        -- Handle null values: remove the key from the top level and from the merged map
        IF v_new_value IS NULL OR v_new_value = 'null'::jsonb THEN

            -- Remove from the map that will build the 'fields' array
            v_merged_fields_map := v_merged_fields_map - v_field_id_text;

            -- Remove top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data - 'name';
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data - 'surname';
            ELSIF v_field_type = 'email' THEN
                v_new_data := v_new_data - 'email';
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data - 'phone';
            END IF;

        -- Handle non-null values: update the top-level keys
        ELSE

            -- Update top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data || jsonb_build_object('name', v_new_value);
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data || jsonb_build_object('surname', v_new_value);
            ELSIF v_field_type = 'email' THEN
                IF NOT public.email_address_is_valid(v_new_value #>> '{}') THEN
                    RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact';
                END IF;
                v_new_data := v_new_data || jsonb_build_object('email', v_new_value);
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data || jsonb_build_object('phone', v_new_value);
            END IF;

        END IF;
    END LOOP;

    -- Rebuild the 'fields' array from the (now null-stripped) merged map
    -- It converts { "id": "val" } back to [ {"id": "val"} ]
    SELECT jsonb_agg(jsonb_build_object(key, value))
    INTO v_new_fields_array
    FROM jsonb_each(v_merged_fields_map);

    -- Set the new 'fields' array in the main data object
    v_new_data := jsonb_set(
        v_new_data,
        '{fields}',
        COALESCE(v_new_fields_array, '[]'::jsonb)
    );

    PERFORM public.notification_center_prepared_invalidate_order(p_order_id);
    -- Update the order in the database
    UPDATE eshop.orders
    SET
        data = v_new_data,
        updated_at = NOW()
    WHERE
        id = p_order_id
    RETURNING
        state, price, data
    INTO
        v_updated_order_state, v_updated_order_price, v_updated_order_data;

    -- Save the change to the orders_history table
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        p_order_id,
        v_updated_order_state,
        v_updated_order_price,
        v_updated_order_data,
        NOW()
    );

END;
$$;

-- SOURCE: eshop_orders/internal_storno_tickets_221.sql
CREATE OR REPLACE FUNCTION internal_storno_tickets_221(ticket_ids_to_storno BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions

AS $$
DECLARE
    opt_ids BIGINT[];
    nc_changed record;
    nc_changes jsonb;
    nc_products bigint[];
    nc_event uuid;
    nc_contexts bigint[];
    nc_blueprints bigint[];
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(ticket_ids_to_storno)));
    PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(ticket_ids_to_storno)));
    IF ticket_ids_to_storno IS NULL OR array_length(ticket_ids_to_storno, 1) = 0 THEN
        RETURN; -- Nothing to do
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)));
    PERFORM public.lock_ticket_order_products_internal(o.id) FROM eshop.orders o WHERE o.id IN
      (SELECT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)) ORDER BY o.id;
    UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN
      (SELECT o.form FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE x.ticket=ANY(ticket_ids_to_storno));
    UPDATE eshop.waitlist_offer_slots SET outcome='cancelled',updated_at=clock_timestamp()
      WHERE ticket_id=ANY(ticket_ids_to_storno) AND outcome='pending';
    SELECT array_agg(DISTINCT s.inventory_context),array_agg(DISTINCT s.blueprint) INTO nc_contexts,nc_blueprints FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE x.ticket=ANY(ticket_ids_to_storno);
    SELECT array_agg(DISTINCT product) INTO nc_products FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno) AND product IS NOT NULL;
    SELECT coalesce(jsonb_agg(to_jsonb(changes)),'[]') INTO nc_changes FROM (
      SELECT x."order" order_id,array_agg(DISTINCT t.id ORDER BY t.id) ticket_ids FROM eshop.order_product_ticket x
      JOIN eshop.tickets t ON t.id=x.ticket WHERE t.id=ANY(ticket_ids_to_storno) AND t.state IS DISTINCT FROM 'storno' GROUP BY x."order"
    ) changes;
    -- 1. Get all related order_product_ticket IDs
    SELECT ARRAY_AGG(opt.id) INTO opt_ids
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ANY(ticket_ids_to_storno);

    -- 2. (NEW) Delete any occasion_users linked to these tickets.
    -- We delete directly because the parent function already
    -- verified the user has 'editor' permissions.
    PERFORM public.notification_center_prepared_invalidate_user(m."user",m.occasion) FROM public.occasion_users m WHERE m.ticket=ANY(ticket_ids_to_storno);
    DELETE FROM public.occasion_users
    WHERE ticket = ANY(ticket_ids_to_storno);

    -- 3. Update the tickets themselves to 'storno'
    UPDATE eshop.tickets
    SET state = 'storno', updated_at = NOW()
    WHERE id = ANY(ticket_ids_to_storno);

    -- 4. Nullify the relevant spots
    IF opt_ids IS NOT NULL THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL,
            secret = NULL,
            secret_expiration_time = NULL,
            updated_at = NOW(),
            resource = NULL,
            state = NULL
        WHERE order_product_ticket = ANY(opt_ids);
    END IF;

    -- 5. Nullify the product link on the order_product_ticket records
    UPDATE eshop.order_product_ticket
    SET product = NULL
    WHERE ticket = ANY(ticket_ids_to_storno);

    FOR nc_changed IN SELECT * FROM jsonb_to_recordset(nc_changes) AS r(order_id bigint,ticket_ids bigint[]) LOOP
      PERFORM public.notification_center_order_internal(nc_changed.order_id,'order_cancelled',encode(extensions.digest(array_to_string(nc_changed.ticket_ids,','),'sha256'),'hex'),auth.uid(),
        jsonb_build_object('count',cardinality(nc_changed.ticket_ids)));
      SELECT id INTO nc_event FROM public.notification_center_events WHERE kind='order_cancelled' AND data->>'orderId'=nc_changed.order_id::text
        AND source_key='order_cancelled:'||nc_changed.order_id||':'||encode(extensions.digest(array_to_string(nc_changed.ticket_ids,','),'sha256'),'hex');
      PERFORM public.notification_center_form_capacity_internal((SELECT form FROM eshop.orders WHERE id=nc_changed.order_id),auth.uid(),nc_event);
    END LOOP;
    PERFORM public.notification_center_product_capacity_internal(p) FROM unnest(nc_products) p;
    PERFORM public.notification_center_inventory_capacity_internal(c) FROM unnest(nc_contexts) c WHERE c IS NOT NULL;
    PERFORM public.notification_center_blueprint_capacity_internal(b) FROM unnest(nc_blueprints) b WHERE b IS NOT NULL;
END;
$$;

-- SOURCE: eshop_orders/delete_order.sql
CREATE OR REPLACE FUNCTION public.delete_order_internal_v1(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payment_info_id BIGINT;
  order_product_ticket_ids BIGINT[];
  ticket_ids BIGINT[];
  order_oc BIGINT;
  ou_record RECORD;
  form_id BIGINT;
  related_orders BIGINT[];
  offer_ids UUID[];
  v_activity_impacts jsonb := '[]'::jsonb;
BEGIN
  -- Retrieve the order's occasion and payment_info.
  SELECT occasion, payment_info, form
    INTO order_oc, payment_info_id, form_id
    FROM eshop.orders
   WHERE id = delete_order_internal_v1.order_id;

  IF order_oc IS NULL THEN
    RAISE EXCEPTION 'Order not found.';
  END IF;

  -- Deletion belongs to scoped unit managers/editors and organization admins.
  IF auth.uid() IS NULL OR NOT public.can_delete_orders(order_oc) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;
  -- The queue send gate locks global capacity before an order. Deletion must
  -- acquire that outer lock before the form/order helper to avoid inversion.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  -- Form serialization fences offer issuance, acceptance, expiry and recovery.
  -- Lock every directly related order in ID order before changing any links.
  PERFORM 1 FROM public.forms WHERE id=form_id FOR UPDATE;
  SELECT array_agg(DISTINCT id ORDER BY id) INTO related_orders FROM (
    SELECT o.id FROM eshop.orders o WHERE o.id=delete_order_internal_v1.order_id OR o.source_waitlist_order_id=delete_order_internal_v1.order_id
      OR o.id=(SELECT source_waitlist_order_id FROM eshop.orders WHERE id=delete_order_internal_v1.order_id)
    UNION SELECT a.source_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
    UNION SELECT a.target_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
  ) related;
  IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(related_orders)
      AND (o.occasion<>order_oc OR o.form IS DISTINCT FROM form_id)) THEN
    RAISE EXCEPTION 'ORDER_WAITLIST_SCOPE_MISMATCH'; END IF;
  PERFORM public.check_batch_order_delete_internal(order_id);
  PERFORM public.lock_order_capacity_scope_internal(related_orders);
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=delete_order_internal_v1.order_id AND state='preparing_payment')
    OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts a
      WHERE (a.target_order_id=delete_order_internal_v1.order_id OR a.source_order_id=delete_order_internal_v1.order_id) AND a.state='preparing') THEN
    RAISE EXCEPTION 'WAITLIST_ACCEPTANCE_IN_PROGRESS'; END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(SELECT form FROM eshop.orders WHERE id=delete_order_internal_v1.order_id);
  -- Match occasion configuration/deletion: forms precede the occasion row.
  -- The group/activity advisory lock does not fence an occasion's unit move.
  PERFORM 1 FROM public.occasions WHERE id=order_oc FOR SHARE;
  PERFORM public.lock_activity_aggregate_internal_v1(order_oc);
  IF auth.uid() IS NULL OR NOT public.can_delete_orders(order_oc) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;

  -- After authorization, match the worker lock order (capacity, order,
  -- attempts, message). Recheck the order after locking against concurrent edits.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  SELECT o.payment_info INTO payment_info_id
    FROM eshop.orders o
   WHERE o.id = delete_order_internal_v1.order_id AND o.occasion = order_oc
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found or occasion changed.';
  END IF;

  -- Delete attention while message identities still exist. Cascading recipients
  -- and deliveries make every overview, count and badge agree immediately.
  PERFORM public.notification_center_prepared_delete_events(ARRAY(SELECT * FROM public.notification_center_prepared_order_events(delete_order_internal_v1.order_id)));
  DELETE FROM public.notification_center_events WHERE id=ANY(ARRAY(SELECT * FROM public.notification_center_prepared_order_events(delete_order_internal_v1.order_id)));
  DELETE FROM public.notification_center_source_state s
  USING public.email_messages m
  WHERE m.order_id=delete_order_internal_v1.order_id
    AND s.organization=m.organization AND s.source_key='email:'||m.message_id;

  -- Remove every queued/reminder/provider record for this order. log_emails
  -- and address suppressions are independent audit/safety records and remain.
  DELETE FROM public.email_delivery_events e
   WHERE e.message_id IN (SELECT m.message_id FROM public.email_messages m
                           WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.attempt_id IN (SELECT a.attempt_id FROM public.email_attempts a
                          JOIN public.email_messages m USING (message_id)
                         WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.provider_message_id IN (
           SELECT m.provider_message_id FROM public.email_messages m
            WHERE m.order_id = delete_order_internal_v1.order_id
           UNION
           SELECT a.provider_message_id FROM public.email_attempts a
           JOIN public.email_messages m USING (message_id)
            WHERE m.order_id = delete_order_internal_v1.order_id);

  DELETE FROM public.email_confirmation_receipts r
   WHERE r.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_attempts a
   WHERE a.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_messages m
   WHERE m.order_id = delete_order_internal_v1.order_id;

  -- Collect all order_product_ticket IDs for the order.
  SELECT ARRAY(SELECT id FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id)
    INTO order_product_ticket_ids;

  -- Collect all ticket IDs from the order_product_ticket rows.
  SELECT ARRAY(SELECT ticket
                 FROM eshop.order_product_ticket
                WHERE "order" = delete_order_internal_v1.order_id
                  AND ticket IS NOT NULL)
    INTO ticket_ids;

  IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=ANY(ticket_ids) AND x."order"<>delete_order_internal_v1.order_id) THEN
    RAISE EXCEPTION 'TICKET_LINKED_TO_ANOTHER_ORDER'; END IF;

  -- Remove only this order's capability/offer evidence. Accepted children are
  -- independent orders: detach their source FK, never their tickets or finance.
  SELECT coalesce(array_agg(w.id),'{}') INTO offer_ids FROM eshop.waitlist_offers w WHERE w.order_id=delete_order_internal_v1.order_id;
  PERFORM 1 FROM eshop.waitlist_acceptance_attempts a
    WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id ORDER BY a.command_id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids) ORDER BY w.id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offer_slots x
    WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids) OR x.resulting_order_id=delete_order_internal_v1.order_id ORDER BY x.id FOR UPDATE;
  DELETE FROM eshop.waitlist_capabilities c WHERE c.order_id=delete_order_internal_v1.order_id OR c.offer_id=ANY(offer_ids);
  DELETE FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id;
  UPDATE eshop.waitlist_offer_slots x SET resulting_order_id=NULL,updated_at=clock_timestamp() WHERE x.resulting_order_id=delete_order_internal_v1.order_id;
  DELETE FROM eshop.waitlist_offer_slots x WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids);
  DELETE FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids);
  UPDATE eshop.orders o SET source_waitlist_order_id=NULL,updated_at=clock_timestamp() WHERE o.source_waitlist_order_id=delete_order_internal_v1.order_id;

  -- Free any spots that reference these order_product_ticket rows:
  -- set order_product_ticket, secret, and secret_expiration_time to NULL.
  UPDATE eshop.spots
     SET order_product_ticket      = NULL,
         secret                  = NULL,
         secret_expiration_time  = NULL,
         updated_at              = NOW()
   WHERE order_product_ticket = ANY(order_product_ticket_ids);

  -- Delete the related order_product_ticket entries.
  DELETE FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id;

  -- Ticket-bound membership teardown has one domain owner, independent of
  -- the retired public RPC. Authorization remains the order's manager boundary.
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE ticket=ANY(ticket_ids) AND occasion<>order_oc) THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket membership belongs to another occasion';
  END IF;
  FOR ou_record IN SELECT "user",occasion FROM public.occasion_users
    WHERE ticket=ANY(ticket_ids) AND occasion=order_oc ORDER BY "user"
  LOOP
    v_activity_impacts:=v_activity_impacts || public.remove_occasion_user_domain_internal_v1(order_oc,ou_record."user");
  END LOOP;
  -- The canonical order facade already invalidates profiles for remaining members.
  -- Teardown must also invalidate affected activity projections in sorted order.
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT DISTINCT x->>'component',order_oc,(x->>'userId')::uuid,1
  FROM jsonb_array_elements(v_activity_impacts) x
  JOIN public.occasion_users ou ON ou.occasion=order_oc AND ou."user"=(x->>'userId')::uuid
  WHERE x->>'component'='private_activity' ORDER BY 1,3
  ON CONFLICT(component,occasion,user_id) DO UPDATE
    SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();

  -- Delete the related tickets.
  -- This is now safe, as any occasion_users foreign key constraints
  -- should be resolved by the loop above.
  DELETE FROM eshop.tickets WHERE id = ANY(ticket_ids);

  -- Delete order history rows.
  DELETE FROM eshop.orders_history WHERE "order" = delete_order_internal_v1.order_id;

  -- Order-specific bank requests must not keep the order alive through their FK.
  DELETE FROM eshop.bank_account_requests WHERE "order" = delete_order_internal_v1.order_id;

  -- If a payment_info row exists, first free it from the order reference, then delete it.
  IF payment_info_id IS NOT NULL THEN
    UPDATE eshop.orders
       SET payment_info = NULL
     WHERE id = delete_order_internal_v1.order_id;

    -- Retain imported/manual bank transactions while removing their payment link.
    UPDATE eshop.transactions
       SET payment_info = NULL
     WHERE payment_info = payment_info_id;

    DELETE FROM eshop.payment_info WHERE id = payment_info_id;
  END IF;

  -- Finally, delete the order record.
  DELETE FROM eshop.orders WHERE id = delete_order_internal_v1.order_id;

END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_internal_v1(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_221(order_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.delete_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_221(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_221(bigint) TO authenticated;


-- SOURCE: groups/remove_occasion_user_domain.sql
-- One occasion-user teardown handler. Authorization and receipt belong to its callers.
CREATE OR REPLACE FUNCTION public.remove_occasion_user_domain_internal_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE groups bigint[]; impacts jsonb;
BEGIN
 PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
 SELECT COALESCE(array_agg(DISTINCT g.id),'{}') INTO groups FROM public.user_group_info g LEFT JOIN public.user_groups ug ON g.id=ug."group" WHERE g.occasion=p_occasion AND (ug."user"=p_user OR g.leader=p_user);
 impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(SELECT "user" FROM public.user_groups WHERE "group"=ANY(groups))||ARRAY[p_user]);
 impacts:=(SELECT COALESCE(jsonb_agg(x),'[]') FROM jsonb_array_elements(impacts) x WHERE x->>'userId'<>p_user::text)||public.remove_user_activity_internal_v1(p_occasion,ARRAY[p_user]);
 UPDATE public.news SET created_by=NULL WHERE created_by=p_user AND occasion=p_occasion;
 UPDATE public.user_group_info SET leader=NULL WHERE occasion=p_occasion AND leader=p_user;
 DELETE FROM public.user_groups WHERE "user"=p_user AND "group"=ANY(groups);
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(groups) id
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 DELETE FROM public.event_users WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.event_users_saved WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.user_news WHERE "user"=p_user AND occasion=p_occasion;
 -- Membership attention belongs to the deleted application, not the account.
 PERFORM public.notification_center_prepared_delete_events(ARRAY(SELECT e.id FROM public.notification_center_events e JOIN public.occasions o ON o.id=p_occasion AND o.organization=e.organization
  WHERE e.occasion=p_occasion AND e.kind='occasion_joined' AND e.data->>'userId'=p_user::text));
 DELETE FROM public.notification_center_events e
 USING public.occasions o
 WHERE o.id=p_occasion AND e.organization=o.organization AND e.occasion=o.id
   AND e.kind='occasion_joined' AND e.data->>'userId'=p_user::text;
 DELETE FROM public.occasion_users WHERE "user"=p_user AND occasion=p_occasion;
 DELETE FROM public.client_sync_private_scopes WHERE occasion=p_occasion AND user_id=p_user;
 DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text;
 RETURN impacts;
END $$;
REVOKE ALL ON FUNCTION public.remove_occasion_user_domain_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;


-- SOURCE: users/occasion_enrolment_internal.sql
CREATE OR REPLACE FUNCTION public.add_user_to_occasion_internal_v1(oc bigint, usr uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    joined_at             timestamptz;
    occasion_open         BOOLEAN;
    user_data             JSONB;
    user_exists           BOOLEAN;
    user_org              BIGINT;
    occasion_org          BIGINT;
    unit_id               BIGINT;

    -- Initialize flags (though SELECT INTO will overwrite these with NULL if no row found)
    unit_is_manager       BOOLEAN := false;
    unit_is_editor        BOOLEAN := false;
    unit_is_editor_view   BOOLEAN := false;

    is_privileged         BOOLEAN := false;
BEGIN
    -- 1. Retrieve the organization, the unit, and the open status of the occasion.
    SELECT organization, unit, is_open
      INTO occasion_org, unit_id, occasion_open
      FROM occasions
     WHERE id = oc;

    -- 2. Get the organization of the user.
    SELECT organization
      INTO user_org
      FROM user_info
     WHERE id = usr;

    -- 3. Ensure the user and the occasion belong to the same organization.
    IF user_org IS DISTINCT FROM occasion_org THEN
        RETURN jsonb_build_object(
                  'code', 403,
                  'message', 'User does not belong to the same organization as the occasion'
              );
    END IF;

    PERFORM public.notification_center_initialized_internal(occasion_org);

    -- 4. Retrieve the unit-level role information from unit_users.
    SELECT is_manager, is_editor, is_editor_view
      INTO unit_is_manager, unit_is_editor, unit_is_editor_view
      FROM unit_users
     WHERE unit = unit_id AND "user" = usr;

    -- CRITICAL FIX: SELECT INTO sets variables to NULL if no row is found.
    -- We must ensure they are boolean FALSE to satisfy NOT NULL constraints later.
    unit_is_manager     := COALESCE(unit_is_manager, false);
    unit_is_editor      := COALESCE(unit_is_editor, false);
    unit_is_editor_view := COALESCE(unit_is_editor_view, false);

    -- 5. Define is_privileged.
    --    User is privileged if they have specific unit roles OR are an admin on the occasion.
    is_privileged := public.closed_occasion_enrolment_rule(unit_is_manager,unit_is_editor,unit_is_editor_view,
                     public.get_is_admin_on_occasion(oc));

    -- 6. Permission Check: Closed Occasions.
    --    If the occasion is not open, only privileged users can be added/modified.
    IF NOT occasion_open AND NOT is_privileged THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- 7. Retrieve the user info and build a JSON object merging any existing data.
    SELECT COALESCE(ui.data, '{}'::jsonb) || jsonb_build_object(
                'name', ui.name,
                'surname', ui.surname,
                'sex', ui.sex,
                'email', ui.email_readonly
           )
      INTO user_data
      FROM user_info ui
     WHERE ui.id = usr;

    -- 8. Check if the user already exists in the occasion_users table.
    SELECT EXISTS (
             SELECT 1
               FROM occasion_users
              WHERE occasion = oc AND "user" = usr
           ) INTO user_exists;

    IF user_exists THEN
        -- Update the existing row with the new data and the unit role flags.
        UPDATE occasion_users
           SET data           = user_data,
               is_manager     = unit_is_manager,
               is_editor      = unit_is_editor,
               is_editor_view = unit_is_editor_view,
               is_editor_order = unit_is_editor,
               is_editor_order_view = unit_is_editor_view
         WHERE occasion = oc AND "user" = usr;
    ELSE
        PERFORM public.notification_center_prepared_invalidate_user(usr,oc);
        -- Insert a new row into occasion_users, using the unit-level role flags.
        INSERT INTO occasion_users (
            occasion,
            "user",
            created_at,
            is_editor,
            is_manager,
            is_editor_view,
            is_editor_order,
            is_editor_order_view,
            is_approved,
            is_approver,
            data,
            role
        )
        VALUES (
            oc,
            usr,
            now(),
            unit_is_editor,
            unit_is_manager,
            unit_is_editor_view,
            unit_is_editor,
            unit_is_editor_view,
            FALSE,
            FALSE,
            user_data,
            NULL
        ) RETURNING created_at INTO joined_at;
        PERFORM public.notification_center_publish_internal(occasion_org,oc,'occasion_joined',
            'occasion-member:'||oc||':'||usr||':'||(joined_at AT TIME ZONE (SELECT timezone FROM public.notification_center_organizations WHERE organization=occasion_org))::date,
            jsonb_build_object('userId',usr),auth.uid());
    END IF;

    RETURN jsonb_build_object('code', 200);
END;
$function$
;
REVOKE ALL ON FUNCTION public.add_user_to_occasion_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion_internal_v1(bigint,uuid) TO service_role;


-- SOURCE: users/reception_qr_login.sql
-- Compatibility parameter is deliberately ignored: limits belong to the catalog.
CREATE OR REPLACE FUNCTION public.reception_rate_limit_v1(p_operation text,p_limit integer DEFAULT 30)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR p_operation IS NULL OR p_operation NOT IN ('create','issue','revoke','cancel') THEN RETURN false; END IF;
 RETURN public.abuse_charge_v1(public.abuse_effective_rules_v1('reception.'||p_operation,NULL,NULL),jsonb_build_object('actor',auth.uid()),'{}',true);
END $$;

CREATE OR REPLACE FUNCTION public.get_reception_registration_options_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_services jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN
    RETURN jsonb_build_object('code',403,'message','reception_unavailable');
  END IF;
  SELECT COALESCE(o.services,'{}'::jsonb) INTO v_services FROM public.occasions o WHERE o.id=p_occasion;
  RETURN jsonb_build_object('code',200,'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',g.id,'title',g.title) ORDER BY g.title)
    FROM public.user_group_info g WHERE g.occasion=p_occasion AND g.type IS NULL),'[]'::jsonb),
    'accommodations',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.item->>'code','title',x.item->>'title','placeTitle',p.title) ORDER BY x.ordinality)
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_services->'accommodation')='array' THEN v_services->'accommodation' ELSE '[]'::jsonb END)
      WITH ORDINALITY x(item,ordinality) LEFT JOIN public.places p ON p.occasion=p_occasion AND p.id=CASE WHEN x.item->>'reference' ~ '^[0-9]+$' THEN (x.item->>'reference')::bigint END),'[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.create_reception_user_v1(p_occasion bigint,p_command_id uuid,p_profile jsonb,p_group_id bigint DEFAULT NULL,p_accommodation_code text DEFAULT NULL,p_confirm_same_name boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_org bigint; v_user uuid; v_hash text; v_existing public.reception_registrations%rowtype;
  v_name text:=btrim(p_profile->>'name'); v_surname text:=btrim(p_profile->>'surname'); v_email text:=lower(btrim(p_profile->>'email'));
  v_sex text:=p_profile->>'sex'; v_matches jsonb; v_services jsonb:='{}'::jsonb; v_catalog jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('create') THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_profile) k WHERE k NOT IN('name','surname','email','sex','phone','birthDate'))
  THEN RETURN jsonb_build_object('code',400,'message','invalid_profile_fields'); END IF;
  IF COALESCE(v_name,'')='' OR COALESCE(v_surname,'')='' OR COALESCE(v_email,'')='' OR position('@' IN v_email)<=1 OR v_sex NOT IN('male','female','unspecified')
  THEN RETURN jsonb_build_object('code',400,'message','required_profile_fields'); END IF;
  v_hash:=encode(digest(jsonb_build_object('profile',p_profile,'group',p_group_id,'accommodation',p_accommodation_code)::text,'sha256'),'hex');
  SELECT * INTO v_existing FROM public.reception_registrations WHERE occasion=p_occasion AND created_by=v_actor AND command_id=p_command_id;
  IF FOUND THEN
    IF v_existing.request_hash<>v_hash THEN RETURN jsonb_build_object('code',409,'message','command_conflict'); END IF;
    SELECT ui.email_readonly INTO v_email FROM public.user_info ui WHERE ui.id=v_existing."user";
    RETURN jsonb_build_object('code',200,'userId',v_existing."user",'email',v_email,'replayed',true);
  END IF;
  SELECT o.organization,COALESCE(o.services,'{}'::jsonb) INTO v_org,v_catalog FROM public.occasions o WHERE o.id=p_occasion FOR SHARE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reception-email:'||v_org::text||':'||v_email,0));
  SELECT ui.id INTO v_user
  FROM public.user_info ui
  WHERE ui.organization=v_org AND lower(btrim(ui.email_readonly))=v_email;
  IF v_user IS NOT NULL THEN
    IF (public.can_manage_occasion_participants(p_occasion))
      AND EXISTS(SELECT 1 FROM public.occasion_users ou
        WHERE ou.occasion=p_occasion AND ou."user"=v_user) THEN
      RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,
        'existing',true,'replayed',false);
    END IF;
    RETURN jsonb_build_object('code',409,'message','email_already_exists');
  END IF;
  SELECT COALESCE(jsonb_agg(candidate),'[]'::jsonb) INTO v_matches FROM (
    SELECT jsonb_build_object('name',ui.name,'surname',ui.surname,'sex',ui.sex,
      'birthYear',CASE WHEN ui.birth_date IS NULL THEN NULL ELSE extract(year FROM ui.birth_date)::int END,
      'email',CASE WHEN position('@' IN ui.email_readonly)>2 THEN left(ui.email_readonly,1)||'***@'||split_part(ui.email_readonly,'@',2) ELSE '***' END,
      'onOccasion',EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=ui.id)) candidate
    FROM public.user_info ui WHERE ui.organization=v_org AND public.f_unaccent(btrim(ui.name))=public.f_unaccent(v_name)
      AND public.f_unaccent(btrim(ui.surname))=public.f_unaccent(v_surname) ORDER BY ui.created_at NULLS LAST LIMIT 10) q;
  IF jsonb_array_length(v_matches)>0 AND NOT p_confirm_same_name THEN RETURN jsonb_build_object('code',409,'message','same_name_confirmation_required','candidates',v_matches); END IF;
  IF p_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.user_group_info g WHERE g.id=p_group_id AND g.occasion=p_occasion AND g.type IS NULL FOR SHARE)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_group'); END IF;
  IF p_accommodation_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_catalog->'accommodation')='array' THEN v_catalog->'accommodation' ELSE '[]'::jsonb END) x WHERE x->>'code'=p_accommodation_code)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_accommodation'); END IF;
  v_user:=public.create_user_in_organization_with_data_pure(v_org,v_email,v_email,encode(gen_random_bytes(32),'hex'),p_profile-'email');
  IF p_accommodation_code IS NOT NULL THEN v_services:=jsonb_build_object('accommodation',jsonb_build_object(p_accommodation_code,'paid')); END IF;
  PERFORM public.notification_center_prepared_invalidate_user(v_user,p_occasion);
  INSERT INTO public.occasion_users(occasion,"user",data,services) VALUES(p_occasion,v_user,p_profile,v_services);
  IF p_group_id IS NOT NULL THEN INSERT INTO public.user_groups("user","group",is_admin) VALUES(v_user,p_group_id,false); END IF;
  INSERT INTO public.reception_registrations(occasion,"user",created_by,command_id,request_hash) VALUES(p_occasion,v_user,v_actor,p_command_id,v_hash);
  RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,'replayed',false);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('code',409,'message','email_or_command_conflict');
END $$;

CREATE OR REPLACE FUNCTION public.issue_reception_login_qr_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_token text; v_hash text; v_actor uuid:=auth.uid();
  v_manual text; v_manual_hash text; v_manual_bytes bytea; v_alphabet constant text:='23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('issue') THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=p_user)
    OR NOT (public.can_manage_occasion_participants(p_occasion) OR EXISTS(
      SELECT 1 FROM public.reception_registrations r
      WHERE r.occasion=p_occasion AND r."user"=p_user AND r.status='active'
        AND r.created_by=v_actor AND r.created_at>now()-interval '30 minutes')) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  v_token:=translate(encode(gen_random_bytes(32),'base64'),E'+/=\n','-_'); v_hash:=encode(digest(v_token,'sha256'),'hex');
  v_manual_bytes:=gen_random_bytes(8);
  SELECT string_agg(substr(v_alphabet,(get_byte(v_manual_bytes,i)%32)+1,1),'') INTO v_manual FROM generate_series(0,7) i;
  v_manual_hash:=encode(digest(v_manual,'sha256'),'hex');
  INSERT INTO public.user_login_qr_credentials(occasion,"user",token_hash,manual_token_hash,manual_expires_at,created_by)
  VALUES(p_occasion,p_user,v_hash,v_manual_hash,now()+interval '30 minutes',v_actor)
  ON CONFLICT(occasion,"user") DO UPDATE SET token_hash=excluded.token_hash,manual_token_hash=excluded.manual_token_hash,
    manual_expires_at=excluded.manual_expires_at,created_by=excluded.created_by,rotated_at=now(),revoked_at=NULL,last_used_at=NULL,use_count=0;
  RETURN jsonb_build_object('code',200,'payload','festapp-login:v1:'||p_occasion::text||':'||v_token,
    'manualCode',left(v_manual,4)||'-'||right(v_manual,4));
END $$;

CREATE OR REPLACE FUNCTION public.get_reception_occasion_users_v1(p_occasion bigint,p_query text DEFAULT '')
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
SELECT CASE
  WHEN public.get_can_use_reception(p_occasion)
    AND (public.can_manage_occasion_participants(p_occasion))
  THEN COALESCE(jsonb_agg(jsonb_build_object(
    'userId',q.id,'name',q.name,'surname',q.surname,'email',q.email_readonly
  ) ORDER BY q.surname,q.name,q.email_readonly),'[]'::jsonb)
  ELSE '[]'::jsonb
END
FROM (
  SELECT ui.id,ui.name,ui.surname,ui.email_readonly
  FROM public.occasion_users ou
  JOIN public.user_info ui ON ui.id=ou."user"
  WHERE ou.occasion=p_occasion
    AND (COALESCE(btrim(p_query),'')=''
      OR public.f_unaccent(COALESCE(ui.name,'')||' '||COALESCE(ui.surname,'')||' '||COALESCE(ui.email_readonly,''))
        ILIKE '%'||public.f_unaccent(btrim(left(p_query,100)))||'%')
  ORDER BY ui.surname,ui.name,ui.email_readonly
  LIMIT 50
) q; $$;

CREATE OR REPLACE FUNCTION public.resolve_reception_login_qr_v1(p_occasion bigint,p_token_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_user uuid; v_email text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
  SELECT c."user",(o.organization::text||'+'||au.email_readonly) INTO v_user,v_email
  FROM public.user_login_qr_credentials c JOIN public.occasion_users ou ON (ou.occasion,ou."user")=(c.occasion,c."user")
  JOIN public.user_info au ON au.id=c."user" JOIN public.occasions o ON o.id=c.occasion
  WHERE c.occasion=p_occasion
    AND (c.token_hash=p_token_hash OR (c.manual_token_hash=p_token_hash AND c.manual_expires_at>now()))
    AND c.revoked_at IS NULL
    AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),'$[*] ? (@.code == "reception" && @.is_enabled == true)') FOR UPDATE OF c;
  IF v_user IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('userId',v_user,'authEmail',v_email);
END $$;

CREATE OR REPLACE FUNCTION public.revoke_reception_login_qr_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid();
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN
    RETURN jsonb_build_object('code',403,'message','reception_unavailable');
  END IF;
  IF NOT public.reception_rate_limit_v1('revoke') THEN
    RETURN jsonb_build_object('code',429,'message','rate_limited');
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.reception_registrations r
    WHERE r.occasion=p_occasion AND r."user"=p_user AND r.status='active'
      AND ((r.created_by=v_actor AND r.created_at>now()-interval '30 minutes')
        OR public.can_manage_occasion_participants(p_occasion))
  ) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable');
  END IF;
  UPDATE public.user_login_qr_credentials
  SET revoked_at=now()
  WHERE occasion=p_occasion AND "user"=p_user AND revoked_at IS NULL;
  RETURN jsonb_build_object('code',200,'status','revoked');
END $$;

CREATE OR REPLACE FUNCTION public.mark_reception_login_qr_used_v1(p_occasion bigint,p_token_hash text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
  UPDATE public.user_login_qr_credentials c SET
    last_used_at=now(),
    use_count=use_count+1,
    manual_token_hash=CASE WHEN c.manual_token_hash=p_token_hash THEN NULL ELSE c.manual_token_hash END,
    manual_expires_at=CASE WHEN c.manual_token_hash=p_token_hash THEN NULL ELSE c.manual_expires_at END
  FROM public.occasion_users ou,public.occasions o
  WHERE c.occasion=p_occasion
    AND (c.token_hash=p_token_hash OR (c.manual_token_hash=p_token_hash AND c.manual_expires_at>now()))
    AND c.revoked_at IS NULL
    AND (ou.occasion,ou."user")=(c.occasion,c."user") AND o.id=c.occasion
    AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),'$[*] ? (@.code == "reception" && @.is_enabled == true)');
END $$;

CREATE OR REPLACE FUNCTION public.cancel_reception_registration_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_r public.reception_registrations%rowtype; v_actor uuid:=auth.uid(); v_impacts jsonb;
BEGIN
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  SELECT * INTO v_r FROM public.reception_registrations WHERE occasion=p_occasion AND "user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','registration_unavailable'); END IF;
  IF NOT public.get_can_use_reception(p_occasion) OR NOT (public.can_manage_occasion_participants(p_occasion) OR (v_r.created_by=v_actor AND (v_r.status='cancelled' OR v_r.created_at>now()-interval '30 minutes'))) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  IF v_r.status='cancelled' THEN RETURN jsonb_build_object('code',200,'status',CASE WHEN v_r.auth_revoked_at IS NULL THEN 'domain_blocked_auth_revocation_pending' ELSE 'cancelled' END,'targetUser',p_user); END IF;
  IF NOT public.reception_rate_limit_v1('cancel') THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  UPDATE public.reception_registrations SET status='cancelled',cancelled_by=v_actor,cancelled_at=now() WHERE occasion=p_occasion AND "user"=p_user;
  v_impacts:=public.remove_occasion_user_domain_internal_v1(p_occasion,p_user);
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT x->>'component',p_occasion,(x->>'userId')::uuid,1 FROM jsonb_array_elements(v_impacts) x ORDER BY x->>'component',x->>'userId'
  ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();
  RETURN jsonb_build_object('code',200,'status','domain_blocked_auth_revocation_pending','targetUser',p_user);
END $$;

CREATE OR REPLACE FUNCTION public.mark_reception_auth_revoked_v1(p_occasion bigint,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
UPDATE public.reception_registrations SET auth_revoked_at=now() WHERE occasion=p_occasion AND "user"=p_user AND status='cancelled'; END $$;

CREATE OR REPLACE FUNCTION public.get_my_recent_reception_registrations_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
SELECT CASE WHEN public.get_can_use_reception(p_occasion) THEN COALESCE(jsonb_agg(jsonb_build_object('userId',r."user",'name',ui.name,'surname',ui.surname,'email',ui.email_readonly,'createdAt',r.created_at,'qrUsed',c.last_used_at IS NOT NULL) ORDER BY r.created_at DESC),'[]'::jsonb) ELSE '[]'::jsonb END
FROM public.reception_registrations r JOIN public.user_info ui ON ui.id=r."user" LEFT JOIN public.user_login_qr_credentials c ON (c.occasion,c."user")=(r.occasion,r."user")
WHERE r.occasion=p_occasion AND r.created_by=auth.uid() AND r.status='active' AND r.created_at>now()-interval '30 minutes'; $$;

REVOKE ALL ON FUNCTION public.reception_rate_limit_v1(text,integer),public.get_reception_occasion_users_v1(bigint,text),public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text),public.mark_reception_auth_revoked_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text),public.mark_reception_auth_revoked_v1(bigint,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_reception_registration_options_v1(bigint),public.create_reception_user_v1(bigint,uuid,jsonb,bigint,text,boolean),public.issue_reception_login_qr_v1(bigint,uuid),public.get_reception_occasion_users_v1(bigint,text),public.revoke_reception_login_qr_v1(bigint,uuid),public.cancel_reception_registration_v1(bigint,uuid),public.get_my_recent_reception_registrations_v1(bigint) TO authenticated,service_role;


-- SOURCE: account_deletion/account_deletion_contract.sql
CREATE OR REPLACE FUNCTION public.create_account_deletion_request(
  p_user uuid,
  p_organization bigint,
  p_token_hash text,
  p_expires_at timestamptz,
  p_masked_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_previous public.account_deletion_requests%ROWTYPE;
  v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_invalid_request' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id = p_user AND ui.organization = p_organization
  ) THEN
    RAISE EXCEPTION 'account_deletion_account_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_previous
  FROM public.account_deletion_requests
  WHERE user_id = p_user
    AND status IN ('email_pending','email_sent','deletion_pending')
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF v_previous.status = 'deletion_pending' THEN
    RAISE EXCEPTION 'account_deletion_already_pending' USING ERRCODE = '55000';
  END IF;
  IF v_previous.id IS NOT NULL AND v_previous.cooldown_until > clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_cooldown' USING ERRCODE = 'P0001';
  END IF;
  IF v_previous.id IS NOT NULL THEN
    UPDATE public.account_deletion_requests
    SET status = 'revoked', token_hash = NULL, masked_email = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_previous.id;
  END IF;

  INSERT INTO public.account_deletion_requests(
    user_id, organization, token_hash, masked_email, expires_at, cooldown_until
  ) VALUES (
    p_user, p_organization, p_token_hash, p_masked_email, p_expires_at,
    clock_timestamp() + interval '5 minutes'
  ) RETURNING * INTO v_request;

  RETURN jsonb_build_object('requestId', v_request.id, 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_account_deletion_email_state(
  p_request_id uuid,
  p_delivered boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_deletion_requests
  SET status = CASE WHEN p_delivered THEN 'email_sent' ELSE 'revoked' END,
      email_sent_at = CASE WHEN p_delivered THEN clock_timestamp() ELSE NULL END,
      token_hash = CASE WHEN p_delivered THEN token_hash ELSE NULL END,
      masked_email = CASE WHEN p_delivered THEN masked_email ELSE NULL END,
      error_class = CASE WHEN p_delivered THEN NULL ELSE 'email_delivery' END,
      updated_at = clock_timestamp()
  WHERE id = p_request_id AND status = 'email_pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.inspect_account_deletion_token(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  IF p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;
  RETURN jsonb_build_object('status', 'valid', 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_account_deletion(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_request public.account_deletion_requests%ROWTYPE;
  v_completion_email text;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1 FOR UPDATE;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status IN ('deletion_pending','failed') AND v_request.used_token_hash = p_token_hash THEN
    RETURN jsonb_build_object('status','processing','requestId',v_request.id,
      'userId',v_request.user_id,'organization',v_request.organization,
      'publicDeleted',v_request.public_deleted,'authDeleted',v_request.auth_deleted,
      'onesignalDeleted',v_request.onesignal_deleted);
  END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;

  v_completion_email := public.get_user_delivery_email(v_request.user_id);

  UPDATE public.account_deletion_requests SET
    status='deletion_pending', used_token_hash=token_hash, token_hash=NULL,
    masked_email=NULL, claimed_at=clock_timestamp(), attempt_count=attempt_count+1,
    updated_at=clock_timestamp()
  WHERE id=v_request.id RETURNING * INTO v_request;
  -- The claim and first-party cleanup share one transaction. Consequently an
  -- already-issued JWT cannot regain domain access between confirmation and a
  -- later Edge call; its public.user_info row is gone before claim commits.
  PERFORM public.cleanup_account_deletion_domain(v_request.id);
  RETURN jsonb_build_object('status','processing','requestId',v_request.id,
    'userId',v_request.user_id,'organization',v_request.organization,
    'completionEmail',v_completion_email,
    'publicDeleted',true,'authDeleted',false,'onesignalDeleted',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_account_deletion_domain(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user uuid; v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE id=p_request_id FOR UPDATE;
  IF v_request.id IS NULL OR v_request.status NOT IN ('deletion_pending','failed') THEN
    RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000';
  END IF;
  IF v_request.public_deleted THEN RETURN jsonb_build_object('status','already_deleted'); END IF;
  v_user := v_request.user_id;

  PERFORM public.record_account_deletion_sync_v1(
    v_user,v_request.organization);

  UPDATE public.cleaning_reports SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.cleaning_reports SET resolved_by=NULL WHERE resolved_by=v_user;
  UPDATE public.news SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.orders_history SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.bank_account_requests SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.transactions SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.client_commits SET actor_id=NULL, actor_display=NULL WHERE actor_id=v_user;
  DELETE FROM public.event_feedback WHERE "user"=v_user;

  DELETE FROM public.client_mutation_receipts WHERE actor_id=v_user;
  DELETE FROM public.client_sync_private_scopes WHERE user_id=v_user;
  DELETE FROM public.activity_assignments WHERE "user"=v_user;
  DELETE FROM public.activity_history WHERE user_id=v_user;
  DELETE FROM public.event_users_saved WHERE "user"=v_user;
  DELETE FROM public.event_users WHERE "user"=v_user;
  DELETE FROM public.user_groups WHERE "user"=v_user;
  DELETE FROM public.user_companions WHERE "user"=v_user OR companion=v_user;
  DELETE FROM public.user_reset_token WHERE "user"=v_user;
  DELETE FROM eshop.bank_account_users WHERE "user"=v_user;
  PERFORM public.notification_center_prepared_invalidate_user(v_user);
  DELETE FROM public.occasion_users WHERE "user"=v_user;
  DELETE FROM public.unit_users WHERE "user"=v_user;
  DELETE FROM public.organization_users WHERE "user"=v_user;
  PERFORM public.invalidate_external_login_for_user_v1(v_user);
  DELETE FROM public.user_info WHERE id=v_user;

  UPDATE public.account_deletion_requests SET public_deleted=true,
    status='deletion_pending', error_class=NULL, updated_at=clock_timestamp()
  WHERE id=p_request_id;
  RETURN jsonb_build_object('status','deleted');
END;
$$;

CREATE OR REPLACE FUNCTION public.update_account_deletion_job(
  p_request_id uuid,
  p_auth_deleted boolean DEFAULT NULL,
  p_onesignal_deleted boolean DEFAULT NULL,
  p_error_class text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE; v_assets_done boolean;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  v_assets_done := COALESCE(v_request.assets_prepared AND
    (SELECT active FROM public.canonical_asset_cutover WHERE singleton) AND
    NOT EXISTS(SELECT 1 FROM public.account_deletion_assets WHERE request_id=p_request_id AND deleted_at IS NULL) AND
    NOT EXISTS(SELECT 1 FROM public.canonical_assets WHERE owner_id=v_request.user_id::text AND deleted_at IS NULL),false);
  UPDATE public.account_deletion_requests SET
    auth_deleted=coalesce(p_auth_deleted,auth_deleted),
    onesignal_deleted=coalesce(p_onesignal_deleted,onesignal_deleted),
    error_class=p_error_class,
    status=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN 'completed'
      WHEN p_error_class IS NOT NULL THEN 'failed' ELSE 'deletion_pending' END,
    completed_at=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN clock_timestamp()
      ELSE completed_at END,
    user_id=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN NULL ELSE user_id END,
    updated_at=clock_timestamp()
  WHERE id=p_request_id AND status IN ('deletion_pending','failed')
  RETURNING * INTO v_request;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
  RETURN jsonb_build_object('status',v_request.status);
END;
$$;

REVOKE ALL ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_account_deletion(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_account_deletion_domain(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_account_deletion_domain(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) TO service_role;
REVOKE ALL ON FUNCTION public.inspect_account_deletion_token(text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.inspect_account_deletion_token(text) TO anon, service_role;


-- SOURCE: eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    v_ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    form_blueprint BIGINT;
    selected_spots BIGINT[];
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
    v_payment_method text;
    v_payment_instructions jsonb;
    v_stripe_connection uuid;
    v_stripe_attempt uuid;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid)]);
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(coalesce(input_data->'ticket','[]')) t WHERE t->>'spot' IS NOT NULL));
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open, blueprint
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val, form_blueprint
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.can_write_orders(occasion_id);

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        form_deadline_duration := COALESCE(form_deadline_duration,
            (SELECT (elem->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) elem WHERE elem->>'code'='form'),604800);

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_ticket_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id AND (NOT p_offer OR product IS NOT NULL)) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        SELECT coalesce(array_agg((t->>'spot')::bigint),'{}') INTO selected_spots
        FROM jsonb_array_elements(input_data->'ticket') t WHERE t->>'spot' IS NOT NULL;
        IF cardinality(selected_spots)<>(SELECT count(DISTINCT id) FROM unnest(selected_spots) id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',1007,'message','Duplicate spot')::text; END IF;
        -- Admission locks product/inventory parents before any seat row. The
        -- occasion scope is acquired by every caller before form/order parents.
        PERFORM 1 FROM eshop.spots WHERE id=ANY(selected_spots) ORDER BY id FOR UPDATE;
        now:=clock_timestamp();
        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS NOT TRUE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Identity is explicit: offers reuse the waiting ticket; checkout creates it.
        FOR ticket_data IN SELECT * FROM jsonb_array_elements(input_data->'ticket') LOOP
            SELECT value->>'note' INTO ticket_note FROM jsonb_array_elements(coalesce(ticket_data->'fields','[]'))
              WHERE value ? 'note' LIMIT 1;
            v_ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            IF p_offer THEN
              ticket_id:=(ticket_data->>'ticketId')::bigint;
              UPDATE eshop.tickets t SET state='ordered',ticket_symbol=v_ticket_symbol,
                note=ticket_note,data=public.extract_ticket_answers_internal(form_id,ticket_data),updated_at=now
              WHERE t.id=ticket_id AND t.state='waitlisted' AND t.ticket_symbol IS NULL
                AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=order_id AND x.product IS NULL)
                AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots x WHERE x.ticket_id=t.id AND x.outcome='accepted');
              IF NOT FOUND THEN RAISE EXCEPTION 'Invalid waiting ticket finalization'; END IF;
              DELETE FROM eshop.order_product_ticket WHERE "order"=order_id AND ticket=ticket_id AND product IS NULL;
            ELSE
              IF ticket_data ? 'ticketId' THEN RAISE EXCEPTION 'Ticket identity is server assigned'; END IF;
              INSERT INTO eshop.tickets (state,occasion,ticket_symbol,note,data,created_at,updated_at)
              VALUES('ordered',occasion_id,v_ticket_symbol,ticket_note,public.extract_ticket_answers_internal(form_id,ticket_data),now,now) RETURNING id INTO ticket_id;
            END IF;
            result:=public.materialize_ticket_products_internal_v1(order_id,form_id,ticket_id,ticket_data,(input_data->>'secret')::uuid);
            IF first_currency_code IS NULL THEN first_currency_code:=result->>'currency_code';
            ELSIF first_currency_code IS DISTINCT FROM result->>'currency_code' THEN
              RAISE EXCEPTION '%',jsonb_build_object('code',1014,'message','Products in the order must have the same currency',
                'expected_currency',first_currency_code,'actual_currency',result->>'currency_code')::text;
            END IF;
            calculated_price:=calculated_price+(result->>'price')::numeric;
            v_total_deposit:=v_total_deposit+(result->>'deposit')::numeric;
            IF result->>'spot' IS NOT NULL THEN used_spots:=used_spots||jsonb_build_array((result->>'spot')::bigint); END IF;
            ticket_details:=ticket_details||jsonb_build_object('id',ticket_id,'ticket_symbol',v_ticket_symbol,
              'note',ticket_note,'products',result->'products');
        END LOOP;

        order_data := input_data - 'ticket' - 'stripePaymentSource' || JSONB_BUILD_OBJECT('tickets', public.order_tickets_with_seating_internal(order_id, ticket_details));

        v_payment_method:=coalesce(input_data->>'payment_method','bank');
        IF v_payment_method NOT IN ('bank','stripe') THEN RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
        IF calculated_price=0 THEN v_payment_method:='bank'; END IF;
        IF calculated_price=0 THEN
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at) VALUES(0,first_currency_code,now) RETURNING id INTO payment_info_id;
        ELSIF v_payment_method='stripe' THEN
          IF coalesce(input_data->>'payment_type','full')<>'full' OR v_total_deposit>0 THEN
            RAISE EXCEPTION 'STRIPE_DEPOSIT_UNSUPPORTED'; END IF;
          v_stripe_connection:=public.assert_stripe_form_payable_internal(form_id,
            (input_data->>'stripe_connection_id')::uuid,input_data->>'payment_surface');
          IF (input_data->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM calculated_price*100
            OR input_data->>'expected_payment_currency' IS DISTINCT FROM first_currency_code::text THEN
            RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','STRIPE_PRICE_CHANGED','message','Order price changed. Review the order before paying.')::text;
          END IF;
          IF first_currency_code NOT IN ('CZK','EUR','PLN','USD','GBP') OR calculated_price*100<>trunc(calculated_price*100) THEN
            RAISE EXCEPTION 'STRIPE_AMOUNT_UNSUPPORTED'; END IF;
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method,stripe_connection_id)
          VALUES(calculated_price,first_currency_code,now,'stripe',v_stripe_connection) RETURNING id INTO payment_info_id;
        ELSE
          IF input_data->>'payment_type' = 'full' THEN v_total_deposit:=0; END IF;
          INSERT INTO eshop.payment_info(amount,deposit_amount,currency_code,created_at)
          VALUES(calculated_price,NULLIF(v_total_deposit,0),first_currency_code,now)
          RETURNING id INTO payment_info_id;


        END IF;

        PERFORM public.notification_center_prepared_invalidate_order(order_id);
        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        v_payment_instructions:=public.ensure_order_payment_instructions_internal(order_id);
        bank_account_id:=(v_payment_instructions->>'bank_account')::bigint;
        generated_variable_symbol:=(v_payment_instructions->>'variable_symbol')::bigint;
        generated_creditor_reference:=v_payment_instructions->>'creditor_reference';
        account_number:=v_payment_instructions->>'account_number';
        account_number_human_readable:=v_payment_instructions->>'account_number_human_readable';
        creditor_name:=v_payment_instructions->>'creditor_name';

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- NULL inherits the occasion default; zero is an explicit immediate deadline.
          form_deadline_duration := coalesce(form_deadline_duration,
            (SELECT (feature->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) feature WHERE feature->>'code'='form'),604800);
          -- Calculate deadline if deadline duration is provided
          IF v_payment_method='stripe' THEN
              v_stripe_attempt:=public.create_stripe_order_attempt_internal(order_id);
              SELECT reservation_expires_at INTO deadline FROM eshop.stripe_checkout_attempts WHERE id=v_stripe_attempt;
          ELSIF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- One queue boundary resolves form and occasion reminder settings.
                    PERFORM public.queue_payment_reminders_internal(occasion_id,payment_info_id);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'payment',public.stripe_order_payment_projection_internal(order_id),
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'payment_method',v_payment_method,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN SQLERRM = 'STRIPE_RECIPIENT_CHANGED' THEN
                JSONB_BUILD_OBJECT('code',409,'errorCode','STRIPE_RECIPIENT_CHANGED',
                    'message','The payment recipient changed. Review the current form.')
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    PERFORM public.notification_center_order_capacity_internal(order_id);
    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;


-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT (EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now())
  OR EXISTS(SELECT 1 FROM public.email_capacity WHERE quota_at IS NULL OR quota_at<now()-interval '5 minutes')) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 p_recipient:=public.normalize_order_email_contact(p_recipient);
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer','sale_opening_opened')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer','sale_opening_opened')) AND
    (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=v_org)='en' THEN
   p_data:=coalesce(p_data,'{}'::jsonb)||'{"lang":"en"}'::jsonb;
 END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',p_data-'requested_by','code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE organization=v_org AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 PERFORM public.admit_email_intent_v1(v_row.id);
 PERFORM public.notification_center_email_internal(v_row.message_id);
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.occasion_team_invitations i
   JOIN public.occasions o ON o.id=i.occasion AND o.unit=i.unit AND o.organization=i.organization
   JOIN public.unit_users uu ON uu.unit=i.unit AND uu."user"=i.created_by AND uu.is_manager
   WHERE i.message_id=p_message.message_id AND i.accepted_at IS NULL AND i.expires_at>now()
    AND i.email=p_message.recipient AND i.occasion=p_message.occasion AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id'
      AND public.bank_sync_alert_ready(c.id)
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_confirmation' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_opened' THEN
  RETURN public.sale_opening_intent_valid_internal(p_message);
 END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.data->>'repair_payment_fingerprint' IS NOT NULL AND p_message.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(v_order.id) THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND payment_method='stripe')
   AND public.stripe_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_confirmation' THEN
  RETURN public.order_checkout_email_kind_internal(v_order.id)='order_confirmation'
   AND v_order.state IN ('ordered','paid') AND v_order.email_payment_version=p_message.source_version
   AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method='stripe' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid(); v_wait integer;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now() WHERE singleton;
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT (x->>'base_limit')::integer INTO v_wait FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.dispatch',NULL,NULL)->'rules') x;
 IF v_wait IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY CASE WHEN m.created_at<=now()-make_interval(secs=>v_wait) THEN 0 ELSE priority END,
 (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.last_claimed_at IS NOT NULL) NULLS FIRST,
 CASE WHEN m.unit IS NULL THEN (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.unit IS NULL AND served.last_claimed_at IS NOT NULL)
 ELSE (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.unit=m.unit AND served.last_claimed_at IS NOT NULL) END NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error='intent_invalid' WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',last_claimed_at=now(),lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF octet_length(p_prepared::text)>(SELECT (x->>'base_limit')::bigint
  FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.payload',NULL,NULL)->'rules') x LIMIT 1) THEN
  RAISE configuration_limit_exceeded USING MESSAGE='email_payload_too_large'; END IF;
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=p_message),true);
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric; v_detail text; v_retry integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.forms f JOIN public.sale_opening_campaigns c ON c.form_id=f.id
  JOIN public.email_messages m ON m.data->>'campaign_id'=c.id::text
  JOIN public.email_attempts a ON a.message_id=m.message_id
  WHERE a.attempt_id=p_attempt AND m.message_kind IN ('sale_opening_opened') FOR UPDATE OF f;
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET last_error=CASE WHEN v_row.message_kind='sale_opening_opened' THEN 'intent_invalid' ELSE last_error END,workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  PERFORM public.notification_center_email_internal(v_row.message_id);
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 -- A partial acceptance can change a queued offer after its rendered snapshot
 -- was cached. Re-render within this same queue before granting a send permit.
 IF v_row.message_kind='waitlist_offer' AND
  (v_row.post_action->>'waitlist_pending_count')::bigint IS DISTINCT FROM
  (SELECT count(*) FROM eshop.waitlist_offer_slots
   WHERE offer_id=(v_row.data->>'offer_id')::uuid AND outcome='pending') THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),
   prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'waitlist_pending_count',lease_token=NULL,lease_until=NULL,
   last_error='offer_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),
   error_code='offer_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Recipient admission at enqueue does not protect against many future intents
 -- converging on one date. Meter the actual fenced send, with separate essential
 -- classes so ordinary bulk cannot consume Auth or accepted-order capacity.
 BEGIN
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.'||v_row.admission_class,v_row.unit,v_row.organization),
   jsonb_build_object('recipient',public.abuse_recipient_key_v1(v_row.recipient)));
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
  v_retry:=greatest(coalesce((v_detail::jsonb->>'retryAfterSeconds')::integer,60),1);
  UPDATE public.email_messages SET workflow_state='pending',target_time=now()+make_interval(secs=>v_retry),lease_token=NULL,lease_until=NULL,last_error='recipient_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='recipient_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
 UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
END $$;

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision) WHERE singleton; END IF;
  PERFORM public.notification_center_email_internal(v_m.message_id);
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
 PERFORM public.notification_center_email_internal(v_m.message_id);
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  PERFORM public.notification_center_email_internal(v_event.message_id);
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05) WHERE singleton;
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100) WHERE singleton;END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete','sale_opening_opened')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.email_messages m JOIN public.notification_center_events e
  ON e.organization=m.organization AND e.kind='email_problem' AND e.data->>'messageId'=m.message_id::text
  WHERE m.message_kind='sale_opening_opened' AND m.expires_at<now()-interval '30 days' AND m.workflow_state NOT IN ('sending','unknown') AND m.recipient IS NOT NULL;
 UPDATE public.email_messages SET recipient=NULL,prepared=NULL,data='{}'
 WHERE message_kind IN ('sale_opening_opened') AND expires_at<now()-interval '30 days'
 AND workflow_state NOT IN ('sending','unknown');
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;


-- SOURCE: notification_center/prepared_operations.sql
CREATE OR REPLACE FUNCTION public.get_notification_center_projection_health(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization) THEN RAISE invalid_parameter_value USING MESSAGE='notification_organization_required'; END IF;
 SELECT jsonb_build_object('organization',p_organization,'scopes',count(*),'backfilling',count(*) FILTER(WHERE phase<>'ready'),
  'failed',count(*) FILTER(WHERE quarantined),'pendingDelivery',coalesce(sum(pending_delivery),0),'pendingSourceRepairs',coalesce(sum(pending_events),0),
  'pendingReadRepairs',coalesce(sum(pending_groups),0),'privacyRepairs',count(*) FILTER(WHERE privacy_pending),
  'expiryDebt',count(*) FILTER(WHERE next_expiry<clock_timestamp()),'oldestReadyAt',min(last_ready_at),
  'liveViews',(SELECT count(*) FROM public.notification_center_views WHERE organization=p_organization AND expires_at>clock_timestamp()),
  'expiredViews',(SELECT count(*) FROM public.notification_center_views WHERE organization=p_organization AND expires_at<=clock_timestamp()),
  'failedViewRows',(SELECT count(*) FROM public.notification_center_view_rows r JOIN public.notification_center_views v ON v.token=r.token WHERE v.organization=p_organization AND r.quarantined))
 INTO result FROM public.notification_center_projection_scopes WHERE organization=p_organization;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_projection_health(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_center_projection_health(bigint) TO service_role;
CREATE OR REPLACE FUNCTION public.retry_notification_center_projection(p_organization bigint,p_recipient uuid DEFAULT NULL,p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization) THEN RAISE invalid_parameter_value USING MESSAGE='notification_organization_required'; END IF;
 UPDATE public.notification_center_projection_scopes SET retry_count=0,last_error_code=NULL,quarantined=false,next_check_at='-infinity'
 WHERE (organization,recipient) IN(SELECT organization,recipient FROM public.notification_center_projection_scopes
  WHERE organization=p_organization AND (p_recipient IS NULL OR recipient=p_recipient)
  ORDER BY recipient LIMIT greatest(1,least(coalesce(p_limit,100),100)) FOR UPDATE SKIP LOCKED);
 GET DIAGNOSTICS n=ROW_COUNT;
 UPDATE public.notification_center_view_rows SET retry_count=0,last_error_code=NULL,quarantined=false,next_attempt_at='-infinity'
 WHERE (token,position) IN(SELECT r.token,r.position FROM public.notification_center_view_rows r JOIN public.notification_center_views v ON v.token=r.token
  WHERE v.organization=p_organization AND (p_recipient IS NULL OR v.recipient=p_recipient) AND r.quarantined ORDER BY r.token,r.position LIMIT 100 FOR UPDATE OF r SKIP LOCKED);
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.retry_notification_center_projection(bigint,uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.retry_notification_center_projection(bigint,uuid,integer) TO service_role;
CREATE OR REPLACE FUNCTION public.set_notification_center_prepared_paused(p_organization bigint,p_paused boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 UPDATE public.notification_center_organizations SET prepared_paused=coalesce(p_paused,true) WHERE organization=p_organization;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='notification_organization_required'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.set_notification_center_prepared_paused(bigint,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_notification_center_prepared_paused(bigint,boolean) TO service_role;
NOTIFY pgrst,'reload schema';


-- SOURCE: eshop_orders/update_order_and_tickets_to_storno.sql
CREATE OR REPLACE FUNCTION public.cancel_order_domain_internal_v1(order_id BIGINT,p_notify boolean)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
    v_order eshop.orders;
    v_occasion public.occasions;
    v_notice jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=order_id)]);
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=order_id FOR UPDATE;
    IF v_order.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
    IF v_order.state='storno' THEN RETURN; END IF;
    PERFORM public.check_order_is_mutable(order_id);
    -- Card finances and admission are resolved by provider facts and the
    -- audited refund decision, never by resetting an order's original price.
    IF EXISTS(SELECT 1 FROM eshop.payment_info pi
      WHERE pi.id=v_order.payment_info AND pi.payment_method='stripe') THEN
        RAISE EXCEPTION 'STRIPE_USE_REFUND_ADMISSION_DECISION';
    END IF;
    PERFORM public.cancel_order_email_intents(order_id);
    -- Retrieve all ticket ids associated with the order
    SELECT ARRAY_AGG(t.id) INTO ticket_ids
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = order_id;

    -- Check if the order exists and has associated tickets
    IF ticket_ids IS NULL THEN
        -- This is not an error, just an order with no tickets yet.
        -- But we can still storno the order itself.
        RAISE NOTICE 'No tickets found for order %, proceeding to storno order shell.', order_id;
    END IF;

    -- Call the helper to storno all tickets and their relations
    -- The helper function gracefully handles an empty/NULL array
    PERFORM internal_storno_tickets_221(ticket_ids);

    -- Set the order state to 'storno', price to 0, and update the data field
    UPDATE eshop.orders
    SET state = 'storno',
        price = 0,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('tickets', '[]'::jsonb),
        updated_at = NOW()
    WHERE id = order_id
    RETURNING data INTO updated_order_data;
    PERFORM public.notification_center_order_state_internal(order_id);

    -- Finish the original email recovery task in the same cancellation transaction.
    -- Keep provider messages and delivery history intact.
    UPDATE public.notification_center_events e SET status='recovered'
    FROM public.email_messages m
    WHERE m.order_id=v_order.id AND m.occasion=v_order.occasion
      AND m.message_kind<>'order_storno' AND e.organization=m.organization
      AND e.kind='email_problem' AND e.source_key='email:'||m.message_id;


    -- Save the change to orders_history by inserting the updated order row
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        order_id,
        'storno',
        0,
        updated_order_data,
        NOW()
    );

    -- The full transition owns the durable automatic commitment for every caller.
    SELECT * INTO v_occasion FROM public.occasions WHERE id=v_order.occasion;
    IF p_notify AND position('@' in v_order.data->>'email')>0
      AND length(v_order.data->>'email')<=320 THEN
      v_notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',
        jsonb_build_object('order_id',order_id),v_occasion.organization,
        v_occasion.id,v_occasion.unit);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_order_domain_internal_v1(bigint,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
-- Compatibility for trusted SQL callers; domain logic exists only above.
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_221(order_id bigint)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.cancel_order_domain_internal_v1(order_id,true);
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_221(bigint)
 FROM PUBLIC,anon,authenticated,service_role;


-- SOURCE: seed/crons.sql
CREATE OR REPLACE FUNCTION setup_crons(p_project_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $func$
BEGIN
  -- Security Check
  IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
      RAISE EXCEPTION 'Access Denied: Service role required.';
  END IF;

  -- Schedule the apply_planned_changes cron job (runs every minute)
  PERFORM cron.schedule(
    'apply_planned_changes',
    '*/1 * * * *',
    'SELECT apply_planned_changes()'
  );

  -- BankSync owns bank polling. This job recovers durable control intents.
  -- Scoped health observation is configured explicitly with configure_bank_sync_health_monitor.
  PERFORM cron.schedule('festapp_canonical_bank_sync_reconcile','*/5 * * * *',
    format($$SELECT net.http_post(url:='%s/functions/v1/bank-sync-reconcile',
      body:=jsonb_build_object('requestSecret',public.generate_request_secret(3600)),
      timeout_milliseconds:=360000)$$,p_project_url));

  -- The protected worker alternates delivery/repair/backfill with a commit per RPC.
  -- Retire direct, co-timed drains to avoid starving a work class on the lease.
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname IN ('festapp_canonical_notification_center_delivery','festapp_canonical_notification_center_prepare');
  PERFORM public.configure_notification_center_worker(p_project_url);
  PERFORM cron.schedule('festapp_canonical_notification_center_wake','1 second','SELECT public.wake_notification_center()');
  PERFORM cron.schedule('festapp_canonical_notification_center_project','*/1 * * * *','SELECT public.maintain_notification_center(100)');
  PERFORM cron.schedule('festapp_canonical_sale_opening_notifications','*/1 * * * *','SELECT public.maintain_sale_opening_notifications(100)');
  PERFORM cron.schedule('festapp_canonical_waitlist_expiry','*/1 * * * *','SELECT public.expire_waitlist_offers(100)');
  PERFORM cron.schedule('festapp_canonical_process_email_queue','*/1 * * * *','SELECT public.recover_email_delivery()');
END;
$func$;

COMMIT;
