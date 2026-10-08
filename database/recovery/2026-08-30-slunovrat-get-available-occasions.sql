DO $guard$
BEGIN
  IF to_regprocedure('public.get_available_occasions(bigint,bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'get_available_occasions already exists; refusing an unreviewed replacement';
  END IF;
  IF to_regclass('public.external_occasions_cache') IS NOT NULL THEN
    RAISE EXCEPTION 'legacy compatibility migration is not valid after external cache installation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = 1) THEN
    RAISE EXCEPTION 'expected Slunovrat organization 1 is missing';
  END IF;
END
$guard$;

CREATE FUNCTION public.get_available_occasions(
  p_organization_id bigint,
  p_unit_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  occasions_data jsonb;
  result_data jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RAISE EXCEPTION 'organization_not_found: Organization % does not exist.', p_organization_id
      USING ERRCODE = 'P0002';
  END IF;

  IF p_unit_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.units
    WHERE id = p_unit_id AND organization = p_organization_id
  ) THEN
    RAISE EXCEPTION 'unit_not_found: Unit % not found in Org %.', p_unit_id, p_organization_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,
    'title',o.title,
    'description',o.description,
    'link',o.link,
    'start_time',o.start_time,
    'end_time',o.end_time,
    'is_open',o.is_open,
    'is_hidden',o.is_hidden,
    'is_promoted',o.is_promoted,
    'features',o.features,
    'created_at',o.created_at,
    'updated_at',o.updated_at,
    'data',o.data,
    'source_name',NULL,
    'last_synced_at',NULL,
    'is_external',false,
    'form',(
      SELECT jsonb_build_object(
        'id',f.id,
        'created_at',f.created_at,
        'data',f.data,
        'type',f.type,
        'is_open',f.is_open,
        'link',f.link,
        'header',f.header
      )
      FROM public.forms f
      WHERE f.occasion = o.id
      ORDER BY f.is_open DESC,f.id
      LIMIT 1
    )
  ) ORDER BY o.start_time DESC),'[]'::jsonb)
  INTO occasions_data
  FROM public.occasions o
  WHERE o.organization = p_organization_id
    AND (p_unit_id IS NULL OR o.unit = p_unit_id)
    AND o.is_hidden = false
    AND (p_unit_id IS NOT NULL OR o.is_promoted = true);

  IF p_unit_id IS NULL THEN
    result_data := jsonb_build_object(
      'title','All Occasions',
      'organization',p_organization_id,
      'occasions',occasions_data
    );
  ELSE
    SELECT jsonb_build_object(
      'id',u.id,
      'title',u.title,
      'organization',u.organization,
      'occasions',occasions_data
    )
    INTO result_data
    FROM public.units u
    WHERE u.id = p_unit_id;
  END IF;

  RETURN result_data;
END
$function$;

REVOKE ALL ON FUNCTION public.get_available_occasions(bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_available_occasions(bigint,bigint)
  TO anon,authenticated,service_role;

COMMENT ON FUNCTION public.get_available_occasions(bigint,bigint) IS
  'Slunovrat legacy compatibility RPC; canonical backend additionally merges registered external sources.';
