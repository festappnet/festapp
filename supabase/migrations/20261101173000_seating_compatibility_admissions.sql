-- Waiting items have no purchased admission entitlement. Keep their counts
-- and publication checks, but exclude them from product compatibility groups.
CREATE OR REPLACE FUNCTION public.get_seating_transition_context(p_transition uuid,p_search text DEFAULT '',p_category text DEFAULT NULL,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; rows_data jsonb; totals jsonb; cohort jsonb; seats jsonb; compat jsonb; lim integer:=least(greatest(coalesce(p_limit,50),1),200); last_id bigint; read_holders boolean;
BEGIN
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition;
 IF tr.id IS NULL OR NOT public.can_read_seating_status(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='seating access required'; END IF;
 IF length(coalesce(p_search,''))>256 THEN RAISE invalid_parameter_value USING MESSAGE='search too long'; END IF;
 read_holders:=coalesce(public.can_read_orders(tr.occasion),false);
 WITH a AS MATERIALIZED(SELECT * FROM public.seating_admissions_internal(p_transition))
 SELECT jsonb_build_object('unassigned',count(*) FILTER(WHERE category='unassigned'),'assigned',count(*) FILTER(WHERE category='assigned'),
 'standing',count(*) FILTER(WHERE category='standing'),'blocked',count(*) FILTER(WHERE category='blocked'),'waiting',count(*) FILTER(WHERE category='waiting'),'offered',count(*) FILTER(WHERE category='offered')) INTO totals FROM a;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'formId',form,'revision',revision) ORDER BY id),'[]') INTO cohort
 FROM public.form_seating_transitions WHERE blueprint=tr.blueprint AND state=tr.state;
 rows_data:='[]';
 IF read_holders THEN
 WITH page AS(SELECT * FROM public.seating_admissions_internal(p_transition) WHERE (p_after IS NULL OR ticket_id>p_after)
 AND (p_category IS NULL OR category=p_category) AND (coalesce(p_search,'')='' OR concat_ws(' ',holder,ticket_symbol,order_symbol,ticket_id::text,order_id::text) ILIKE '%'||p_search||'%') ORDER BY ticket_id LIMIT lim)
 SELECT coalesce(jsonb_agg(jsonb_build_object('ticketId',ticket_id,'admissionItemId',item_id,'orderId',order_id,'formId',form_id,'productId',product_id,'productTitle',product_title,
 'spotId',spot_id,'category',category,'reason',reason,'ticketSymbol',ticket_symbol,'orderSymbol',order_symbol,'holder',holder) ORDER BY ticket_id),'[]'),CASE WHEN count(*)=lim THEN max(ticket_id) END INTO rows_data,last_id FROM page;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'title',s.title,'productId',s.product,'available',s.order_product_ticket IS NULL AND NOT sb.blocked AND NOT coalesce(s.secret_expiration_time>clock_timestamp() AND s.secret IS NOT NULL,false),
 'reason',CASE WHEN sb.blocked THEN 'SEAT_UNAVAILABLE' WHEN s.order_product_ticket IS NOT NULL THEN 'SEAT_UNAVAILABLE' WHEN s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp() THEN 'HOLD_ACTIVE' END,
 'unitSpotIds',public.blueprint_selection_unit_spots_internal(s.id)) ORDER BY s.id),'[]') INTO seats
 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot WHERE sb.blueprint=tr.blueprint;
 WITH a AS MATERIALIZED(SELECT * FROM public.seating_admissions_internal(p_transition))
 SELECT coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'productTitle',product_title,'admissions',n,'seats',seat_count,'standing',area_count>0,
 'reason',CASE WHEN seat_count>0 AND area_count>0 THEN 'PLACEMENT_MODE_AMBIGUOUS' WHEN seat_count=0 AND area_count=0 THEN 'PRODUCT_MISMATCH' WHEN seat_count>0 AND seat_count<n THEN 'INVENTORY_CONFLICT' END) ORDER BY product_id),'[]') INTO compat
 FROM (SELECT product_id,max(product_title) product_title,count(*) n,
 (SELECT count(*) FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot WHERE sb.blueprint=tr.blueprint AND s.product=a.product_id AND NOT sb.blocked) seat_count,
 (SELECT count(*) FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=tr.blueprint AND ab.product=a.product_id) area_count
 FROM a WHERE category NOT IN ('waiting','offered') AND product_id IS NOT NULL GROUP BY product_id) q;
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('transitionId',tr.id,'blueprintId',tr.blueprint,'state',tr.state,'revision',tr.revision,
 'layoutRevision',(SELECT layout_revision FROM eshop.blueprints WHERE id=tr.blueprint),'cohort',cohort,'counts',totals,'items',rows_data,'nextCursor',last_id,'seats',seats,'compatibility',compat,
 'publicationAvailable',coalesce(public.can_author_forms(tr.occasion),false),'capabilities',jsonb_build_object('configure',coalesce(public.can_author_forms(tr.occasion),false),'readHolders',read_holders,'assign',public.can_assign_existing_admissions(tr.occasion))));
END $$;
REVOKE ALL ON FUNCTION public.get_seating_transition_context(uuid,text,text,bigint,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_seating_transition_context(uuid,text,text,bigint,integer) TO authenticated;
