-- Supported old entrypoints delegate to command receipts and never own slugs.
CREATE OR REPLACE FUNCTION public.update_occasion(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; id bigint; version bigint;
BEGIN
 id:=nullif(input_data->>'id','')::bigint;
 IF id IS NULL THEN result:=public.create_occasion_client_sync_v1(gen_random_uuid(),input_data);
 ELSE
  SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
   ON v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=id AND v.aggregate_id=id::text;
  result:=public.save_occasion_client_sync_v1(id,gen_random_uuid(),version,input_data);
 END IF;
 RETURN jsonb_build_object('code',result->'code','occasion',result#>'{data,occasion}');
END $$;
CREATE OR REPLACE FUNCTION public.update_occasion_182(input_data jsonb)
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.update_occasion_203(input_data);
$$;
CREATE OR REPLACE FUNCTION public.duplicate_form(p_old_form_id bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target text;
BEGIN
 SELECT o.link INTO target FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_old_form_id;
 RETURN public.duplicate_form_to_occasion(p_old_form_id,target);
END $$;
CREATE OR REPLACE FUNCTION public.copy_form_with_fields(p_source_form_id bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.duplicate_form(p_source_form_id);
$$;
REVOKE ALL ON FUNCTION public.update_occasion(jsonb),public.update_occasion_182(jsonb),
 public.duplicate_form(bigint),public.copy_form_with_fields(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion(jsonb),public.update_occasion_182(jsonb),
 public.duplicate_form(bigint),public.copy_form_with_fields(bigint) TO authenticated;
-- Abandoned implementations have no remaining callers after the cutover.
DROP FUNCTION IF EXISTS public.create_form_ws_obsolete_v1(jsonb);
DROP FUNCTION IF EXISTS public.sync_source_via_http_internal_v1(text);

DROP FUNCTION IF EXISTS public.duplicate_occasion_domain_command_internal_v1(bigint,uuid);
