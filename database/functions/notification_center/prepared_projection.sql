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
 banks AS MATERIALIZED(SELECT DISTINCT c.id FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts uba
  ON uba.bank_account=c.bank_account_id OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
  JOIN public.units u ON u.id=uba.unit AND u.organization=p_org
  WHERE public.notification_center_allowed(jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',p_org,'kind','bank_problem','data',jsonb_build_object('bankConnectionId',c.id),'affected_occasions','[]'::jsonb)),p_user))
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
