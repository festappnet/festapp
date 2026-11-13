-- Private invokers inherit only the existing authorized domain definer.
CREATE OR REPLACE FUNCTION public.enqueue_ticket_wallet_internal(p_tickets bigint[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE w eshop.ticket_wallet_objects;
BEGIN
 FOR w IN SELECT * FROM eshop.ticket_wallet_objects WHERE ticket_id=ANY(p_tickets) ORDER BY ticket_id LOOP
  INSERT INTO eshop.ticket_wallet_work(kind,resource,organization,occasion,ticket_id)
  VALUES('object',w.object_id,w.organization,w.occasion,w.ticket_id)
  ON CONFLICT(provider,kind,resource) DO UPDATE SET requested=ticket_wallet_work.requested+1,
   due_at=least(ticket_wallet_work.due_at,now()),
   dirty_since=CASE WHEN ticket_wallet_work.requested=ticket_wallet_work.applied THEN now() ELSE ticket_wallet_work.dirty_since END;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_order_wallet_internal(p_order bigint)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.enqueue_ticket_wallet_internal(ARRAY(SELECT DISTINCT ticket FROM eshop.order_product_ticket WHERE "order"=p_order ORDER BY ticket));
$$;
CREATE OR REPLACE FUNCTION public.enqueue_wallet_scope_internal(p_occasion bigint DEFAULT NULL,p_organization bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE org bigint; scope_kind text; scope_id bigint;
BEGIN
 IF p_occasion IS NOT NULL THEN
  SELECT organization INTO org FROM public.occasions WHERE id=p_occasion;
  scope_kind:='occasion';scope_id:=p_occasion;
 ELSE org:=p_organization;scope_kind:='organization';scope_id:=p_organization; END IF;
 IF org IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=org) THEN RETURN; END IF;
 INSERT INTO eshop.ticket_wallet_work(kind,resource,organization,occasion)
 VALUES(scope_kind,scope_id::text,org,p_occasion)
 ON CONFLICT(provider,kind,resource) DO UPDATE SET requested=ticket_wallet_work.requested+1,
 due_at=least(ticket_wallet_work.due_at,now()),
 dirty_since=CASE WHEN ticket_wallet_work.requested=ticket_wallet_work.applied THEN now() ELSE ticket_wallet_work.dirty_since END;
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_wallet_class_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE w eshop.ticket_wallet_objects;
BEGIN
 SELECT * INTO w FROM eshop.ticket_wallet_objects WHERE ticket_id=p_ticket;
 IF NOT FOUND THEN RETURN; END IF;
 INSERT INTO eshop.ticket_wallet_work(kind,resource,organization,occasion,ticket_id)
 VALUES('class',w.class_id,w.organization,w.occasion,w.ticket_id)
 ON CONFLICT(provider,kind,resource) DO UPDATE SET requested=ticket_wallet_work.requested+1,
 due_at=least(ticket_wallet_work.due_at,now()),
 dirty_since=CASE WHEN ticket_wallet_work.requested=ticket_wallet_work.applied THEN now() ELSE ticket_wallet_work.dirty_since END;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_wallet_internal(bigint[]),public.enqueue_order_wallet_internal(bigint),public.enqueue_wallet_scope_internal(bigint,bigint),public.enqueue_wallet_class_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
