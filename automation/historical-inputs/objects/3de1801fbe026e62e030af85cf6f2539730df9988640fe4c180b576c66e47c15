BEGIN;

-- The pre-cutover default cloud still has the old global companion table,
-- while the canonical target and source A already have occasion-scoped
-- relationships and private-profile projection. Keep one public RPC contract
-- during the final hybrid window without applying the unrelated migration
-- backlog to the legacy production database.
DROP FUNCTION IF EXISTS public.get_user_companions_data();
DROP FUNCTION IF EXISTS public.get_user_companions_data(bigint);

DO $migration$
BEGIN
  IF to_regprocedure(
      'public.get_private_profile_payload_v1(bigint,uuid)') IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name='user_companions'
        AND column_name='occasion'
    ) THEN
    EXECUTE $sql$
      CREATE FUNCTION public.get_user_companions_data(p_occasion bigint)
      RETURNS jsonb
      LANGUAGE sql STABLE SECURITY DEFINER
      SET search_path = public, extensions
      AS $function$
        SELECT jsonb_build_object('code',200,'data',payload->'companions')
        FROM (SELECT public.get_private_profile_payload_v1(
          p_occasion,auth.uid()) payload) projected
        WHERE EXISTS (SELECT 1 FROM public.occasion_users ou
          WHERE ou.occasion=p_occasion AND ou."user"=auth.uid());
      $function$
    $sql$;
  ELSE
    -- Compatibility boundary for the default cloud only. A legacy relation is
    -- visible solely when owner and companion share the requested occasion;
    -- ambiguous historical rows remain invisible and untouched. Remove this
    -- branch after the default cloud is retired at the self-hosted cutover.
    EXECUTE $sql$
      CREATE FUNCTION public.get_user_companions_data(p_occasion bigint)
      RETURNS jsonb
      LANGUAGE sql STABLE SECURITY DEFINER
      SET search_path = public, extensions
      AS $function$
        SELECT jsonb_build_object(
          'code',200,
          'data',COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
              'id',ui.id,
              'name',ui.name,
              'surname',COALESCE(ui.surname,''),
              'group_title',COALESCE((
                SELECT string_agg(ugi.title,', ' ORDER BY ugi.title)
                FROM public.user_groups ug
                JOIN public.user_group_info ugi ON ugi.id=ug."group"
                WHERE ug."user"=uc.companion
                  AND ugi.occasion=p_occasion
                  AND ugi.type IS NULL
              ),''),
              'origin','self_created',
              'can_owner_delete',true,
              'services',COALESCE(companion_membership.services,'{}'::jsonb),
              'event_ids',COALESCE((
                SELECT jsonb_agg(eu.event ORDER BY eu.event)
                FROM public.event_users eu
                JOIN public.events e ON e.id=eu.event
                WHERE eu."user"=uc.companion
                  AND e.occasion=p_occasion
              ),'[]'::jsonb)
            ) ORDER BY ui.name,ui.surname,ui.id)
            FROM public.user_companions uc
            JOIN public.user_info ui ON ui.id=uc.companion
            JOIN public.occasion_users companion_membership
              ON companion_membership.occasion=p_occasion
             AND companion_membership."user"=uc.companion
            WHERE uc."user"=auth.uid()
          ),'[]'::jsonb)
        )
        WHERE EXISTS (SELECT 1 FROM public.occasion_users owner_membership
          WHERE owner_membership.occasion=p_occasion
            AND owner_membership."user"=auth.uid());
      $function$
    $sql$;
  END IF;
END
$migration$;

REVOKE ALL ON FUNCTION public.get_user_companions_data(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_companions_data(bigint)
  TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
