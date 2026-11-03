CREATE OR REPLACE FUNCTION public.delete_form_ws(p_form_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_response jsonb;
BEGIN
  v_response:=public.delete_form_client_sync_v1(
    p_form_id,extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',(v_response->>'code')::integer,
    'message',COALESCE(v_response#>>'{data,message}',
      'Form deleted successfully'));
END; $function$;


REVOKE ALL ON FUNCTION public.delete_form_ws(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_form_ws(bigint) TO authenticated;
