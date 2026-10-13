-- Canonical source: database/functions/eshop_waitlist/offers.sql
-- CREATE OR REPLACE preserves the existing owner and execute privileges.
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_proposal(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; proposals jsonb; available integer;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 PERFORM 1 FROM public.forms WHERE id=f.id FOR UPDATE;
 PERFORM public.expire_waitlist_form_internal(f.id);
 c:=public.get_form_capacity_snapshot_internal(f.id); available:=(c->>'offerablePlaces')::integer;
 -- count is the suggested allocation; waitingCount is the authoritative recipient limit.
 -- Keep unallocated eligible recipients so editors can adjust the allocation safely.
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',order_id,'count',offered,'waitingCount',total) ORDER BY first_queue,order_id),'[]') INTO proposals
 FROM (SELECT order_id,min(waitlist_queue_at) first_queue,count(*) total,
  count(*) FILTER(WHERE position<=available) offered FROM
  (SELECT p.*,o.id order_id,row_number() OVER(ORDER BY p.waitlist_queue_at,p.created_at,p.id) position FROM eshop.tickets p
   JOIN LATERAL(SELECT DISTINCT x."order" FROM eshop.order_product_ticket x WHERE x.ticket=p.id) x ON true
   JOIN eshop.orders o ON o.id=x."order" WHERE o.form=f.id AND o.state='waitlisted' AND public.get_effective_waitlist_ticket_lifecycle_internal(p.id)='waiting' ) ranked GROUP BY order_id) grouped;
 RETURN jsonb_build_object('code',200,'formId',f.id,'revision',c->'revision','capacity',c,'recipients',proposals,
 'offerDurationSeconds',f.waitlist_offer_duration_seconds,'serverTime',clock_timestamp());
END $$;
