CREATE OR REPLACE FUNCTION public.update_spot_assignments_internal_v1(p_changes jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE change jsonb; oc bigint; resource_id bigint; slot_id bigint; context_id bigint; old_id bigint; new_id bigint;
 spot_ids bigint[]; resource_ids bigint[];
BEGIN
 IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'array' OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 1000 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid spot assignment batch'; END IF;
 SELECT ARRAY(SELECT DISTINCT e.value::bigint FROM jsonb_array_elements(p_changes) c CROSS JOIN LATERAL jsonb_each_text(c) e
  WHERE e.key IN('old_spot_id','new_spot_id') AND nullif(e.value,'') IS NOT NULL),
  ARRAY(SELECT DISTINCT (c->>'resource_id')::bigint FROM jsonb_array_elements(p_changes) c) INTO spot_ids,resource_ids;
 PERFORM public.lock_spot_assignment_scope_internal_v1(spot_ids,resource_ids);
 SELECT min(occasion) INTO oc FROM public.resources WHERE id=ANY(resource_ids);
 IF oc IS NULL OR public.get_is_editor_order_on_occasion(oc) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='inventory editor required'; END IF;
 IF EXISTS(SELECT 1 FROM public.resources WHERE id=ANY(resource_ids) AND occasion<>oc)
 OR (SELECT count(*) FROM public.resources WHERE id=ANY(resource_ids))<>cardinality(resource_ids)
 OR (SELECT count(*) FROM eshop.spots WHERE id=ANY(spot_ids) AND occasion=oc)<>cardinality(spot_ids) THEN
  RAISE invalid_parameter_value USING MESSAGE='assignment outside occasion'; END IF;
 -- Validate every change before writing the first one. Old IDs are the editor's
 -- original assignment, not a fresh baseline fetched immediately before save.
 FOR change IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  resource_id:=(change->>'resource_id')::bigint;slot_id:=(change->>'resource_slot_id')::bigint;
  context_id:=(change->>'inventory_context_id')::bigint;old_id:=(change->>'old_spot_id')::bigint;new_id:=(change->>'new_spot_id')::bigint;
  IF resource_id IS NULL OR (old_id IS NULL AND new_id IS NULL)
  OR (slot_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.resource_slots WHERE id=slot_id AND resource=resource_id))
  OR EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN public.inventory_contexts c ON c.id=s.inventory_context
    JOIN public.resources r ON r.id=resource_id WHERE s.id=ANY(ARRAY[old_id,new_id])
    AND (c.inventory_pool IS DISTINCT FROM r.inventory_pool OR (context_id IS NOT NULL AND s.inventory_context IS DISTINCT FROM context_id))) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid resource, slot or inventory context'; END IF;
  IF old_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.spots WHERE id=old_id AND resource=resource_id AND resource_slot IS NOT DISTINCT FROM slot_id) THEN
   RAISE serialization_failure USING MESSAGE='original spot assignment changed; reload editor'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(ARRAY[old_id,new_id]) AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp()) THEN
   RAISE object_not_in_prerequisite_state USING MESSAGE='SPOT_HELD'; END IF;
 END LOOP;
 FOR change IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  UPDATE eshop.spots SET resource=NULL,resource_slot=NULL,updated_at=now() WHERE id=(change->>'old_spot_id')::bigint;
  UPDATE eshop.spots SET resource=(change->>'resource_id')::bigint,resource_slot=(change->>'resource_slot_id')::bigint,updated_at=now() WHERE id=(change->>'new_spot_id')::bigint;
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.spots s JOIN public.resources r ON r.id=s.resource WHERE r.id=ANY(resource_ids)
  GROUP BY r.id,r.capacity,s.inventory_context HAVING count(*)>r.capacity)
 OR EXISTS(SELECT 1 FROM eshop.spots WHERE resource=ANY(resource_ids) AND resource_slot IS NOT NULL GROUP BY resource_slot,inventory_context HAVING count(*)>1) THEN
  RAISE object_not_in_prerequisite_state USING MESSAGE='RESOURCE_CAPACITY_EXCEEDED'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.update_spot_assignments_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Installed Flutter versions use the void-returning shape.
CREATE OR REPLACE FUNCTION public.update_spot_assignments(p_changes jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.update_spot_assignments_client_sync_v1(p_changes,extensions.gen_random_uuid()); END $$;
REVOKE ALL ON FUNCTION public.update_spot_assignments(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_spot_assignments(jsonb) TO authenticated;
