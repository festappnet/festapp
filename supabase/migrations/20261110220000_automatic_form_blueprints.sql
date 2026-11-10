-- Saved plans are immediately available to enabled form seat selectors.
-- The existing form availability window remains the only public sales gate.

-- Source: database/functions/eshop_waitlist/form_capacity.sql
-- SHA256: ddd92d61fd8c265a02e6c40fdf1102861bf4cdc24ec69861bd3a84a0f68aeb3c
CREATE OR REPLACE FUNCTION public.get_form_capacity_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH counts AS (
 SELECT f.*, (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted' AND o.state IS DISTINCT FROM 'storno') occupied,
 (SELECT count(*) FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.form_id=f.id AND s.outcome='pending' AND w.expires_at>p_at) reserved,
 (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND o.state='waitlisted' AND public.get_effective_waitlist_ticket_lifecycle_internal(t.id)='waiting') waiting
 FROM public.forms f WHERE f.id=p_form), free AS (
 SELECT *,greatest(participant_capacity-occupied-reserved,0) available FROM counts)
 SELECT jsonb_build_object('enabled',participant_capacity IS NOT NULL,'limit',participant_capacity,
 'remainingPublic',CASE WHEN participant_capacity IS NOT NULL THEN greatest(available-waiting,0) END,
 'showRemaining',show_remaining_capacity,'occupiedPeople',occupied,'offeredPlaces',reserved,'waitingPeople',waiting,
 'offerablePlaces',available,'heldForWaiting',least(available,waiting),'revision',capacity_revision,
 'canSendOffers',waitlist_enabled AND available>0,'blockedReason',CASE WHEN NOT waitlist_enabled THEN 'WAITLIST_NOT_AVAILABLE'
 WHEN available=0 THEN 'FORM_CAPACITY_EXCEEDED' END,'serverTime',p_at) FROM free;
$$;
CREATE OR REPLACE FUNCTION public.get_form_registration_mode_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 IF NOT (public.get_form_availability_snapshot_internal(p_form,p_at)->>'isWindowOpen')::boolean THEN RETURN 'closed'; END IF;
 IF f.blueprint IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
 ) THEN RETURN 'blueprint'; END IF;
 c:=public.get_form_capacity_snapshot_internal(p_form,p_at);
 IF f.participant_capacity IS NULL OR (c->>'remainingPublic')::bigint>0 THEN RETURN 'regular'; END IF;
 RETURN CASE WHEN f.waitlist_enabled THEN 'waitlist' ELSE 'full' END;
END $$;
CREATE OR REPLACE FUNCTION public.check_form_capacity_settings_internal(p_form bigint,p_input jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; n integer; enabled boolean; bp bigint;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 c:=public.get_form_capacity_snapshot_internal(p_form);
 n:=CASE WHEN p_input ? 'participant_capacity' THEN (p_input->>'participant_capacity')::integer ELSE f.participant_capacity END;
 enabled:=CASE WHEN p_input ? 'waitlist_enabled' THEN (p_input->>'waitlist_enabled')::boolean ELSE f.waitlist_enabled END;
 bp:=CASE WHEN p_input ? 'blueprint' THEN nullif(p_input->>'blueprint','')::bigint ELSE f.blueprint END;
 -- Switching or disabling a selector cannot abandon sold places or live holds.
 IF bp IS DISTINCT FROM f.blueprint AND f.blueprint IS NOT NULL AND (
   EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
     JOIN eshop.orders o ON o.id=x."order" WHERE o.form=f.id AND s.blueprint=f.blueprint)
   OR EXISTS(SELECT 1 FROM eshop.spots WHERE blueprint=f.blueprint AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp())) THEN
   RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
 -- A retained blueprint is inactive when the occasion feature is disabled.
 IF NOT EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN bp:=NULL; END IF;
 IF n IS NOT NULL AND n<(c->>'occupiedPeople')::bigint+(c->>'offeredPlaces')::bigint+coalesce((c->>'heldForWaiting')::bigint,0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','CAPACITY_BELOW_COMMITTED','capacity',c)::text; END IF;
 IF ((NOT enabled) OR n IS NULL OR bp IS NOT NULL) AND
 ((c->>'waitingPeople')::bigint>0 OR (c->>'offeredPlaces')::bigint>0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','WAITLIST_HAS_ACTIVE_ENTRIES','capacity',c)::text; END IF;
 IF bp IS NOT NULL AND (n IS NOT NULL OR enabled) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','BLUEPRINT_CONFLICT')::text; END IF;
END $$;
REVOKE ALL ON FUNCTION public.get_form_capacity_snapshot_internal(bigint,timestamptz),
 public.get_form_registration_mode_internal(bigint,timestamptz),public.check_form_capacity_settings_internal(bigint,jsonb)
 FROM PUBLIC,anon,authenticated;

-- Source: database/functions/blueprint/form_binding.sql
-- SHA256: 477400371003ccafe458c4c74efa4b8320cb3159e4e538834310f085360f3f68
-- forms.blueprint is the sole saved association. Saving never publishes a
-- second resource: the form's existing schedule/open flag controls sales.
CREATE OR REPLACE FUNCTION public.sync_form_blueprint_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; bp bigint; candidates integer;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=f.occasion AND
   jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN RETURN; END IF;
 bp:=f.blueprint;
 IF NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND type='spot' AND NOT is_hidden) THEN
   -- An explicitly disabled selector returns to ordinary product choices.
   IF NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND type='spot' AND is_hidden) THEN RETURN; END IF;
   bp:=NULL;
 ELSE
 IF bp IS NULL THEN
   SELECT count(*),min(id) INTO candidates,bp FROM eshop.blueprints
   WHERE occasion=f.occasion AND layout->>'schemaVersion'='2';
   IF candidates=0 THEN RETURN; END IF;
   IF candidates<>1 THEN RAISE EXCEPTION 'BLUEPRINT_SELECTION_REQUIRED'; END IF;
 END IF;
 END IF;
 IF bp IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints b JOIN public.occasions o ON o.id=f.occasion
   WHERE b.id=bp AND b.occasion=f.occasion AND b.organization=o.organization AND b.layout->>'schemaVersion'='2') THEN
   RAISE EXCEPTION 'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 IF f.blueprint IS DISTINCT FROM bp THEN
   PERFORM public.check_form_capacity_settings_internal(f.id,jsonb_build_object('blueprint',bp));
   UPDATE public.forms SET blueprint=bp,capacity_revision=capacity_revision+1,updated_at=clock_timestamp() WHERE id=f.id;
   INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
   VALUES('form','occasion',f.occasion,f.id::text,1)
   ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
   SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
   PERFORM public.notification_center_form_capacity_internal(f.id);
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.sync_form_blueprint_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/blueprint/seating_context.sql
-- SHA256: 2ca49cab7ad2709d6174627003b16a2788e16f02845dbffdb4aac3a3286fd636
-- Worklists derive from saved plans, current offers and actual placements.
-- Generic registrations keep their existing capacity/waitlist and public flow.
CREATE OR REPLACE FUNCTION public.blueprint_seating_sources_internal(p_blueprint bigint)
RETURNS TABLE(form_id bigint) LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT f.id FROM public.forms f JOIN eshop.blueprints b ON b.occasion=f.occasion AND b.id=p_blueprint
 WHERE f.blueprint=b.id OR (f.blueprint IS NULL AND (
   (SELECT count(*) FROM eshop.blueprints WHERE occasion=b.occasion AND layout->>'schemaVersion'='2')=1
   OR EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
     WHERE ff.form=f.id AND NOT ff.is_hidden AND (p.id IN(SELECT product FROM eshop.spots WHERE blueprint=b.id)
       OR p.id IN(SELECT product FROM eshop.blueprint_area_bindings WHERE blueprint=b.id)))
   OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.order_product_ticket x ON x."order"=o.id
     JOIN eshop.spots s ON s.order_product_ticket=x.id WHERE o.form=f.id AND s.blueprint=b.id)));
$$;
REVOKE ALL ON FUNCTION public.blueprint_seating_sources_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One current admission projection. No cached person/placement lifecycle.
CREATE OR REPLACE FUNCTION public.seating_admissions_internal(p_blueprint bigint)
RETURNS TABLE(ticket_id bigint,item_id bigint,order_id bigint,form_id bigint,product_id bigint,spot_id bigint,
 category text,reason text,ticket_symbol text,order_symbol text,holder text,product_title text)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH scope AS (SELECT * FROM eshop.blueprints WHERE id=p_blueprint),
 sources AS (SELECT f.form_id AS form,s.id AS blueprint,s.occasion FROM scope s
 CROSS JOIN LATERAL public.blueprint_seating_sources_internal(s.id) f),
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
REVOKE ALL ON FUNCTION public.seating_admissions_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_seating_workspace(p_occasion bigint,p_blueprint bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; plans jsonb; forms_data jsonb; valid boolean;
BEGIN
 IF NOT public.can_read_seating_status(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='seating access required'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'valid',coalesce(layout->>'schemaVersion'='2',false)) ORDER BY id),'[]') INTO plans FROM eshop.blueprints WHERE occasion=p_occasion;
 bp:=p_blueprint;
 IF bp IS NULL AND jsonb_array_length(plans)=1 THEN bp:=(plans->0->>'id')::bigint; END IF;
 IF bp IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=bp AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='seating access required'; END IF;
 SELECT layout->>'schemaVersion'='2' INTO valid FROM eshop.blueprints WHERE id=bp;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'link',f.link,'blueprintId',bp) ORDER BY f.id),'[]') INTO forms_data
 FROM public.forms f JOIN public.blueprint_seating_sources_internal(bp) source ON source.form_id=f.id WHERE f.occasion=p_occasion;
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('blueprintId',bp,'plans',plans,'forms',forms_data,
 'status',CASE WHEN bp IS NULL THEN 'choose_plan' WHEN NOT coalesce(valid,false) THEN 'repair_plan' WHEN jsonb_array_length(forms_data)=0 THEN 'no_source' ELSE 'ready' END,
 'capabilities',jsonb_build_object('configure',coalesce(public.can_author_forms(p_occasion),false),'readHolders',coalesce(public.can_read_orders(p_occasion),false),'assign',public.can_assign_existing_admissions(p_occasion))));
END $$;
REVOKE ALL ON FUNCTION public.get_seating_workspace(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_seating_workspace(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_blueprint_seating_context(p_blueprint bigint,p_search text DEFAULT '',p_category text DEFAULT NULL,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr eshop.blueprints; rows_data jsonb; totals jsonb; cohort jsonb; seats jsonb; compat jsonb; lim integer:=least(greatest(coalesce(p_limit,50),1),200); last_id bigint; read_holders boolean;
BEGIN
 SELECT * INTO tr FROM eshop.blueprints WHERE id=p_blueprint;
 IF tr.id IS NULL OR NOT public.can_read_seating_status(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='seating access required'; END IF;
 IF length(coalesce(p_search,''))>256 THEN RAISE invalid_parameter_value USING MESSAGE='search too long'; END IF;
 read_holders:=coalesce(public.can_read_orders(tr.occasion),false);
 WITH a AS MATERIALIZED(SELECT * FROM public.seating_admissions_internal(p_blueprint))
 SELECT jsonb_build_object('unassigned',count(*) FILTER(WHERE category='unassigned'),'assigned',count(*) FILTER(WHERE category='assigned'),
 'standing',count(*) FILTER(WHERE category='standing'),'blocked',count(*) FILTER(WHERE category='blocked'),'waiting',count(*) FILTER(WHERE category='waiting'),'offered',count(*) FILTER(WHERE category='offered')) INTO totals FROM a;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'formId',id,'revision',capacity_revision) ORDER BY id),'[]') INTO cohort
 FROM public.forms WHERE id IN(SELECT form_id FROM public.blueprint_seating_sources_internal(tr.id));
 rows_data:='[]';
 IF read_holders THEN
 WITH page AS(SELECT * FROM public.seating_admissions_internal(p_blueprint) WHERE (p_after IS NULL OR ticket_id>p_after)
 AND (p_category IS NULL OR category=p_category) AND (coalesce(p_search,'')='' OR concat_ws(' ',holder,ticket_symbol,order_symbol,ticket_id::text,order_id::text) ILIKE '%'||p_search||'%') ORDER BY ticket_id LIMIT lim)
 SELECT coalesce(jsonb_agg(jsonb_build_object('ticketId',ticket_id,'admissionItemId',item_id,'orderId',order_id,'formId',form_id,'productId',product_id,'productTitle',product_title,
 'spotId',spot_id,'category',category,'reason',reason,'ticketSymbol',ticket_symbol,'orderSymbol',order_symbol,'holder',holder) ORDER BY ticket_id),'[]'),CASE WHEN count(*)=lim THEN max(ticket_id) END INTO rows_data,last_id FROM page;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'title',s.title,'productId',s.product,'available',s.order_product_ticket IS NULL AND NOT sb.blocked AND NOT coalesce(s.secret_expiration_time>clock_timestamp() AND s.secret IS NOT NULL,false),
 'reason',CASE WHEN sb.blocked THEN 'SEAT_UNAVAILABLE' WHEN s.order_product_ticket IS NOT NULL THEN 'SEAT_UNAVAILABLE' WHEN s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp() THEN 'HOLD_ACTIVE' END,
 'unitSpotIds',public.blueprint_selection_unit_spots_internal(s.id)) ORDER BY s.id),'[]') INTO seats
 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot WHERE sb.blueprint=tr.id;
 WITH a AS MATERIALIZED(SELECT * FROM public.seating_admissions_internal(p_blueprint))
 SELECT coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'productTitle',product_title,'admissions',n,'seats',seat_count,'standing',area_count>0,
 'reason',CASE WHEN seat_count>0 AND area_count>0 THEN 'PLACEMENT_MODE_AMBIGUOUS' WHEN seat_count=0 AND area_count=0 THEN 'PRODUCT_MISMATCH' WHEN seat_count>0 AND seat_count<n THEN 'INVENTORY_CONFLICT' END) ORDER BY product_id),'[]') INTO compat
 FROM (SELECT product_id,max(product_title) product_title,count(*) n,
 (SELECT count(*) FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot WHERE sb.blueprint=tr.id AND s.product=a.product_id AND NOT sb.blocked) seat_count,
 (SELECT count(*) FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=tr.id AND ab.product=a.product_id) area_count
 FROM a WHERE category NOT IN ('waiting','offered') AND product_id IS NOT NULL GROUP BY product_id) q;
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('blueprintId',tr.id,'revision',tr.layout_revision,
 'layoutRevision',(SELECT layout_revision FROM eshop.blueprints WHERE id=tr.id),'cohort',cohort,'counts',totals,'items',rows_data,'nextCursor',last_id,'seats',seats,'compatibility',compat,
 'capabilities',jsonb_build_object('configure',coalesce(public.can_author_forms(tr.occasion),false),'readHolders',read_holders,'assign',public.can_assign_existing_admissions(tr.occasion))));
END $$;
REVOKE ALL ON FUNCTION public.get_blueprint_seating_context(bigint,text,text,bigint,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_blueprint_seating_context(bigint,text,text,bigint,integer) TO authenticated;

-- Source: database/functions/blueprint/seating_assignment.sql
-- SHA256: 0d265f90850d98d18bd2ee9b80c126aefea7b720697f302f1d39aa7724e434bb
-- Public adapters verify organizer authority; this private seam owns exact scope.
CREATE OR REPLACE FUNCTION public.seating_assignment_scope_internal(p_blueprint bigint,p_mappings jsonb)
RETURNS eshop.blueprints LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE tr eshop.blueprints; v_mapping jsonb;
BEGIN
 SELECT * INTO tr FROM eshop.blueprints WHERE id=p_blueprint;
 IF tr.id IS NULL OR NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF tr.layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 IF jsonb_typeof(p_mappings) IS DISTINCT FROM 'array' OR jsonb_array_length(p_mappings) NOT BETWEEN 1 AND least(256,(SELECT hard_cap FROM public.abuse_policy_rules WHERE rule_key='order.mutation.items')) OR octet_length(p_mappings::text)>131072 THEN
 RAISE invalid_parameter_value USING MESSAGE='invalid assignment batch'; END IF;
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) LOOP
 IF jsonb_typeof(v_mapping) IS DISTINCT FROM 'object' OR NOT v_mapping ?& ARRAY['ticketId','admissionItemId','expectedSpotId','targetSpotId']
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_mapping) k WHERE k NOT IN ('ticketId','admissionItemId','expectedSpotId','targetSpotId'))
 OR v_mapping->>'ticketId' IS NULL OR v_mapping->>'admissionItemId' IS NULL THEN
 RAISE invalid_parameter_value USING MESSAGE='exact changed item mapping required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket i JOIN eshop.orders o ON o.id=i."order"
 JOIN public.blueprint_seating_sources_internal(tr.id) source ON source.form_id=o.form
 WHERE i.id=(v_mapping->>'admissionItemId')::bigint AND i.ticket=(v_mapping->>'ticketId')::bigint AND o.occasion=tr.occasion)
 OR EXISTS(SELECT 1 FROM eshop.spots WHERE id IN ((v_mapping->>'expectedSpotId')::bigint,(v_mapping->>'targetSpotId')::bigint) AND (occasion<>tr.occasion OR blueprint IS DISTINCT FROM tr.id)) THEN
 RAISE insufficient_privilege USING MESSAGE='assignment context unavailable'; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_mappings) m WHERE m->'expectedSpotId' IS DISTINCT FROM m->'targetSpotId') THEN
 RAISE invalid_parameter_value USING MESSAGE='changed assignment batch required'; END IF;
 IF (SELECT count(DISTINCT value->>'admissionItemId') FROM jsonb_array_elements(p_mappings))<>jsonb_array_length(p_mappings)
 OR (SELECT count(*) FROM jsonb_array_elements(p_mappings) WHERE value->>'targetSpotId' IS NOT NULL)<>(SELECT count(DISTINCT value->>'targetSpotId') FROM jsonb_array_elements(p_mappings)) THEN
 RAISE invalid_parameter_value USING MESSAGE='duplicate assignment identity'; END IF;
 RETURN tr;
END $$;
REVOKE ALL ON FUNCTION public.seating_assignment_scope_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.seating_assignment_preview_internal(p_blueprint bigint,p_mappings jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE tr eshop.blueprints; v_mapping jsonb; a record; v_spot eshop.spots; why text; blockers jsonb:='[]'; mappings jsonb:='[]'; revisions jsonb; semantic jsonb; affected bigint[]; ids bigint[]; before_ids bigint[]; target_ids bigint[]; rev bigint;
BEGIN
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings);
 SELECT layout_revision INTO rev FROM eshop.blueprints WHERE id=tr.id;
 SELECT ARRAY(SELECT DISTINCT v FROM jsonb_array_elements(p_mappings) m CROSS JOIN LATERAL unnest(ARRAY[(m->>'expectedSpotId')::bigint,(m->>'targetSpotId')::bigint]) v WHERE v IS NOT NULL ORDER BY v) INTO ids;
 SELECT ARRAY(SELECT DISTINCT member FROM unnest(ids) id CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(id)) member ORDER BY member) INTO affected;
 -- Each side independently covers its complete units. A single item moving
 -- between two members cannot count as the two purchased couch admissions.
 SELECT ARRAY(SELECT (m->>'expectedSpotId')::bigint FROM jsonb_array_elements(p_mappings)m WHERE m->>'expectedSpotId' IS NOT NULL),
 ARRAY(SELECT (m->>'targetSpotId')::bigint FROM jsonb_array_elements(p_mappings)m WHERE m->>'targetSpotId' IS NOT NULL)
 INTO before_ids,target_ids;
 IF EXISTS(SELECT 1 FROM unnest(before_ids) requested CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member WHERE NOT member=ANY(before_ids))
 OR EXISTS(SELECT 1 FROM unnest(target_ids) requested CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member WHERE NOT member=ANY(target_ids)) THEN
 blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','ATOMIC_UNIT_INCOMPLETE')); END IF;
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) ORDER BY (value->>'admissionItemId')::bigint LOOP
 SELECT * INTO a FROM public.seating_admissions_internal(p_blueprint) WHERE ticket_id=(v_mapping->>'ticketId')::bigint AND item_id=(v_mapping->>'admissionItemId')::bigint;
 why:=NULL;
 IF NOT FOUND THEN why:='ADMISSION_DATA_AMBIGUOUS';
 ELSIF a.category NOT IN ('assigned','unassigned') THEN why:=coalesce(a.reason,'MODE_CHANGED');
 ELSIF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=a.ticket_id AND state='used') THEN why:='USED_TICKET_PROTECTED';
 ELSIF EXISTS(SELECT 1 FROM eshop.ticket_batch_items WHERE ticket_id=a.ticket_id) THEN why:='BATCH_TICKET_PRINT_IMMUTABLE';
 ELSIF a.spot_id IS DISTINCT FROM (v_mapping->>'expectedSpotId')::bigint THEN why:='CONTEXT_CHANGED'; END IF;
 IF why IS NULL AND v_mapping->>'targetSpotId' IS NOT NULL THEN
 SELECT * INTO v_spot FROM eshop.spots WHERE id=(v_mapping->>'targetSpotId')::bigint;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=tr.id AND spot=v_spot.id AND NOT blocked) THEN why:='SEAT_UNAVAILABLE';
 ELSIF v_spot.product IS DISTINCT FROM a.product_id THEN why:='PRODUCT_MISMATCH';
 ELSIF v_spot.order_product_ticket IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_mappings) other WHERE (other->>'admissionItemId')::bigint=v_spot.order_product_ticket AND (other->>'expectedSpotId')::bigint=v_spot.id) THEN why:='SEAT_UNAVAILABLE';
 ELSIF v_spot.secret IS NOT NULL AND v_spot.secret_expiration_time>clock_timestamp() THEN why:='HOLD_ACTIVE';
 ELSIF v_spot.inventory_context IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts WHERE product=a.product_id AND inventory_context=v_spot.inventory_context) THEN why:='INVENTORY_CONFLICT'; END IF;
 END IF;
 IF why IS NOT NULL THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason',why,'ticketId',v_mapping->'ticketId','spotId',v_mapping->'targetSpotId')); END IF;
 mappings:=mappings||jsonb_build_array(v_mapping||jsonb_build_object('formId',a.form_id,'productId',a.product_id));
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'revision',t.capacity_revision) ORDER BY t.id),'[]') INTO revisions
 FROM public.forms t WHERE t.id IN (SELECT (m->>'formId')::bigint FROM jsonb_array_elements(mappings) m);
 semantic:=jsonb_build_object('mappings',mappings,'revisions',revisions,'layoutRevision',rev,'blockers',blockers,
 'seats',(SELECT jsonb_agg(to_jsonb(s)-'updated_at'-'created_at' ORDER BY s.id) FROM eshop.spots s WHERE s.id=ANY(affected)),
 'bindings',(SELECT jsonb_agg(to_jsonb(sb) ORDER BY sb.spot) FROM eshop.blueprint_seat_bindings sb WHERE sb.spot=ANY(affected)),
 'admissions',(SELECT jsonb_agg(jsonb_build_object('item',to_jsonb(i),'ticket',to_jsonb(t)-'updated_at','order',to_jsonb(o)-'updated_at','payment',to_jsonb(pi)) ORDER BY i.id)
 FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket JOIN eshop.orders o ON o.id=i."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE i.id IN (SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m)),
 'allocations',(SELECT jsonb_agg(jsonb_build_array(s.id,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id) FROM eshop.spots s WHERE s.order_product_ticket IN(SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m)),
 'requirements',(SELECT jsonb_agg(to_jsonb(pic) ORDER BY pic.product,pic.inventory_context) FROM eshop.product_inventory_contexts pic WHERE product IN(SELECT (m->>'productId')::bigint FROM jsonb_array_elements(mappings)m)));
 RETURN jsonb_build_object('fingerprint',encode(extensions.digest(semantic::text,'sha256'),'hex'),'revisions',revisions,'mappings',mappings,'blockers',blockers,'layoutRevision',rev);
END $$;
REVOKE ALL ON FUNCTION public.seating_assignment_preview_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.preview_ticket_seat_assignment(p_blueprint bigint,p_mappings jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('code',200,'data',public.seating_assignment_preview_internal(p_blueprint,p_mappings))
$$;
REVOKE ALL ON FUNCTION public.preview_ticket_seat_assignment(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_ticket_seat_assignment(bigint,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_ticket_seat_assignments(p_blueprint bigint,p_mappings jsonb,p_fingerprint text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr eshop.blueprints; started jsonb; preview jsonb; v_orders bigint[]; v_items bigint[]; v_spots bigint[]; v_products bigint[]; v_mapping jsonb; dest eshop.spots; required integer; occupied integer; spare bigint; oid bigint; touched bigint[];
BEGIN
 SELECT * INTO tr FROM eshop.blueprints WHERE id=p_blueprint;
 IF tr.id IS NULL OR NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF tr.layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name='seating.assignment.set') THEN
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings); END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[tr.occasion]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.assignment.set',tr.occasion,auth.uid(),encode(extensions.digest(jsonb_build_array(p_blueprint,p_mappings,p_fingerprint)::text,'sha256'),'hex'));
 IF NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings);
 PERFORM public.admit_order_mutation_v1(tr.occasion,jsonb_array_length(p_mappings));
 SELECT ARRAY(SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m ORDER BY 1) INTO v_items;
 SELECT array_agg(DISTINCT "order" ORDER BY "order"),array_agg(DISTINCT product ORDER BY product) INTO v_orders,v_products FROM eshop.order_product_ticket WHERE id=ANY(v_items);
 PERFORM 1 FROM public.forms WHERE id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders)) ORDER BY id FOR UPDATE;
 -- Lock union of before/after units and all allocation parents before children.
 SELECT ARRAY(SELECT DISTINCT s.id FROM eshop.spots s WHERE s.order_product_ticket=ANY(v_items)
 OR s.inventory_context IN(SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(v_products))
 OR s.id IN(SELECT member FROM jsonb_array_elements(p_mappings)m CROSS JOIN LATERAL unnest(ARRAY[(m->>'expectedSpotId')::bigint,(m->>'targetSpotId')::bigint]) id CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(id)) member) ORDER BY s.id) INTO v_spots;
 PERFORM public.lock_spot_assignment_scope_internal(v_spots,'{}',true,v_products,false,v_orders,v_items);
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings);
 preview:=public.seating_assignment_preview_internal(p_blueprint,p_mappings);
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
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders));
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,tr.occasion,'seating.assignment.set',
 jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',tr.id,'operation','update','safeLabel','Admission placement','changedFields',jsonb_build_array('seating'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=tr.occasion),jsonb_build_object('blueprintId',tr.id,'mappings',preview->'mappings','context',public.get_blueprint_seating_context(tr.id)->'data'));
END $$;
REVOKE ALL ON FUNCTION public.set_ticket_seat_assignments(bigint,jsonb,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_ticket_seat_assignments(bigint,jsonb,text,uuid) TO authenticated;

-- Source: database/functions/blueprint/admission_seating.sql
-- SHA256: a371a80535b49d1eab2959ad187e308085ce071003a12c1abf642e39d1af0534
-- Applied by every materializer, including stale/editor/direct callers.
CREATE OR REPLACE FUNCTION public.assert_admission_seating_internal(p_form bigint,p_product bigint,p_spot bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE bp bigint; bound_bp bigint;
BEGIN
 SELECT f.blueprint INTO bp FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form
 AND jsonb_path_exists(o.features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)');
 SELECT min(f.blueprint) INTO bound_bp FROM public.forms f JOIN public.occasions owner ON owner.id=f.occasion
 JOIN eshop.spots s ON s.blueprint=f.blueprint AND s.product=p_product JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
 WHERE jsonb_path_exists(owner.features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)');
 IF bound_bp IS NOT NULL AND (bp IS DISTINCT FROM bound_bp OR p_spot IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.spots WHERE id=p_spot AND blueprint=bp AND product=p_product)) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
 IF bp IS NOT NULL AND p_spot IS NULL AND EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id WHERE sb.blueprint=bp AND s.product=p_product)
 AND NOT EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings WHERE blueprint=bp AND product=p_product) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_admission_seating_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_form_seating_source_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id AND NOT ff.is_hidden
 JOIN eshop.products p ON p.product_type=ff.product_type AND NOT p.is_hidden
 JOIN eshop.spots s ON s.product=p.id JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
 JOIN public.forms bound ON bound.blueprint=sb.blueprint JOIN public.occasions owner ON owner.id=bound.occasion
 WHERE f.id=p_form AND f.is_open AND jsonb_path_exists(owner.features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)') AND f.blueprint IS DISTINCT FROM bound.blueprint) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_form_seating_source_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/blueprint/save.sql
-- SHA256: c6eca6a5c78c43c525af33fbc19c306c799680041072a177266d498372f7a8d4
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_impl_internal(p_blueprint jsonb,p_reviewed_demo boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean; assignment_mode text;
 pool public.inventory_pools; capacity_int bigint; physical_supply bigint;
 node_index jsonb; unit_index jsonb; seat_count bigint; text_ids text[]:='{}';
 doc jsonb:=p_blueprint->'layout'; result jsonb; expected bigint; issue text; all_seats uuid[]; supplied uuid[];
BEGIN
 IF nullif(p_blueprint->>'id','') IS NULL THEN
  IF public.can_write_blueprints((p_blueprint->>'occasion')::bigint) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  INSERT INTO eshop.blueprints(occasion,organization,title) SELECT id,organization,p_blueprint->>'title' FROM public.occasions WHERE id=(p_blueprint->>'occasion')::bigint RETURNING * INTO b;
 ELSE
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint;
  PERFORM 1 FROM eshop.products WHERE occasion=b.occasion ORDER BY id FOR UPDATE;
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint FOR UPDATE;
 END IF;
 IF b.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_NOT_FOUND'; END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF NOT public.can_migrate_reviewed_legacy_blueprint(b.occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint migration reviewer required'; END IF;
 ELSE
 IF public.can_write_blueprints(b.occasion) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF b.layout IS NOT NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_INITIAL_LAYOUT_REQUIRED'; END IF;
 ELSE PERFORM public.check_occasion_writable(b.occasion); END IF;
 expected:=(p_blueprint->>'expected_layout_revision')::bigint;
 IF expected IS NULL OR expected<>b.layout_revision THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
 PERFORM public.validate_blueprint_layout_internal(doc);
  PERFORM public.check_blueprint_text_resources_internal(doc,b.occasion);
  text_ids:=public.blueprint_text_resource_ids_internal(doc,b.occasion);
  IF jsonb_typeof(p_blueprint->'textResourceIds') IS DISTINCT FROM 'array'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_blueprint->'textResourceIds') id WHERE jsonb_typeof(id)<>'string')
    OR (SELECT coalesce(array_agg(id ORDER BY id),'{}'::text[]) FROM jsonb_array_elements_text(p_blueprint->'textResourceIds') id) IS DISTINCT FROM text_ids
    THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_REFS_MISMATCH'; END IF;

 PERFORM public.check_blueprint_image_resource_internal(doc,b.occasion);
 PERFORM public.check_blueprint_bitmap_resources_internal(doc,b.occasion);
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}'),count(*) FILTER(WHERE x->>'kind'='seat') INTO node_index,seat_count FROM jsonb_array_elements(doc->'nodes') x;
 -- Membership is projected from the document, never trusted from an overlay.
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u WHERE
   (u->>'id')::uuid IS NULL OR jsonb_array_length(u->'nodeIds')=0 OR coalesce(u->>'kind','atomic')<>'atomic')
  OR EXISTS(SELECT member FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member GROUP BY member HAVING count(*)>1)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member
   WHERE coalesce(node_index->member->>'kind','')<>'seat') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SELECTION_UNITS'; END IF;
 SELECT coalesce(jsonb_object_agg(member,u->>'id'),'{}') INTO unit_index
 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member;
 PERFORM public.lock_blueprint_inventory_internal(b.occasion,b.id);
 PERFORM public.check_batch_blueprint_print_immutable_internal(b.id,doc);
 PERFORM public.check_blueprint_block_changes_internal(b.id,doc,p_blueprint->'seatChanges');
 IF EXISTS(SELECT change->>'nodeId' FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) change GROUP BY change->>'nodeId' HAVING count(*)>1) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_DUPLICATE_SEAT_CHANGE'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid;
  SELECT * INTO binding FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN
   IF binding.node_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_NOT_FOUND',DETAIL=c::text; END IF;
   SELECT * INTO s FROM eshop.spots WHERE id=binding.spot;
   IF s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
   DELETE FROM eshop.spots WHERE id=s.id;
   CONTINUE;
  END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'seat' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SEAT_CHANGE',DETAIL=c::text; END IF;
  IF NOT c ? 'productId' OR NOT c ? 'blocked' OR NOT c ? 'groupNodeId' OR NOT c ? 'selectionUnitId' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_SEAT_CHANGE',DETAIL=c::text; END IF;
  assignment_mode:=coalesce(c->>'productAssignmentMode','override');
  IF assignment_mode NOT IN ('inherit','override') OR NOT c ? 'productAssignmentMode' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRODUCT_ASSIGNMENT_MODE'; END IF;
  product_id:=(c->>'productId')::bigint; group_id:=(c->>'groupNodeId')::uuid; unit_id:=(c->>'selectionUnitId')::uuid; blocked_value:=(c->>'blocked')::boolean;
  IF blocked_value IS NULL OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_PRODUCT',DETAIL=c::text; END IF;
  IF group_id IS NOT NULL AND coalesce(node_index->group_id::text->>'kind','') NOT IN ('group','table','furniture') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP',DETAIL=c::text; END IF;
  IF unit_id IS DISTINCT FROM (unit_index->>node::text)::uuid THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_UNIT_MEMBERSHIP_MISMATCH',DETAIL=c::text; END IF;
  spot_id:=(c->>'spotId')::bigint;
  IF binding.node_id IS NOT NULL AND spot_id IS DISTINCT FROM binding.spot THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_IDENTITY_CHANGED',DETAIL=c::text; END IF;
  IF spot_id IS NOT NULL THEN
   SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=b.id AND occasion=b.occasion;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_SCOPE_MISMATCH',DETAIL=c::text; END IF;
   IF (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()))
    AND (s.product IS DISTINCT FROM product_id OR s.title IS DISTINCT FROM c->>'title'
     OR coalesce(binding.blocked,false) IS DISTINCT FROM blocked_value OR binding.selection_unit IS DISTINCT FROM unit_id OR binding.group_node IS DISTINCT FROM group_id OR binding.product_assignment_mode IS DISTINCT FROM assignment_mode) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   UPDATE eshop.spots SET product=product_id,title=c->>'title',updated_at=now() WHERE id=spot_id
    AND (product IS DISTINCT FROM product_id OR title IS DISTINCT FROM c->>'title');
  ELSE
   INSERT INTO eshop.spots(blueprint,occasion,product,title) VALUES(b.id,b.occasion,product_id,c->>'title') RETURNING id INTO spot_id;
  END IF;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
   VALUES(b.id,node,spot_id,unit_id,group_id,blocked_value,assignment_mode)
   ON CONFLICT(blueprint,node_id) DO UPDATE SET selection_unit=excluded.selection_unit,group_node=excluded.group_node,blocked=excluded.blocked,product_assignment_mode=excluded.product_assignment_mode;
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND coalesce(node_index->sb.node_id::text->>'kind','')<>'seat')
  OR (SELECT count(*) FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id)<>seat_count
  OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.selection_unit IS DISTINCT FROM
   (unit_index->>sb.node_id::text)::uuid) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_SET_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.group_node IS NOT NULL AND coalesce(node_index->sb.group_node::text->>'kind','') NOT IN ('group','table','furniture')) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'groupProductChanges','[]')) LOOP
  IF NOT c ? 'productId' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_GROUP_CHANGE',DETAIL=c::text; END IF;
  node:=(c->>'groupNodeId')::uuid; product_id:=(c->>'productId')::bigint;
  IF coalesce(node_index->node::text->>'kind','') NOT IN ('table','group','furniture')
   OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP_PRODUCT',DETAIL=c::text; END IF;
  DELETE FROM eshop.blueprint_group_products WHERE blueprint=b.id AND group_node=node;
  IF product_id IS NOT NULL THEN INSERT INTO eshop.blueprint_group_products VALUES(b.id,node,product_id); END IF;
 END LOOP;
 DELETE FROM eshop.blueprint_group_products gp WHERE blueprint=b.id AND NOT node_index ? gp.group_node::text;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots bound_spot ON bound_spot.id=sb.spot LEFT JOIN eshop.blueprint_group_products gp ON gp.blueprint=sb.blueprint AND gp.group_node=sb.group_node WHERE sb.blueprint=b.id AND sb.product_assignment_mode='inherit' AND (sb.group_node IS NULL OR gp.product IS NULL)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INHERITED_PRODUCT_MISMATCH'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'areaBindingChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid; product_id:=(c->>'productId')::bigint;
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN CONTINUE; END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'capacityArea'
   OR NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=product_id AND pic.inventory_context=(c->>'inventoryContextId')::bigint AND p.occasion=b.occasion AND ip.occasion=b.occasion) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_AREA_BINDING',DETAIL=c::text; END IF;
  IF c ? 'capacity' THEN
   capacity_int:=(c->>'capacity')::bigint;
   IF capacity_int IS NULL OR capacity_int<0 OR capacity_int>1000000 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
   SELECT ip.* INTO pool FROM public.inventory_pools ip JOIN public.inventory_contexts ic ON ic.inventory_pool=ip.id WHERE ic.id=(c->>'inventoryContextId')::bigint;
   PERFORM public.update_inventory_pool_bundle(jsonb_build_object('pool',jsonb_build_object(
    'id',pool.id,'occasion',pool.occasion,'title',pool.title,
    'description',pool.description,'type',pool.type,'data',pool.data,
    'sellable_capacity',capacity_int)));
   -- The standing count owns the complete setup: a higher count must also
   -- provide real supply. Preserve existing resources/allocations and add only
   -- the missing quantity through the canonical inventory resource command.
   SELECT coalesce(sum(r.capacity),0) INTO physical_supply
    FROM public.resources r WHERE r.inventory_pool=pool.id;
   IF physical_supply<capacity_int THEN
    PERFORM public.update_resource(jsonb_build_object('inventory_pool',pool.id,
     'title',coalesce(pool.title,b.title),'capacity',capacity_int-physical_supply));
   END IF;
  END IF;
  INSERT INTO eshop.blueprint_area_bindings VALUES(b.id,node,(c->>'inventoryContextId')::bigint,product_id);
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab WHERE blueprint=b.id AND coalesce(node_index->ab.node_id::text->>'kind','')<>'capacityArea') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_AREA_BINDING_SET_MISMATCH'; END IF;
 UPDATE eshop.blueprints SET layout=doc,layout_text_resource_ids=text_ids,layout_revision=layout_revision+1,updated_at=now(),title=coalesce(p_blueprint->>'title',title) WHERE id=b.id RETURNING * INTO b;
 result:=public.blueprint_binding_projection_internal(b.id)||jsonb_build_object('code',200,'blueprint_id',b.id,'layout_revision',b.layout_revision,
  'document_hash',encode(extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),'hex'));
 IF octet_length(result::text)>4194304 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_RESULT_TOO_LARGE'; END IF;
 PERFORM public.sync_form_blueprint_internal(id) FROM public.forms WHERE occasion=b.occasion ORDER BY id;
 PERFORM public.assert_form_seating_source_internal(id) FROM public.forms WHERE occasion=b.occasion;
 PERFORM public.notification_center_blueprint_capacity_internal(b.id);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_impl_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Runtime entry always enforces occasion writability, including demo read-only.
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_internal_v1(p_blueprint jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.save_blueprint_layout_impl_internal(p_blueprint,false);
$$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/eshop_forms/update_form.sql
-- SHA256: 444d16c60cab6fceb32b748a12decac46fd1f87082fde75e6d00386e000fc2e3
CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    availability_at timestamptz;
    form_metadata jsonb;
    previous_form_metadata jsonb;
    analytics_write_requested boolean;
    availability_new boolean;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;
    protected_primary_types bigint[];

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic


        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT public.can_author_forms(occasion_id) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        PERFORM public.notification_center_initialized_internal(occasion_org);
        PERFORM public.lock_blueprint_scope_internal(ARRAY[occasion_id]);
        availability_at:=clock_timestamp();
        form_id := NULLIF(input_data->>'id','')::bigint;
        availability_new:=form_id IS NULL;
        IF form_id IS NOT NULL THEN
          IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          PERFORM 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id FOR UPDATE;
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        IF form_id IS NULL THEN
          INSERT INTO public.forms(created_at,occasion) VALUES(now_ts,occasion_id) RETURNING id INTO form_id;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',true);
        ELSE
          IF NOT EXISTS (SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN
            RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',false);
        END IF;

        IF input_data ? 'settings' AND input_data ? 'data' THEN
          RAISE invalid_parameter_value USING MESSAGE='choose settings patch or released metadata, not both'; END IF;
        SELECT data INTO form_metadata FROM public.forms WHERE id=form_id;
        previous_form_metadata:=form_metadata;
        -- Preserve explicit reset intent before legacy presale ingress turns a
        -- settings patch into a full metadata candidate with removed keys.
        analytics_write_requested:=CASE WHEN input_data ? 'settings' THEN
          coalesce((input_data->'settings') ? 'analytics',false) ELSE
          public.normalize_form_metadata_internal(input_data->'data') ? 'analytics' END;
        PERFORM public.guard_form_payment_write_internal(form_metadata,form_metadata,input_data);
        input_data:=public.guard_form_presale_write_internal(form_metadata,input_data);
        IF input_data ? 'settings' THEN
          form_metadata:=public.apply_form_settings_internal(form_metadata,input_data->'settings');
        ELSIF input_data ? 'data' THEN
          -- Released full-metadata boundary, same settings owner/validation.
          form_metadata:=public.normalize_form_metadata_internal(input_data->'data')
            ||CASE WHEN NOT public.normalize_form_metadata_internal(input_data->'data') ? 'sale_opening_notifications'
              AND public.normalize_form_metadata_internal(form_metadata) ? 'sale_opening_notifications'
              THEN jsonb_build_object('sale_opening_notifications',public.normalize_form_metadata_internal(form_metadata)->'sale_opening_notifications') ELSE '{}'::jsonb END;
          -- Released clients predate embed_inherit_style. Omission in their full
          -- metadata is not a request to reset a newer setting. An explicit null
          -- or boolean still goes through the one settings validator below.
          IF jsonb_typeof(coalesce(nullif(form_metadata->'design','null'::jsonb),'{}'::jsonb))='object'
            AND NOT coalesce(form_metadata->'design','{}'::jsonb) ? 'embed_inherit_style'
            AND public.normalize_form_metadata_internal(previous_form_metadata)#>'{design,embed_inherit_style}' IS NOT NULL THEN
            form_metadata:=jsonb_set(form_metadata,'{design}',
              coalesce(nullif(form_metadata->'design','null'::jsonb),'{}'::jsonb) ||
              jsonb_build_object('embed_inherit_style',public.normalize_form_metadata_internal(previous_form_metadata)#>'{design,embed_inherit_style}'));
          END IF;
          IF NOT analytics_write_requested AND NOT form_metadata ? 'analytics'
            AND public.normalize_form_metadata_internal(previous_form_metadata) ? 'analytics' THEN
            form_metadata:=form_metadata||jsonb_build_object('analytics',public.normalize_form_metadata_internal(previous_form_metadata)->'analytics');
          END IF;
          IF jsonb_typeof(form_metadata->'analytics')='object' THEN
            form_metadata:=jsonb_set(form_metadata,'{analytics}',
              coalesce(nullif(public.normalize_form_metadata_internal(previous_form_metadata)->'analytics','null'::jsonb),'{}'::jsonb) || (form_metadata->'analytics'));
          END IF;
          -- Full metadata from released clients owns only its bank/Stripe part.
          form_metadata:=jsonb_set(form_metadata,'{payments}',public.merge_form_payments_internal(
            previous_form_metadata->'payments',public.normalize_form_metadata_internal(input_data->'data')->'payments'));
          form_metadata:=public.apply_form_settings_internal(form_metadata,
            public.form_settings_from_metadata_internal(form_metadata));
        END IF;

        form_metadata:=public.guard_form_payment_write_internal(previous_form_metadata,form_metadata,input_data);
        IF form_metadata#>>'{payment_deadline,mode}' IN ('inherit','none') AND
          (coalesce(input_data->'settings',input_data->'data','{}'::jsonb) ? 'payment_deadline'
            OR form_metadata#>'{payments,cashEnabled}'='true'::jsonb) THEN
          input_data:=input_data||'{"deadline_duration_seconds":null}'::jsonb;
        END IF;

        -- Form writers can change only the boolean intent, never Unit destination code.
        -- Bind permission to the stored form/occasion after normalization.
        IF form_metadata->'analytics' IS DISTINCT FROM public.normalize_form_metadata_internal(previous_form_metadata)->'analytics'
          AND NOT public.can_manage_form_measurement(occasion_id) THEN
          RAISE insufficient_privilege USING MESSAGE='form author required to change measurement intent'; END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT coalesce(array_agg(DISTINCT pt.id),'{}'::bigint[]) INTO protected_primary_types
        FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
        WHERE ff.form=form_id AND pt.type='spot';
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
            WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);
        DELETE FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion'
          AND scope_id=occasion_id AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(deleted_products) id));

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                IF field_data->>'type' IN ('select_one','select_many') THEN
                    IF jsonb_typeof(field_data#>'{data,options}') IS DISTINCT FROM 'array' THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                    IF jsonb_array_length(field_data#>'{data,options}') = 0
                       OR EXISTS (SELECT 1 FROM jsonb_array_elements(field_data#>'{data,options}') option
                           WHERE jsonb_typeof(option->'value') IS DISTINCT FROM 'string'
                              OR btrim(option->>'value') = '') THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                END IF;
                field_id := NULLIF(field_data->>'id', '')::BIGINT;
                IF field_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields WHERE id=field_id AND form=form_id) THEN
                  RAISE invalid_parameter_value USING MESSAGE='Foreign form field'; END IF;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF field_data ? 'product_type_id' THEN
                    field_product_type := (field_data->>'product_type_id')::bigint;
                    IF field_product_type IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types
                      WHERE id=field_product_type AND occasion=occasion_id) THEN
                      RAISE invalid_parameter_value USING MESSAGE='Foreign product type'; END IF;
                ELSIF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    PERFORM public.advance_ticketing_authoring_version_internal_v1('product_type',occasion_id,product_type_id);
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            PERFORM public.advance_ticketing_authoring_version_internal_v1('product',occasion_id,product_id);
                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = CASE WHEN field_data ? 'data' THEN field_data->'data' ELSE data END,
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = CASE WHEN field_data ? 'product_type' OR field_data ? 'product_type_id' THEN field_product_type ELSE product_type END,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        IF input_data->>'blueprint' IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM eshop.blueprints WHERE id=(input_data->>'blueprint')::bigint AND occasion=occasion_id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',403,'message','Foreign blueprint')::text; END IF;
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = CASE WHEN input_data ? 'title' THEN input_data->>'title' ELSE title END,
               -- Opening the real form ends its initial preparation phase.
               -- Later closing it is a pause, irrespective of test orders.
               data = CASE WHEN coalesce((input_data->>'is_open')::boolean,is_open) THEN
                 jsonb_set(coalesce(form_metadata,'{}'::jsonb),'{schedule}',
                  coalesce((form_metadata)->'schedule','{}'::jsonb)
                   ||'{"sale_preparation":false}'::jsonb)
                 ELSE form_metadata END,
               header = CASE WHEN input_data ? 'header' THEN input_data->>'header' ELSE header END,
               header_off = CASE WHEN input_data ? 'header_off' THEN input_data->>'header_off' ELSE header_off END,
               link = link_param,
               blueprint = CASE WHEN input_data ? 'blueprint' THEN NULLIF(input_data->>'blueprint','')::BIGINT ELSE blueprint END,
               bank_account = CASE WHEN input_data ? 'bank_account' THEN bank_account_val ELSE bank_account END,
               deadline_duration_seconds = CASE WHEN input_data ? 'deadline_duration_seconds' THEN deadline_val ELSE deadline_duration_seconds END,
               is_open = CASE WHEN input_data ? 'is_open' THEN (input_data->>'is_open')::boolean ELSE is_open END
         WHERE id = form_id;

        IF input_data ? 'form_fields' OR cardinality(deleted_fields)>0 OR cardinality(deleted_products)>0 THEN
          PERFORM public.assert_form_primary_products_internal(form_id,protected_primary_types);
        END IF;
        PERFORM public.validate_form_payment_configuration_internal(form_id);

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        PERFORM public.queue_payment_reminders(occasion_id, COALESCE(v_seconds_before_deadline,86400));

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        PERFORM public.sync_form_blueprint_internal(form_id);
        PERFORM public.assert_form_seating_source_internal(form_id);
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'link', link_param,
            'form_fields', form_fields_data
        );

        PERFORM public.sync_sale_opening_settings_internal(form_id,previous_form_metadata);

        IF availability_new THEN
          PERFORM public.notification_center_form_created_internal(form_id);
        ELSE
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        PERFORM public.notification_center_form_capacity_internal(form_id);
    EXCEPTION WHEN raise_exception THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.update_form_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/eshop_forms/form_creation_domain.sql
-- SHA256: 8237165d9dd00f0e4181b7f2796e1073162fa68dcd110939a02a17eb770e591a
-- Shared form construction. Invoker-only, private to explicit checked owners.
CREATE OR REPLACE FUNCTION public.insert_form_for_occasion_internal_v1(p_occasion_id bigint, p_link text, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    now TIMESTAMPTZ := NOW();
    payment_default text;
    initial_data jsonb := '{"is_reminder_enabled": true,"design":{"presale_header":"event_and_date"}}'::jsonb;
BEGIN
    SELECT org.data->>'DEFAULT_FORM_PAYMENT_METHOD' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default='cash' THEN
      initial_data := initial_data || '{"payments":{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}},"payment_deadline":{"mode":"none"}}'::jsonb;
    ELSIF public.payment_method_is_online_internal(payment_default) THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
    PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion_id));
    -- Create the new form
    INSERT INTO public.forms(
        title,
        is_open,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        false,
        NULL,
        p_occasion_id,
        now,
        now,
        NULL, -- New forms inherit the occasion policy; legacy stored durations stay custom.
        initial_data
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,p_link,true) WHERE id=new_form_id;
    SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Ensure 'spot' product type exists for the occasion
    IF NOT EXISTS (SELECT 1 FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot') THEN
        INSERT INTO eshop.product_types(title, type, occasion)
        VALUES ('Spot', 'spot', p_occasion_id)
        RETURNING id INTO new_product_type_id;
    ELSE
        SELECT id INTO new_product_type_id FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot' LIMIT 1;
    END IF;

    -- Ensure the 'spot' product type has at least one product
    IF NOT EXISTS (SELECT 1 FROM eshop.products WHERE occasion = p_occasion_id AND product_type = new_product_type_id) THEN
        INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
        VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    IF EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion_id AND
      jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
      INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden,"order")
      VALUES(new_form_id,'spot',true,true,false,-1);
      PERFORM public.sync_form_blueprint_internal(new_form_id);
      SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;
    END IF;

    -- Return the raw data of the newly created form
    PERFORM public.notification_center_form_created_internal(new_form_id);
    RETURN new_form;
END;
$function$;
REVOKE ALL ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) TO postgres;

-- Only the explicit occasion-create owner calls this initial-form boundary.
-- Manager-only creation uses its own domain right, not a fabricated editor role.
CREATE OR REPLACE FUNCTION public.create_initial_occasion_form_internal_v1(p_occasion_id bigint,p_link text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(v_unit)
    OR EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion_id) THEN
    RAISE insufficient_privilege USING MESSAGE='initial occasion form creation unavailable';
  END IF;
  PERFORM public.check_occasion_writable(p_occasion_id);
  RETURN public.insert_form_for_occasion_internal_v1(p_occasion_id,p_link,p_title);
END $$;
REVOKE ALL ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) TO postgres;

-- Source: database/functions/others/update_occasion.sql
-- SHA256: f02015d2039227fc38ddea200fd723e7024d4082dd05a3ee99e472e081f2b0a5
CREATE OR REPLACE FUNCTION public.update_occasion_internal_v1(input_data JSONB)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 AS $$
 DECLARE
     updated_occ public.occasions;
     occ_id BIGINT;
     now TIMESTAMPTZ := NOW();
     final_unit BIGINT;

     -- Variable for the determined support flag
     is_app_supported BOOLEAN;

     -- Variable to help find the organization to check settings
     v_org_id BIGINT;

     -- Variables for feature handling
     new_blueprint_id BIGINT;
     v_form_id BIGINT;
     v_form_blueprint BIGINT;
     v_form_settings JSONB;
     v_form_link TEXT;
     v_reminder_interval_seconds BIGINT;
     v_email_order record;

     input_features JSONB;
     old_features JSONB;
     old_sync_enabled boolean := false;
     processed_features JSONB;
     feature JSONB;
     form_feature_found BOOLEAN;
 BEGIN
     -- Validate input data. Raise an exception if it's missing or empty.
     IF input_data IS NULL OR input_data = '{}'::jsonb THEN
         RAISE EXCEPTION 'Input data is missing or empty';
     END IF;

     -- 1. Identify the Organization ID
     IF (input_data->>'id') IS NOT NULL THEN
         -- Case A: UPDATE - Get organization from the existing occasion
         SELECT organization INTO v_org_id
         FROM public.occasions
         WHERE id = (input_data->>'id')::BIGINT;
     ELSE
         -- Case B: INSERT - Try to get organization from input
         v_org_id := (input_data->>'organization')::BIGINT;

         -- Case C: INSERT fallback - If org is missing, try to get it via the Unit
         IF v_org_id IS NULL AND (input_data->>'unit') IS NOT NULL THEN
            SELECT organization INTO v_org_id
            FROM public.units
            WHERE id = (input_data->>'unit')::BIGINT;
         END IF;
     END IF;

     -- 2. Fetch the setting from public.organizations.data
     -- Defaults to TRUE if the organization or the key is not found to ensure backward compatibility
     IF v_org_id IS NOT NULL THEN
         SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
         INTO is_app_supported
         FROM public.organizations
         WHERE id = v_org_id;
     ELSE
         is_app_supported := false;
     END IF;

     -- Ensure is_app_supported is not null (redundant safety check)
     is_app_supported := COALESCE(is_app_supported, false);

     --
     -- Prepare features based on is_app_supported flag
     --
     input_features := COALESCE(input_data->'features', '[]'::jsonb);
     processed_features := '[]'::jsonb;

     IF NOT is_app_supported THEN
         -- If the app is not supported, we must enable the 'form' feature.
         form_feature_found := false;
         -- Loop through existing features to find and enable the form feature
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             IF feature->>'code' = 'form' THEN
                 -- If form feature exists, ensure it is enabled
                 feature := feature || '{"is_enabled": true}';
                 form_feature_found := true;
             END IF;
             processed_features := processed_features || feature;
         END LOOP;

         -- If the form feature was not found in the original array, add it.
         IF NOT form_feature_found THEN
             processed_features := processed_features || '{"code": "form", "is_enabled": true}';
         END IF;
     ELSE
         -- If app is supported, use features as they were provided.
         processed_features := input_features;
     END IF;

     -- Determine if this is an UPDATE or INSERT based on the presence of an 'id'
     occ_id := (input_data->>'id')::BIGINT;

     IF occ_id IS NOT NULL THEN
         PERFORM public.lock_blueprint_scope_internal(ARRAY[occ_id]);
         PERFORM public.check_occasion_writable(occ_id);
         -- This is an UPDATE operation

         -- Check for the existence of the occasion and get its current unit
         SELECT unit, features, is_order_synchronization_enabled INTO final_unit, old_features, old_sync_enabled FROM public.occasions WHERE id = occ_id FOR UPDATE;
         IF NOT FOUND THEN
             RAISE EXCEPTION 'Occasion with ID % not found', occ_id;
         END IF;

         processed_features := public.merge_ticket_layout_features(old_features, processed_features, input_data->'ticket_layout_change');
         PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';

         -- Determine the final unit, allowing it to be updated.
         final_unit := COALESCE((input_data->>'unit')::BIGINT, final_unit);

         -- Security check: ensure the current user has editor rights on the target unit.
         IF NOT public.can_edit_occasion(occ_id,final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         IF (input_data ? 'organization' AND (input_data->>'organization')::bigint IS DISTINCT FROM v_org_id)
           OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=final_unit AND organization=v_org_id) THEN
           RAISE insufficient_privilege USING MESSAGE='Occasion tenant cannot change'; END IF;

         IF jsonb_path_exists(coalesce(old_features,'[]'), '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
           AND NOT jsonb_path_exists(processed_features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
           IF EXISTS(SELECT 1 FROM public.forms WHERE occasion=occ_id AND blueprint IS NOT NULL)
             OR EXISTS(SELECT 1 FROM eshop.spots WHERE occasion=occ_id AND blueprint IS NOT NULL AND
               (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))) THEN
             RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
         END IF;

         UPDATE public.occasions
            SET updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',false),
                data        = COALESCE(input_data->'data', data),
                is_hidden   = COALESCE((input_data->>'is_hidden')::BOOLEAN, is_hidden),
                is_open     = COALESCE((input_data->>'is_open')::BOOLEAN, is_open),
                is_promoted = COALESCE((input_data->>'is_promoted')::BOOLEAN, is_promoted),
                start_time  = COALESCE((input_data->>'start_time')::TIMESTAMPTZ, start_time),
                end_time    = COALESCE((input_data->>'end_time')::TIMESTAMPTZ, end_time),
                organization = COALESCE((input_data->>'organization')::BIGINT, organization),
                services    = COALESCE(input_data->'services', services),
                unit        = final_unit,
                is_order_synchronization_enabled=COALESCE((input_data->>'is_order_synchronization_enabled')::boolean,is_order_synchronization_enabled),
                features    = processed_features -- Use the processed features
          WHERE id = occ_id
          RETURNING * INTO updated_occ;

     ELSE
         -- This is an INSERT operation

         -- For new occasions, the 'unit' field is mandatory.
         final_unit := (input_data->>'unit')::BIGINT;
         IF final_unit IS NULL THEN
             RAISE EXCEPTION 'The "unit" field is required for new occasions';
         END IF;

         -- Security check for the new occasion's unit.
         IF NOT public.can_create_occasion(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         -- We still need to default 'reminder_is_enabled' for the 'form' feature if not specified.
         -- We do this on the already processed_features array.
         input_features := processed_features; -- Use the result from the is_app_supported logic
         processed_features := '[]'::jsonb;
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             -- If the current feature is the 'form' feature
             IF feature->>'code' = 'form' THEN
                 -- And if 'reminder_is_enabled' is NOT specified, default it to true.
                 IF NOT (feature ? 'reminder_is_enabled') THEN
                     feature := feature || '{"reminder_is_enabled": true}';
                 END IF;
             END IF;
             processed_features := processed_features || feature::jsonb;
         END LOOP;

         processed_features := public.merge_ticket_layout_features('[]', processed_features, input_data->'ticket_layout_change', true);

         INSERT INTO public.occasions(
             created_at, updated_at, title, description, link, data,
             is_hidden, is_open, is_promoted, start_time, end_time, organization,
             services, unit, features
         )
         VALUES(
             now, now,
             COALESCE(input_data->>'title', ''),
             COALESCE(input_data->>'description', ''),
             '',
             COALESCE(input_data->'data', '{}'::jsonb),
             COALESCE((input_data->>'is_hidden')::BOOLEAN, false),
             COALESCE((input_data->>'is_open')::BOOLEAN, true),
             COALESCE((input_data->>'is_promoted')::BOOLEAN, false),
             (input_data->>'start_time')::TIMESTAMPTZ,
             (input_data->>'end_time')::TIMESTAMPTZ,
             (input_data->>'organization')::BIGINT,
             COALESCE(input_data->'services', '{}'::jsonb),
             final_unit,
             processed_features
         )
         RETURNING * INTO updated_occ;

         -- Set the occ_id from the newly created record for subsequent logic
         occ_id := updated_occ.id;
         UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',true) WHERE id=occ_id RETURNING * INTO updated_occ;
     END IF;

     PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
     --
     -- Post-update/insert feature handling
     --

     -- Check if form feature is enabled and handle related logic.
     -- This will now be triggered if is_app_supported was false (based on organization settings).
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "form" && @.is_enabled == true)') THEN
         -- Extract the settings for the 'form' feature from the newly saved data
         SELECT elem INTO v_form_settings
         FROM jsonb_array_elements(updated_occ.features) AS elem
         WHERE elem->>'code' = 'form';

         -- Create a default form if one doesn't exist for the occasion
         IF NOT EXISTS (SELECT 1 FROM public.forms WHERE occasion = occ_id) THEN
             v_form_link := NULLIF(btrim(input_data->>'form_link'), '');
             IF input_data->>'id' IS NULL THEN
               PERFORM public.create_initial_occasion_form_internal_v1(occ_id,v_form_link,'Registration');
             ELSE
               PERFORM public.create_form(occ_id,v_form_link,'Registration');
             END IF;
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders

         END IF;
     END IF;

     -- Revalidate in-flight reminders after every relevant occasion update.
     PERFORM public.queue_payment_reminders(occ_id,coalesce(v_reminder_interval_seconds,86400));
     IF updated_occ.is_order_synchronization_enabled AND (
       NOT coalesce(old_sync_enabled,false) OR (
        NOT jsonb_path_exists(coalesce(old_features,'[]'), '$[*] ? (@.code == "ticket" && @.is_enabled == true)')
        AND jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "ticket" && @.is_enabled == true)'))) THEN
       FOR v_email_order IN SELECT id FROM eshop.orders WHERE occasion=occ_id AND state='paid' LOOP
         PERFORM public.enqueue_paid_order_tickets(v_email_order.id);
       END LOOP;
     END IF;
     -- Check if the blueprint feature is enabled in the final, saved state
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         -- Prepare a plan even when all forms use capacity/waitlisting.
         SELECT id INTO new_blueprint_id FROM eshop.blueprints
          WHERE occasion=occ_id AND (SELECT count(*) FROM eshop.blueprints WHERE occasion=occ_id)=1;
         IF new_blueprint_id IS NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=occ_id) THEN
             INSERT INTO eshop.blueprints(occasion, organization, created_at, updated_at,layout)
             VALUES (occ_id, COALESCE(updated_occ.organization, 1), now, now,
              '{"schemaVersion":2,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1120,"height":2080,"fill":"#ffffffff"},"styles":{},"seatingDefaults":{},"textPolicy":{"language":"und","direction":"auto"},"nodes":[],"selectionUnits":[],"attachments":[],"sections":[],"presets":[]}'::jsonb)
             RETURNING id INTO new_blueprint_id;
         END IF;

         -- Saved seat selectors use the plan immediately. Ordinary forms keep
         -- their product choices, capacity and waitlist until that selector is enabled.
         PERFORM public.sync_form_blueprint_internal(id) FROM public.forms WHERE occasion=occ_id ORDER BY id;
     END IF;
 END;
 $$;

-- Source: database/functions/eshop_forms/delete_form_internal_v1.sql
-- SHA256: 4faa230c57cfd757f085ca5f79bbdb013fb8397882bd43b837af0bb700327504
CREATE OR REPLACE FUNCTION public.delete_form_internal_v1(p_form_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_response_count BIGINT;
    v_form_key UUID;
    v_product_type_ids_to_check BIGINT[];
    v_deletable_product_type_ids BIGINT[];
BEGIN
    -- Shared current/historical reference guard, without casting untrusted
    -- legacy data to UUID or repeating a separate definition of form usage.
    SELECT key INTO v_form_key FROM public.forms WHERE id = p_form_id;

    IF v_form_key IS NOT NULL THEN
        v_response_count:=(public.get_form_usage_internal(p_form_id)->>'blocking_orders')::bigint;

        IF v_response_count > 0 THEN
            RAISE EXCEPTION 'This form cannot be deleted because it has responses.';
        END IF;
    END IF;

    -- Step 2: Collect all product_type IDs associated with this form's fields.
    -- We need this list to attempt a cleanup after deleting the fields.
    SELECT ARRAY_AGG(DISTINCT product_type)
    INTO v_product_type_ids_to_check
    FROM public.form_fields
    WHERE form = p_form_id AND product_type IS NOT NULL;

    PERFORM 1 FROM public.occasions WHERE id=(SELECT occasion FROM public.forms WHERE id=p_form_id) FOR UPDATE;
    IF EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=ANY(v_product_type_ids_to_check) AND public.ticket_layout_uses_product_type(pt.occasion,pt.id) AND NOT EXISTS(SELECT 1 FROM eshop.products p WHERE p.product_type=pt.id) AND NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.product_type=pt.id AND ff.form<>p_form_id))
    THEN RAISE EXCEPTION 'ticket_product_type_in_use'; END IF;
    -- Step 3: Delete the form fields unconditionally (after the response check).
    -- This severs the link from the form to the product types, fulfilling the
    -- requirement to "delete field anyway".
    DELETE FROM public.form_fields WHERE form = p_form_id;

    -- Step 4: Attempt to clean up the product types that were associated with the form.
    -- We will only delete product types that are not referenced by any existing products.
    IF v_product_type_ids_to_check IS NOT NULL AND array_length(v_product_type_ids_to_check, 1) > 0 THEN
        -- From our list of candidates, find which ones are NOT used by any products.
        SELECT ARRAY_AGG(pt.id)
        INTO v_deletable_product_type_ids
        FROM unnest(v_product_type_ids_to_check) AS pt(id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM eshop.products p
            WHERE p.product_type = pt.id
        ) AND NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.product_type=pt.id);

        -- If we found any deletable product types, delete them.
        IF v_deletable_product_type_ids IS NOT NULL AND array_length(v_deletable_product_type_ids, 1) > 0 THEN
            DELETE FROM eshop.product_types
            WHERE id = ANY(v_deletable_product_type_ids);
        END IF;
    END IF;

    -- Step 5: Finally, delete the form itself.
    DELETE FROM public.notification_center_source_state WHERE source_key='form-availability:'||p_form_id;
    DELETE FROM public.forms WHERE id = p_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_form_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/others/delete_occasion.sql
-- SHA256: 783811858a99d43a4d3adc2e6053cba2870516f2fcef1d2ef15618275c4c69eb
CREATE OR REPLACE FUNCTION public.delete_occasion_internal_v1(oc bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_id BIGINT;
BEGIN
  PERFORM public.check_occasion_writable(oc);

  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = oc;

  IF NOT public.can_delete_occasion_in_unit(unit_id) THEN RAISE EXCEPTION 'User is not manager.'; END IF;

  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=oc));

-- ***********************************************************
  -- 0. SAFETY CHECK: Strict Order Check
  --    Prevent deletion if ANY order exists (even storno).
  -- ***********************************************************
  IF EXISTS (
      SELECT 1
      FROM eshop.orders
      WHERE occasion = oc
  ) THEN
      RAISE EXCEPTION 'Cannot delete occasion % because it contains orders (including storno).', oc;
  END IF;

  -- ***********************************************************
  -- 1. Delete records that depend on 'events'.
  -- ***********************************************************
  PERFORM public.lock_blueprint_scope_internal(ARRAY[oc]);
  DELETE FROM public.scanner_settings WHERE occasion_id=oc;

  DELETE FROM public.event_groups
    WHERE event_parent IN (SELECT id FROM public.events WHERE occasion = oc)
       OR event_child  IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_roles
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users_saved
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.exclusive_events
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  -- ***********************************************************
  -- 2. Delete the 'events' themselves.
  -- ***********************************************************
  DELETE FROM public.events
    WHERE occasion = oc;

  -- ***********************************************************
  -- 3. Delete 'orders' dependent records.
  -- ***********************************************************
  DELETE FROM eshop.order_product_ticket
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.orders_history
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.bank_account_requests
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  -- ***********************************************************
  -- 4. Delete form-related records.
  -- ***********************************************************
  DELETE FROM public.form_fields
    WHERE form IN (SELECT id FROM public.forms WHERE occasion = oc);

  DELETE FROM public.notification_center_source_state WHERE source_key LIKE 'form-availability:%'
    AND (state->>'formId')::bigint IN (SELECT id FROM public.forms WHERE occasion=oc);
  DELETE FROM public.forms
    WHERE occasion = oc;

  -- ***********************************************************
  -- 5. Delete records from tables that reference the occasion directly.
  -- ***********************************************************
  DELETE FROM public.email_templates
    WHERE occasion = oc;

  DELETE FROM public.email_wrappers
    WHERE occasion = oc;

  DELETE FROM public.information
    WHERE occasion = oc;

  DELETE FROM public.information_hidden
    WHERE occasion = oc;

  DELETE FROM public.log_notifications
    WHERE occasion = oc;

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='occasion_deleted',data='{}',prepared=NULL,recipient=NULL,occasion=NULL,unit=NULL
    WHERE occasion = oc;

  DELETE FROM public.log_emails
    WHERE occasion = oc;

  DELETE FROM public.news
    WHERE occasion = oc;

  DELETE FROM public.occasion_users
    WHERE occasion = oc;

  DELETE FROM public.user_news
    WHERE occasion = oc;

  -- Resources can reference places and own slots referenced by copied spots.
  -- Remove them before places; slot references detach through their FK rules.
  DELETE FROM public.resources
    WHERE occasion = oc OR inventory_pool IN (
      SELECT id FROM public.inventory_pools WHERE occasion = oc);

  DELETE FROM public.places
    WHERE occasion = oc;

  DELETE FROM public.role_info
    WHERE occasion = oc;

  DELETE FROM public.user_groups
    WHERE "group" IN (SELECT id FROM public.user_group_info WHERE occasion = oc);

  DELETE FROM public.user_group_info
    WHERE occasion = oc;

  DELETE FROM public.exclusive_groups
    WHERE occasion = oc;

  -- ***********************************************************
  -- 6. Delete remaining records from the eshop schema.
  -- ***********************************************************
  DELETE FROM eshop.tickets
    WHERE occasion = oc;

  -- Configuration bindings depend on seats/products as well as their plan.
  DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_group_products WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);

  DELETE FROM eshop.spots
    WHERE occasion = oc;

  DELETE FROM eshop.products
    WHERE occasion = oc;

  DELETE FROM eshop.product_types
    WHERE occasion = oc;

  DELETE FROM eshop.planned_changes
    WHERE occasion = oc;

  DELETE FROM eshop.bank_account_requests
    WHERE occasion = oc;


  DELETE FROM eshop.blueprints
    WHERE occasion = oc;

  -- Blueprint area bindings and product mappings no longer retain contexts.
  DELETE FROM public.inventory_contexts
    WHERE inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion = oc);
  DELETE FROM public.inventory_pools
    WHERE occasion = oc;

  -- Delete orders (Safe now: we checked for non-storno orders at step 0,
  -- and deleted dependents in step 3).
  DELETE FROM eshop.orders
    WHERE occasion = oc;

  -- ***********************************************************
  -- 7. Null out referencing images.
  -- ***********************************************************
  UPDATE public.images
    SET occasion = NULL
    WHERE occasion = oc;

  -- ***********************************************************
  -- 8. Finally, delete the occasion itself.
  -- ***********************************************************
  DELETE FROM public.occasions
    WHERE id = oc;

  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_occasion_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.delete_occasion(oc bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN
  PERFORM public.delete_occasion_client_sync_v1(oc,extensions.gen_random_uuid());
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion(bigint) TO authenticated;

-- Source: database/functions/eshop/order_seating.sql
-- SHA256: 13d51fc539adfa31d982e148b44ab6ab2e3f7fb60f1edbba8f781d9d15ceaf1e
-- Presentation metadata only. Callers retain their existing order access checks.
CREATE OR REPLACE FUNCTION public.order_spot_metadata_internal(p_spot bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('spot_title',s.title,'spot_group_title',(
   SELECT n->>'label' FROM eshop.blueprint_seat_bindings binding
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
   WHERE binding.spot=s.id AND binding.blueprint=b.id AND n->>'id'=binding.group_node::text LIMIT 1
))
 FROM eshop.spots s LEFT JOIN eshop.blueprints b ON b.id=s.blueprint AND b.occasion=s.occasion
 WHERE s.id=p_spot;
$$;
REVOKE ALL ON FUNCTION public.order_spot_metadata_internal(bigint) FROM PUBLIC,anon,authenticated;

-- Read enrichment also repairs old snapshots without rewriting historical orders.
CREATE OR REPLACE FUNCTION public.order_tickets_with_seating_internal(p_order bigint,p_tickets jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(t || jsonb_build_object('products',(
   SELECT coalesce(jsonb_agg(p || coalesce((
     SELECT CASE WHEN s.blueprint IS NOT NULL THEN public.order_spot_metadata_internal(s.id) ||
       jsonb_build_object('is_standing',false,'standing_area_title',NULL)
       ELSE jsonb_build_object('spot_title',NULL,'spot_group_title',NULL,
         'is_standing',true,'standing_area_title',area.node->>'label') END
     FROM eshop.order_product_ticket x JOIN eshop.spots s ON s.order_product_ticket=x.id
     JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
     LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
     LEFT JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
       JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
         AND candidate.product=x.product AND target.occasion=o.occasion HAVING count(DISTINCT candidate.blueprint)=1))
       AND ab.inventory_context=s.inventory_context AND ab.product=x.product
     LEFT JOIN eshop.blueprints b ON b.id=ab.blueprint AND b.occasion=o.occasion
     LEFT JOIN LATERAL (SELECT n AS node FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
       WHERE n->>'id'=ab.node_id::text AND n->>'kind'='capacityArea') area ON true
     WHERE x."order"=p_order AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint
       AND (s.blueprint IS NOT NULL OR area.node IS NOT NULL)
     ORDER BY (s.blueprint IS NOT NULL) DESC,x.id,s.id LIMIT 1),'{}') ORDER BY pi),'[]')
   FROM jsonb_array_elements(coalesce(t->'products','[]')) WITH ORDINALITY products(p,pi)
 )) ORDER BY ti),'[]')
 FROM jsonb_array_elements(coalesce(p_tickets,'[]')) WITH ORDINALITY tickets(t,ti);
$$;
REVOKE ALL ON FUNCTION public.order_tickets_with_seating_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_spot_metadata_internal(bigint), public.order_tickets_with_seating_internal(bigint,jsonb) TO service_role;

-- Source: database/functions/eshop_orders/get_order_admin_detail.sql
-- SHA256: fd63ef7ae3a20c6ede85b831ba8fa28ee10c9080551b815a78a3dd44a5ea6b8d
-- Exact-order read projection. This fingerprint is a read consistency token,
-- never authorization or a command fence. No registry, trigger, locks or writes.
CREATE OR REPLACE FUNCTION public.order_admin_places_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH own AS (
  SELECT x.id item_id,x.ticket,x.product,o.occasion,o.form,o.state order_state,t.state ticket_state,
   count(*) FILTER (WHERE pt.type='spot') OVER(PARTITION BY x.ticket) primary_count,
   pt.type product_type
  FROM eshop.orders o JOIN eshop.order_product_ticket x ON x."order"=o.id
  JOIN eshop.tickets t ON t.id=x.ticket AND t.occasion=o.occasion
  JOIN eshop.products p ON p.id=x.product AND p.occasion=o.occasion
  JOIN eshop.product_types pt ON pt.id=p.product_type WHERE o.id=p_order
 ), places AS (
 SELECT x.*,s.id spot_id,coalesce(s.blueprint,ab.blueprint) blueprint_id,
 coalesce(sb.node_id,ab.node_id) node_id,sb.group_node,sb.selection_unit,
 s.title,coalesce(sb.blocked,false) blocked,ab.node_id IS NOT NULL standing,
 (SELECT count(*) FROM eshop.spots sp WHERE sp.order_product_ticket=x.item_id AND sp.blueprint IS NOT NULL) addressed_count,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket other WHERE other.ticket=x.ticket AND other."order"<>p_order) foreign_order,
 b.layout,
 EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) has_node,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=sb.group_node::text) group_title,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) node_title
 FROM own x JOIN eshop.spots s ON s.order_product_ticket=x.item_id AND s.occasion=x.occasion
 LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=s.blueprint
 LEFT JOIN public.forms f ON f.id=x.form AND f.occasion=x.occasion
 LEFT JOIN eshop.blueprint_area_bindings ab ON s.blueprint IS NULL AND ab.inventory_context=s.inventory_context AND ab.product=x.product
   AND ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
     JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
       AND candidate.product=x.product AND target.occasion=x.occasion HAVING count(DISTINCT candidate.blueprint)=1))
 LEFT JOIN eshop.blueprints b ON b.id=coalesce(s.blueprint,ab.blueprint) AND b.occasion=x.occasion
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'spotId',spot_id,'ticketId',ticket,'admissionItemId',item_id,'productId',product,
  'blueprintId',blueprint_id,'nodeId',node_id,'groupNodeId',group_node,'selectionUnitId',selection_unit,
  'title',coalesce(node_title,title),'groupTitle',group_title,'standing',standing,
  'active',ticket_state NOT IN ('storno','waitlisted') AND order_state NOT IN ('storno','stock','waitlisted')
    AND primary_count=1 AND NOT foreign_order AND NOT blocked AND (standing OR addressed_count=1) AND has_node,
  'problem',CASE WHEN primary_count<>1 OR foreign_order OR addressed_count>1 THEN 'ADMISSION_DATA_AMBIGUOUS'
    WHEN ticket_state='storno' OR order_state='storno' THEN 'HISTORICAL'
    WHEN NOT has_node THEN 'PLACE_NOT_IN_CURRENT_PLAN' WHEN blocked THEN 'BLOCKED' END
 ) ORDER BY item_id,spot_id,node_id),'[]') FROM places;
$$;
REVOKE ALL ON FUNCTION public.order_admin_places_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One canonical placement snapshot/fingerprint. The plan reader must not rebuild
-- payment, form, or email projections just to validate its read consistency token.
CREATE OR REPLACE FUNCTION public.order_admin_placement_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; places jsonb; tickets jsonb; plans jsonb; tr bigint;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL THEN RETURN NULL; END IF;
 places:=public.order_admin_places_internal(o.id);
 SELECT min(b.id) INTO tr FROM eshop.blueprints b CROSS JOIN LATERAL public.blueprint_seating_sources_internal(b.id) source WHERE b.occasion=o.occasion AND source.form_id=o.form HAVING count(*)=1;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,'state',t.state,
  'note',t.note,'note_hidden',t.note_hidden,'data',t.data,
  'snapshot',coalesce((SELECT v FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) v WHERE v->>'id'=t.id::text),
    (SELECT v FROM eshop.orders_history h CROSS JOIN LATERAL jsonb_array_elements(coalesce(h.data->'tickets','[]')) v
     WHERE h."order"=o.id AND v->>'id'=t.id::text ORDER BY h.created_at DESC,h.id DESC LIMIT 1)),
  'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'productId',x.product) ORDER BY x.id),'[]') FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=t.id),
  'admission',CASE WHEN tr IS NOT NULL THEN (SELECT jsonb_build_object('category',a.category,'reason',a.reason) FROM public.seating_admissions_internal(tr) a WHERE a.order_id=o.id AND a.ticket_id=t.id) END,
  'batch',(SELECT jsonb_build_object('id',i.batch_id,'title',b.title,'ordinal',i.ordinal) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id)
 ) ORDER BY t.id),'[]') INTO tickets FROM eshop.tickets t
 WHERE t.occasion=o.occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=o.id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,'layoutRevision',b.layout_revision) ORDER BY b.id),'[]') INTO plans
 FROM eshop.blueprints b WHERE b.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(places) v WHERE v->>'blueprintId'=b.id::text);
 RETURN jsonb_build_object('places',places,'tickets',tickets,'plans',plans,'placementFingerprint',md5(jsonb_build_object('order',o.id,'state',o.state,'form',o.form,'transition',tr,'places',places,'tickets',tickets)::text));
END $$;
REVOKE ALL ON FUNCTION public.order_admin_placement_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_order_admin_detail(p_order bigint,p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; places jsonb; tickets jsonb; plans jsonb; actions jsonb; placement jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL OR o.occasion IS DISTINCT FROM p_occasion OR public.can_read_orders(o.occasion) IS NOT TRUE THEN
  RETURN jsonb_build_object('code',404,'message','Order unavailable'); END IF;
 placement:=public.order_admin_placement_internal(o.id);
 places:=placement->'places';tickets:=placement->'tickets';plans:=placement->'plans';
 actions:=public.get_order_allowed_actions_internal_v1(o.id);
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
  'order',jsonb_build_object('id',o.id,'occasion',o.occasion,'form_id',o.form,'order_symbol',o.order_symbol,'order_sequence',o.order_sequence,
   'created_at',o.created_at,'updated_at',o.updated_at,'state',o.state,'price',o.price,'currency_code',o.currency_code,
   'data',o.data,'note_hidden',o.note_hidden,'allowedActions',actions,'email_payment_version',o.email_payment_version,
   'email_payment_fingerprint',public.order_email_payment_fingerprint(o.id),
   'payment_method',(SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info)),
  'capabilities',jsonb_build_object('write',coalesce(public.can_write_orders(o.occasion),false),'allowedActions',actions),
  'payment',public.customer_order_payment_internal(o.id)-'transactions',
  -- Authorized admin metadata stays readable after payment. Never issue or
  -- regenerate instructions as a side effect of viewing an order.
  'bankPaymentDetails',(SELECT jsonb_build_object(
    'account',coalesce(b.account_number_human_readable,b.account_number),
    'iban',b.account_number,'creditorName',b.creditor_name,
    'referenceKind',CASE WHEN o.currency_code='EUR' THEN 'RF' ELSE 'VS' END,
    'reference',CASE WHEN o.currency_code='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END)
    FROM eshop.payment_info pi JOIN eshop.bank_accounts b ON b.id=pi.bank_account
    WHERE pi.id=o.payment_info AND pi.payment_method='bank'
      AND pi.currency_code=o.currency_code),
  'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL THEN public.get_waitlist_summary_internal(o.id) END,
  'tickets',tickets,'places',places,'placesComplete',true,'plans',plans,
  'placementFingerprint',placement->>'placementFingerprint',
  'form',(SELECT jsonb_build_object('id',f.id,'title',f.title) FROM public.forms f WHERE f.id=o.form AND f.occasion=o.occasion),
  'fields',(SELECT coalesce(jsonb_agg(to_jsonb(ff)||jsonb_build_object('product_type_data',
    CASE WHEN pt.id IS NOT NULL THEN jsonb_build_object('id',pt.id,'title',pt.title,'description',pt.description,'type',pt.type) END)
    ORDER BY ff."order",ff.id),'[]') FROM public.form_fields ff
    LEFT JOIN eshop.product_types pt ON pt.id=ff.product_type AND pt.occasion=o.occasion WHERE ff.form=o.form),
  'productCategories',(SELECT coalesce(jsonb_object_agg(p.id::text,p.product_type),'{}') FROM eshop.products p
    WHERE p.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(tickets) t
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(t#>'{snapshot,products}','[]')) pr WHERE pr->>'id'=p.id::text)),
  'answers',coalesce(o.data->'fields','[]'),
  'emailSummary',public.get_order_email_summary(o.id)
 ));
END $$;
REVOKE ALL ON FUNCTION public.get_order_admin_detail(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_admin_detail(bigint,bigint) TO authenticated;

-- Source: database/functions/eshop/materialize_ticket_products_internal_v1.sql
-- SHA256: 88dddec1cadf512f787023d6edf803cd8f5c3eeb5dcdb15f15d65a7a863cec88
-- Private product materializer. Callers normalize selection, lock capacity/products,
-- and determine ticket identity first. It never creates an order or a ticket.
CREATE OR REPLACE FUNCTION public.materialize_ticket_products_internal_v1(
 order_id bigint,form_id bigint,ticket_id bigint,ticket_data jsonb,spot_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE
 is_editor boolean; occasion_id bigint; spot_data record; spot_product record; spot_id bigint;
 spot_product_id bigint;
 missing_required_product_field bigint;
 ticket_note text; product_id bigint; ordered_count bigint; field_item jsonb;
 products_array bigint[] := '{}'; product_data record; ticket_products jsonb;
 order_product_ticket_id bigint; first_currency_code text; calculated_price numeric := 0;
 v_product_deposit numeric; v_total_deposit numeric := 0; now timestamptz := clock_timestamp();
BEGIN
 SELECT occasion INTO STRICT occasion_id FROM public.forms WHERE id=form_id;
 is_editor:=coalesce(public.can_write_orders(occasion_id),false);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=order_id AND form=form_id AND occasion=occasion_id)
 OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=ticket_id AND occasion=occasion_id AND state='ordered') THEN
  RAISE EXCEPTION 'TICKET_MATERIALIZATION_SCOPE_MISMATCH'; END IF;
            spot_data := NULL;
            spot_product_id := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT s.* INTO spot_data
                FROM eshop.spots s
                JOIN public.forms f ON f.id=form_id AND f.blueprint=s.blueprint AND f.occasion=s.occasion
                JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=f.blueprint
                WHERE s.id = (ticket_data->>'spot')::BIGINT
                  AND s.occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings b WHERE b.spot=spot_data.id AND b.blocked) OR spot_data.product IS NULL THEN
                    RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (spot_secret::text)::UUID;
                IF (NOT coalesce(is_editor,false) AND
                     (spot_secret IS NULL OR spot_data.secret IS NULL
                      OR spot_data.secret IS DISTINCT FROM spot_secret
                      OR spot_data.secret_expiration_time IS NULL
                      OR spot_data.secret_expiration_time <= clock_timestamp()))
                   OR (coalesce(is_editor,false) AND spot_data.secret IS NOT NULL
                       AND spot_data.secret_expiration_time > clock_timestamp()
                       AND spot_data.secret IS DISTINCT FROM spot_secret) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
                spot_product_id := spot_product.id;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product_id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden)
                  AND NOT EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(form_id) offered
                    WHERE offered.product=product_data.id AND offered.has_capacity) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                PERFORM public.assert_admission_seating_internal(form_id,product_id,spot_id);

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product_id IS NULL THEN
                    spot_product := product_data;
                    spot_product_id := product_data.id;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product_id IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product_id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product_id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, secret = NULL, secret_expiration_time = NULL, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- Active seat sales still require an actual admission entitlement.
            -- Hiding ticket issuance cannot turn an auxiliary fee into a
            -- seatless admission behind the published/legacy seating plan.
            IF spot_product_id IS NULL AND EXISTS(
                SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
                WHERE f.id=form_id AND f.blueprint IS NOT NULL
                  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
            ) THEN
                RAISE EXCEPTION '%',jsonb_build_object('code',409,
                  'errorCode','ADMISSION_SOURCE_REQUIRES_SEATING')::text;
            END IF;

            -- Only explicitly application-only forms may omit admission products.
            -- Missing/active ticket containers retain the admission requirement.
            -- Use the ID sentinel: an unassigned record cannot be inspected on
            -- a fresh database connection with only ordinary fee products.
            IF spot_product_id IS NULL AND NOT coalesce((
                SELECT bool_and(ff.is_hidden IS TRUE)
                FROM public.form_fields ff
                WHERE ff.form=form_id AND ff.type='ticket'
            ),false) THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- An application fee is not an admission product. Removing that
            -- requirement must still reject a missing mandatory fee, including
            -- requests selecting only an optional dinner or no products at all.
            IF spot_product_id IS NULL THEN
                SELECT ff.id INTO missing_required_product_field
                FROM public.form_fields ff
                WHERE ff.form=form_id AND ff.type='product_type'
                  AND ff.is_ticket_field AND ff.is_required AND NOT ff.is_hidden
                  AND NOT EXISTS(SELECT 1 FROM eshop.products p
                    WHERE p.id=ANY(products_array) AND p.product_type=ff.product_type)
                ORDER BY ff.id LIMIT 1;
                IF FOUND THEN
                    RAISE EXCEPTION '%',jsonb_build_object('code',400,
                      'errorCode','REQUIRED_FIELD_MISSING',
                      'fieldId',missing_required_product_field,
                      'message','Required product selection missing')::text;
                END IF;
            END IF;


 RETURN jsonb_build_object('products',ticket_products,'price',calculated_price,
  'deposit',v_total_deposit,'currency_code',first_currency_code,'spot',spot_id,'note',ticket_note);
END $$;
REVOKE ALL ON FUNCTION public.materialize_ticket_products_internal_v1(bigint,bigint,bigint,jsonb,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/blueprint/retire_publication.sql
-- SHA256: 6f01bcb7c5e7d979fa2eefa23b0aef348869bfc88f36d9561ae43494722dda3c
-- Forward cutover only. Preserve physical placements and commercial records.
-- Refuse contradictory source bindings instead of choosing another plan.
DO $$
DECLARE row record;
BEGIN
 IF to_regclass('public.form_seating_transitions') IS NOT NULL THEN
   LOCK TABLE public.form_seating_transitions IN EXCLUSIVE MODE;
   IF EXISTS(SELECT form FROM public.form_seating_transitions WHERE state<>'cancelled' AND form IS NOT NULL
     GROUP BY form HAVING count(DISTINCT blueprint)>1) THEN RAISE EXCEPTION 'SEATING_BINDING_AMBIGUOUS'; END IF;
   FOR row IN SELECT DISTINCT t.form,t.blueprint,f.occasion FROM public.form_seating_transitions t
     JOIN public.forms f ON f.id=t.form WHERE t.state<>'cancelled' AND t.blueprint IS NOT NULL ORDER BY t.form LOOP
     IF NOT EXISTS(SELECT 1 FROM eshop.blueprints b JOIN public.occasions o ON o.id=row.occasion
       WHERE b.id=row.blueprint AND b.occasion=o.id AND b.organization=o.organization AND b.layout->>'schemaVersion'='2') THEN
       RAISE EXCEPTION 'SEATING_BINDING_INVALID'; END IF;
     IF EXISTS(SELECT 1 FROM public.forms WHERE id=row.form AND blueprint IS NOT NULL AND blueprint<>row.blueprint) THEN
       RAISE EXCEPTION 'SEATING_BINDING_AMBIGUOUS'; END IF;
     IF EXISTS(SELECT 1 FROM public.occasions WHERE id=row.occasion AND jsonb_path_exists(features,
       '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
       IF EXISTS(SELECT 1 FROM public.form_fields WHERE form=row.form AND type='spot' AND NOT is_hidden) THEN
         PERFORM public.lock_blueprint_scope_internal(ARRAY[row.occasion]);
         PERFORM public.check_form_capacity_settings_internal(row.form,jsonb_build_object('blueprint',row.blueprint));
         UPDATE public.forms SET blueprint=row.blueprint,capacity_revision=capacity_revision+1,updated_at=clock_timestamp()
         WHERE id=row.form;
         INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
         VALUES('form','occasion',row.occasion,row.form::text,1)
         ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
         SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
         PERFORM public.notification_center_form_capacity_internal(row.form);
       END IF;
     END IF;
     IF NOT EXISTS(SELECT 1 FROM public.blueprint_seating_sources_internal(row.blueprint) WHERE form_id=row.form) THEN
       RAISE EXCEPTION 'SEATING_SOURCE_AMBIGUOUS'; END IF;
   END LOOP;
 END IF;
 -- Also repair the same missing association where no transition was created.
 PERFORM public.sync_form_blueprint_internal(id) FROM public.forms f WHERE f.blueprint IS NULL AND
   EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND type='spot' AND NOT is_hidden) ORDER BY id;
END $$;

DROP FUNCTION IF EXISTS public.publish_seating_transitions(uuid,uuid[],text,uuid);
DROP FUNCTION IF EXISTS public.preview_seating_publication(uuid);
DROP FUNCTION IF EXISTS public.seating_publication_preview_internal(uuid);
DROP FUNCTION IF EXISTS public.start_seating_configuration(bigint,bigint,uuid);
DROP FUNCTION IF EXISTS public.cancel_seating_configuration(uuid,bigint,uuid);
DROP FUNCTION IF EXISTS public.start_seating_configuration_internal(bigint,bigint);
DROP FUNCTION IF EXISTS public.set_ticket_seat_assignments(uuid,jsonb,text,uuid);
DROP FUNCTION IF EXISTS public.preview_ticket_seat_assignment(uuid,jsonb);
DROP FUNCTION IF EXISTS public.seating_assignment_preview_internal(uuid,jsonb);
DROP FUNCTION IF EXISTS public.seating_assignment_scope_internal(uuid,jsonb);
DROP FUNCTION IF EXISTS public.get_seating_transition_context(uuid,text,text,bigint,integer);
DROP FUNCTION IF EXISTS public.seating_admissions_internal(uuid);
DROP FUNCTION IF EXISTS public.assert_published_admission_seating_internal(bigint,bigint,bigint);
DELETE FROM public.client_sync_component_sources WHERE registry_version=1 AND source_relation=to_regclass('public.form_seating_transitions');
DROP TABLE IF EXISTS public.form_seating_transitions;
UPDATE public.client_sync_component_sources SET canonical_writers=ARRAY(SELECT writer FROM unnest(canonical_writers) writer
 WHERE writer NOT IN ('start_seating_configuration','cancel_seating_configuration','publish_seating_transitions')) WHERE registry_version=1;

-- Source: database/functions/blueprint/seating_sync.sql
-- SHA256: 5a295dbefbde3328e3ea5a900199c41733d4dd43fa8953295c3184d5e4ec26fb
WITH readiness AS MATERIALIZED (
 SELECT coalesce(bool_and(cutover_ready),false) ready FROM public.client_sync_component_sources WHERE registry_version=1
)
INSERT INTO public.client_sync_component_sources
(registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
(1,'private_inventory','eshop.spots','spots.occasion',ARRAY['order_product_ticket','state'],
 ARRAY['set_ticket_seat_assignments'],ARRAY[]::text[],'migrate','database/tests/blueprint/seating_assignment_test.sql',(SELECT ready FROM readiness)),
(1,'private_inventory','public.forms','forms.occasion',ARRAY['blueprint','participant_capacity','waitlist_enabled','capacity_revision'],
 ARRAY['update_form_client_sync_v1','update_blueprint_client_sync_v1','save_occasion_client_sync_v1','set_ticket_seat_assignments'],ARRAY[]::text[],'migrate','database/tests/blueprint/automatic_form_binding_test.sql',(SELECT ready FROM readiness))
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 tracked_columns=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns)),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers)),
 test_factory=excluded.test_factory;

-- Source: database/functions/others/get_ticket_layout_write_contract_v1.sql
-- SHA256: 0f6e4da1fb9e3107a4b9ab4c76bc37effdfdb1e737f6b09e661904038713bd5a
-- Generated by automation/generate_ticket_layout_write_contract.py.
-- A readiness probe, not a write dispatcher or a grant to any new executor.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_write_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ready boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 SELECT coalesce(bool_and(p.oid IS NOT NULL AND md5(btrim(p.prosrc,E' \n\r\t'))=expected.body_md5
  AND p.prosecdef=expected.definer AND (EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
   WHERE regexp_replace(setting,'[[:space:]]','','g')='search_path=public,extensions')=expected.needs_path)),false)
 INTO ready FROM (VALUES
  ('public.active_membership(boolean,boolean)','2dd31a8b531c745b2ed16af90e0260ea',false,false),
  ('public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)','7a9559975e19ae53e8b15a23a4b8b68a',false,false),
  ('public.blueprint_write_rule(boolean,boolean)','0c68680b6879b48966f2bf3bc0210d37',false,false),
  ('public.can_create_occasion(bigint)','f13b39c68d18a53dbb79125c23d7dc23',true,true),
  ('public.can_delete_orders(bigint)','8db8081db5e65a6948f4cefe1b109f93',true,true),
  ('public.can_edit_occasion(bigint,bigint)','af8850fc3a3bed9a06274880669c340d',true,true),
  ('public.can_edit_ticket_layout(bigint)','bb45fdb1e72cd16860e9719c8f9ab84f',true,true),
  ('public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint)','f6ee7e318387522f6146e13b3c4854f7',true,true),
  ('public.can_manage_occasion_participants(bigint)','8cb3dd4327ae5c9302da134994dd5d07',true,true),
  ('public.can_manage_unit_users(bigint)','700c32f30396d2bc5bb21553c2f42ca8',true,true),
  ('public.can_preview_ticket_readonly(bigint)','48efb47c1529b5106cbab4edf641fd0a',true,true),
  ('public.can_read_information_editor_bundle(bigint)','ba203be730cbf9acca46c0b3e63363ad',true,true),
  ('public.can_read_map_editor_bundle(bigint)','02c9fbcfcd61c8598e88407a9f3070fa',true,true),
  ('public.can_read_orders(bigint)','6b8f1152158aa8ab01bd13cec9dbbdf3',true,true),
  ('public.can_read_ticket_layout(bigint)','50105a20a0ff5d89389f80e5dd9f891c',true,true),
  ('public.can_read_unit_users(bigint)','76b08038f169406ba1ba56652e44608e',true,true),
  ('public.can_write_orders(bigint)','680cbd3862cc0f6abc89d7d2497c7fb1',true,true),
  ('public.can_write_orders_as_actor_internal(uuid,bigint)','064d9d9fe95cfbb62ccbe39efa120a62',false,false),
  ('public.cleaning_crew_navigation_rule(boolean)','30e845096d248f7112e1d570bb489e6a',false,false),
  ('public.client_activity_read_rule(boolean,boolean,boolean)','002ce7bce477126bcdab9e94db022734',false,false),
  ('public.client_commit_read_rule(boolean,boolean,boolean)','229306cbca2f8a160f4d66b2598fc127',false,false),
  ('public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean)','9f7f53c36711c06eb5a130dc339b325b',false,false),
  ('public.companion_assignment_rule(boolean,boolean)','7d53e2d7e2196b118c29f85cc90d0ab2',false,false),
  ('public.context_private_access_rule(boolean,boolean,boolean)','a187283398f1802a1b79b46963ff98b6',false,false),
  ('public.demo_own_work_rule(boolean,boolean,boolean,boolean)','3dd99e356714a2005743f678f09f7ae9',false,false),
  ('public.email_template_read_rule(boolean,boolean)','6501d868e3a245da411c8685a6c39406',false,false),
  ('public.email_template_write_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.event_attendance_read_rule(boolean,boolean)','e85f194d54fb7db63b079e5d689de085',false,false),
  ('public.form_authoring_rule(boolean,boolean)','378d42348079d8d5df8ed0d914f5d007',false,false),
  ('public.form_catalog_read_rule(boolean,boolean,boolean)','7a7263f988a28c0272c14f0234b12563',false,false),
  ('public.form_copy_source_rule(boolean,boolean)','0fff049746a86488382290a67c8c9838',false,false),
  ('public.group_assignments_write_rule(boolean,boolean,boolean,boolean)','0221c1b7823f38a4d5afa4abe5e0912f',false,false),
  ('public.group_data_read_rule(boolean,boolean)','a5a4e0f5924790a0c9e68e79bc606a1e',false,false),
  ('public.group_editor_read_rule(boolean,boolean,boolean)','c1fd67eb4de0001ed5aaffb65d36b437',false,false),
  ('public.group_members_read_rule(boolean,boolean,boolean)','c8e7fdf47b08fac95a18ed026d4d07bc',false,false),
  ('public.group_members_write_rule(boolean,boolean)','46f6cef5344290b2caf0182185c3ce4e',false,false),
  ('public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','937805bab351b685970512e7f5e6f285',false,false),
  ('public.group_write_rule(boolean,boolean,boolean)','3dd26a325ee3dd2e391136570cbc5f60',false,false),
  ('public.inventory_copy_target_rule(boolean,boolean)','604bd24712dc418a35616de6d38e0578',false,false),
  ('public.map_editor_read_rule(boolean,boolean)','3f4dc9022d50562b6a48d6e46b0c5928',false,false),
  ('public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb)','454cb997425470c75fb41a1519238708',false,true),
  ('public.merge_ticket_layout_features(jsonb,jsonb,jsonb,boolean)','6a50d4e8877de4585d90046816e43817',false,true),
  ('public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','f68f00938a5a8efee47af7edc0062f94',false,false),
  ('public.occasion_commit_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.occasion_context_read_rule(boolean,boolean,boolean)','b54f8cf02bc1580acba23e2497d1cc9f',false,false),
  ('public.occasion_create_rule(boolean,boolean)','faa2f799767b4c9edb52c58944b4a66b',false,false),
  ('public.occasion_directory_read_rule(boolean,boolean)','d4937332739a00292987baae5b876b2b',false,false),
  ('public.occasion_edit_rule(boolean,boolean)','1d4987935db34cc6011f633ef3f6f291',false,false),
  ('public.occasion_editor_read_rule(boolean,boolean,boolean)','1702aa0f9d1003c29f02ef70a017dee6',false,false),
  ('public.occasion_list_read_rule(boolean,boolean)','7ecb040f0c43bb540a15e2ab868ac31e',false,false),
  ('public.occasion_media_upload_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean)','6c7cfeabfb173e0283543f575272d4d8',false,false),
  ('public.occasion_users_write_rule(boolean,boolean,boolean)','2a1ee1bc8a910030a6010ff778df7bc4',false,false),
  ('public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean)','939699b1b32832f4e2ad0c3af5f22210',false,false),
  ('public.order_delete_rule(boolean,boolean,boolean)','6fdbd70c92f774e10d2be6e0e30eb219',false,false),
  ('public.order_editor_membership_as_actor_internal(uuid,bigint)','aa05414eef3f73d8792cdaaa22023c39',false,false),
  ('public.order_read_rule(boolean,boolean,boolean)','d8acd43d69e2797bbd63063512eb4e69',false,false),
  ('public.order_write_rule(boolean,boolean)','4dd2fa01cd16e5c36983aa7aeb280d3f',false,false),
  ('public.participant_contacts_read_rule(boolean,boolean,boolean)','c371f5c035213b1fd9c8a5f15ba3c6e3',false,false),
  ('public.participant_manage_rule(boolean,boolean)','2ddebfa1df2bdd7becf910d5b619a3c0',false,false),
  ('public.place_move_rule(boolean,boolean,boolean,boolean)','73f870eaea9c56088435b4d80cbf5315',false,false),
  ('public.public_publication_actor_rule(boolean,boolean,boolean)','47ad63e39013d34b5a4105a18f04457d',false,false),
  ('public.readable_membership(boolean,boolean,boolean)','057c3a891e1c41c9b77dc8af67983e20',false,false),
  ('public.reception_enabled(jsonb)','0844ea35e4e7bfad821b8f09f81e8fbb',false,false),
  ('public.reception_use_rule(boolean,boolean,boolean,boolean)','99350a72fb204f5160cb72714b85882c',false,false),
  ('public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean)','53eb537fe636ad48274e61bafb683e4a',false,false),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)','56bf52d069b80a2ffa254509afdaa5a1',true,true),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','00af445f9e641905e395adaca48ce248',true,true),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)','eda19f32835616334b3adc0f4d2cd2f6',true,true),
  ('public.scanner_settings_rule(boolean,boolean,boolean)','2b1717b65933cede78c39b44f5d6230d',false,false),
  ('public.schedule_entry_navigation_rule(boolean)','f0258b7a3cc8e3a024dee1a96d34d407',false,false),
  ('public.schedule_feedback_read_rule(boolean,boolean)','a546bbfc24dce06e231e832a11ddb4b4',false,false),
  ('public.schedule_participants_read_rule(boolean,boolean,boolean)','7f6977ddb21f0e2044e154b4428275d1',false,false),
  ('public.ticket_delivery_mode(jsonb)','c2590b2701840fc3cba0df9e8d0359cd',false,true),
  ('public.ticket_layout_rule(boolean,boolean)','8bc8e0cd6a5a45d10d57f79cec655768',false,false),
  ('public.ticket_layout_uses_product_type(bigint,bigint)','dddc7962230734dd5835601b455d8bb4',false,true),
  ('public.unit_abuse_policy_read_rule(boolean,boolean)','42fc89183ec978eccce36173bc6c3a50',false,false),
  ('public.unit_discovery_rule(boolean,boolean,boolean)','d49526989a25babf6f7ca9ba34b3061c',false,false),
  ('public.unit_landing_read_rule(boolean,boolean,boolean,boolean)','14e7808464b1206a6842240b8db567ff',false,false),
  ('public.unit_legal_profile_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.unit_template_read_rule(boolean,boolean,boolean)','a22a3f456bfac47bcc58b72c2ec5f75f',false,false),
  ('public.unit_users_read_rule(boolean,boolean,boolean)','a7131760aa20a35fa57d63f718037a34',false,false),
  ('public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean)','5ba3417d0406073b8ce9421770304558',false,false),
  ('public.update_occasion(jsonb)','0425e6f46c20d2c30a2ffd054619b2b0',true,true),
  ('public.update_occasion_182(jsonb)','bdcda71506ac0abb50a466bb18eb1cc7',true,true),
  ('public.update_occasion_203(jsonb)','916b23b47758d87e478b3b7d84a50ee2',true,true),
  ('public.update_occasion_internal_v1(jsonb)','2446d470f7e49092199946b0cc8fa6bd',true,true),
  ('public.validate_ticket_layout(jsonb)','53d7703a06dbde87349a0ac04e50cd54',false,true),
  ('public.validate_ticket_layout_references(bigint,jsonb)','aad01d93c9f0a7035efa243caa3d5a20',false,true)
 ) expected(signature,body_md5,definer,needs_path)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);
 ready:=ready AND NOT EXISTS(
  SELECT 1 FROM (VALUES('authenticated'),('anon')) actor(role_name)
  WHERE has_table_privilege(actor.role_name,'public.occasions','INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_any_column_privilege(actor.role_name,'public.occasions','INSERT,UPDATE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion_internal_v1(jsonb)'),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)')
 ) private(signature) WHERE has_function_privilege('authenticated',to_regprocedure(private.signature),'EXECUTE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion(jsonb)'),('public.update_occasion_203(jsonb)'),('public.update_occasion_182(jsonb)'),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)')
 ) boundary(signature) WHERE NOT has_function_privilege('authenticated',to_regprocedure(boundary.signature),'EXECUTE')
 OR has_function_privilege('anon',to_regprocedure(boundary.signature),'EXECUTE'));
 RETURN jsonb_build_object('family','ticket_layouts','contractVersion',1,'ready',coalesce(ready,false));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_write_contract_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_write_contract_v1() TO authenticated;

NOTIFY pgrst, 'reload schema';
