-- Forward correction: the superseded uncommitted prototype is retained
-- because no complete live-ledger absence proof is available. Never release
-- that migration alone; this source-matched migration owns the final contract.

-- Source: database/functions/blueprint/seating_transition_schema.sql
-- SHA256: 1f9d829366d636d5acea9313a8edfa4ba1da854be4dfab4d50615f73b0eec446
-- Configuration history only. Physical placement remains eshop.spots.
CREATE TABLE IF NOT EXISTS public.form_seating_transitions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE RESTRICT,
 form bigint REFERENCES public.forms(id) ON DELETE SET NULL,
 blueprint bigint REFERENCES eshop.blueprints(id) ON DELETE SET NULL,
 state text NOT NULL DEFAULT 'organizer_managed' CHECK(state IN ('organizer_managed','published','cancelled')),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 started_by uuid NOT NULL, started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 finished_by uuid, finished_at timestamptz,
 CHECK(state<>'organizer_managed' OR (form IS NOT NULL AND blueprint IS NOT NULL)),
 CHECK((state='organizer_managed' AND finished_at IS NULL AND finished_by IS NULL) OR
       (state<>'organizer_managed' AND finished_at IS NOT NULL AND finished_by IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS form_seating_transitions_active_form ON public.form_seating_transitions(form) WHERE state='organizer_managed';
CREATE INDEX IF NOT EXISTS form_seating_transitions_target ON public.form_seating_transitions(blueprint,state);
ALTER TABLE public.form_seating_transitions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.form_seating_transitions FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/user_permissions/seating_transition_operations.sql
-- SHA256: 89391b70981e729ef975316bb79ede8c43ca80678b0f21833fe2887ead80195d
CREATE OR REPLACE FUNCTION public.can_read_seating_status(p_occasion bigint)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.can_author_forms(p_occasion) OR public.can_read_orders(p_occasion),false)
$$;
CREATE OR REPLACE FUNCTION public.can_assign_existing_admissions(p_occasion bigint)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND coalesce(public.can_read_orders(p_occasion) AND public.can_write_orders(p_occasion),false)
$$;
REVOKE ALL ON FUNCTION public.can_read_seating_status(bigint),public.can_assign_existing_admissions(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_seating_status(bigint),public.can_assign_existing_admissions(bigint) TO authenticated,service_role;

-- Source: database/functions/blueprint/seating_transition_context.sql
-- SHA256: 29476c4fc4294b0215ca39a05adae784d3ecf4d632baf313e988352585bc40d3
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

-- Source: database/functions/blueprint/seating_transition_lifecycle.sql
-- SHA256: d9e3c98c0dcd51d0dfd5acb6a94f6fcb21e91cf25fa782732f7b7a7084227b86
CREATE OR REPLACE FUNCTION public.start_seating_configuration_internal(p_form bigint,p_blueprint bigint)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; b eshop.blueprints; tid uuid;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 IF f.id IS NULL OR NOT coalesce(public.can_author_forms(f.occasion) OR public.can_edit_occasion(f.occasion,NULL),false) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 SELECT * INTO b FROM eshop.blueprints WHERE id=p_blueprint;
 IF b.id IS NULL OR b.occasion<>f.occasion OR b.organization IS DISTINCT FROM (SELECT organization FROM public.occasions WHERE id=f.occasion) THEN
 RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF NOT coalesce(public.can_author_forms(f.occasion) OR public.can_edit_occasion(f.occasion,NULL),false) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=f.occasion AND jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
 RAISE EXCEPTION 'MODE_CHANGED'; END IF;
 IF b.layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE EXCEPTION 'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 SELECT id INTO tid FROM public.form_seating_transitions WHERE form=f.id AND state='organizer_managed';
 IF tid IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM public.form_seating_transitions WHERE id=tid AND blueprint=b.id) THEN RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
 RETURN tid; END IF;
 IF EXISTS(SELECT 1 FROM public.forms WHERE blueprint=b.id) THEN RAISE EXCEPTION 'TARGET_ALREADY_PUBLIC'; END IF;
 IF f.blueprint IS NOT NULL THEN RAISE EXCEPTION 'MODE_CHANGED'; END IF;
 INSERT INTO public.form_seating_transitions(occasion,form,blueprint,started_by) VALUES(f.occasion,f.id,b.id,auth.uid()) RETURNING id INTO tid;
 RETURN tid;
END $$;
REVOKE ALL ON FUNCTION public.start_seating_configuration_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.start_seating_configuration(p_form bigint,p_blueprint bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ bigint; started jsonb; tid uuid;
BEGIN
 SELECT occasion INTO occ FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name='seating.configuration.start';
 IF NOT FOUND THEN SELECT occasion INTO occ FROM public.forms WHERE id=p_form; END IF;
 IF occ IS NULL OR NOT public.can_author_forms(occ) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.configuration.start',occ,auth.uid(),encode(extensions.digest(jsonb_build_array(p_form,p_blueprint)::text,'sha256'),'hex'));
 IF NOT public.can_author_forms(occ) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 tid:=public.start_seating_configuration_internal(p_form,p_blueprint);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,occ,'seating.configuration.start',
 jsonb_build_array(jsonb_build_object('entityType','form','entityId',p_form,'operation','update','safeLabel','Seating configuration','changedFields',jsonb_build_array('seating'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=occ),jsonb_build_object('transitionId',tid,'context',jsonb_set(public.get_seating_transition_context(tid)->'data','{items}','[]'::jsonb)));
END $$;
REVOKE ALL ON FUNCTION public.start_seating_configuration(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.start_seating_configuration(bigint,bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_seating_configuration(p_transition uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; started jsonb; original_form bigint; original_bp bigint;
BEGIN
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition;
 IF tr.id IS NULL OR NOT public.can_author_forms(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[tr.occasion]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.configuration.cancel',tr.occasion,auth.uid(),encode(extensions.digest(jsonb_build_array(p_transition,p_expected_revision)::text,'sha256'),'hex'));
 IF NOT public.can_author_forms(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 PERFORM 1 FROM public.forms WHERE id=tr.form FOR UPDATE;
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition FOR UPDATE;
 IF tr.state<>'organizer_managed' OR tr.revision IS DISTINCT FROM p_expected_revision THEN
 RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','CONTEXT_CHANGED')); END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket JOIN eshop.orders o ON o.id=x."order" WHERE o.form=tr.form AND s.blueprint=tr.blueprint)
 OR EXISTS(SELECT 1 FROM eshop.spots WHERE blueprint=tr.blueprint AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp()) THEN
 RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','ASSIGNMENTS_EXIST')); END IF;
 UPDATE public.form_seating_transitions SET state='cancelled',revision=revision+1,finished_by=auth.uid(),finished_at=clock_timestamp() WHERE id=tr.id;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,tr.occasion,'seating.configuration.cancel',
 jsonb_build_array(jsonb_build_object('entityType','form','entityId',tr.form,'operation','update','safeLabel','Seating configuration removed','changedFields',jsonb_build_array('seating'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=tr.occasion),jsonb_build_object('transitionId',tr.id,'sourceFormId',tr.form,'targetBlueprintId',tr.blueprint,'context',jsonb_set(public.get_seating_transition_context(tr.id)->'data','{items}','[]'::jsonb)));
END $$;
REVOKE ALL ON FUNCTION public.cancel_seating_configuration(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_seating_configuration(uuid,bigint,uuid) TO authenticated;

-- Source: database/functions/inventory/lock_spot_assignment_scope_internal_v1.sql
-- SHA256: dc705a4c685ee31ea5266a3281cb6d4e2b47c56129d1e314444c79ce9fdb0912
-- One parent-before-child lock owner. Financial seat commands include the
-- complete order-product closure; existing inventory callers keep their scope.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(
 p_spots bigint[],p_resources bigint[],p_financial boolean,p_products bigint[],p_preserve_print boolean,p_source_orders bigint[],p_source_items bigint[])
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE before_spots jsonb;after_spots jsonb;before_resources jsonb;after_resources jsonb;
 resource_ids bigint[];v_orders bigint[];v_order_products bigint[]:=coalesce(p_products,'{}');
BEGIN
 IF p_financial IS NULL OR p_preserve_print IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='assignment lock mode required'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO before_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 SELECT ARRAY(SELECT DISTINCT id FROM (
  SELECT unnest(p_resources) id UNION SELECT s.resource FROM eshop.spots s WHERE s.id=ANY(p_spots)
  UNION SELECT rs.resource FROM public.resource_slots rs JOIN eshop.spots s ON s.resource_slot=rs.id WHERE s.id=ANY(p_spots)) r WHERE id IS NOT NULL)
 INTO resource_ids;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO before_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 SELECT ARRAY(SELECT DISTINCT i."order" FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) UNION SELECT unnest(coalesce(p_source_orders,'{}'::bigint[])) UNION SELECT "order" FROM eshop.order_product_ticket WHERE id=ANY(p_source_items) ORDER BY 1) INTO v_orders;
 PERFORM public.lock_order_capacity_scope_internal(v_orders);
 IF p_financial THEN
  IF v_orders IS DISTINCT FROM ARRAY(SELECT DISTINCT i."order" FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) UNION SELECT unnest(coalesce(p_source_orders,'{}'::bigint[])) UNION SELECT "order" FROM eshop.order_product_ticket WHERE id=ANY(p_source_items) ORDER BY 1) THEN
   RAISE serialization_failure USING MESSAGE='assignment order parents changed; retry the same command'; END IF;
  SELECT ARRAY(SELECT product FROM eshop.order_product_ticket WHERE "order"=ANY(v_orders) AND product IS NOT NULL UNION SELECT unnest(coalesce(p_products,'{}'::bigint[])) ORDER BY 1) INTO v_order_products;
 END IF;
 -- Union every affected product before taking any blueprint/inventory child.
 PERFORM 1 FROM eshop.products WHERE id IN(
  SELECT product FROM eshop.spots WHERE id=ANY(p_spots) UNION SELECT unnest(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.blueprints WHERE id IN(
  SELECT blueprint FROM eshop.spots WHERE id=ANY(p_spots)
  UNION SELECT blueprint FROM public.forms WHERE p_financial AND id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders))
  UNION SELECT blueprint FROM eshop.spots WHERE product=ANY(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(
  SELECT inventory_pool FROM public.resources WHERE id=ANY(resource_ids)
  UNION SELECT c.inventory_pool FROM public.inventory_contexts c JOIN eshop.spots s ON s.inventory_context=c.id WHERE s.id=ANY(p_spots)
  UNION SELECT c.inventory_pool FROM public.inventory_contexts c JOIN eshop.product_inventory_contexts pc ON pc.inventory_context=c.id WHERE pc.product=ANY(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.resources WHERE id=ANY(resource_ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO after_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 IF before_resources IS DISTINCT FROM after_resources THEN RAISE serialization_failure USING MESSAGE='resource parent changed; retry the same command'; END IF;
 IF p_financial THEN
  PERFORM 1 FROM public.inventory_contexts WHERE id IN(
   SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(v_order_products)
   UNION SELECT inventory_context FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 END IF;
 PERFORM 1 FROM public.resource_slots WHERE resource=ANY(resource_ids) ORDER BY id FOR UPDATE;
 IF p_financial THEN
  PERFORM 1 FROM eshop.payment_info WHERE id IN(SELECT payment_info FROM eshop.orders WHERE id=ANY(v_orders)) ORDER BY id FOR UPDATE;
 END IF;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spots) ORDER BY id FOR UPDATE;
 IF p_financial THEN
  PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT i.ticket FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) UNION SELECT ticket FROM eshop.order_product_ticket WHERE id=ANY(p_source_items)) ORDER BY id FOR UPDATE;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO after_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 IF p_preserve_print THEN PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT x.ticket FROM eshop.spots s
 JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spots))); END IF;
 IF before_spots IS DISTINCT FROM after_spots THEN RAISE serialization_failure USING MESSAGE='spot parent changed; retry the same command'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean,bigint[],boolean,bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Existing callers share the same explicit source-parent implementation.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(p_spots bigint[],p_resources bigint[],p_financial boolean,p_products bigint[],p_preserve_print boolean)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,p_financial,p_products,p_preserve_print,'{}'::bigint[],'{}'::bigint[])
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean,bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Print-content mutations preserve the guard. Canonical cancellation may void
-- the admission identity without changing any printed content.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(p_spots bigint[],p_resources bigint[],p_financial boolean,p_products bigint[])
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,p_financial,p_products,true)
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Existing callers retain their arity; the product closure has one lock owner.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(p_spots bigint[],p_resources bigint[],p_financial boolean)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,p_financial,'{}'::bigint[])
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Existing private SQL callers retain their arity, not a second implementation.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal_v1(p_spots bigint[],p_resources bigint[] DEFAULT '{}')
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,false)
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal_v1(bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/inventory/apply_allocations.sql
-- SHA256: c78de8227bf85bc75667c10d98083127b64ad33233df9df4e6767d3f58fb970d
CREATE OR REPLACE FUNCTION apply_allocations(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_order_state TEXT;
    v_item_to_allocate RECORD;
    v_existing_spot_count INT;
    v_spots_to_claim INT;
    v_available_spot_id BIGINT;
    v_occasion_id BIGINT;
    v_spots_to_disallocate BIGINT[];
    v_occasion_features JSONB;
    v_is_blueprint_enabled BOOLEAN;
BEGIN
    PERFORM public.lock_ticket_order_products_internal(p_order_id);
    -- Initial check for the order's state.
    SELECT state, occasion INTO v_order_state, v_occasion_id
    FROM eshop.orders
    WHERE id = p_order_id;

    SELECT features INTO v_occasion_features FROM public.occasions WHERE id = v_occasion_id;
    v_is_blueprint_enabled := jsonb_path_exists(v_occasion_features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)');

    -- If the order is not found, raise a structured exception.
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 'A001', 'message', 'Order with ID ' || p_order_id || ' not found.')::text;
    END IF;

    -- If the order state is 'storno', disallocate all spots and exit.
    IF v_order_state = 'storno' THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL, state = NULL, resource = CASE WHEN blueprint IS NULL THEN NULL ELSE resource END, updated_at = now()
        WHERE order_product_ticket IN (SELECT id FROM eshop.order_product_ticket WHERE "order" = p_order_id);
        RETURN;
    END IF;

    -- Disallocate spots that are no longer required by the order.
    WITH required_spots AS (
        SELECT opt.id as order_product_ticket_id, pic.inventory_context as inventory_context_id, generate_series(1, pic.quantity)
        FROM eshop.order_product_ticket opt
        JOIN eshop.products p ON opt.product = p.id
        JOIN eshop.product_inventory_contexts pic ON p.id = pic.product
        WHERE opt."order" = p_order_id
    ),
    current_spots AS (
        SELECT s.id, s.order_product_ticket, s.inventory_context, s.blueprint
        FROM eshop.spots s
        WHERE s.order_product_ticket IN (SELECT id FROM eshop.order_product_ticket WHERE "order" = p_order_id)
    )
    SELECT array_agg(cs.id)
    INTO v_spots_to_disallocate
    FROM current_spots cs
    LEFT JOIN required_spots rs ON cs.order_product_ticket = rs.order_product_ticket_id AND cs.inventory_context = rs.inventory_context_id
    JOIN eshop.order_product_ticket opt ON cs.order_product_ticket = opt.id
    JOIN eshop.products p ON opt.product = p.id
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE rs.order_product_ticket_id IS NULL
      -- Retained legacy plans also own explicit placements before conversion.
      AND cs.blueprint IS NULL
      AND NOT EXISTS (SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.spot=cs.id);

    IF v_spots_to_disallocate IS NOT NULL AND array_length(v_spots_to_disallocate, 1) > 0 THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL, state = NULL, resource = CASE WHEN blueprint IS NULL THEN NULL ELSE resource END, updated_at = now()
        WHERE id = ANY(v_spots_to_disallocate);
    END IF;

    -- Loop through each product in the order that requires an inventory spot to allocate new spots.
    FOR v_item_to_allocate IN
        SELECT
            opt.id AS order_product_ticket_id,
            opt.product AS product_id,
            pic.inventory_context AS inventory_context_id,
            pic.quantity AS required_quantity
        FROM eshop.orders o
        JOIN eshop.order_product_ticket opt ON o.id = opt."order"
        JOIN eshop.products p ON opt.product = p.id
        JOIN eshop.product_inventory_contexts pic ON p.id = pic.product
        WHERE o.id = p_order_id
    LOOP
        -- Check for existing spots for this specific order item AND inventory context.
        SELECT COUNT(*)
        INTO v_existing_spot_count
        FROM eshop.spots s
        WHERE s.order_product_ticket = v_item_to_allocate.order_product_ticket_id
          AND s.inventory_context = v_item_to_allocate.inventory_context_id;

        -- Calculate exactly how many spots are missing.
        v_spots_to_claim := v_item_to_allocate.required_quantity - v_existing_spot_count;

        IF v_spots_to_claim <= 0 THEN
            CONTINUE;
        END IF;

        IF EXISTS(SELECT 1 FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
          WHERE ic.id=v_item_to_allocate.inventory_context_id AND ip.sellable_capacity IS NOT NULL AND
          (SELECT count(*) FROM eshop.spots s WHERE s.inventory_context=ic.id AND (s.order_product_ticket IS NOT NULL OR
            (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp())))+v_spots_to_claim>ip.sellable_capacity) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',1017,'errorCode','PRODUCT_CAPACITY_EXCEEDED','productId',v_item_to_allocate.product_id)::text;
        END IF;
        -- This loop runs precisely the number of times needed to claim the required spots.
        FOR i IN 1..v_spots_to_claim LOOP
            v_available_spot_id := NULL;

            -- Find an available spot. A spot is available only if it's unassigned.
            WITH available_spot_cte AS (
                SELECT s.id
                FROM eshop.spots s
                WHERE s.inventory_context = v_item_to_allocate.inventory_context_id
                  AND s.order_product_ticket IS NULL
                  AND s.blueprint IS NULL
                  AND NOT EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.spot=s.id)
                  AND (s.secret IS NULL OR s.secret_expiration_time IS NULL OR s.secret_expiration_time<=clock_timestamp())
                LIMIT 1
                FOR UPDATE SKIP LOCKED
            )
            SELECT id INTO v_available_spot_id FROM available_spot_cte;

            -- If no available spot is found, we must fail with a structured error.
            IF v_available_spot_id IS NULL THEN
                 DECLARE
                    product_data RECORD;
                 BEGIN
                    -- Fetch the details of the product that could not be allocated.
                    SELECT
                        p.id,
                        p.title,
                        p.description,
                        p.price,
                        pt.type,
                        pt.title as type_title,
                        p.currency_code
                    INTO product_data
                    FROM eshop.products p
                    LEFT JOIN eshop.product_types pt ON p.product_type = pt.id
                    WHERE p.id = v_item_to_allocate.product_id;

                    -- Raise the specific overbooked exception with product details.
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1017,
                        'message', 'Product is overbooked',
                        'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                            'id', product_data.id,
                            'title', product_data.title,
                            'description', product_data.description,
                            'price', product_data.price,
                            'type', product_data.type,
                            'type_title', product_data.type_title,
                            'currency_code', product_data.currency_code
                        ))
                    )::TEXT;
                 END;
            END IF;

            -- Claim the found spot.
            UPDATE eshop.spots
            SET
                order_product_ticket = v_item_to_allocate.order_product_ticket_id,
                occasion = v_occasion_id,
                state = 'ordered',
                secret = NULL,
                secret_expiration_time = NULL,
                updated_at = now()
            WHERE id = v_available_spot_id;

            -- After claiming the spot, check if it should be automatically assigned to a resource.
            DECLARE
                v_is_auto_assign BOOLEAN;
            BEGIN
                -- Get the auto-assignment setting from the pool associated with the context.
                SELECT (ip.data->>'is_auto_resource_assignment')::boolean
                INTO v_is_auto_assign
                FROM public.inventory_contexts ic
                JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
                WHERE ic.id = v_item_to_allocate.inventory_context_id;

                -- If auto-assignment is enabled for this pool, call the assignment function.
                IF v_is_auto_assign IS TRUE THEN
                    PERFORM assign_spot_to_resource(v_available_spot_id, v_item_to_allocate.inventory_context_id);
                END IF;
            END;

        END LOOP;
    END LOOP;
    PERFORM public.notification_center_order_capacity_internal(p_order_id);
END;
$$;

-- Source: database/functions/blueprint/seating_assignment.sql
-- SHA256: eda63443a53bd70e05bf247271a01686714cb6ae348ea4129e4a5d7787c82076
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

-- Source: database/functions/blueprint/seating_publication.sql
-- SHA256: 3852cec7cb8f4ba88d797e4473b703f699ce24f42bde609bf8710016729269ca
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

-- Source: database/functions/blueprint/save.sql
-- SHA256: d811ec2250e2452ae1238858907d027f1f686b17fcc74b6444e447f1c8badab7
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

-- Source: database/functions/eshop/update_product_client_sync_v1.sql
-- SHA256: eb3af3c57e6bdf7de68f23025aa4f0e6f9c7120595e285e9f59903e56dc3402e
CREATE OR REPLACE FUNCTION public.update_product_client_sync_v1(p_product jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_product bigint; v_occasion bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_version bigint; v_expected bigint;
BEGIN
  IF p_product IS NULL OR jsonb_typeof(p_product)<>'object'
    OR octet_length(p_product::text)>524288 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid product aggregate'; END IF;
  v_product:=NULLIF(p_product->>'id','')::bigint;
  SELECT occasion INTO v_occasion FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=v_actor AND command_name='inventory.product.save';
  IF NOT FOUND THEN
  IF v_product IS NOT NULL THEN
    SELECT p.occasion INTO v_occasion FROM eshop.products p WHERE p.id=v_product;
  ELSE
    SELECT pt.occasion INTO v_occasion FROM eshop.product_types pt
      WHERE pt.id=NULLIF(p_product->>'product_type','')::bigint;
  END IF;
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF jsonb_typeof(p_product->'inventory_contexts')='array' THEN
    p_product:=jsonb_set(p_product,'{inventory_contexts}',coalesce((SELECT jsonb_agg(c ORDER BY (c->>'inventory_context_id')::bigint)
      FROM jsonb_array_elements(p_product->'inventory_contexts') c),'[]')); END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'product',p_product)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.product.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_product IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
    FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
      ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
    WHERE opt.product=v_product;
  ELSE v_users:='{}'::uuid[]; END IF;
  -- Context replacement recalculates allocations: acquire the same outer order
  -- parents before saving a product, never product then order in this command.
  PERFORM public.lock_primary_product_forms_internal(v_product);
  PERFORM public.lock_product_order_dependencies_internal_v1(v_product);
  IF v_product IS NOT NULL THEN
    PERFORM 1 FROM eshop.products WHERE id=v_product AND occasion=v_occasion FOR UPDATE;
    SELECT coalesce(v.version,0) INTO v_version FROM (SELECT 1) seed
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='product'
    AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_product::text;
    -- Released scalar facades may omit this control until their explicit upgrade gate.
    v_expected:=CASE WHEN p_product ? 'expected_aggregate_version'
      THEN (p_product->>'expected_aggregate_version')::bigint ELSE v_version END;
    IF v_expected IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('productId',v_product,'aggregate_version',v_version)); END IF;
  ELSIF p_product->>'expected_aggregate_version' IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new product cannot have expected version';
  END IF;
  v_product:=public.update_product_internal_v1(p_product-'expected_aggregate_version');
  PERFORM public.assert_form_seating_source_internal(id) FROM public.forms WHERE occasion=v_occasion;
  SELECT version INTO v_version FROM public.client_aggregate_versions WHERE aggregate_type='product'
    AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_product::text;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.product.save',jsonb_build_array(jsonb_build_object(
      'entityType','product','entityId',v_product,'operation',
      CASE WHEN p_product->>'id' IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_product->>'title',240),'changedFields',jsonb_build_array(
        'configuration','contexts'))),v_users,jsonb_build_object('productId',v_product,'aggregate_version',v_version));
END; $function$;
REVOKE ALL ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid) TO authenticated;

-- Source: database/functions/eshop_waitlist/form_capacity.sql
-- SHA256: 5e100eae9460e9604170d09028f54c4dc6b8041d5136cf7c23b22e49a765fac6
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
DECLARE f public.forms; d jsonb; c jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form; d:=public.get_effective_form_data(p_form);
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
 -- Generic saves may neither switch a configured source nor activate its
 -- still-private target through another form. Publication owns both bindings.
 IF bp IS DISTINCT FROM f.blueprint AND (
 EXISTS(SELECT 1 FROM public.form_seating_transitions WHERE form=p_form AND state IN ('organizer_managed','published'))
 OR EXISTS(SELECT 1 FROM public.form_seating_transitions WHERE blueprint=bp AND state='organizer_managed')) THEN
 RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','MODE_CHANGED')::text; END IF;
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

-- Source: database/functions/eshop/materialize_ticket_products_internal_v1.sql
-- SHA256: 62541a2dfc0ac73c9c3c8bafdf3187125780e7428b2fe512115fe926fcfb17b3
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

                PERFORM public.assert_published_admission_seating_internal(form_id,product_id,spot_id);

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

-- Source: database/functions/others/update_occasion.sql
-- SHA256: 2f4cbf18d2e43dae01843fdacc34cc71d9418f1cb8dacb7176371d86d4b7eb8c
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
           UPDATE public.form_seating_transitions SET state='cancelled',revision=revision+1,finished_by=auth.uid(),finished_at=clock_timestamp()
             WHERE occasion=occ_id AND state='organizer_managed';
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

     -- Enabling the editor does not switch bounded registrations to seat sales.
     -- Detach inactive, retained plans only on activation; keep their documents
     -- and every registration/offer intact for an explicit later form switch.
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
       IF NOT jsonb_path_exists(coalesce(old_features,'[]'::jsonb), '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         FOR v_form_id IN SELECT id FROM public.forms
           WHERE occasion=occ_id AND blueprint IS NOT NULL
           ORDER BY id FOR UPDATE LOOP
           UPDATE public.forms SET blueprint=NULL,updated_at=now WHERE id=v_form_id;
           INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
           VALUES('form','occasion',occ_id,v_form_id::text,1)
           ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
           SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
         END LOOP;
       END IF;
       -- Validate actual seat-selling forms, rather than a fictitious plan on
       -- every form in the occasion. Form assignment retains the same guards.
       FOR v_form_id IN SELECT id FROM public.forms WHERE occasion=occ_id AND blueprint IS NOT NULL ORDER BY id LOOP
         PERFORM public.check_form_capacity_settings_internal(v_form_id, '{}'::jsonb);
       END LOOP;
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

         -- Start only an unambiguous, valid organizer configuration. Choosing a
         -- target/repairing legacy data remains possible after feature enabling.
         IF (SELECT count(*) FROM eshop.blueprints WHERE occasion=occ_id)=1
           AND (SELECT layout->>'schemaVersion' FROM eshop.blueprints WHERE id=new_blueprint_id)='2'
           AND NOT EXISTS(SELECT 1 FROM public.forms WHERE blueprint=new_blueprint_id)
           AND (SELECT count(*) FROM public.forms WHERE occasion=occ_id)=1 THEN
           SELECT id INTO v_form_id FROM public.forms WHERE occasion=occ_id;
           PERFORM public.start_seating_configuration_internal(v_form_id,new_blueprint_id);
         END IF;
     END IF;
 END;
 $$;

-- Source: database/functions/others/save_occasion_domain_command_internal_v1.sql
-- SHA256: e0c6db5e0c8cf3aa93f2f2f51ae25f2ac99b4a74332995408746b081b5810bf0

-- The public save wrapper and the settings UI allow unit editors. The renamed
-- canonical domain command retained its older occasion-only guard, so it must
-- accept the same role before it reaches update_occasion_internal_v1.
CREATE OR REPLACE FUNCTION public.save_occasion_domain_command_internal_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_version bigint;
  v_begin jsonb;
  v_hash text;
  v_entity jsonb;
  v_old_hidden boolean;
  v_new_hidden boolean;
  v_old_unit bigint;
  v_new_unit bigint;
  v_features jsonb;
  v_seating_provenance jsonb;
  v_fanout_units bigint[] := '{}';
BEGIN
  SELECT o.unit INTO v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion;

  IF v_actor IS NULL OR NOT public.can_edit_occasion(p_occasion,(p_config->>'unit')::bigint) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object'
    OR octet_length(p_config::text) > 1048576
    OR (p_config->>'id')::bigint IS DISTINCT FROM p_occasion
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_config) key
      WHERE key NOT IN (
        'id', 'start_time', 'end_time', 'is_open', 'is_hidden', 'is_promoted',
        'link', 'title', 'description', 'data', 'services', 'organization',
        'unit', 'features', 'settings', 'feature_changes', 'form_link', 'has_orders', 'stats', 'ticket_layout_change'
      )
    )
  THEN
    RAISE invalid_parameter_value USING MESSAGE = 'invalid occasion aggregate';
  END IF;

  PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion', p_occasion,
    'expectedVersion', p_expected_version,
    'config', p_config
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_client_mutation_v1(
    p_command_id,
    'occasion.config.save',
    p_occasion,
    v_actor,
    v_hash
  );
  IF v_begin->>'disposition' = 'replay' THEN
    RETURN v_begin->'response';
  END IF;

  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion));
  IF NOT (p_config ? 'ticket_layout_change' AND p_config-ARRAY['id','ticket_layout_change']='{}'::jsonb) THEN
    PERFORM 1 FROM public.forms WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  END IF;

  SELECT o.is_hidden, o.unit INTO v_old_hidden, v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'rejected',
      404,
      jsonb_build_object('version', 0, 'occasion', NULL)
    );
  END IF;

  INSERT INTO public.client_aggregate_versions(
    aggregate_type, scope_type, scope_id, aggregate_id, version
  ) VALUES ('occasion', 'occasion', p_occasion, p_occasion::text, 0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version
  FROM public.client_aggregate_versions
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version,'seatingPreviousConfiguration',v_seating_provenance)
    INTO v_entity
    FROM public.occasions o
    WHERE o.id = p_occasion;
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'conflict',
      409,
      jsonb_build_object('version', v_version, 'occasion', v_entity)
    );
  END IF;

  SELECT jsonb_build_object('features',o.features,'bindings',(SELECT coalesce(jsonb_agg(jsonb_build_object('formId',f.id,'blueprintId',f.blueprint) ORDER BY f.id),'[]') FROM public.forms f WHERE f.occasion=p_occasion AND f.blueprint IS NOT NULL)) INTO v_seating_provenance FROM public.occasions o WHERE o.id=p_occasion;

  IF p_config ? 'ticket_layout_change' AND p_config - ARRAY['id','ticket_layout_change']='{}'::jsonb THEN
    IF NOT public.can_edit_ticket_layout(p_occasion) THEN
      RAISE insufficient_privilege USING MESSAGE='unit editor required';
    END IF;
    SELECT features INTO v_features FROM public.occasions WHERE id=p_occasion;
    v_features:=public.merge_ticket_layout_features(v_features,v_features,p_config->'ticket_layout_change');
    v_features:=public.merge_ticket_appearance_internal_v1(p_occasion,v_features,p_config#>'{ticket_layout_change,appearance}');
    PERFORM public.validate_ticket_layout_references(p_occasion,f->'layout')
      FROM jsonb_array_elements(v_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
    UPDATE public.occasions SET features=v_features,updated_at=clock_timestamp() WHERE id=p_occasion;
  ELSE
    PERFORM public.update_occasion_internal_v1(
      public.apply_occasion_settings_intent_internal_v1(p_occasion,p_config));
  END IF;
  UPDATE public.client_aggregate_versions
  SET version = version + 1, updated_at = clock_timestamp()
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  RETURNING version INTO v_version;
  SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version,'seatingPreviousConfiguration',v_seating_provenance)
  INTO v_entity
  FROM public.occasions o
  WHERE o.id = p_occasion;

  v_new_hidden := (v_entity->>'is_hidden')::boolean;
  v_new_unit := (v_entity->>'unit')::bigint;
  IF NOT v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_old_unit);
  END IF;
  IF NOT v_new_hidden AND v_new_unit IS DISTINCT FROM v_old_unit THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  ELSIF NOT v_new_hidden AND v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  END IF;

  RETURN public.complete_client_mutation_applied_v1(
    p_command_id,
    p_occasion,
    'occasion.config.save',
    'configuration',
    jsonb_build_array(jsonb_build_object(
      'entityType', 'occasion',
      'entityId', p_occasion,
      'operation', 'update',
      'safeLabel', left(v_entity->>'title', 240),
      'changedFields', jsonb_build_array('configuration')
    )),
    CASE WHEN v_old_hidden AND NOT v_new_hidden THEN ARRAY[
      'occasion_config', 'program_catalog', 'map_catalog', 'content_catalog',
      'live_public'
    ] ELSE ARRAY['occasion_config'] END,
    '[]',
    '[]',
    jsonb_build_object('version', v_version, 'occasion', v_entity),
    CASE WHEN NOT v_new_hidden THEN ARRAY['occasion_config'] ELSE '{}'::text[] END,
    '[]',
    'user',
    NULL,
    '[]',
    v_fanout_units
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_occasion_domain_command_internal_v1(
  bigint, uuid, bigint, jsonb
) FROM PUBLIC, anon, authenticated;

-- Source: database/functions/eshop_forms/update_form_client_sync_v1.sql
-- SHA256: d951680ae3985eb583df55e8ee40d78ad9b70d10be91d11a075d0fe928650a1a
CREATE OR REPLACE FUNCTION public.update_form_client_sync_v1(p_form jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_form bigint;
  v_begin jsonb; v_hash text; v_version bigint; v_expected bigint; v_users uuid[]; v_result jsonb; v_check record; v_current bigint;
BEGIN
  IF p_form IS NULL OR jsonb_typeof(p_form)<>'object'
    OR octet_length(p_form::text)>4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid form aggregate'; END IF;
  v_occasion:=NULLIF(p_form->>'occasion','')::bigint;
  v_form:=NULLIF(p_form->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL OR v_form IS NULL
    OR NOT public.can_author_forms(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'form',p_form)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=v_occasion));
  -- Parent order matches checkout: form, product, blueprint, then seats.
  PERFORM 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion FOR UPDATE;
  PERFORM 1 FROM eshop.product_types WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eshop.products WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  IF v_form IS NOT NULL THEN
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_form::text FOR UPDATE;
  ELSE v_version:=0; END IF;
  -- Missing baseline remains an installed-client adapter, explicitly not MCP-ready.
  v_expected:=CASE WHEN p_form ? 'expected_aggregate_version' THEN (p_form->>'expected_aggregate_version')::bigint ELSE v_version END;
  IF v_expected IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',v_version)); END IF;
  -- These maps were frozen when the editor loaded. No read-before-write rebasing.
  -- Missing maps are the bounded released-client facade, not MCP-ready authoring.
  IF p_form ? 'expected_product_versions' OR p_form ? 'expected_product_type_versions' THEN
    IF jsonb_typeof(p_form->'expected_product_versions') IS DISTINCT FROM 'object'
      OR jsonb_typeof(p_form->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
      RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
    FOR v_check IN
      SELECT DISTINCT 'product'::text kind, (p->>'id')::bigint id FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(f#>'{product_type,products}','null'),'[]')) p WHERE p->>'id' IS NOT NULL
      UNION SELECT 'product',value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_product_ids','[]'))
      UNION SELECT DISTINCT 'product',p.id FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
        WHERE ff.form=v_form AND ff.id IN (SELECT value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_field_ids','[]')))
      UNION SELECT DISTINCT 'product_type',(f#>>'{product_type,id}')::bigint FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        WHERE f#>>'{product_type,id}' IS NOT NULL
      ORDER BY 1,2
    LOOP
      IF NOT (CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions'
        ELSE p_form->'expected_product_type_versions' END) ? v_check.id::text THEN
        RAISE invalid_parameter_value USING MESSAGE='missing original product baseline'; END IF;
      IF (v_check.kind='product' AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=v_check.id AND occasion=v_occasion))
        OR (v_check.kind='product_type' AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=v_check.id AND occasion=v_occasion)) THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('entity_type',v_check.kind,'entity_id',v_check.id,'deleted',true)); END IF;
      SELECT coalesce(v.version,0) INTO v_current FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
        ON v.aggregate_type=v_check.kind AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_check.id::text;
      IF ((CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions' ELSE p_form->'expected_product_type_versions' END)->>v_check.id::text)::bigint IS DISTINCT FROM v_current THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
          jsonb_build_object('aggregate_version',v_version,'entity_type',v_check.kind,'entity_id',v_check.id,'entity_version',v_current));
      END IF;
    END LOOP;
  END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.products p ON p.id=opt.product
  WHERE ou.occasion=v_occasion AND p.occasion=v_occasion;
  BEGIN
    v_result:=public.update_form_internal_v1(p_form-'expected_aggregate_version'-'expected_product_versions'-'expected_product_type_versions');
    IF coalesce((v_result->>'code')::integer,500)<>200 THEN
      RAISE SQLSTATE 'P0F01' USING MESSAGE='authoring domain rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0F01' THEN NULL;
  END;
  IF coalesce((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer BETWEEN 100 AND 599 THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  v_form:=(v_result->>'form_id')::bigint;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,1)
    ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
    RETURNING version INTO v_version;
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version,
    'product_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product'),
    'product_type_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product_type'),
    'authoring',public.get_form_authoring_snapshot_internal(v_form));
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.save',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','update',
      'safeLabel',left(p_form->>'title',240),'changedFields',jsonb_build_array(
        'configuration','products'))),v_users,v_result);
END; $function$;

REVOKE ALL ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_form(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.update_form_client_sync_v1(input_data,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||result->'data';
END $$;
REVOKE ALL ON FUNCTION public.update_form(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form(jsonb) TO authenticated;

-- Source: database/functions/eshop_forms/update_form.sql
-- SHA256: 0ed85d138ef0cd54cee51693e45ca959334825948a688a1bb25fcbdfef01375d
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
        IF input_data ? 'settings' THEN
          form_metadata:=public.apply_form_settings_internal(form_metadata,input_data->'settings');
        ELSIF input_data ? 'data' THEN
          -- Released full-metadata boundary, same settings owner/validation.
          form_metadata:=public.normalize_form_metadata_internal(input_data->'data');
          form_metadata:=public.apply_form_settings_internal(form_metadata,
            public.form_settings_from_metadata_internal(form_metadata));
        END IF;

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
        PERFORM public.assert_form_seating_source_internal(form_id);
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'link', link_param,
            'form_fields', form_fields_data
        );

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

-- Source: database/functions/eshop_forms/delete_form_internal_v1.sql
-- SHA256: 347b185d9d98fae12879d6570d5db44edc90d537c54fed4097611257cf365d3d
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
    IF EXISTS(SELECT 1 FROM public.form_seating_transitions WHERE form=p_form_id AND state='organizer_managed') THEN RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
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

-- Source: database/functions/eshop_forms/duplicate_form_to_occasion.sql
-- SHA256: 44ac8afc108d9d676c423e28002e08841ad1b6ded295ae29e7db21c301dfd80f
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_internal_v1(
    source_form_id BIGINT,
    target_occasion_link TEXT,
    p_locale TEXT DEFAULT 'en'
)
RETURNS BIGINT -- Returns the ID of the new form
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    user_id UUID := auth.uid();
    target_occasion_id BIGINT;
    target_organization_id BIGINT;
    source_occasion_id BIGINT;
    source_unit_id BIGINT;
    has_source_permission BOOLEAN;
    has_target_permission BOOLEAN;
    new_form_id BIGINT;
    v_new_form_link TEXT;
    form_field_record RECORD;
    new_product_type_id BIGINT;
    product_record RECORD;
BEGIN
    -- Step 1: Resolve the target occasion ID and its organization ID from its link.
    SELECT id, organization INTO target_occasion_id, target_organization_id
    FROM public.occasions WHERE id = public.resolve_occasion_link_internal(target_occasion_link);
    IF target_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Target occasion not found for link: %', target_occasion_link;
    END IF;

    PERFORM public.check_occasion_writable(target_occasion_id);

    PERFORM public.notification_center_initialized_internal(target_organization_id);
    -- Step 2: Get the source occasion and unit IDs for permission checking.
    SELECT f.occasion, o.unit
    INTO source_occasion_id, source_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = source_form_id;

    IF source_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Source form not found.';
    END IF;

    -- Step 3: Check if the user has editor_view rights on the source occasion or its unit.
    SELECT public.can_copy_form_source(source_occasion_id)
    INTO has_source_permission;

    IF NOT has_source_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to view the source form.';
    END IF;

    -- Step 4: Check if the user has editor rights on the target occasion.
    SELECT public.can_copy_form_target(target_occasion_id)
    INTO has_target_permission;

    IF NOT has_target_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to create a form in the target occasion.';
    END IF;

    -- Step 6: Copy the main form record to the target occasion.
    INSERT INTO public.forms (title, data, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds)
    SELECT
        public.copy_occasion_title_internal(title,p_locale),
        CASE WHEN source_unit_id IS DISTINCT FROM (SELECT unit FROM public.occasions WHERE id=target_occasion_id)
          THEN data #- '{payments,stripeConnectionId}' ELSE data END,
        target_occasion_id,
        type,
        bank_account,
        deadline_duration_seconds,
        CASE WHEN source_unit_id IS DISTINCT FROM (SELECT unit FROM public.occasions WHERE id=target_occasion_id)
          AND data#>'{payments,bankEnabled}'='false'::jsonb THEN false ELSE is_open END,
        NULL,
        blueprint,
        header,
        header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds
    FROM public.forms
    WHERE id = source_form_id
    RETURNING id INTO new_form_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,NULL,true) WHERE id=new_form_id;

    -- Step 7: Loop through each field of the source form and perform a deep copy.
    FOR form_field_record IN
        SELECT * FROM public.form_fields WHERE form = source_form_id
    LOOP
        -- Check if the field is linked to a product type.
        IF form_field_record.product_type IS NOT NULL THEN
            -- A) If yes, perform a deep copy of the product type and its products.
            INSERT INTO eshop.product_types (title, description, type, data, occasion, maximum)
            SELECT title, description, type, data, target_occasion_id, maximum
            FROM eshop.product_types
            WHERE id = form_field_record.product_type
            RETURNING id INTO new_product_type_id;

            FOR product_record IN
                SELECT * FROM eshop.products WHERE product_type = form_field_record.product_type
            LOOP
                INSERT INTO eshop.products (title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
                VALUES (
                    product_record.title, product_record.description, product_record.price, product_record.data,
                    new_product_type_id, target_occasion_id, product_record.is_hidden, product_record.currency_code,
                    product_record.order, product_record.maximum
                );
            END LOOP;

            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                new_product_type_id, form_field_record.is_ticket_field
            );
        ELSE
            -- B) If not, perform a simple copy of the form field.
            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                NULL, form_field_record.is_ticket_field
            );
        END IF;
    END LOOP;

    -- Step 8: Return the ID of the newly created form.
    PERFORM public.notification_center_form_created_internal(new_form_id);
    PERFORM public.assert_form_seating_source_internal(new_form_id);
    RETURN new_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion(source_form_id bigint,target_occasion_link text)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (public.duplicate_form_to_occasion_client_sync_v1(source_form_id,target_occasion_link,gen_random_uuid())#>>'{data,formId}')::bigint;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion(bigint,text) TO authenticated;

-- Source: database/functions/eshop_forms/duplicate_form_to_occasion_client_sync_v1.sql
-- SHA256: 0f454550c0ec5a45712dd5160b6e7355669183305e04bb3e1065beb5afb1eb2e
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_client_sync_v1(
  p_source_form_id bigint,p_target_occasion_link text,p_command_id uuid,
  p_locale text DEFAULT 'en'
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_source_occasion bigint; v_source_unit bigint;
  v_target bigint; v_begin jsonb; v_hash text; v_form bigint;
BEGIN
  SELECT f.occasion,o.unit INTO v_source_occasion,v_source_unit
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    WHERE f.id=p_source_form_id;
  SELECT o.id INTO v_target FROM public.occasions o
    WHERE o.id=public.resolve_occasion_link_internal(p_target_occasion_link);
  IF v_actor IS NULL OR v_target IS NULL
    OR NOT public.can_copy_form_target(v_target) THEN
    RAISE insufficient_privilege USING MESSAGE='form copy permission required'; END IF;
  IF v_source_occasion IS NULL OR NOT public.can_copy_form_source(v_source_occasion) THEN RAISE insufficient_privilege USING MESSAGE='form copy permission required'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_source_occasion,v_target]);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'sourceFormId',p_source_form_id,'targetOccasion',v_target,'locale',p_locale)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.duplicate',v_target,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_form:=public.duplicate_form_to_occasion_internal_v1(
    p_source_form_id,p_target_occasion_link,p_locale);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_target,
    'inventory.form.duplicate',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','insert',
      'safeLabel','Duplicated form','changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('formId',v_form,'authoring',public.get_form_authoring_snapshot_internal(v_form)));
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(bigint,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(bigint,text,uuid,text) TO authenticated;

-- Source: database/functions/others/delete_occasion.sql
-- SHA256: 68dc4eb8d4fb42d6e9ac6397cf91b76dedf8933d4aedb08799425dc87bd63893
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
  DELETE FROM public.form_seating_transitions WHERE occasion=oc;

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

-- Source: database/functions/eshop/get_blueprint_for_edit.sql
-- SHA256: 2b752fe4bbc949088d1acb0316035de3ba316f389d07c353c878dd032721e6fe
CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit(
    occasion_link TEXT, p_blueprint_id bigint
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprint_id BIGINT;
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    valid_spots JSONB;
    occasion_id BIGINT;
BEGIN
    -- Resolve occasion_id using occasion_link
    SELECT id
    INTO occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Check if occasion_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion link does not exist');
    END IF;

    -- Authorization check
    IF public.can_read_seating_status(occasion_id) IS NOT TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    IF p_blueprint_id IS NULL AND (SELECT count(*) FROM eshop.blueprints WHERE occasion=occasion_id)>1 THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_SELECTION_REQUIRED'); END IF;
    SELECT id INTO blueprint_id FROM eshop.blueprints WHERE occasion=occasion_id AND (p_blueprint_id IS NULL OR id=p_blueprint_id);

    -- Check if a blueprint exists for the occasion
    IF blueprint_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No blueprint found for this occasion');
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='blueprint' AND scope_type='occasion' AND scope_id=b.occasion AND aggregate_id=b.id::text),0),
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Shared lifecycle interpretation; only this released/private UI view
    -- includes the order-product relationship ID needed by its order controls.
    SELECT jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'product',f.product,
      'order_product_ticket',CASE WHEN public.can_read_orders(occasion_id) THEN f.order_product_ticket END,'state',f.state) ORDER BY f.id) INTO spotsData
    FROM public.blueprint_spot_facts_internal(occasion_id,ARRAY(SELECT jsonb_array_elements_text(valid_spots)::bigint)) f;

    -- Fetch all products of type "spot", "taxi", "food"
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=p.occasion AND aggregate_id=p.id::text),0),
        'title', p.title,
        'price', p.price,
        'type', pt.type,
        'description', pt.description,
        'product_type', p.product_type,
        'currency_code', p.currency_code
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    IF public.can_read_orders(occasion_id) THEN
    -- Fetch relevant tickets associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND t.occasion = occasion_id;

    -- Fetch relevant orders associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'order_symbol', o.order_symbol,
        'order_sequence', o.order_sequence,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note', 'note_hidden', coalesce(o.note_hidden,o.data->>'note_hidden'))
    ))
    INTO ordersData
    FROM eshop.orders o
    JOIN eshop.order_product_ticket opt ON opt."order" = o.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
            'id', opt.id,
            'order', opt."order",
            'product', opt.product,
            'ticket', opt.ticket,
            'created_at', opt.created_at
        ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    END IF;

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    -- Add relevant tickets data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{tickets}',
        COALESCE(ticketsData, '[]'::jsonb)
    );

    -- Add relevant orders data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{orders}',
        COALESCE(ordersData, '[]'::jsonb)
    );

    -- Add relevant order-product-ticket data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{order_product_ticket}',
        COALESCE(orderProductTicketsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_binding_projection_internal(blueprint_id);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,NULL));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_blueprint_for_edit(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_blueprint_for_edit(text,bigint) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit(occasion_link text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_blueprint_for_edit(occasion_link,NULL::bigint)
$$;
REVOKE ALL ON FUNCTION public.get_blueprint_for_edit(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_blueprint_for_edit(text) TO anon,authenticated,service_role;

-- Source: database/functions/eshop/order_seating.sql
-- SHA256: 090df6cae8ffad01af7775456672ffe7396e70ae4374613c0cf8720ba87cb7c6
-- Presentation metadata only. Callers retain their existing order access checks.
CREATE OR REPLACE FUNCTION public.order_spot_metadata_internal(p_spot bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('spot_title',s.title,'spot_group_title',CASE WHEN b.layout IS NOT NULL THEN (
   SELECT n->>'label' FROM eshop.blueprint_seat_bindings binding
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
   WHERE binding.spot=s.id AND binding.blueprint=b.id AND n->>'id'=binding.group_node::text LIMIT 1
 ) ELSE (
   SELECT g->>'title' FROM jsonb_array_elements(coalesce(b.groups,'[]')) g
   WHERE g->>'id'=(SELECT obj->>'group' FROM jsonb_array_elements(coalesce(b.objects,'[]')) obj
     WHERE obj->>'type'='spot' AND obj->>'id'=s.id::text LIMIT 1) LIMIT 1) END)
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
     LEFT JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=coalesce(f.blueprint,(SELECT tr.blueprint FROM public.form_seating_transitions tr WHERE tr.form=f.id AND tr.state='organizer_managed'))
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

-- Source: database/functions/eshop/get_order_history.sql
-- SHA256: b15685edeb19be66e6ac819033e81472d75b0e78555abe007f19eae0db2271ef
CREATE OR REPLACE FUNCTION public.get_order_history(order_id bigint)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    v_occasion_id bigint;
    v_order_data jsonb;
    v_history_data jsonb;
    v_users_data jsonb;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT o.occasion, to_jsonb(o) || jsonb_build_object('payment_method', pi.payment_method,'email_payment_fingerprint',public.order_email_payment_fingerprint(o.id))
    INTO v_occasion_id, v_order_data
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id;

    -- Check if the order exists
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found');
    END IF;

    -- Verify if the current user is an editor for the order's occasion
    IF NOT can_read_orders(v_occasion_id) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this order history');
    END IF;

    v_order_data:=jsonb_set(v_order_data,'{data,tickets}',public.order_tickets_with_seating_internal(order_id,v_order_data#>'{data,tickets}'));

    -- Fetch history items for the order, ordered by creation date
    SELECT jsonb_agg(to_jsonb(h) || jsonb_build_object('order_symbol', v_order_data->>'order_symbol', 'order_sequence', v_order_data->'order_sequence') ORDER BY h.created_at)
    INTO v_history_data
    FROM eshop.orders_history h
    WHERE h. "order" = order_id;

    -- Fetch unique users who created the history items
    WITH user_ids AS (
        SELECT DISTINCT created_by
        FROM eshop.orders_history
        WHERE "order" = order_id AND created_by IS NOT NULL
    )
    SELECT jsonb_agg(u.*)
    INTO v_users_data
    FROM public.user_info u
    WHERE u.id IN (SELECT created_by FROM user_ids);

    -- Return the combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'order', COALESCE(v_order_data, '{}'::jsonb),
            'history', COALESCE(v_history_data, '[]'::jsonb),
            'users', COALESCE(v_users_data, '[]'::jsonb)
        )
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- Source: database/functions/eshop/get_ticket_details_for_generating.sql
-- SHA256: 38773871bbfa78e93d1cd828b19e482f68b322ebc6cbbf65fa70ce1f4bf93dc7
CREATE OR REPLACE FUNCTION public.get_ticket_details_for_generating(ticket_id_input BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        -- 1. Build the 'ticket' key
        'ticket', (
            SELECT to_jsonb(t_detail)
            FROM (
                SELECT
                    t.id,
                    (SELECT i.batch_id FROM eshop.ticket_batch_items i WHERE i.ticket_id=t.id) AS batch_id,
                    t.ticket_symbol,
                    t.occasion,
                    t.note,
                    t.state,
                    b.title AS table_title,
                    -- Subquery for Spot/Product details
                    (
                        SELECT jsonb_agg(ticket_prod ORDER BY ticket_prod.id)
                        FROM (
                            SELECT
                                opt2.id,
                                opt2.product,
                                s.title AS spot_title,
                                p.data->>'short_title' AS short_title,
                                p.title AS product_title,
                                public.order_spot_metadata_internal(s.id)->>'spot_group_title' AS spot_group_title
                            FROM eshop.order_product_ticket opt2
                            LEFT JOIN eshop.spots s
                                ON s.order_product_ticket = opt2.id
                            LEFT JOIN eshop.products p
                                ON p.id = opt2.product
                            LEFT JOIN eshop.product_types pt
                                ON pt.id = p.product_type
                            LEFT JOIN eshop.blueprints bp
                                ON bp.id = s.blueprint
                            WHERE opt2.ticket = t.id
                              AND NOT (pt.type = 'spot' AND s.title IS NULL)
                        ) ticket_prod
                    ) AS order_product_ticket,

                    -- Subquery for Price (extracting from ord.data)
                    (
                      SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                    ) AS price,

                    -- Subquery for Currency (extracting from ord.data)
                    (
                      SELECT (prod->>'currency_code')
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                      LIMIT 1
                    ) AS currency_code
            ) t_detail
        ),

        -- 2. Build the 'occasion' key (dumps the whole occasion row including 'features')
        'occasion', to_jsonb(o)||jsonb_build_object('demo_read_only',public.is_demo_occasion(o.id),'locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=o.organization),'cs')),
        'order_data', jsonb_build_object('name', ord.data->'name', 'surname', ord.data->'surname')
    )
    INTO result
    FROM eshop.tickets t
    -- Join Occasion to get the occasion object
    JOIN public.occasions o
        ON o.id = t.occasion
    -- Join Blueprint for the table title
    LEFT JOIN eshop.blueprints b
        ON b.occasion = o.id
    -- Join Order Tables to expose 'ord.data' for the ticket sub-calculations above
    LEFT JOIN eshop.order_product_ticket opt
        ON opt.ticket = t.id
    LEFT JOIN eshop.orders ord
        ON ord.id = opt."order"
    WHERE t.id = ticket_id_input AND t.state IS DISTINCT FROM 'waitlisted' AND t.ticket_symbol IS NOT NULL
      AND ord.state IS DISTINCT FROM 'waitlisted';

    RETURN result;
END;
$$;

-- Source: database/functions/eshop_orders/operator_orders.sql
-- SHA256: d03b3c43d0ccaa590e04c344784fc5fa011e16020310dadfe386a774e38cfa16
-- Thin delegated adapters over the existing order, payment, report and mail owners.
-- Scope is locked in the same transaction as every read, write and receipt replay.
CREATE OR REPLACE FUNCTION public.check_operator_order_scope_internal_v1(
  p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.organization=o.organization AND ui.id=auth.uid()
    WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
  IF NOT FOUND OR public.can_read_orders(p_occasion) IS DISTINCT FROM TRUE OR (p_write AND public.can_write_orders(p_occasion) IS DISTINCT FROM TRUE) THEN
    RAISE insufficient_privilege USING MESSAGE='order context unavailable'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.operator_order_revision_internal_v1(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('order',to_jsonb(o),
   'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE p.id=o.payment_info),
   'items',(SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i WHERE i."order"=o.id),
   'tickets',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id)))::text,'UTF8'),'sha256'),'hex')
 FROM eshop.orders o WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_facts_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('id',o.id,'occasionId',o.occasion,'symbol',o.order_symbol,'state',o.state,
   'ticketCount',(SELECT count(DISTINCT i.ticket) FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket WHERE i."order"=o.id AND o.state IS DISTINCT FROM 'storno' AND o.state IS DISTINCT FROM 'waitlisted' AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'),
   'price',o.price::text,'currency',o.currency_code,'allowedActions',public.get_order_allowed_actions_internal_v1(o.id),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text) END)
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_snapshot_internal_v1(p_order bigint,p_detail boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.operator_order_facts_internal_v1(o.id) || jsonb_build_object(
   'createdAt',o.created_at,'updatedAt',o.updated_at,'revision',public.operator_order_revision_internal_v1(o.id),
   'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('method',p.payment_method,'amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'variableSymbol',p.variable_symbol::text,'deadline',p.deadline) END)
   || CASE WHEN p_detail THEN jsonb_build_object('note',o.note_hidden,'responses',coalesce(o.data->'fields','[]'),
     'formFields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'type',f.type) ORDER BY f.id),'[]') FROM public.form_fields f WHERE f.form=o.form),
     'tickets',public.order_tickets_with_seating_internal(o.id,(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'state',t.state,
        'products',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',pr.id,'title',pr.title,'price',jsonb_path_query_first(o.data,'$.tickets[*] ? (@.id == $ticket).products[*] ? (@.id == $product).price',jsonb_build_object('ticket',t.id,'product',pr.id))#>>'{}','currentPrice',pr.price::text) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i JOIN eshop.products pr ON pr.id=i.product WHERE i."order"=o.id AND i.ticket=t.id)) ORDER BY t.id),'[]')
       FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id)))) ELSE '{}'::jsonb END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_summary_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_set(facts,'{allowedActions}',
   CASE WHEN facts->'allowedActions' ? 'view' THEN '["view"]'::jsonb ELSE '[]'::jsonb END)
 FROM (SELECT public.operator_order_facts_internal_v1(p_order) facts) safe;
$$;

CREATE OR REPLACE FUNCTION public.get_operator_order_summaries_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_symbol text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR (p_symbol IS NOT NULL AND p_symbol !~ '^[A-Z0-9]{10}$')
   OR (p_state IS NOT NULL AND length(p_state)>40)
   OR (p_order IS NOT NULL AND (p_before IS NOT NULL OR p_state IS NOT NULL OR p_symbol IS NOT NULL OR p_limit<>25)) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order summary page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_summary_internal_v1(p_order)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (p_symbol IS NULL OR order_symbol=p_symbol)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_summary_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN p_symbol IS NULL AND (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

REVOKE ALL ON FUNCTION public.operator_order_facts_internal_v1(bigint),public.operator_order_summary_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_operator_order_report_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb; v_link text;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 SELECT link INTO v_link FROM public.occasions WHERE id=p_occasion;
 r:=public.get_report_ws(v_link);
 IF (r->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order report unavailable'; END IF;
 RETURN jsonb_build_object('occasionId',p_occasion,'report',r->'report',
   'waitingTickets',(SELECT count(*) FROM eshop.tickets WHERE occasion=p_occasion AND state='waitlisted'));
END $$;

CREATE OR REPLACE FUNCTION public.get_operator_orders_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_search text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR coalesce(length(p_search),0)>200 THEN RAISE invalid_parameter_value USING MESSAGE='invalid order page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_snapshot_internal_v1(p_order,true)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (nullif(p_search,'') IS NULL OR position(lower(p_search) IN lower(concat_ws(' ',order_symbol,data->>'name',data->>'surname',data->>'email')))>0)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_snapshot_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

CREATE OR REPLACE FUNCTION public.manage_operator_order_v1(p_occasion bigint,p_organization bigint,p_unit bigint,
  p_order bigint,p_command_id uuid,p_expected_revision text,p_action text,p_changes jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_unit bigint; v_begin jsonb; v_hash text; v_child uuid;
 v_result jsonb; v_actions jsonb; v_item jsonb; v_products jsonb; v_message jsonb; v_users uuid[]; v_data jsonb;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,true);
 IF p_action IS NULL OR p_expected_revision IS NULL OR p_action NOT IN('update','cancel','mark_paid','record_payment','send_tickets') OR p_expected_revision !~ '^[a-f0-9]{64}$'
   OR p_changes IS NULL OR jsonb_typeof(p_changes)<>'object' OR octet_length(p_changes::text)>65536 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order command'; END IF;
 IF p_action NOT IN('update','record_payment') AND p_changes<>'{}'::jsonb THEN RAISE invalid_parameter_value USING MESSAGE='unexpected order changes'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('order',p_order,'occasion',p_occasion,'organization',p_organization,'unit',p_unit,'revision',p_expected_revision,'action',p_action,'changes',p_changes)::text,'UTF8'),'sha256'),'hex');
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 v_begin:=public.begin_client_mutation_v1(p_command_id,'orders.operator.'||p_action,p_occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN jsonb_set(v_begin->'response','{mutation,replayed}','true'); END IF;
 -- Preserve the domain lock order, including form -> order and blueprint scope.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_order AND occasion=p_occasion FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion;
 IF public.operator_order_revision_internal_v1(p_order) IS DISTINCT FROM p_expected_revision THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('orderId',p_order,'reason','ORDER_CHANGED_RELOAD_REQUIRED')); END IF;
 v_actions:=public.get_order_allowed_actions_internal_v1(p_order);
 IF NOT (v_actions ? CASE p_action WHEN 'update' THEN CASE WHEN p_changes ? 'note' AND p_changes - 'note'='{}'::jsonb THEN 'note' ELSE 'edit' END WHEN 'cancel' THEN 'cancel' WHEN 'mark_paid' THEN 'paid' WHEN 'record_payment' THEN 'edit' ELSE 'send' END) THEN
   RAISE insufficient_privilege USING MESSAGE='order action unavailable'; END IF;
 v_child:=md5(p_command_id::text||':domain')::uuid;
 IF p_action='cancel' THEN
   v_result:=public.storno_order_client_sync_v1(p_order,v_child);
 ELSIF p_action='update' THEN
   IF p_changes - ARRAY['responses','note','tickets']::text[]<>'{}'::jsonb OR p_changes='{}' THEN RAISE invalid_parameter_value USING MESSAGE='invalid order changes'; END IF;
   IF p_changes ? 'responses' THEN PERFORM public.update_order_responses(p_order,p_changes->'responses'); END IF;
   IF p_changes ? 'note' THEN
     v_result:=public.update_order_note_hidden(p_order,p_changes->>'note');
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order note rejected'; END IF;
   END IF;
   FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_changes->'tickets','[]')) LOOP
     IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=p_order AND ticket=(v_item->>'ticketId')::bigint) THEN RAISE insufficient_privilege USING MESSAGE='ticket unavailable'; END IF;
     SELECT coalesce(jsonb_agg(jsonb_build_object('id',x->'productId','price',x->'price')),'[]') INTO v_products FROM jsonb_array_elements(v_item->'products') x;
     v_result:=public.update_ticket_products_client_sync_v1((v_item->>'ticketId')::bigint,v_products,md5(p_command_id::text||':ticket:'||(v_item->>'ticketId'))::uuid);
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='ticket products rejected'; END IF;
   END LOOP;
 ELSIF p_action='mark_paid' THEN
   v_result:=public.update_order_and_tickets_to_paid_ws(p_order);
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='payment state rejected'; END IF;
   v_result:=NULL;
 ELSIF p_action='record_payment' THEN
   IF NOT (p_changes ?& ARRAY['amount','currency','receivedAt']) OR p_changes - ARRAY['amount','currency','receivedAt','note']::text[]<>'{}'::jsonb
     OR jsonb_typeof(p_changes->'amount') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'currency') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'receivedAt') IS DISTINCT FROM 'string'
     OR v_pi.id IS NULL OR v_pi.payment_method='stripe' OR (p_changes->>'currency') IS DISTINCT FROM trim(v_order.currency_code)
     OR (p_changes->>'amount') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR (p_changes->>'amount')::numeric<=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='manual payment unavailable'; END IF;
   PERFORM public.insert_manual_transaction((p_changes->>'amount')::double precision,p_changes->>'currency',v_unit::int,v_pi.variable_symbol::text,
     p_changes->>'receivedAt',p_changes->>'note',v_pi.id::int);
 ELSIF p_action='send_tickets' THEN
   v_message:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',p_order,'requested_by',auth.uid()),p_organization,p_occasion,v_unit,now(),'operator:'||p_command_id);
 END IF;
 v_data:=jsonb_build_object('orderId',p_order,'occasionId',p_occasion,'revision',public.operator_order_revision_internal_v1(p_order))
   ||CASE WHEN v_message IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('delivery','queued','messageId',v_message->'message_id') END;
 IF v_result ? 'mutation' THEN
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='cancellation rejected'; END IF;
   v_result:=jsonb_set(v_result,'{data}',v_data);
   v_result:=jsonb_set(v_result,'{mutation,commandId}',to_jsonb(p_command_id));v_result:=jsonb_set(v_result,'{mutation,receiptId}',to_jsonb(p_command_id));
   RETURN public.finish_client_mutation_v1(p_command_id,v_result,(v_result#>>'{mutation,commitId}')::uuid);
 END IF;
 IF p_action='send_tickets' THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,v_data);
 END IF;
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=p_occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,'orders.operator.'||p_action,
   jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,'operation','update','safeLabel','Order management','changedFields',jsonb_build_array(p_action))),v_users,v_data);
END $$;

REVOKE ALL ON FUNCTION public.check_operator_order_scope_internal_v1(bigint,bigint,bigint,boolean),public.operator_order_revision_internal_v1(bigint),
 public.operator_order_snapshot_internal_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) TO authenticated;

-- Source: database/functions/blueprint/seating_transition_sync.sql
-- SHA256: 6ec2df53294fd5fb56e134c7070545bee3b2c0b95d8d5dd408c02cea2e61a229
WITH readiness AS MATERIALIZED (
 SELECT coalesce(bool_and(cutover_ready),false) ready FROM public.client_sync_component_sources WHERE registry_version=1
)
INSERT INTO public.client_sync_component_sources
(registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
(1,'private_inventory','public.form_seating_transitions','form_seating_transitions.occasion',ARRAY['form','blueprint','state','revision'],
 ARRAY['save_occasion_client_sync_v1','start_seating_configuration','cancel_seating_configuration','set_ticket_seat_assignments','publish_seating_transitions'],ARRAY[]::text[],'migrate','database/tests/blueprint/seating_transition_test.sql',(SELECT ready FROM readiness)),
(1,'private_inventory','eshop.spots','spots.occasion',ARRAY['order_product_ticket','state'],
 ARRAY['set_ticket_seat_assignments'],ARRAY[]::text[],'migrate','database/tests/blueprint/seating_assignment_test.sql',(SELECT ready FROM readiness)),
(1,'private_inventory','public.forms','forms.occasion',ARRAY['blueprint','participant_capacity','waitlist_enabled','capacity_revision'],
 ARRAY['publish_seating_transitions','save_occasion_client_sync_v1'],ARRAY[]::text[],'migrate','database/tests/blueprint/seating_publication_test.sql',(SELECT ready FROM readiness))
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 tracked_columns=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns)),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers));

NOTIFY pgrst, 'reload schema';
