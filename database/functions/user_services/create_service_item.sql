CREATE OR REPLACE FUNCTION public.create_service_item_internal_v1(oc bigint, type text, code text, title text, reference bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  existing_codes JSONB;
  new_service_item JSONB;
BEGIN

  IF (SELECT get_is_manager_on_occasion(oc)) <> TRUE THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Check if the code already exists within the specified type
  SELECT jsonb_agg(item)
  INTO existing_codes
  FROM public.occasions,
       jsonb_array_elements(COALESCE(occasions.services->type, '[]'::jsonb)) AS item
  WHERE occasions.id = oc
    AND (item->>'code') = code;

  IF existing_codes IS NOT NULL THEN
    -- If code exists, return an error response
    RETURN jsonb_build_object(
      'code', 400,
      'message', 'Code must be unique within the specified type'
    );
  END IF;

  -- Build the new service item JSON
  new_service_item := jsonb_build_object(
    'code', code,
    'title', title,
    'reference', reference
  );

  -- Update the occasion to add the new item to the specified type array in services.
  -- Guard against `services` being SQL NULL *or* a JSON scalar/`null` (which
  -- COALESCE does not catch and which makes jsonb_set raise
  -- "cannot set path in scalar"). Same guard for the per-type array.
  UPDATE public.occasions
  SET services = jsonb_set(
    CASE WHEN jsonb_typeof(services) = 'object' THEN services ELSE '{}'::jsonb END,
    ARRAY[type],
    CASE WHEN jsonb_typeof(services->type) = 'array' THEN services->type ELSE '[]'::jsonb END || new_service_item,
    true
  )
  WHERE id = oc;

  -- Return success response
  RETURN jsonb_build_object(
    'code', 200,
    'message', 'Service item created successfully'
  );
END;
$function$
;
REVOKE ALL ON FUNCTION public.create_service_item_internal_v1(bigint,text,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.create_service_item(oc bigint, type text, code text, title text, reference bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN RETURN public.create_service_item_client_sync_v1(
  oc,type,code,title,reference,extensions.gen_random_uuid())->'data'; END; $function$
;
REVOKE ALL ON FUNCTION public.create_service_item(bigint,text,text,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_service_item(bigint,text,text,text,bigint) TO authenticated;
