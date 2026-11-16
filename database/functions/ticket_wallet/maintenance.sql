-- Bounded, restartable fanout. A new scope version resets the cursor on its next batch.
CREATE OR REPLACE FUNCTION public.maintain_ticket_wallet(p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s eshop.ticket_wallet_work; w eshop.ticket_wallet_objects; n integer:=0; last_id bigint; batch_size integer:=greatest(1,least(1000,p_limit));
BEGIN
 PERFORM public.require_service_role();
 -- Idempotent adoption includes never-synced, deleted and uncertain identities.
 -- No fake applied version. Legacy leases must have drained before cutover.
 FOR w IN SELECT o.* FROM eshop.ticket_wallet_objects o WHERE NOT EXISTS(
  SELECT 1 FROM eshop.ticket_wallet_work q WHERE q.kind='object' AND q.resource=o.object_id) OR NOT EXISTS(
  SELECT 1 FROM eshop.ticket_wallet_work cls WHERE cls.kind='class' AND cls.resource=o.class_id)
  ORDER BY o.ticket_id LIMIT batch_size LOOP
  PERFORM public.refresh_ticket_wallet_term_internal(w.ticket_id);
  PERFORM public.enqueue_wallet_class_internal(w.ticket_id);
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[w.ticket_id]);n:=n+1;
 END LOOP;
 SELECT * INTO s FROM eshop.ticket_wallet_work WHERE kind IN ('occasion','organization') AND requested>applied AND due_at<=now()
 ORDER BY dirty_since,kind,resource LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF FOUND THEN
  IF s.cursor_version<>s.requested THEN s.cursor_ticket:=0; END IF;
  last_id:=s.cursor_ticket;
  FOR w IN SELECT * FROM eshop.ticket_wallet_objects WHERE organization=s.organization
   AND (s.kind='organization' OR occasion=s.occasion) AND ticket_id>s.cursor_ticket ORDER BY ticket_id LIMIT batch_size LOOP
   PERFORM public.refresh_ticket_wallet_term_internal(w.ticket_id);
   PERFORM public.enqueue_wallet_class_internal(w.ticket_id);
   PERFORM public.enqueue_ticket_wallet_internal(ARRAY[w.ticket_id]);last_id:=w.ticket_id;n:=n+1;
  END LOOP;
  UPDATE eshop.ticket_wallet_work SET cursor_ticket=last_id,cursor_version=s.requested,captured=s.requested,
   applied=CASE WHEN NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_objects WHERE organization=s.organization AND
    (s.kind='organization' OR occasion=s.occasion) AND ticket_id>last_id) THEN s.requested ELSE applied END
   WHERE provider=s.provider AND kind=s.kind AND resource=s.resource;
 END IF;
 -- Class repair is independently fenced; never acquire a class after object work.
 FOR s IN SELECT * FROM eshop.ticket_wallet_work WHERE kind='class' AND repair_at<=now()
  ORDER BY repair_at,resource LIMIT batch_size FOR UPDATE SKIP LOCKED LOOP
  UPDATE eshop.ticket_wallet_work SET requested=requested+1,due_at=least(due_at,now()),
   dirty_since=CASE WHEN requested=applied THEN now() ELSE dirty_since END,repair_at=now()+interval '1 day'
   WHERE provider=s.provider AND kind=s.kind AND resource=s.resource;
 END LOOP;
 -- Slow remote repair and precise time transitions use the same work owner.
 FOR s IN SELECT * FROM eshop.ticket_wallet_work WHERE kind='object'
  AND (repair_at<=now() OR boundary_at<=now()) ORDER BY least(repair_at,coalesce(boundary_at,repair_at)),resource LIMIT batch_size FOR UPDATE SKIP LOCKED LOOP
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[s.ticket_id]);
  UPDATE eshop.ticket_wallet_work SET repair_at=now()+interval '1 day',boundary_at=NULL WHERE provider=s.provider AND kind=s.kind AND resource=s.resource;
  n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('scheduled',n);
END $$;
REVOKE ALL ON FUNCTION public.maintain_ticket_wallet(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.maintain_ticket_wallet(integer) TO service_role;
