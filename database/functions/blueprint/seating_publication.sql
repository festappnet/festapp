CREATE OR REPLACE FUNCTION public.seating_publication_preview_internal(p_transition uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; ids uuid[]; forms_data jsonb; catalog jsonb; blockers jsonb:='[]'; obligations jsonb; revisions jsonb; semantic jsonb; row record;
BEGIN
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition;
 IF tr.id IS NULL OR NOT coalesce(public.can_author_forms(tr.occasion),false) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 SELECT array_agg(id ORDER BY id),coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',revision) ORDER BY id),'[]') INTO ids,revisions
 FROM public.form_seating_transitions WHERE blueprint=tr.blueprint AND state='organizer_managed';
 IF tr.state<>'organizer_managed' THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','MODE_CHANGED')); END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'participantCapacity',f.participant_capacity,'blueprintId',tr.blueprint,
 'capacity',public.get_form_capacity_snapshot_internal(f.id),'available',NULL) ORDER BY f.id),'[]') INTO forms_data
 FROM public.forms f JOIN public.form_seating_transitions t ON t.form=f.id WHERE t.id=ANY(ids);
 FOR row IN SELECT * FROM public.seating_admissions_internal(p_transition) WHERE category IN ('blocked','unassigned','waiting','offered') LOOP
 blockers:=blockers||jsonb_build_array(jsonb_build_object('reason',CASE row.category WHEN 'waiting' THEN 'WAITLIST_PENDING' WHEN 'offered' THEN 'OFFERS_PENDING' WHEN 'unassigned' THEN 'ADMISSION_SOURCE_REQUIRES_SEATING' ELSE row.reason END,'formId',row.form_id));
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=tr.blueprint AND layout->>'schemaVersion'='2') THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED')); END IF;
 IF EXISTS(SELECT 1 FROM public.forms WHERE blueprint=tr.blueprint) THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','TARGET_ALREADY_PUBLIC')); END IF;
 FOR row IN SELECT DISTINCT f.id FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id AND NOT ff.is_hidden JOIN eshop.products p ON p.product_type=ff.product_type
 WHERE f.occasion=tr.occasion AND NOT EXISTS(SELECT 1 FROM public.form_seating_transitions t WHERE t.id=ANY(ids) AND t.form=f.id)
 AND p.id IN(SELECT s.product FROM eshop.spots s JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id WHERE sb.blueprint=tr.blueprint UNION SELECT product FROM eshop.blueprint_area_bindings WHERE blueprint=tr.blueprint) LOOP
 blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','UNCOVERED_ADMISSION_SOURCE','formId',row.id)); END LOOP;
 -- Products cannot already promise the same entitlement through another live hall.
 IF EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id JOIN public.forms f ON f.blueprint=sb.blueprint
 WHERE sb.blueprint<>tr.blueprint AND s.product IN(SELECT product FROM eshop.spots WHERE blueprint=tr.blueprint)) THEN
 blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','TARGET_ALREADY_PUBLIC')); END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE blueprint=tr.blueprint AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp()) THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','HOLD_ACTIVE')); END IF;
 WITH offerings AS(SELECT s.product product_id,count(*) FILTER(WHERE NOT sb.blocked) seats,false standing
 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot WHERE sb.blueprint=tr.blueprint GROUP BY s.product
 UNION ALL SELECT product,0,true FROM eshop.blueprint_area_bindings WHERE blueprint=tr.blueprint)
 SELECT coalesce(jsonb_agg(jsonb_build_object('productId',p.id,'title',p.title,'price',p.price,'currencyCode',p.currency_code,'maximum',p.maximum,
 'seats',o.seats,'standing',o.standing,'supply',public.blueprint_product_availability_internal(p.id)) ORDER BY p.id,o.standing),'[]') INTO catalog FROM offerings o JOIN eshop.products p ON p.id=o.product_id;
 SELECT coalesce(jsonb_agg(c||jsonb_build_object('capacity',CASE WHEN (c->>'standing')::boolean THEN (c#>>'{supply,capacity}')::bigint ELSE least((c->>'seats')::bigint,(c#>>'{supply,capacity}')::bigint) END,
 'available',CASE WHEN (c->>'standing')::boolean THEN (c#>>'{supply,available}')::bigint ELSE least((c#>>'{supply,available}')::bigint,(SELECT count(*) FROM eshop.spots s JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id WHERE sb.blueprint=tr.blueprint AND s.product=(c->>'productId')::bigint AND NOT sb.blocked AND s.order_product_ticket IS NULL AND NOT coalesce(s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp(),false))) END) ORDER BY (c->>'productId')::bigint),'[]') INTO catalog FROM jsonb_array_elements(catalog)c;
 SELECT coalesce(jsonb_agg(f||jsonb_build_object('capacity',(SELECT coalesce(sum((c->>'capacity')::bigint),0) FROM jsonb_array_elements(catalog)c),
 'available',(SELECT coalesce(sum((c->>'available')::bigint),0) FROM jsonb_array_elements(catalog)c)) ORDER BY (f->>'id')::bigint),'[]') INTO forms_data FROM jsonb_array_elements(forms_data)f;
 IF jsonb_array_length(catalog)=0 OR NOT EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=tr.blueprint AND NOT sb.blocked)
 AND NOT EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings WHERE blueprint=tr.blueprint) THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','INVENTORY_CONFLICT')); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(catalog) c WHERE c->>'price' IS NULL OR c->>'currencyCode' IS NULL OR (c#>>'{supply,capacity}')::bigint=0)
 OR EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings a WHERE a.blueprint=tr.blueprint AND NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts WHERE product=a.product AND inventory_context=a.inventory_context)) THEN
 blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','INVENTORY_CONFLICT')); END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY ticket_id,item_id),'[]') INTO obligations FROM public.seating_admissions_internal(p_transition) a;
 semantic:=jsonb_build_object('cohort',revisions,'catalog',catalog,'blockers',blockers,'obligations',obligations,
 'forms',(SELECT jsonb_agg(to_jsonb(f) ORDER BY f.id) FROM public.forms f WHERE f.occasion=tr.occasion),
 'fields',(SELECT jsonb_agg(to_jsonb(ff) ORDER BY ff.id) FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form WHERE f.occasion=tr.occasion),
 'orders',(SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) FROM eshop.orders o WHERE o.form IN(SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids))),
 'tickets',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM eshop.tickets t WHERE t.id IN(SELECT x.ticket FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE o.form IN(SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids)))),
 'layout',(SELECT layout FROM eshop.blueprints WHERE id=tr.blueprint),'revision',(SELECT layout_revision FROM eshop.blueprints WHERE id=tr.blueprint),
 'seats',(SELECT jsonb_agg(to_jsonb(s)-'updated_at'-'created_at' ORDER BY s.id) FROM eshop.spots s WHERE blueprint=tr.blueprint),
 'offers',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM eshop.waitlist_offer_slots s WHERE s.form_id IN(SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids))));
 RETURN jsonb_build_object('fingerprint',encode(extensions.digest(semantic::text,'sha256'),'hex'),'transitionIds',coalesce(to_jsonb(ids),'[]'),'revisions',revisions,
 'forms',forms_data,'catalog',catalog,'blockers',blockers,'layoutRevision',(SELECT layout_revision FROM eshop.blueprints WHERE id=tr.blueprint));
END $$;
REVOKE ALL ON FUNCTION public.seating_publication_preview_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.preview_seating_publication(p_transition uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('code',200,'data',public.seating_publication_preview_internal(p_transition))
$$;
REVOKE ALL ON FUNCTION public.preview_seating_publication(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_seating_publication(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.publish_seating_transitions(p_transition uuid,p_transition_ids uuid[],p_fingerprint text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; started jsonb; preview jsonb; ids uuid[]; f bigint;
BEGIN
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition;
 IF tr.id IS NULL OR NOT coalesce(public.can_author_forms(tr.occasion),false) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF cardinality(p_transition_ids) NOT BETWEEN 1 AND 256 THEN RAISE invalid_parameter_value USING MESSAGE='invalid publication cohort'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[tr.occasion]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.publication.publish',tr.occasion,auth.uid(),encode(extensions.digest(jsonb_build_array(p_transition,p_transition_ids,p_fingerprint)::text,'sha256'),'hex'));
 IF NOT coalesce(public.can_author_forms(tr.occasion),false) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 PERFORM 1 FROM public.forms WHERE occasion=tr.occasion ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.form_seating_transitions WHERE blueprint=tr.blueprint AND state='organizer_managed' ORDER BY id FOR UPDATE;
 SELECT array_agg(id ORDER BY id) INTO ids FROM public.form_seating_transitions WHERE blueprint=tr.blueprint AND state='organizer_managed';
 -- Freeze the full inventory/commercial closure before final semantic recheck.
 PERFORM public.lock_spot_assignment_scope_internal(
 ARRAY(SELECT s.id FROM eshop.spots s WHERE s.blueprint=tr.blueprint OR s.inventory_context IN(
 SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic WHERE pic.product IN(
 SELECT product FROM eshop.spots WHERE blueprint=tr.blueprint UNION SELECT product FROM eshop.blueprint_area_bindings WHERE blueprint=tr.blueprint)) ORDER BY s.id),
 '{}'::bigint[],true,
 ARRAY(SELECT product FROM eshop.spots WHERE blueprint=tr.blueprint UNION SELECT product FROM eshop.blueprint_area_bindings WHERE blueprint=tr.blueprint),false,
 ARRAY(SELECT o.id FROM eshop.orders o WHERE o.form IN(SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids)) ORDER BY o.id),
 ARRAY(SELECT x.id FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE o.form IN(SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids)) ORDER BY x.id));
 -- Existing expiry owner handles lifecycle; never cancel a waiting admission.
 FOR f IN SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids) ORDER BY form LOOP PERFORM public.expire_waitlist_form_internal(f); END LOOP;
 preview:=public.seating_publication_preview_internal(p_transition);
 IF preview->>'fingerprint' IS DISTINCT FROM p_fingerprint OR ids IS DISTINCT FROM ARRAY(SELECT x FROM unnest(p_transition_ids)x ORDER BY x) OR jsonb_array_length(preview->'blockers')>0 THEN
 RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','CONTEXT_CHANGED','blockers',preview->'blockers')); END IF;
 UPDATE public.form_seating_transitions SET state='published',revision=revision+1,finished_by=auth.uid(),finished_at=clock_timestamp() WHERE id=ANY(ids);
 UPDATE public.forms SET blueprint=tr.blueprint,participant_capacity=NULL,waitlist_enabled=false,waitlist_offer_duration_seconds=NULL,capacity_revision=capacity_revision+1,updated_at=clock_timestamp() WHERE id IN(SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids));
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'form','occasion',tr.occasion,form::text,1 FROM public.form_seating_transitions WHERE id=ANY(ids)
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 PERFORM public.notification_center_form_capacity_internal(form) FROM public.form_seating_transitions WHERE id=ANY(ids);
 PERFORM public.notification_center_blueprint_capacity_internal(tr.blueprint);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,tr.occasion,'seating.publication.publish',
 jsonb_build_array(jsonb_build_object('entityType','form','entityId',NULL,'operation','update','safeLabel','Public seating enabled','changedFields',jsonb_build_array('seating','capacity'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=tr.occasion),jsonb_build_object('transitionIds',ids,'sourceFormIds',ARRAY(SELECT form FROM public.form_seating_transitions WHERE id=ANY(ids)),'targetBlueprintId',tr.blueprint,'context',jsonb_set(public.get_seating_transition_context(tr.id)->'data','{items}','[]'::jsonb)));
END $$;
REVOKE ALL ON FUNCTION public.publish_seating_transitions(uuid,uuid[],text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.publish_seating_transitions(uuid,uuid[],text,uuid) TO authenticated;

-- Applied by every materializer, including stale/editor/direct callers.
CREATE OR REPLACE FUNCTION public.assert_published_admission_seating_internal(p_form bigint,p_product bigint,p_spot bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE bp bigint; published_bp bigint;
BEGIN
 SELECT blueprint INTO bp FROM public.forms WHERE id=p_form;
 SELECT min(t.blueprint) INTO published_bp FROM public.form_seating_transitions t JOIN public.forms f ON f.blueprint=t.blueprint
 JOIN eshop.spots s ON s.blueprint=t.blueprint AND s.product=p_product JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
 WHERE t.state='published';
 IF published_bp IS NOT NULL AND (bp IS DISTINCT FROM published_bp OR p_spot IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.spots WHERE id=p_spot AND blueprint=bp AND product=p_product)) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
 IF bp IS NOT NULL AND p_spot IS NULL AND EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id WHERE sb.blueprint=bp AND s.product=p_product)
 AND NOT EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings WHERE blueprint=bp AND product=p_product) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_published_admission_seating_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_form_seating_source_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id AND NOT ff.is_hidden
 JOIN eshop.products p ON p.product_type=ff.product_type AND NOT p.is_hidden
 JOIN eshop.spots s ON s.product=p.id JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
 JOIN public.form_seating_transitions t ON t.blueprint=sb.blueprint AND t.state='published'
 WHERE f.id=p_form AND f.is_open AND f.blueprint IS DISTINCT FROM t.blueprint) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_form_seating_source_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
