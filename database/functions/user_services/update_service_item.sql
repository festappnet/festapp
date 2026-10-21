CREATE OR REPLACE FUNCTION public.update_service_item_internal_v1(oc bigint, type text, code text, new_title text, new_reference bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  updated_services JSONB;
BEGIN

  IF (SELECT can_write_service_items(oc)) <> TRUE THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Check if the code exists within the specified type
  IF NOT EXISTS (
    SELECT 1
    FROM public.occasions,
         jsonb_array_elements(occasions.services->type) AS item
    WHERE occasions.id = oc
      AND (item->>'code') = code
  ) THEN
    -- If code does not exist, return an error response
    RETURN jsonb_build_object(
      'code', 404,
      'message', 'Service item not found'
    );
  END IF;

  -- Update the specified service item
  updated_services := (
    SELECT jsonb_agg(
      CASE
        WHEN (item->>'code') = code THEN
          item || jsonb_build_object('title', new_title, 'reference', new_reference)
        ELSE
          item
      END
    )
    FROM public.occasions,
         jsonb_array_elements(occasions.services->type) AS item
    WHERE occasions.id = oc
  );

  -- Apply the updated services JSON to the specified type
  UPDATE public.occasions
  SET services = jsonb_set(
    services,
    ARRAY[type],
    updated_services,
    true
  )
  WHERE id = oc;

  -- Return success response
  RETURN jsonb_build_object(
    'code', 200,
    'message', 'Service item updated successfully'
  );
END;
$function$
;
REVOKE ALL ON FUNCTION public.update_service_item_internal_v1(bigint,text,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.update_service_item(oc bigint, type text, code text, new_title text, new_reference bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN RETURN public.update_service_item_client_sync_v1(
  oc,type,code,new_title,new_reference,extensions.gen_random_uuid())->'data'; END; $function$
;
REVOKE ALL ON FUNCTION public.update_service_item(bigint,text,text,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_service_item(bigint,text,text,text,bigint) TO authenticated;
