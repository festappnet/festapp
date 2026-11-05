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
  EXISTS(SELECT 1 FROM public.notification_center_prepared_batch_at(e,d,p_capture_at) b WHERE (b.batch_id=regexp_replace(p_id,':(read|unread)$','') OR (p_id=p_group||':history:read' AND p_capture_read)) AND b.is_read=p_capture_read) END
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
