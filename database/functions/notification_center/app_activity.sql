-- Trusted producers and recipient authorization for program/occasion activity.
CREATE OR REPLACE FUNCTION public.notification_center_app_admin_internal(p_org bigint,p_occ bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_user IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions o
 WHERE o.id=p_occ AND o.organization=p_org AND NOT public.is_demo_occasion(o.id)
 AND (EXISTS(SELECT 1 FROM public.organization_users m WHERE m.organization=p_org AND m."user"=p_user AND m.is_admin)
 OR EXISTS(SELECT 1 FROM public.occasion_users m WHERE m.occasion=o.id AND m."user"=p_user
 AND public.participant_contacts_read_rule(m.is_editor,m.is_manager,false))));
$$;
REVOKE ALL ON FUNCTION public.notification_center_app_admin_internal(bigint,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Called under the event row lock, before and after successful attendance changes.
-- A silent first observation also supports events created after activation.
CREATE OR REPLACE FUNCTION public.notification_center_event_capacity_internal(p_event bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ev public.events; org bigint; occupied bigint; males bigint; females bigint; capacity bigint; remaining bigint; full_now boolean; prior public.notification_center_source_state;
 key text:='schedule-event:'||p_event; nc_episode bigint; notification uuid; snapshot jsonb; day_key text;
BEGIN
 SELECT * INTO ev FROM public.events WHERE id=p_event;
 IF NOT FOUND THEN RETURN; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=ev.occasion;
 IF NOT public.notification_center_active_internal(org) OR public.is_demo_occasion(ev.occasion) THEN RETURN; END IF;
 SELECT count(*),count(*) FILTER(WHERE u.sex='male'),count(*) FILTER(WHERE u.sex<>'male')
 INTO occupied,males,females FROM public.event_users m LEFT JOIN public.user_info u ON u.id=m."user" WHERE m.event=ev.id;
 capacity:=CASE WHEN ev.split_for_men_women THEN 2*(ev.max_participants/2) ELSE ev.max_participants END;
 remaining:=CASE WHEN ev.split_for_men_women THEN greatest(ev.max_participants/2-males,0)+greatest(ev.max_participants/2-females,0)
 ELSE greatest(ev.max_participants-occupied,0) END;
 full_now:=coalesce(ev.max_participants>0 AND remaining=0,false);
 snapshot:=jsonb_build_object('eventId',ev.id,'title',ev.title,'limit',capacity,
   'remainingPublic',CASE WHEN ev.max_participants>0 THEN remaining END,'full',full_now);
 SELECT * INTO prior FROM public.notification_center_source_state WHERE organization=org AND source_key=key FOR UPDATE;
 IF NOT FOUND THEN
   INSERT INTO public.notification_center_source_state(organization,source_key,state) VALUES(org,key,snapshot);
   RETURN;
 END IF;
 nc_episode:=prior.episode;
 day_key:=key||':day:'||(clock_timestamp() AT TIME ZONE (SELECT timezone FROM public.notification_center_activation WHERE organization=org))::date;
 IF full_now AND NOT coalesce((prior.state->>'full')::boolean,false) THEN
   nc_episode:=nc_episode+1;
   notification:=public.notification_center_publish_internal(org,ev.occasion,'event_capacity_full',
     day_key,snapshot,p_actor);
   UPDATE public.notification_center_events SET status='active',data=data||snapshot WHERE id=notification;
 ELSIF NOT full_now AND coalesce((prior.state->>'full')::boolean,false) THEN
   UPDATE public.notification_center_events SET status='recovered',data=data||snapshot
   WHERE id=(prior.state->>'notificationId')::uuid;
 END IF;
 UPDATE public.notification_center_source_state SET state=snapshot||jsonb_build_object('notificationId',coalesce(notification::text,prior.state->>'notificationId')),episode=nc_episode,observed_at=clock_timestamp()
 WHERE organization=org AND source_key=key;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_event_capacity_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
