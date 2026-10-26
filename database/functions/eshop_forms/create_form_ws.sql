CREATE OR REPLACE FUNCTION public.create_form_ws(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_response jsonb;
BEGIN
  IF input_data IS NULL OR jsonb_typeof(input_data)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(input_data) k
      WHERE k NOT IN ('occasion_link','link','title')) THEN
    RETURN jsonb_build_object('code',4000,'message','Invalid form input'); END IF;
  v_response:=public.create_form_client_sync_v1(input_data->>'occasion_link',
    input_data->>'link',input_data->>'title',extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',CASE WHEN v_response->>'status'='applied'
      THEN 201 ELSE (v_response->>'code')::integer END,
    'message',CASE WHEN v_response->>'status'='applied'
      THEN 'Form created successfully' ELSE v_response#>>'{data,message}' END,
    'data',v_response#>'{data,form}');
END; $$;
REVOKE ALL ON FUNCTION public.create_form_ws(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_form_ws(jsonb) TO authenticated;
