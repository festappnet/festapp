-- Generated forward migration: notification-open-work-2026-11-05
-- Prerequisites: 20261021100000_canonical_authorization.sql, 20261024010000_organization_notification_center.sql, 20261024025000_notification_email_recipient.sql, 20261024120000_order_email_recovery.sql, 20261024220000_cancelled_order_email_alerts.sql, 20261024235000_notification_center_canonical_availability.sql, 20261026120000_notification_center_feed.sql, 20261026150000_notification_center_order_periods.sql, 20261026230000_notification_center_unread_snapshot.sql, 20261027210000_notification_center_overview.sql, 20261027220000_notification_center_daily_overview.sql, 20261027234500_notification_group_order_selection.sql, 20261028010000_notification_legacy_place_totals.sql, 20261028013000_notification_category_rollups.sql, 20261028020000_notification_center_lifecycle.sql, 20261028030000_notification_new_orders_exclude_cancelled.sql, 20261028120000_notification_center_current_rollups.sql, 20261028130000_notification_personal_read_batches.sql, 20261030093000_notification_deleted_entities.sql, 20261031110000_notification_current_participants.sql, 20261031120000_notification_center_source_alignment.sql, 20261101170000_hidden_participant_notifications.sql, 20261105070000_notification_subject_lookup_performance.sql, 20261105110000_notification_center_delivery_draining.sql, 20261105120000_notification_center_prepared_views.sql, 20261105181000_notification_prepared_retention.sql, 20261105190000_notification_prepared_scope_discovery.sql, 20261105203000_notification_idle_wake.sql
BEGIN;
DO $$ BEGIN IF to_regclass('public.notification_center_organizations') IS NULL OR to_regclass('public.notification_center_activation') IS NOT NULL OR to_regclass('public.notification_center_source_state') IS NULL OR to_regprocedure('public.get_notification_center_updates(bigint,bigint,uuid[])') IS NULL THEN RAISE EXCEPTION 'notification_feed_prerequisites_missing'; END IF; END $$;

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
 -- Candidate discovery reads current roles once. Payloads and selection still
 -- authorize each real event with notification_center_allowed before private reads.
 WITH admin AS MATERIALIZED(SELECT EXISTS(SELECT 1 FROM public.organization_users
  WHERE organization=p_org AND "user"=p_user AND is_admin) is_admin),
 members AS MATERIALIZED(SELECT m.occasion,bool_or(m.is_editor_order_view) orders,
  bool_or(public.participant_contacts_read_rule(m.is_editor,m.is_manager,false)) app
  FROM public.occasion_users m WHERE m."user"=p_user AND (m.is_editor_order_view OR m.is_editor OR m.is_manager)
  GROUP BY m.occasion),
 own AS MATERIALIZED(SELECT occasion id FROM members
  UNION SELECT o.id FROM public.occasions o,admin a WHERE o.organization=p_org AND a.is_admin),
 occasions AS MATERIALIZED(SELECT oc.id,CASE WHEN oc.id=p_current THEN 1 ELSE 2 END priority,
  coalesce(m.orders,false) AND d.occasion IS NULL orders,
  (a.is_admin OR coalesce(m.app,false)) AND d.occasion IS NULL app,
  a.is_admin OR (coalesce(m.orders,false) AND d.occasion IS NULL) email,
  coalesce(m.orders,false) bank
  FROM public.occasions oc JOIN own ON own.id=oc.id CROSS JOIN admin a
  LEFT JOIN members m ON m.occasion=oc.id
  LEFT JOIN public.demo_occasions d ON d.occasion=oc.id
  WHERE oc.organization=p_org),
 bank_access AS MATERIALIZED(SELECT bu.bank_account FROM eshop.bank_account_users bu
  WHERE bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user)
   AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
    WHERE uba.bank_account=bu.bank_account AND u.organization=p_org)),
 banks AS MATERIALIZED(SELECT c.id FROM eshop.bank_sync_connections c WHERE EXISTS(
  SELECT 1 FROM bank_access ba WHERE ba.bank_account=c.bank_account_id OR ba.bank_account IN(
   SELECT alias.bank_account_id FROM eshop.bank_sync_account_aliases alias WHERE alias.connection_id=c.id)))
 SELECT 'orders:'||id,priority FROM occasions WHERE orders
 UNION ALL SELECT 'app:'||id,priority FROM occasions WHERE app
 UNION ALL SELECT 'email-admin:'||id,priority FROM occasions WHERE email
 UNION ALL SELECT 'email-admin:shared',0 FROM admin WHERE is_admin
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
-- The scope vector is derived from live roles inside the payload's SQL snapshot.
-- Private subject visibility remains per event; no role result survives a request.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_event_access(e public.notification_center_events,p_org bigint,p_scopes text[])
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(e.organization=p_org AND public.notification_center_subject_visible_internal(e.organization,e.kind,e.data) AND
 CASE WHEN e.kind IN ('occasion_joined','event_capacity_full') THEN ('app:'||e.occasion)=ANY(p_scopes)
 WHEN e.kind='email_problem' THEN 'email-admin:shared'=ANY(p_scopes) OR ('email-admin:'||e.occasion)=ANY(p_scopes)
 WHEN e.kind='bank_problem' THEN ('bank:'||(e.data->>'bankConnectionId'))=ANY(p_scopes)
  OR EXISTS(SELECT 1 FROM unnest(e.affected_occasions) oc WHERE ('bank-occasion:'||oc)=ANY(p_scopes))
 ELSE ('orders:'||e.occasion)=ANY(p_scopes)
  OR EXISTS(SELECT 1 FROM unnest(e.affected_occasions) oc WHERE ('orders:'||oc)=ANY(p_scopes)) END,false);
$$;
DROP FUNCTION IF EXISTS public.notification_center_prepared_render(public.notification_center_view_rows,public.notification_center_views);
CREATE OR REPLACE FUNCTION public.notification_center_prepared_render(r public.notification_center_view_rows,v public.notification_center_views,p_scopes text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; d public.notification_center_deliveries; dto jsonb; contact jsonb; previews jsonb; payload jsonb; grouped boolean;
BEGIN
 IF r.state<>'ready' THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state',r.state); END IF;
 SELECT * INTO e FROM public.notification_center_events WHERE id=r.latest_event;
 IF NOT FOUND OR e.organization<>v.organization OR NOT (CASE WHEN p_scopes IS NULL THEN public.notification_center_allowed(e,auth.uid())
  ELSE public.notification_center_prepared_event_access(e,v.organization,p_scopes) END) THEN RETURN jsonb_build_object('id',r.id,'position',r.position,'state','removed'); END IF;
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
DROP FUNCTION IF EXISTS public.notification_center_prepared_display_key(uuid,integer,integer);
CREATE OR REPLACE FUNCTION public.notification_center_prepared_display_key(p_token uuid,p_cursor integer,p_limit integer,p_scopes text[] DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH owned AS MATERIALIZED(SELECT * FROM public.notification_center_views WHERE token=p_token AND recipient=auth.uid()),
 rights AS MATERIALIZED(SELECT v.organization,coalesce(p_scopes,ARRAY(SELECT a.scope FROM public.notification_center_prepared_allowed_scopes(v.organization,v.current_occasion,v.recipient) a ORDER BY a.scope)) scopes FROM owned v),
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
  FROM rows r CROSS JOIN rights ac CROSS JOIN LATERAL unnest(r.preview_events) WITH ORDINALITY p(id,position)
  JOIN LATERAL(SELECT permitted.*,permitted.xmin::text event_xid,permitted.ctid::text event_tid FROM public.notification_center_events permitted WHERE permitted.id=p.id AND public.notification_center_prepared_event_access(permitted,ac.organization,ac.scopes) OFFSET 0) ev ON true
  LEFT JOIN eshop.orders o ON o.occasion=ev.occasion AND o.id=CASE WHEN ev.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (ev.data->>'orderId')::bigint END
  LEFT JOIN public.email_messages m ON m.organization=ev.organization AND m.message_id=CASE WHEN ev.data->>'messageId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (ev.data->>'messageId')::uuid END
  LEFT JOIN eshop.orders mo ON mo.id=m.order_id AND mo.occasion=m.occasion
  LEFT JOIN public.user_info ui ON ui.organization=ev.organization AND ui.id=coalesce(m.recipient_user,CASE WHEN ev.data->>'userId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (ev.data->>'userId')::uuid END)
  LEFT JOIN public.occasions oc ON oc.id=ev.occasion AND oc.organization=ev.organization)
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(jsonb_build_array(position,row_xid,row_tid) ORDER BY position) FROM rows),
  (SELECT jsonb_agg(to_jsonb(f) ORDER BY position,preview) FROM facts f),
  (SELECT to_jsonb(scopes) FROM rights))::text);
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
 rights AS MATERIALIZED(SELECT o.token,ARRAY(SELECT a.scope FROM public.notification_center_prepared_allowed_scopes(o.organization,o.current_occasion,o.recipient) a ORDER BY a.scope) scopes FROM status o WHERE NOT o.preparing),
 keyed AS MATERIALIZED(SELECT o.*,a.scopes,CASE WHEN o.preparing THEN NULL ELSE public.notification_center_prepared_display_key(o.token,p_cursor,p_limit,a.scopes) END display_key FROM status o LEFT JOIN rights a USING(token))
 SELECT jsonb_build_object('viewSupported',true,'state',CASE WHEN o.expires_at<=clock_timestamp() THEN 'expired' WHEN o.preparing THEN 'preparing' ELSE 'ready' END,
  'viewToken',o.token,'snapshot',o.snapshot,'snapshotAt',o.anchor,'snapshotDay',(o.anchor AT TIME ZONE o.timezone)::date,'timezone',o.timezone,
  'previousReadThrough',o.previous_seen,'acknowledged',o.acknowledged,'truncated',o.truncated,
  'revision',o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key,
  'unchanged',NOT o.preparing AND p_revision=(o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key),
  'items',CASE WHEN o.expires_at<=clock_timestamp() OR (NOT o.preparing AND p_revision=(o.current_revision::text||':'||o.current_read_revision::text||':'||o.current_privacy||':'||o.display_key)) THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(
   CASE WHEN o.preparing THEN jsonb_build_object('id',r.id,'position',r.position,'state','preparing')
   ELSE public.notification_center_prepared_render(r,ROW(o.token,o.organization,o.recipient,o.current_occasion,o.timezone,o.snapshot,o.anchor,o.previous_seen,o.source_revision,o.read_revision,o.privacy_key,o.created_at,o.expires_at,o.acknowledged,o.truncated)::public.notification_center_views,o.scopes) END ORDER BY r.position)
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
     ranked AS MATERIALIZED(SELECT *,row_number() OVER(ORDER BY section,latest_at DESC,id DESC) position FROM candidates ORDER BY section,latest_at DESC,id DESC LIMIT 101),
     inserted AS(INSERT INTO public.notification_center_view_rows(token,position,id,group_key,after_sequence,through_sequence,kind,occasion,latest_at,latest_event,preview_events,capture_is_read,
      activity_count,known_count,places,multiple_count,is_read,revision,read_revision,privacy_key)
     SELECT token,r.position,r.id,b.group_key,least(b.after_sequence,b.first_sequence-1),b.through_sequence,b.kind,b.occasion,b.latest_at,b.latest_event,b.preview_events,b.is_read,
      b.activity_count,b.known_count,b.places,b.multiple_count,b.is_read,s.revision,u.view_read_revision,md5(s.privacy::text)
      FROM ranked r JOIN public.notification_center_batch_summaries b ON b.organization=p_organization AND b.recipient=auth.uid() AND b.id=r.id WHERE r.position<=100 RETURNING 1)
     -- Catalogue rows and truncation share one authorized candidate discovery.
     SELECT (SELECT count(*) FROM ranked) INTO total FROM (SELECT count(*) FROM inserted) completed;
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
  'lastSequence',last_delivery_sequence,'unread',CASE WHEN preparing THEN NULL WHEN last_delivery_sequence<=seen THEN false ELSE EXISTS(
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

COMMIT;
