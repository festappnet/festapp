CREATE OR REPLACE FUNCTION public.delete_service_item_internal_v1(oc bigint, type text, code text, force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  in_use BOOLEAN;
BEGIN
  IF (SELECT get_is_manager_on_occasion(oc)) <> TRUE THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Check if the code is in use in occasion_users for the same occasion and type
  SELECT EXISTS(
    SELECT 1
    FROM public.occasion_users
    WHERE occasion_users.occasion = oc
      AND (occasion_users.services->type->>code IS NOT NULL AND occasion_users.services->type->>code <> 'none')
  ) INTO in_use;

  -- If the code is in use and force is not true, return an error response
  IF in_use AND NOT force THEN
    RETURN jsonb_build_object(
      'code', 400,
      'message', 'Service item is in use and cannot be deleted without force'
    );
  END IF;

  -- If force is true, remove the same code from any matching occasion_user records
  IF force AND in_use THEN
    UPDATE public.occasion_users
    SET services = jsonb_set(
      services,
      ARRAY[type],
      (services->type) - code
    )
    WHERE occasion_users.occasion = oc
      AND (occasion_users.services->type->>code IS NOT NULL AND occasion_users.services->type->>code <> 'none');
  END IF;

  IF NOT force AND NOT in_use THEN
    UPDATE public.occasion_users
    SET services = jsonb_set(
      services,
      ARRAY[type],
      (services->type) - code
    )
    WHERE occasion_users.occasion = oc
      AND (occasion_users.services->type->>code IS NULL OR occasion_users.services->type->>code = 'none');
  END IF;

  -- Remove the item from the occasions.services->type array
  UPDATE public.occasions
  SET services = jsonb_set(
    services,
    ARRAY[type],
    coalesce((SELECT jsonb_agg(item)
     FROM jsonb_array_elements(services->type) AS item
     WHERE item->>'code' IS DISTINCT FROM code),'[]'::jsonb),
    true
  )
  WHERE id = oc;

  -- Return success response
  RETURN jsonb_build_object(
    'code', 200,
    'message', 'Service item deleted successfully'
  );
END;
$function$
;
REVOKE ALL ON FUNCTION public.delete_service_item_internal_v1(bigint,text,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.delete_service_item(oc bigint, type text, code text, force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN
  RETURN public.delete_service_item_client_sync_v1(
    oc,type,code,force,extensions.gen_random_uuid());
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_service_item(bigint,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_service_item(bigint,text,text,boolean) TO authenticated;
