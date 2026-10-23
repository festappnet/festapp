-- Snapshot-bound hold release shared by current UI and MCP, preserving legacy receipts.
CREATE OR REPLACE FUNCTION public.blueprint_hold_snapshot_internal(p_occasion bigint,p_ids bigint[])
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object('id',id,'blueprint',blueprint,'secret',secret,
  'expires',extract(epoch FROM secret_expiration_time),'orderItem',order_product_ticket) ORDER BY id),'[]')::text,'UTF8'),'sha256'),'hex')
 FROM eshop.spots WHERE occasion=p_occasion AND id=ANY(p_ids)
$$;
REVOKE ALL ON FUNCTION public.blueprint_hold_snapshot_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_hold_selection_internal(p_occasion bigint,p_blueprint bigint,p_spots bigint[],p_max integer)
RETURNS bigint[] LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];
BEGIN
 IF coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>256 OR array_position(p_spots,NULL) IS NOT NULL
  OR (SELECT count(DISTINCT x) FROM unnest(p_spots)x)<>cardinality(p_spots) THEN RAISE invalid_parameter_value USING MESSAGE='invalid hold selection'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=p_blueprint AND b.spot=ANY(p_spots))<>cardinality(p_spots) THEN RAISE insufficient_privilege USING MESSAGE='hold selection unavailable'; END IF;
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM unnest(p_spots) selected
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(selected))member;
 IF cardinality(ids)>p_max THEN RAISE program_limit_exceeded USING MESSAGE='expanded hold selection exceeds operation limit'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=p_blueprint AND b.spot=ANY(ids))<>cardinality(ids) THEN RAISE insufficient_privilege USING MESSAGE='expanded hold selection unavailable'; END IF;
 RETURN ids;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_hold_selection_internal(bigint,bigint,bigint[],integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_blueprint_hold_release(p_occasion bigint,p_organization bigint,p_unit bigint,p_spots bigint[],p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint;rev bigint;ids bigint[];rows jsonb;snapshot text;read_time timestamptz;
BEGIN
 IF p_editor IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='hold preview mode required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 SELECT min(blueprint) INTO bp FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion;
 SELECT layout_revision INTO rev FROM eshop.blueprints WHERE id=bp AND occasion=p_occasion AND layout IS NOT NULL FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='canonical blueprint unavailable'; END IF;
 ids:=public.blueprint_hold_selection_internal(p_occasion,bp,p_spots,CASE WHEN p_editor THEN 20000 ELSE 1000 END);
 -- One locked snapshot for both displayed state and opaque confirmation token.
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR SHARE;
 read_time:=clock_timestamp();
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',f.id,'title',f.title,'state',f.state) ORDER BY f.id),'[]') INTO rows
 FROM public.blueprint_spot_facts_internal(p_occasion,ids,read_time) f;
 snapshot:=public.blueprint_hold_snapshot_internal(p_occasion,ids);
 IF octet_length(rows::text)>(CASE WHEN p_editor THEN 8388608 ELSE 1048576 END) THEN RAISE program_limit_exceeded USING MESSAGE='hold preview exceeds payload limit'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'blueprintId',bp,'layoutRevision',rev,'requestedSpotIds',p_spots,
  'affectedSpotIds',ids,'holdSnapshot',snapshot,'seats',rows,
  'activeHoldCount',(SELECT count(*) FROM jsonb_array_elements(rows)r WHERE r->>'state'='selected'),
  'canApply',NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows)r WHERE r->>'state' IN ('ordered','used')),'readAt',read_time);
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_hold_release(bigint,bigint,bigint,bigint[],boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_hold_release(bigint,bigint,bigint,bigint[],boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.release_blueprint_holds(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint,
 p_spots bigint[],p_affected_spots bigint[],p_expected_revision bigint,p_hold_snapshot text,p_command_id uuid,p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_editor IS NULL OR p_command_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0
  OR p_hold_snapshot IS NULL OR p_hold_snapshot!~'^[0-9a-f]{64}$' OR coalesce(cardinality(p_affected_spots),0)=0
  OR cardinality(p_affected_spots)>(CASE WHEN p_editor THEN 20000 ELSE 1000 END) THEN RAISE invalid_parameter_value USING MESSAGE='confirmed hold release required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
 -- Validate actual requested binding before a legacy owner can lock foreign scope.
 IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion AND blueprint=p_blueprint)
  IS DISTINCT FROM cardinality(p_spots) THEN RAISE insufficient_privilege USING MESSAGE='hold selection unavailable'; END IF;
 result:=public.release_blueprint_holds_command_internal(p_spots,p_command_id,p_affected_spots,p_expected_revision,p_hold_snapshot);
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
 IF NOT p_editor THEN result:=result-'sync'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.release_blueprint_holds(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,text,uuid,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.release_blueprint_holds(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,text,uuid,boolean) TO authenticated;

-- One receipt owner; the legacy response/hash remain available through its adapter.
-- Administrative release of temporary holds. Buyers still use select_spot.
CREATE OR REPLACE FUNCTION public.release_blueprint_holds_command_internal(
 p_spots bigint[], p_command_id uuid,p_expected_spots bigint[] DEFAULT NULL,p_expected_revision bigint DEFAULT NULL,p_hold_snapshot text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid(); occ bigint; ids bigint[]; bp bigint; started jsonb; users uuid[]; fingerprint text; revision bigint; released bigint; confirmed boolean:=p_expected_revision IS NOT NULL;
BEGIN
 IF (p_expected_spots IS NULL OR p_expected_revision IS NULL OR p_hold_snapshot IS NULL)
  AND (p_expected_spots IS NOT NULL OR p_expected_revision IS NOT NULL OR p_hold_snapshot IS NOT NULL) THEN
  RAISE invalid_parameter_value USING MESSAGE='complete hold confirmation required'; END IF;
 IF actor IS NULL OR coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>256 THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 SELECT min(b.occasion),min(s.blueprint) INTO occ,bp FROM eshop.spots s JOIN eshop.blueprints b ON b.id=s.blueprint WHERE s.id=ANY(p_spots);
 IF occ IS NULL OR public.can_write_orders(occ) IS NOT TRUE OR
  (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND blueprint=bp) <>
  cardinality(ARRAY(SELECT DISTINCT x FROM unnest(p_spots) x)) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM public.check_occasion_writable(occ);
 fingerprint:=encode(extensions.digest(convert_to((jsonb_build_object('spots',p_spots)||CASE WHEN confirmed THEN jsonb_build_object('affected',p_expected_spots,'revision',p_expected_revision,'snapshot',p_hold_snapshot) ELSE '{}'::jsonb END)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.blueprint.holds.release',occ,actor,fingerprint);
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM unnest(p_spots) requested
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member;
 SELECT layout_revision INTO revision FROM eshop.blueprints WHERE id=bp AND occasion=occ FOR SHARE;
 IF confirmed AND (revision IS DISTINCT FROM p_expected_revision OR ids IS DISTINCT FROM ARRAY(SELECT x FROM unnest(p_expected_spots)x ORDER BY x)) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_SELECTION_CHANGED')); END IF;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF confirmed AND public.blueprint_hold_snapshot_internal(occ,ids) IS DISTINCT FROM p_hold_snapshot THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_HOLDS_CHANGED')); END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(ids) AND (blueprint IS DISTINCT FROM bp OR order_product_ticket IS NOT NULL)) THEN
  IF confirmed THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_SEAT_ORDERED')); END IF;
  RAISE check_violation USING MESSAGE='Spot is already ordered'; END IF;
 SELECT count(*) INTO released FROM eshop.spots WHERE id=ANY(ids) AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp();
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO users FROM public.occasion_users ou WHERE ou.occasion=occ;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now()
 WHERE id=ANY(ids) AND order_product_ticket IS NULL;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.blueprint.holds.release',
  jsonb_build_array(jsonb_build_object('entityType','spot','entityId',NULL,'operation','update','safeLabel','Temporary reservation released','changedFields',jsonb_build_array('reservation'))),
  users,jsonb_build_object('spotIds',to_jsonb(ids))||CASE WHEN confirmed THEN jsonb_build_object('releasedCount',released,'blueprintId',bp,'layoutRevision',revision) ELSE '{}'::jsonb END);
END $$;
REVOKE ALL ON FUNCTION public.release_blueprint_holds_command_internal(bigint[],uuid,bigint[],bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- Released legacy intent delegates to the one receipt owner.
CREATE OR REPLACE FUNCTION public.release_blueprint_holds_client_sync_v1(p_spots bigint[],p_command_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.release_blueprint_holds_command_internal(p_spots,p_command_id)
$$;
REVOKE ALL ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) TO authenticated;
