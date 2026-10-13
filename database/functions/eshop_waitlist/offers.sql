DROP FUNCTION IF EXISTS public.expire_waitlist_form_internal(bigint,timestamptz);
CREATE OR REPLACE FUNCTION public.expire_waitlist_form_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp(),p_limit integer DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 WITH expired AS (UPDATE eshop.waitlist_offer_slots s SET outcome='expired',updated_at=p_at
 FROM eshop.waitlist_offers w WHERE w.id=s.offer_id AND w.form_id=p_form AND w.expires_at<=p_at AND s.outcome='pending'
 AND s.id IN(SELECT x.id FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers y ON y.id=x.offer_id WHERE y.form_id=p_form AND y.expires_at<=p_at AND x.outcome='pending' ORDER BY x.id LIMIT p_limit)
 RETURNING s.participant_id)
 UPDATE eshop.order_participants SET lifecycle='offer_expired',queue_at=p_at,updated_at=p_at WHERE id IN(SELECT participant_id FROM expired);
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n>0 THEN
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=p_form;
  UPDATE eshop.waitlist_capabilities SET revoked_at=p_at WHERE form_id=p_form AND kind='offer' AND expires_at<=p_at AND revoked_at IS NULL;
 END IF;
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_proposal(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; proposals jsonb; available integer;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 PERFORM 1 FROM public.forms WHERE id=f.id FOR UPDATE;
 PERFORM public.expire_waitlist_form_internal(f.id);
 c:=public.get_form_capacity_snapshot_internal(f.id); available:=(c->>'offerablePlaces')::integer;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',current_order_id,'count',offered,'waitingCount',total) ORDER BY first_queue,current_order_id),'[]') INTO proposals
 FROM (SELECT current_order_id,min(queue_at) first_queue,count(*) total,
  count(*) FILTER(WHERE position<=available) offered FROM
  (SELECT p.*,row_number() OVER(ORDER BY queue_at,registered_at,id) position FROM eshop.order_participants p
   WHERE form_id=f.id AND lifecycle='waiting') ranked GROUP BY current_order_id) grouped WHERE offered>0;
 RETURN jsonb_build_object('code',200,'formId',f.id,'revision',c->'revision','capacity',c,'recipients',proposals,
 'offerDurationSeconds',f.waitlist_offer_duration_seconds,'serverTime',clock_timestamp());
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_waitlist_email_internal(p_order bigint,p_offer uuid,p_command uuid,p_delivery jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; result jsonb; expiry timestamptz; code text; kind text;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order; SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 code:=CASE WHEN p_offer IS NULL THEN 'waitlist_confirmation' ELSE 'waitlist_offer' END;
 kind:=code;
 IF p_delivery->>'recipient' IS DISTINCT FROM o.data->>'email' OR p_delivery->>'templateCode' IS DISTINCT FROM code
 OR p_delivery->'sealed' IS NULL OR p_delivery->>'tokenHash' !~ '^[0-9a-f]{64}$'
 OR p_delivery->>'contentHash' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid waitlist delivery binding'; END IF;
 SELECT expires_at INTO expiry FROM eshop.waitlist_offers WHERE id=p_offer AND order_id=p_order;
 INSERT INTO eshop.waitlist_capabilities(token_hash,organization_id,form_id,order_id,offer_id,kind,expires_at)
 VALUES(p_delivery->>'tokenHash',occ.organization,o.form,o.id,p_offer,CASE WHEN p_offer IS NULL THEN 'manage' ELSE 'offer' END,expiry);
 result:=public.enqueue_email(kind,jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit),o.data->>'email',
 jsonb_build_object('order_id',o.id,'offer_id',p_offer,'command_id',p_command,'content_hash',p_delivery->>'contentHash','waitlistEnvelope',p_delivery->'sealed'),
 p_command::text||':'||o.id::text,code,now(),expiry,o.id,NULL);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.expire_waitlist_form_internal(bigint,timestamptz,integer),public.enqueue_waitlist_email_internal(bigint,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_proposal(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_proposal(bigint) TO authenticated;
