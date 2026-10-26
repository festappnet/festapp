CREATE OR REPLACE FUNCTION public.set_saved_program(p_occasion bigint,p_event_ids bigint[],p_mode text)
RETURNS bigint[] LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb;
BEGIN
 r:=public.set_saved_program_client_sync_v1(p_occasion,p_event_ids,p_mode,extensions.gen_random_uuid());
 IF r->>'code'<>'200' THEN RAISE EXCEPTION 'saved program rejected'; END IF;
 RETURN ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(r#>'{data,saved}'));
END $$;

REVOKE ALL ON FUNCTION public.set_saved_program(bigint,bigint[],text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_saved_program(bigint,bigint[],text) TO authenticated;
