-- Retain released signatures, but never manufacture an editor baseline for artwork.
-- General settings continue through the one canonical occasion command.
CREATE OR REPLACE FUNCTION public.save_occasion_legacy_facade_internal_v1(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE oc bigint; version bigint; old_features jsonb; next_features jsonb;
 old_ticket jsonb; next_ticket jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 oc:=nullif(input_data->>'id','')::bigint;
 IF oc IS NULL THEN
  RETURN public.create_occasion_client_sync_v1(extensions.gen_random_uuid(),input_data);
 END IF;
 IF NOT public.can_edit_ticket_layout(oc) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 -- Same form -> occasion ordering as the canonical general-settings command.
 PERFORM 1 FROM public.forms WHERE occasion=oc ORDER BY id FOR UPDATE;
 SELECT features INTO old_features FROM public.occasions WHERE id=oc FOR UPDATE;
 IF input_data ? 'ticket_layout_change' THEN
  RAISE serialization_failure USING MESSAGE='ticket_layout_editor_upgrade_required'; END IF;
 next_features:=public.merge_ticket_layout_features(old_features,coalesce(input_data->'features','[]'::jsonb));
 SELECT value INTO old_ticket FROM jsonb_array_elements(old_features) WHERE value->>'code'='ticket';
 SELECT value INTO next_ticket FROM jsonb_array_elements(next_features) WHERE value->>'code'='ticket';
 IF jsonb_build_object('background',nullif(old_ticket->>'background',''),
       'ticket_type',coalesce(old_ticket->>'ticket_type','wide'))
    IS DISTINCT FROM jsonb_build_object('background',nullif(next_ticket->>'background',''),
       'ticket_type',coalesce(next_ticket->>'ticket_type','wide')) THEN
  RAISE serialization_failure USING MESSAGE='ticket_layout_editor_upgrade_required'; END IF;
 SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion'
 AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=oc::text;
 RETURN public.save_occasion_client_sync_v1(oc,extensions.gen_random_uuid(),version,input_data);
END $$;
REVOKE ALL ON FUNCTION public.save_occasion_legacy_facade_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.update_occasion(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.save_occasion_legacy_facade_internal_v1(input_data);
 RETURN jsonb_build_object('code',result->'code','occasion',result#>'{data,occasion}');
END $$;

CREATE OR REPLACE FUNCTION public.update_occasion_203(input_data jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.save_occasion_legacy_facade_internal_v1(input_data);
 IF result->>'status'='conflict' THEN RAISE serialization_failure USING MESSAGE='occasion changed'; END IF;
 IF result->>'status'='rejected' THEN RAISE invalid_parameter_value USING MESSAGE='occasion save rejected'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.update_occasion_182(input_data jsonb)
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.update_occasion_203(input_data);
$$;
REVOKE ALL ON FUNCTION public.update_occasion(jsonb),public.update_occasion_203(jsonb),public.update_occasion_182(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion(jsonb),public.update_occasion_203(jsonb),public.update_occasion_182(jsonb) TO authenticated;
