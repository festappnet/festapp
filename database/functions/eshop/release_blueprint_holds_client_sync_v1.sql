-- Administrative release of temporary holds. Buyers still use select_spot.
CREATE OR REPLACE FUNCTION public.release_blueprint_holds_client_sync_v1(
 p_spots bigint[], p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid(); occ bigint; ids bigint[]; bp bigint; started jsonb; users uuid[]; fingerprint text;
BEGIN
 IF actor IS NULL OR coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>256 THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 SELECT min(b.occasion),min(s.blueprint) INTO occ,bp FROM eshop.spots s JOIN eshop.blueprints b ON b.id=s.blueprint WHERE s.id=ANY(p_spots);
 IF occ IS NULL OR public.can_write_orders(occ) IS NOT TRUE OR
  (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND blueprint=bp) <>
  cardinality(ARRAY(SELECT DISTINCT x FROM unnest(p_spots) x)) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM public.check_occasion_writable(occ);
 fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('spots',p_spots)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.blueprint.holds.release',occ,actor,fingerprint);
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM unnest(p_spots) requested
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(ids) AND (blueprint IS DISTINCT FROM bp OR order_product_ticket IS NOT NULL)) THEN
  RAISE check_violation USING MESSAGE='Spot is already ordered'; END IF;
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO users FROM public.occasion_users ou WHERE ou.occasion=occ;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now()
 WHERE id=ANY(ids) AND order_product_ticket IS NULL;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.blueprint.holds.release',
  jsonb_build_array(jsonb_build_object('entityType','spot','entityId',NULL,'operation','update','safeLabel','Temporary reservation released','changedFields',jsonb_build_array('reservation'))),
  users,jsonb_build_object('spotIds',to_jsonb(ids)));
END $$;
REVOKE ALL ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) TO authenticated;
