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
