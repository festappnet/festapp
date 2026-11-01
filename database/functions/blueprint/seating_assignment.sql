-- Public adapters verify organizer authority; this private seam owns exact scope.
CREATE OR REPLACE FUNCTION public.seating_assignment_scope_internal(p_transition uuid,p_mappings jsonb)
RETURNS public.form_seating_transitions LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; v_mapping jsonb;
BEGIN
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition;
 IF tr.id IS NULL OR NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF jsonb_typeof(p_mappings) IS DISTINCT FROM 'array' OR jsonb_array_length(p_mappings) NOT BETWEEN 1 AND least(256,(SELECT hard_cap FROM public.abuse_policy_rules WHERE rule_key='order.mutation.items')) OR octet_length(p_mappings::text)>131072 THEN
 RAISE invalid_parameter_value USING MESSAGE='invalid assignment batch'; END IF;
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) LOOP
 IF jsonb_typeof(v_mapping) IS DISTINCT FROM 'object' OR NOT v_mapping ?& ARRAY['ticketId','admissionItemId','expectedSpotId','targetSpotId']
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_mapping) k WHERE k NOT IN ('ticketId','admissionItemId','expectedSpotId','targetSpotId'))
 OR v_mapping->>'ticketId' IS NULL OR v_mapping->>'admissionItemId' IS NULL THEN
 RAISE invalid_parameter_value USING MESSAGE='exact changed item mapping required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket i JOIN eshop.orders o ON o.id=i."order"
 JOIN public.form_seating_transitions v_spot ON v_spot.form=o.form AND v_spot.blueprint=tr.blueprint AND v_spot.state=tr.state
 WHERE i.id=(v_mapping->>'admissionItemId')::bigint AND i.ticket=(v_mapping->>'ticketId')::bigint AND o.occasion=tr.occasion)
 OR EXISTS(SELECT 1 FROM eshop.spots WHERE id IN ((v_mapping->>'expectedSpotId')::bigint,(v_mapping->>'targetSpotId')::bigint) AND (occasion<>tr.occasion OR blueprint IS DISTINCT FROM tr.blueprint)) THEN
 RAISE insufficient_privilege USING MESSAGE='assignment context unavailable'; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_mappings) m WHERE m->'expectedSpotId' IS DISTINCT FROM m->'targetSpotId') THEN
 RAISE invalid_parameter_value USING MESSAGE='changed assignment batch required'; END IF;
 IF (SELECT count(DISTINCT value->>'admissionItemId') FROM jsonb_array_elements(p_mappings))<>jsonb_array_length(p_mappings)
 OR (SELECT count(*) FROM jsonb_array_elements(p_mappings) WHERE value->>'targetSpotId' IS NOT NULL)<>(SELECT count(DISTINCT value->>'targetSpotId') FROM jsonb_array_elements(p_mappings)) THEN
 RAISE invalid_parameter_value USING MESSAGE='duplicate assignment identity'; END IF;
 RETURN tr;
END $$;
REVOKE ALL ON FUNCTION public.seating_assignment_scope_internal(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.seating_assignment_preview_internal(p_transition uuid,p_mappings jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; v_mapping jsonb; a record; v_spot eshop.spots; why text; blockers jsonb:='[]'; mappings jsonb:='[]'; revisions jsonb; semantic jsonb; affected bigint[]; ids bigint[]; before_ids bigint[]; target_ids bigint[]; rev bigint;
BEGIN
 tr:=public.seating_assignment_scope_internal(p_transition,p_mappings);
 SELECT layout_revision INTO rev FROM eshop.blueprints WHERE id=tr.blueprint;
 SELECT ARRAY(SELECT DISTINCT v FROM jsonb_array_elements(p_mappings) m CROSS JOIN LATERAL unnest(ARRAY[(m->>'expectedSpotId')::bigint,(m->>'targetSpotId')::bigint]) v WHERE v IS NOT NULL ORDER BY v) INTO ids;
 SELECT ARRAY(SELECT DISTINCT member FROM unnest(ids) id CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(id)) member ORDER BY member) INTO affected;
 IF tr.state<>'organizer_managed' THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','MODE_CHANGED')); END IF;
 -- Each side independently covers its complete units. A single item moving
 -- between two members cannot count as the two purchased couch admissions.
 SELECT ARRAY(SELECT (m->>'expectedSpotId')::bigint FROM jsonb_array_elements(p_mappings)m WHERE m->>'expectedSpotId' IS NOT NULL),
 ARRAY(SELECT (m->>'targetSpotId')::bigint FROM jsonb_array_elements(p_mappings)m WHERE m->>'targetSpotId' IS NOT NULL)
 INTO before_ids,target_ids;
 IF EXISTS(SELECT 1 FROM unnest(before_ids) requested CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member WHERE NOT member=ANY(before_ids))
 OR EXISTS(SELECT 1 FROM unnest(target_ids) requested CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member WHERE NOT member=ANY(target_ids)) THEN
 blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','ATOMIC_UNIT_INCOMPLETE')); END IF;
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) ORDER BY (value->>'admissionItemId')::bigint LOOP
 SELECT * INTO a FROM public.seating_admissions_internal(p_transition) WHERE ticket_id=(v_mapping->>'ticketId')::bigint AND item_id=(v_mapping->>'admissionItemId')::bigint;
 why:=NULL;
 IF NOT FOUND THEN why:='ADMISSION_DATA_AMBIGUOUS';
 ELSIF a.category NOT IN ('assigned','unassigned') THEN why:=coalesce(a.reason,'MODE_CHANGED');
 ELSIF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=a.ticket_id AND state='used') THEN why:='USED_TICKET_PROTECTED';
 ELSIF EXISTS(SELECT 1 FROM eshop.ticket_batch_items WHERE ticket_id=a.ticket_id) THEN why:='BATCH_TICKET_PRINT_IMMUTABLE';
 ELSIF a.spot_id IS DISTINCT FROM (v_mapping->>'expectedSpotId')::bigint THEN why:='CONTEXT_CHANGED'; END IF;
 IF why IS NULL AND v_mapping->>'targetSpotId' IS NOT NULL THEN
 SELECT * INTO v_spot FROM eshop.spots WHERE id=(v_mapping->>'targetSpotId')::bigint;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=tr.blueprint AND spot=v_spot.id AND NOT blocked) THEN why:='SEAT_UNAVAILABLE';
 ELSIF v_spot.product IS DISTINCT FROM a.product_id THEN why:='PRODUCT_MISMATCH';
 ELSIF v_spot.order_product_ticket IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_mappings) other WHERE (other->>'admissionItemId')::bigint=v_spot.order_product_ticket AND (other->>'expectedSpotId')::bigint=v_spot.id) THEN why:='SEAT_UNAVAILABLE';
 ELSIF v_spot.secret IS NOT NULL AND v_spot.secret_expiration_time>clock_timestamp() THEN why:='HOLD_ACTIVE';
 ELSIF v_spot.inventory_context IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts WHERE product=a.product_id AND inventory_context=v_spot.inventory_context) THEN why:='INVENTORY_CONFLICT'; END IF;
 END IF;
 IF why IS NOT NULL THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason',why,'ticketId',v_mapping->'ticketId','spotId',v_mapping->'targetSpotId')); END IF;
 mappings:=mappings||jsonb_build_array(v_mapping||jsonb_build_object('formId',a.form_id,'productId',a.product_id));
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'revision',t.revision) ORDER BY t.id),'[]') INTO revisions
 FROM public.form_seating_transitions t WHERE t.blueprint=tr.blueprint AND t.state='organizer_managed' AND t.form IN (SELECT (m->>'formId')::bigint FROM jsonb_array_elements(mappings) m);
 semantic:=jsonb_build_object('mappings',mappings,'revisions',revisions,'layoutRevision',rev,'blockers',blockers,
 'seats',(SELECT jsonb_agg(to_jsonb(s)-'updated_at'-'created_at' ORDER BY s.id) FROM eshop.spots s WHERE s.id=ANY(affected)),
 'bindings',(SELECT jsonb_agg(to_jsonb(sb) ORDER BY sb.spot) FROM eshop.blueprint_seat_bindings sb WHERE sb.spot=ANY(affected)),
 'admissions',(SELECT jsonb_agg(jsonb_build_object('item',to_jsonb(i),'ticket',to_jsonb(t)-'updated_at','order',to_jsonb(o)-'updated_at','payment',to_jsonb(pi)) ORDER BY i.id)
 FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket JOIN eshop.orders o ON o.id=i."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE i.id IN (SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m)),
 'allocations',(SELECT jsonb_agg(jsonb_build_array(s.id,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id) FROM eshop.spots s WHERE s.order_product_ticket IN(SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m)),
 'requirements',(SELECT jsonb_agg(to_jsonb(pic) ORDER BY pic.product,pic.inventory_context) FROM eshop.product_inventory_contexts pic WHERE product IN(SELECT (m->>'productId')::bigint FROM jsonb_array_elements(mappings)m)));
 RETURN jsonb_build_object('fingerprint',encode(extensions.digest(semantic::text,'sha256'),'hex'),'revisions',revisions,'mappings',mappings,'blockers',blockers,'layoutRevision',rev);
END $$;
REVOKE ALL ON FUNCTION public.seating_assignment_preview_internal(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.preview_ticket_seat_assignment(p_transition uuid,p_mappings jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('code',200,'data',public.seating_assignment_preview_internal(p_transition,p_mappings))
$$;
REVOKE ALL ON FUNCTION public.preview_ticket_seat_assignment(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_ticket_seat_assignment(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_ticket_seat_assignments(p_transition uuid,p_mappings jsonb,p_fingerprint text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; started jsonb; preview jsonb; v_orders bigint[]; v_items bigint[]; v_spots bigint[]; v_products bigint[]; v_mapping jsonb; dest eshop.spots; required integer; occupied integer; spare bigint; oid bigint; touched bigint[];
BEGIN
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition;
 IF tr.id IS NULL OR NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name='seating.assignment.set') THEN
 tr:=public.seating_assignment_scope_internal(p_transition,p_mappings); END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[tr.occasion]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.assignment.set',tr.occasion,auth.uid(),encode(extensions.digest(jsonb_build_array(p_transition,p_mappings,p_fingerprint)::text,'sha256'),'hex'));
 IF NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 tr:=public.seating_assignment_scope_internal(p_transition,p_mappings);
 PERFORM public.admit_order_mutation_v1(tr.occasion,jsonb_array_length(p_mappings));
 SELECT ARRAY(SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m ORDER BY 1) INTO v_items;
 SELECT array_agg(DISTINCT "order" ORDER BY "order"),array_agg(DISTINCT product ORDER BY product) INTO v_orders,v_products FROM eshop.order_product_ticket WHERE id=ANY(v_items);
 PERFORM 1 FROM public.forms WHERE id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.form_seating_transitions WHERE blueprint=tr.blueprint AND state='organizer_managed' AND form IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders)) ORDER BY id FOR UPDATE;
 -- Lock union of before/after units and all allocation parents before children.
 SELECT ARRAY(SELECT DISTINCT s.id FROM eshop.spots s WHERE s.order_product_ticket=ANY(v_items)
 OR s.inventory_context IN(SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(v_products))
 OR s.id IN(SELECT member FROM jsonb_array_elements(p_mappings)m CROSS JOIN LATERAL unnest(ARRAY[(m->>'expectedSpotId')::bigint,(m->>'targetSpotId')::bigint]) id CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(id)) member) ORDER BY s.id) INTO v_spots;
 PERFORM public.lock_spot_assignment_scope_internal(v_spots,'{}',true,v_products,false,v_orders,v_items);
 tr:=public.seating_assignment_scope_internal(p_transition,p_mappings);
 preview:=public.seating_assignment_preview_internal(p_transition,p_mappings);
 IF jsonb_array_length(preview->'blockers')>0 OR preview->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN
 RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason',CASE WHEN jsonb_array_length(preview->'blockers')>0 THEN preview#>>'{blockers,0,reason}' ELSE 'CONTEXT_CHANGED' END,'blockers',preview->'blockers')); END IF;
 -- Remove only explicitly reviewed before associations, preserving physical resources.
 UPDATE eshop.spots SET order_product_ticket=NULL,state=NULL,updated_at=clock_timestamp()
 WHERE id IN(SELECT (m->>'expectedSpotId')::bigint FROM jsonb_array_elements(p_mappings)m);
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) ORDER BY (value->>'admissionItemId')::bigint LOOP
 IF v_mapping->>'targetSpotId' IS NULL THEN CONTINUE; END IF;
 SELECT * INTO STRICT dest FROM eshop.spots WHERE id=(v_mapping->>'targetSpotId')::bigint;
 IF dest.inventory_context IS NOT NULL THEN
 SELECT quantity INTO required FROM eshop.product_inventory_contexts WHERE product=dest.product AND inventory_context=dest.inventory_context;
 SELECT count(*) INTO occupied FROM eshop.spots WHERE order_product_ticket=(v_mapping->>'admissionItemId')::bigint AND inventory_context=dest.inventory_context;
 IF occupied>=required THEN
 SELECT id INTO spare FROM eshop.spots WHERE order_product_ticket=(v_mapping->>'admissionItemId')::bigint AND inventory_context=dest.inventory_context AND blueprint IS NULL ORDER BY id LIMIT 1;
 IF spare IS NULL THEN RAISE EXCEPTION 'INVENTORY_CONFLICT'; END IF;
 UPDATE eshop.spots SET order_product_ticket=NULL,state=NULL,resource=NULL,updated_at=clock_timestamp() WHERE id=spare;
 END IF;
 END IF;
 UPDATE eshop.spots SET order_product_ticket=(v_mapping->>'admissionItemId')::bigint,state='ordered',secret=NULL,secret_expiration_time=NULL,updated_at=clock_timestamp() WHERE id=dest.id;
 END LOOP;
 FOREACH oid IN ARRAY v_orders LOOP PERFORM public.apply_allocations(oid); END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.order_product_ticket i JOIN eshop.product_inventory_contexts pic ON pic.product=i.product WHERE i.id=ANY(v_items) AND
 (SELECT count(*) FROM eshop.spots WHERE order_product_ticket=i.id AND inventory_context=pic.inventory_context)<>pic.quantity) THEN RAISE EXCEPTION 'INVENTORY_CONFLICT'; END IF;
 UPDATE public.form_seating_transitions SET revision=revision+1 WHERE blueprint=tr.blueprint AND state='organizer_managed' AND form IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders));
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,tr.occasion,'seating.assignment.set',
 jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',tr.blueprint,'operation','update','safeLabel','Admission placement','changedFields',jsonb_build_array('seating'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=tr.occasion),jsonb_build_object('transitionId',tr.id,'mappings',preview->'mappings','context',public.get_seating_transition_context(tr.id)->'data'));
END $$;
REVOKE ALL ON FUNCTION public.set_ticket_seat_assignments(uuid,jsonb,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_ticket_seat_assignments(uuid,jsonb,text,uuid) TO authenticated;
