CREATE OR REPLACE FUNCTION get_last_sign_in_at_for_users(user_ids uuid[], oc bigint)
RETURNS jsonb
SECURITY definer
SET search_path = public, extensions
AS $$
BEGIN
  -- Check if the user is a manager for the occasion
  IF (SELECT get_is_manager_on_occasion(oc)) <> TRUE THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Aggregate the last sign-in data as JSON
  RETURN jsonb_build_object(
    'code', 200,
    'data', (
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', au.id,
        'last_sign_in_at', au.last_sign_in_at
      ))
      FROM auth.users au
      JOIN public.occasion_users ou ON au.id = ou."user"
      WHERE au.id = ANY(user_ids)
        AND ou.occasion = oc
    )
  );
END;
$$ LANGUAGE plpgsql;