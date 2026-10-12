-- Existing map owner remains the only DML implementation.
CREATE OR REPLACE FUNCTION public.save_place_client_sync_v1(
 p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_place jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
 RETURN public.mutate_map_entity_internal_v1('place','save',p_occasion,p_command_id,p_expected_version,NULL,p_place);
END $$;
CREATE OR REPLACE FUNCTION public.delete_place_client_sync_v1(
 p_occasion bigint,p_place_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
 RETURN public.mutate_map_entity_internal_v1('place','delete',p_occasion,p_command_id,p_expected_version,p_place_id,NULL);
END $$;
