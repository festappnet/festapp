CREATE OR REPLACE FUNCTION public.notification_center_active_internal(p_org bigint) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-activation:'||p_org,0));
 RETURN EXISTS(SELECT 1 FROM public.notification_center_activation WHERE organization=p_org AND enabled);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_active_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
-- Runs under the existing form/product/inventory locks, never takes a recipient lock.
CREATE OR REPLACE FUNCTION public.notification_center_capacity_transition_internal(p_org bigint,p_occ bigint,p_key text,p_snapshot jsonb,p_actor uuid DEFAULT auth.uid(),p_cause uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE old public.notification_center_source_state; nc_episode bigint; next_state jsonb; crossing text; high boolean; remaining bigint; lim bigint; used bigint; event uuid;
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-activation:'||p_org,0));
 PERFORM 1 FROM public.notification_center_activation WHERE organization=p_org AND enabled FOR SHARE;
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
  INSERT INTO public.notification_center_source_state VALUES(p_org,p_key,next_state,0,clock_timestamp()) ON CONFLICT DO NOTHING;
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
 IF NOT public.notification_center_active_internal(org) THEN RETURN; END IF;
 PERFORM public.notification_center_capacity_transition_internal(org,f.occasion,'form:'||f.id,
 public.get_form_capacity_snapshot_internal(f.id)||jsonb_build_object('formId',f.id,'title',f.title),p_actor,p_cause);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_product_capacity_internal(p_product bigint,p_actor uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE p eshop.products; org bigint; used bigint;
BEGIN
 SELECT * INTO p FROM eshop.products WHERE id=p_product;
 SELECT organization INTO org FROM public.occasions WHERE id=p.occasion;
 IF NOT public.notification_center_active_internal(org) THEN RETURN; END IF;
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
 IF NOT public.notification_center_active_internal(org) THEN RETURN; END IF;
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
 IF NOT public.notification_center_active_internal(bp.organization) THEN RETURN; END IF;
 SELECT count(*),count(*) FILTER(WHERE s.order_product_ticket IS NOT NULL) INTO lim,occupied
 FROM eshop.spots s WHERE s.blueprint=bp.id AND s.occasion=bp.occasion AND s.id IN
 (SELECT (o->>'id')::bigint FROM jsonb_array_elements(bp.objects) o WHERE o->>'type'='spot' AND o->>'id' IS NOT NULL);
 PERFORM public.notification_center_capacity_transition_internal(bp.organization,bp.occasion,'blueprint:'||bp.id,
 jsonb_build_object('blueprintId',bp.id,'title',bp.title,'limit',lim,'remainingPublic',greatest(lim-occupied,0)),p_actor);
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_capacity_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE item record; bp bigint; org bigint;
BEGIN
 SELECT oc.organization INTO org FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
 IF NOT public.notification_center_active_internal(org) THEN RETURN; END IF;
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
