CREATE OR REPLACE FUNCTION public.lock_blueprint_inventory_internal(p_occasion bigint,p_blueprint bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 -- Keep the existing financial resource lock ordering, before spot row locks.
 PERFORM 1 FROM eshop.products WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=p_occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=p_occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE blueprint=p_blueprint ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_blueprint_inventory_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Lifecycle facts shared by the current UI reader and bounded operator views.
-- `blocked` is a binding setting, never a synonym for an order or temporary hold.
CREATE OR REPLACE FUNCTION public.blueprint_spot_facts_internal(p_occasion bigint,p_ids bigint[],p_at timestamptz DEFAULT statement_timestamp())
RETURNS TABLE(id bigint,title text,product bigint,order_product_ticket bigint,state text,is_protected boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT s.id,s.title,s.product,s.order_product_ticket,CASE WHEN t.state='used' THEN 'used'
  WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
  WHEN s.secret IS NOT NULL AND s.secret_expiration_time>p_at THEN 'selected' ELSE 'available' END,
  s.order_product_ticket IS NOT NULL OR coalesce(s.secret IS NOT NULL AND s.secret_expiration_time>p_at,false)
 FROM eshop.spots s LEFT JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket
 LEFT JOIN eshop.tickets t ON t.id=opt.ticket WHERE s.occasion=p_occasion AND s.id=ANY(p_ids)
$$;
REVOKE ALL ON FUNCTION public.blueprint_spot_facts_internal(bigint,bigint[],timestamptz) FROM PUBLIC,anon,authenticated,service_role;

-- Enforce UI's atomic block-selection rule at the aggregate owner too. Other
-- geometry edits remain local until the ordinary Save/Cancel boundary is used.
CREATE OR REPLACE FUNCTION public.check_blueprint_block_changes_internal(p_blueprint bigint,p_layout jsonb,p_changes jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE incomplete boolean;protected_member boolean;
BEGIN
 -- Parse incoming changes and selection membership once, then join by identity.
 -- A whole-plan UI save must not scan every unit/JSON change for every member.
 WITH changes AS MATERIALIZED (
  SELECT (c->>'nodeId')::uuid node,(c->>'blocked')::boolean blocked,c->>'operation' operation
  FROM jsonb_array_elements(coalesce(p_changes,'[]'))c
 ), members AS MATERIALIZED (
  SELECT (u->>'id')::uuid unit,member::uuid node FROM jsonb_array_elements(coalesce(p_layout->'selectionUnits','[]'))u
  CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds')member
 ), targets AS MATERIALIZED (
  SELECT DISTINCT m.unit,c.blocked FROM changes c
  JOIN eshop.blueprint_seat_bindings old ON old.blueprint=p_blueprint AND old.node_id=c.node
  JOIN members m ON m.node=c.node
  WHERE c.operation='upsert' AND coalesce(old.blocked,false) IS DISTINCT FROM c.blocked
 )
 SELECT coalesce(bool_or(c.node IS NULL OR c.operation IS DISTINCT FROM 'upsert' OR c.blocked IS DISTINCT FROM t.blocked),false),
  coalesce(bool_or(s.order_product_ticket IS NOT NULL OR s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()),false)
 INTO incomplete,protected_member
 FROM targets t JOIN members m ON m.unit=t.unit LEFT JOIN changes c ON c.node=m.node
 LEFT JOIN eshop.blueprint_seat_bindings b ON b.blueprint=p_blueprint AND b.node_id=m.node
 LEFT JOIN eshop.spots s ON s.id=b.spot;
 IF incomplete THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INCOMPLETE_BLOCK_SELECTION_UNIT'; END IF;
 IF protected_member THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_PROTECTED'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_block_changes_internal(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_blueprint_admin_scope_internal(p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean,p_lock boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,p_lock);
 IF p_write AND public.can_write_blueprints(p_occasion) IS DISTINCT FROM TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_admin_scope_internal(bigint,bigint,bigint,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_admin_seat_rows_internal(p_occasion bigint,p_blueprint bigint,p_ids bigint[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',f.id,'nodeId',b.node_id,'title',f.title,'productId',f.product,
  'productTitle',p.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked,
  'state',f.state,'canBlock',NOT f.is_protected) ORDER BY f.id),'[]')
 FROM eshop.blueprint_seat_bindings b JOIN public.blueprint_spot_facts_internal(p_occasion,p_ids) f ON f.id=b.spot
 LEFT JOIN eshop.products p ON p.id=f.product AND p.occasion=p_occasion WHERE b.blueprint=p_blueprint
$$;
REVOKE ALL ON FUNCTION public.blueprint_admin_seat_rows_internal(bigint,bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_blueprint_seats(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint DEFAULT NULL,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint;meta jsonb;ids bigint[];next_id bigint;rows jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR p_after IS NOT NULL AND p_after<1 THEN RAISE invalid_parameter_value USING MESSAGE='invalid seat page'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,false,true);
 SELECT id,jsonb_build_object('id',id,'title',title,'layoutRevision',layout_revision) INTO bp,meta
 FROM eshop.blueprints WHERE occasion=p_occasion AND (p_blueprint IS NULL OR id=p_blueprint) AND layout IS NOT NULL ORDER BY id LIMIT 1 FOR SHARE;
 IF bp IS NULL THEN RAISE insufficient_privilege USING MESSAGE='canonical blueprint unavailable'; END IF;
 SELECT coalesce(array_agg(spot ORDER BY spot),'{}'::bigint[]) INTO ids FROM (
  SELECT b.spot FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=bp AND (p_after IS NULL OR b.spot>p_after) ORDER BY b.spot LIMIT p_limit+1) selected;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 rows:=public.blueprint_admin_seat_rows_internal(p_occasion,bp,ids);
 IF octet_length(rows::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='seat page exceeds payload limit'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'blueprint',meta,'seats',rows,'nextCursor',next_id,'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.get_blueprint_seats(bigint,bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_blueprint_seats(bigint,bigint,bigint,bigint,bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.blueprint_block_selection_internal(p_occasion bigint,p_blueprint bigint,p_spots bigint[])
RETURNS bigint[] LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];
BEGIN
 IF coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>100 OR array_position(p_spots,NULL) IS NOT NULL
  OR (SELECT count(DISTINCT x) FROM unnest(p_spots)x)<>cardinality(p_spots) THEN RAISE invalid_parameter_value USING MESSAGE='invalid seat selection'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=p_blueprint AND b.spot=ANY(p_spots))<>cardinality(p_spots) THEN RAISE insufficient_privilege USING MESSAGE='seat selection unavailable'; END IF;
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM unnest(p_spots) selected
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(selected))member;
 IF cardinality(ids)>1000 THEN RAISE program_limit_exceeded USING MESSAGE='expanded selection exceeds operation limit'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=p_blueprint AND b.spot=ANY(ids))<>cardinality(ids) THEN RAISE insufficient_privilege USING MESSAGE='expanded selection unavailable'; END IF;
 RETURN ids;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_block_selection_internal(bigint,bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_blueprint_seat_block(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint,p_spots bigint[],p_blocked boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[];rev bigint;rows jsonb;
BEGIN
 IF p_blocked IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='block target required'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true,true);
 SELECT layout_revision INTO rev FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion AND layout IS NOT NULL FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='canonical blueprint unavailable'; END IF;
 ids:=public.blueprint_block_selection_internal(p_occasion,p_blueprint,p_spots);
 rows:=public.blueprint_admin_seat_rows_internal(p_occasion,p_blueprint,ids);
 IF octet_length(rows::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='seat preview exceeds payload limit'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'blueprintId',p_blueprint,'layoutRevision',rev,'requestedSpotIds',p_spots,
  'affectedSpotIds',ids,'blocked',p_blocked,'seats',rows,'canApply',NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows)r WHERE (r->>'canBlock')::boolean IS DISTINCT FROM true),'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_seat_block(bigint,bigint,bigint,bigint,bigint[],boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_seat_block(bigint,bigint,bigint,bigint,bigint[],boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.block_blueprint_seats(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint,p_spots bigint[],p_affected_spots bigint[],p_expected_revision bigint,p_blocked boolean,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid();started jsonb;fingerprint text;bp eshop.blueprints;ids bigint[];changes jsonb;request jsonb;result jsonb;users uuid[];reason text;
BEGIN
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true);
 IF p_command_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0 OR p_blocked IS NULL
  OR coalesce(cardinality(p_affected_spots),0)=0 OR cardinality(p_affected_spots)>1000 OR array_position(p_affected_spots,NULL) IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='confirmed block intention required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
 fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,'blueprint',p_blueprint,'spots',p_spots,
  'affected',p_affected_spots,'revision',p_expected_revision,'blocked',p_blocked)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.blueprint.block',p_occasion,actor,fingerprint);
 IF started->>'disposition'='replay' THEN result:=started->'response';
 ELSE
  PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
  -- Same product/blueprint lock order as the full aggregate owner.
  PERFORM 1 FROM eshop.products WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  SELECT * INTO bp FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
  BEGIN
   IF bp.layout_revision<>p_expected_revision OR bp.layout IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
   ids:=public.blueprint_block_selection_internal(p_occasion,p_blueprint,p_spots);
   IF ids IS DISTINCT FROM ARRAY(SELECT x FROM unnest(p_affected_spots)x ORDER BY x) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SELECTION_CHANGED'; END IF;
   PERFORM public.lock_blueprint_inventory_internal(p_occasion,p_blueprint);
   IF EXISTS(SELECT 1 FROM public.blueprint_spot_facts_internal(p_occasion,ids,clock_timestamp()) WHERE is_protected) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_PROTECTED'; END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object('operation','upsert','blocked',p_blocked,'nodeId',b.node_id,
    'spotId',b.spot,'productId',s.product,'title',s.title,'groupNodeId',b.group_node,'selectionUnitId',b.selection_unit,
    'productAssignmentMode',b.product_assignment_mode) ORDER BY b.spot),'[]') INTO changes
   FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint AND b.spot=ANY(ids);
   request:=jsonb_build_object('id',bp.id,'occasion',bp.occasion,'organization',bp.organization,'title',bp.title,
    'expected_layout_revision',p_expected_revision,'layout',bp.layout,'textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(bp.layout,bp.occasion)),
    'seatChanges',changes,'groupProductChanges','[]'::jsonb,'areaBindingChanges','[]'::jsonb);
   result:=public.save_blueprint_layout_internal_v1(request);
  EXCEPTION WHEN check_violation OR raise_exception OR invalid_text_representation OR not_null_violation OR unique_violation OR foreign_key_violation THEN
   GET STACKED DIAGNOSTICS reason=MESSAGE_TEXT;
   result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason',reason,'layoutRevision',bp.layout_revision));
  END;
  IF result->>'status' IS NULL THEN
   SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO users FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
   result:=public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,'inventory.blueprint.block',
    jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',bp.id,'operation','update','safeLabel',left(bp.title,240),'changedFields',jsonb_build_array('blocked'))),users,
    jsonb_build_object('blueprintId',bp.id,'layoutRevision',(result->>'layout_revision')::bigint,'affectedSpotIds',ids,'blocked',p_blocked));
  END IF;
 END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
 RETURN result-'sync';
END $$;
REVOKE ALL ON FUNCTION public.block_blueprint_seats(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,boolean,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.block_blueprint_seats(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,boolean,uuid) TO authenticated;
