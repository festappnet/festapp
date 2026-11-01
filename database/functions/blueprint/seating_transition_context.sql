-- One current admission projection. No cached person/placement lifecycle.
CREATE OR REPLACE FUNCTION public.seating_admissions_internal(p_transition uuid)
RETURNS TABLE(ticket_id bigint,item_id bigint,order_id bigint,form_id bigint,product_id bigint,spot_id bigint,
 category text,reason text,ticket_symbol text,order_symbol text,holder text,product_title text)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH scope AS (SELECT * FROM public.form_seating_transitions WHERE id=p_transition),
 sources AS (SELECT tr.* FROM public.form_seating_transitions tr,scope s
 WHERE tr.blueprint=s.blueprint AND tr.state=s.state AND tr.occasion=s.occasion),
 base AS (
 SELECT t.id ticket_id,t.occasion ticket_occasion,o.id order_id,o.form form_id,t.state ticket_state,o.state order_state,
 t.ticket_symbol,o.order_symbol,coalesce(public.get_waitlist_ticket_display_name_internal(o.form,t.data,o.data),'') holder,
 s.blueprint,s.occasion,
 (SELECT count(DISTINCT x."order") FROM eshop.order_product_ticket x WHERE x.ticket=t.id) order_count,
 (SELECT count(*) FROM eshop.order_product_ticket x JOIN eshop.products p ON p.id=x.product
 JOIN eshop.product_types pt ON pt.id=p.product_type WHERE x.ticket=t.id AND x."order"=o.id AND pt.type='spot') primary_count,
 (SELECT min(x.id) FROM eshop.order_product_ticket x JOIN eshop.products p ON p.id=x.product
 JOIN eshop.product_types pt ON pt.id=p.product_type WHERE x.ticket=t.id AND x."order"=o.id AND pt.type='spot') item_id,
 CASE WHEN t.state='waitlisted' OR o.state='waitlisted' THEN public.get_effective_waitlist_ticket_lifecycle_internal(t.id) END waiting_state
 FROM sources s JOIN eshop.orders o ON o.form=s.form JOIN eshop.order_product_ticket own ON own."order"=o.id
 JOIN eshop.tickets t ON t.id=own.ticket
 WHERE t.state IS DISTINCT FROM 'storno' AND o.state NOT IN ('storno','stock')
 GROUP BY t.id,o.id,s.blueprint,s.occasion),
 facts AS (
 SELECT a.*,x.product product_id,p.occasion product_occasion,p.title product_title,
 ARRAY(SELECT sp.id FROM eshop.spots sp JOIN eshop.blueprint_seat_bindings sb ON sb.spot=sp.id
 WHERE sp.order_product_ticket=a.item_id AND sp.product=x.product AND sb.blueprint=a.blueprint AND NOT sb.blocked) placements,
 EXISTS(SELECT 1 FROM eshop.spots sp WHERE sp.order_product_ticket=a.item_id AND sp.blueprint IS NOT NULL AND sp.blueprint<>a.blueprint) foreign_placement,
 EXISTS(SELECT 1 FROM eshop.spots sp JOIN eshop.blueprint_seat_bindings sb ON sb.spot=sp.id WHERE sb.blueprint=a.blueprint AND sp.product=x.product) addressed,
 EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=a.blueprint AND ab.product=x.product) standing,
 EXISTS(SELECT 1 FROM eshop.ticket_batch_items bi WHERE bi.ticket_id=a.ticket_id) printed,
 EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) tj
 WHERE tj->>'id'=a.ticket_id::text AND (SELECT count(*) FROM jsonb_array_elements(coalesce(tj->'products','[]')) pj WHERE pj->>'id'=x.product::text)=1) snapshot_valid,
 EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab JOIN eshop.product_inventory_contexts pic ON pic.product=ab.product AND pic.inventory_context=ab.inventory_context
 WHERE ab.blueprint=a.blueprint AND ab.product=x.product AND
 (SELECT count(*) FROM eshop.spots sp WHERE sp.order_product_ticket=a.item_id AND sp.inventory_context=pic.inventory_context)>=pic.quantity)
 AND NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product=x.product AND
 (SELECT count(*) FROM eshop.spots sp WHERE sp.order_product_ticket=a.item_id AND sp.inventory_context=pic.inventory_context)<>pic.quantity) standing_valid
 FROM base a LEFT JOIN eshop.order_product_ticket x ON x.id=a.item_id LEFT JOIN eshop.products p ON p.id=x.product
 JOIN eshop.orders o ON o.id=a.order_id),
 classified AS (
 SELECT f.*,CASE
 WHEN waiting_state IN ('waiting','offered') THEN NULL
 WHEN order_state='preparing_payment' THEN 'PAYMENT_PENDING'
 WHEN primary_count<>1 OR order_count<>1 OR ticket_occasion IS DISTINCT FROM occasion OR product_occasion IS DISTINCT FROM occasion OR NOT snapshot_valid THEN 'ADMISSION_DATA_AMBIGUOUS'
 WHEN foreign_placement THEN 'ADMISSION_ASSIGNED_ELSEWHERE'
 WHEN addressed AND standing THEN 'PLACEMENT_MODE_AMBIGUOUS'
 WHEN cardinality(placements)>1 THEN 'ADMISSION_DATA_AMBIGUOUS'
 WHEN cardinality(placements)=1 THEN NULL
 WHEN standing AND standing_valid THEN NULL
 WHEN ticket_state='used' THEN 'USED_TICKET_PROTECTED'
 WHEN printed THEN 'BATCH_TICKET_PRINT_IMMUTABLE'
 WHEN standing THEN 'INVENTORY_CONFLICT'
 WHEN NOT addressed THEN 'PRODUCT_MISMATCH' END problem
 FROM facts f)
 SELECT DISTINCT ON(ticket_id) ticket_id,item_id,order_id,form_id,product_id,placements[1],
 CASE WHEN waiting_state='offered' THEN 'offered' WHEN waiting_state='waiting' OR ticket_state='waitlisted' OR order_state='waitlisted' THEN 'waiting'
 WHEN problem IS NOT NULL THEN 'blocked' WHEN cardinality(placements)=1 THEN 'assigned'
 WHEN standing THEN 'standing' ELSE 'unassigned' END,CASE WHEN problem IS NULL AND cardinality(placements)=1 AND ticket_state='used' THEN 'USED_TICKET_PROTECTED' WHEN problem IS NULL AND cardinality(placements)=1 AND printed THEN 'BATCH_TICKET_PRINT_IMMUTABLE' ELSE problem END,ticket_symbol,order_symbol,holder,product_title FROM classified ORDER BY ticket_id,order_id
$$;
REVOKE ALL ON FUNCTION public.seating_admissions_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_seating_workspace(p_occasion bigint,p_blueprint bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; plans jsonb; trs jsonb; forms_data jsonb; valid boolean; status text;
BEGIN
 IF NOT public.can_read_seating_status(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='seating access required'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'valid',coalesce(layout->>'schemaVersion'='2',false)) ORDER BY id),'[]') INTO plans FROM eshop.blueprints WHERE occasion=p_occasion;
 bp:=p_blueprint;
 IF bp IS NULL AND jsonb_array_length(plans)=1 THEN bp:=(plans->0->>'id')::bigint; END IF;
 IF bp IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=bp AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='seating access required'; END IF;
 SELECT layout->>'schemaVersion'='2' INTO valid FROM eshop.blueprints WHERE id=bp;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'formId',form,'blueprintId',blueprint,'state',state,'revision',revision) ORDER BY started_at DESC),'[]') INTO trs
 FROM public.form_seating_transitions WHERE occasion=p_occasion AND blueprint=bp AND state<>'cancelled';
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'link',f.link,'transitionId',tr.id,'activeBlueprintId',f.blueprint,
 'canStart',coalesce(public.can_author_forms(p_occasion),false) AND f.blueprint IS NULL AND tr.id IS NULL AND coalesce(valid,false)
 AND NOT EXISTS(SELECT 1 FROM public.forms live WHERE live.blueprint=bp),
 'reason',CASE WHEN f.blueprint IS NOT NULL OR EXISTS(SELECT 1 FROM public.forms live WHERE live.blueprint=bp) THEN 'TARGET_ALREADY_PUBLIC'
 WHEN tr.id IS NOT NULL AND tr.blueprint IS DISTINCT FROM bp THEN 'MODE_CHANGED' WHEN NOT coalesce(valid,false) THEN 'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED' END) ORDER BY f.id),'[]') INTO forms_data
 FROM public.forms f LEFT JOIN public.form_seating_transitions tr ON tr.form=f.id AND tr.state='organizer_managed' WHERE f.occasion=p_occasion;
 status:=CASE WHEN bp IS NULL THEN 'choose_plan' WHEN NOT coalesce(valid,false) THEN 'repair_plan'
 WHEN EXISTS(SELECT 1 FROM public.form_seating_transitions WHERE blueprint=bp AND state='organizer_managed') THEN 'organizer_managed'
 WHEN EXISTS(SELECT 1 FROM public.form_seating_transitions WHERE blueprint=bp AND state='published') OR EXISTS(SELECT 1 FROM public.forms live WHERE live.blueprint=bp) THEN 'published'
 WHEN jsonb_array_length(forms_data)=0 THEN 'no_source' ELSE 'choose_plan' END;
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('blueprintId',bp,'plans',plans,'forms',forms_data,'transitions',trs,'status',status,
 'capabilities',jsonb_build_object('configure',coalesce(public.can_author_forms(p_occasion),false),'readHolders',coalesce(public.can_read_orders(p_occasion),false),'assign',public.can_assign_existing_admissions(p_occasion))));
END $$;
REVOKE ALL ON FUNCTION public.get_seating_workspace(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_seating_workspace(bigint,bigint) TO authenticated;

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
 FROM (SELECT product_id,max(product_title) product_title,count(*) FILTER(WHERE category NOT IN ('waiting','offered')) n,
 (SELECT count(*) FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot WHERE sb.blueprint=tr.blueprint AND s.product=a.product_id AND NOT sb.blocked) seat_count,
 (SELECT count(*) FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=tr.blueprint AND ab.product=a.product_id) area_count FROM a GROUP BY product_id) q;
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('transitionId',tr.id,'blueprintId',tr.blueprint,'state',tr.state,'revision',tr.revision,
 'layoutRevision',(SELECT layout_revision FROM eshop.blueprints WHERE id=tr.blueprint),'cohort',cohort,'counts',totals,'items',rows_data,'nextCursor',last_id,'seats',seats,'compatibility',compat,
 'publicationAvailable',coalesce(public.can_author_forms(tr.occasion),false),'capabilities',jsonb_build_object('configure',coalesce(public.can_author_forms(tr.occasion),false),'readHolders',read_holders,'assign',public.can_assign_existing_admissions(tr.occasion))));
END $$;
REVOKE ALL ON FUNCTION public.get_seating_transition_context(uuid,text,text,bigint,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_seating_transition_context(uuid,text,text,bigint,integer) TO authenticated;
