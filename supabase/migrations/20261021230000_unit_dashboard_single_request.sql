-- One unit-context read and scoped catalogue aggregates.
BEGIN;

-- Source: database/functions/others/get_all_occasions_for_edit.sql
CREATE OR REPLACE FUNCTION public.get_all_occasions_for_edit_v212(unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  occasion_data jsonb;
  org_id bigint;
  unit_catalog_reader boolean;
BEGIN
  -- Step 1: Verify that the unit exists and retrieve its Organization ID.
  SELECT organization INTO org_id
  FROM public.units
  WHERE id = unit_id;

  -- If org_id is null, the unit does not exist.
  IF org_id IS NULL THEN
    RAISE EXCEPTION 'Unit not found' USING ERRCODE = 'PGRST001';
  END IF;

  -- Step 2: Check permissions
  IF NOT public.can_read_unit_occasion_catalog(unit_id) THEN
    RAISE EXCEPTION 'Insufficient permissions for this unit' USING ERRCODE = '42501';
  END IF;

  -- One actor/unit fact for the whole catalogue, not a permission query
  -- repeated for each occasion. Occasion membership remains row scoped.
  SELECT coalesce((SELECT public.unit_discovery_rule(m.is_editor,m.is_manager,m.is_editor_view)
    FROM public.unit_users m WHERE m.unit=unit_id AND m."user"=auth.uid()),false)
    INTO unit_catalog_reader;

  -- Scope all aggregate work before counting tickets/users in other units.
  WITH visible_occasions AS MATERIALIZED (
    SELECT o.* FROM public.occasions o
    WHERE o.unit = unit_id AND (unit_catalog_reader OR EXISTS (
      SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=o.id
        AND ou."user"=auth.uid()
        AND public.occasion_staff_navigation_rule(ou.is_manager,ou.is_editor,
          ou.is_editor_view,ou.is_editor_order,ou.is_editor_order_view)))
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'title', o.title,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'data', o.data #- '{heavy_field}', -- OPTIMIZATION: Remove heavy_field
      'is_hidden', o.is_hidden,
      'is_open', o.is_open,
      'start_time', o.start_time,
      'end_time', o.end_time,
      'link', o.link,
      'organization', o.organization,
      'services', o.services,
      'unit', o.unit,
      'features', (
          SELECT jsonb_agg(
              jsonb_build_object('code',elem->'code','is_enabled',elem->'is_enabled')
          )
          FROM jsonb_array_elements(o.features) elem
      ),
      'stats', jsonb_build_object(
          'total', COALESCE(ticket_stats.total, 0),
          'storno', COALESCE(ticket_stats.storno, 0),
          'paid_or_sent', COALESCE(ticket_stats.paid_or_sent, 0),
          'ordered', COALESCE(ticket_stats.ordered, 0),
          'used', COALESCE(ticket_stats.used, 0),
          'users', COALESCE(user_stats.user_count, 0)
      ),
      'sale_forms', public.get_occasion_sale_forms_internal(o.id),
      'form', (
         -- This subquery fetches the first associated form for the occasion.
         SELECT jsonb_build_object(
           'id', f.id,
           'created_at', f.created_at,
           'data', f.data,
           'key', f.key,
           'occasion', f.occasion,
           'type', f.type,
           'is_open', f.is_open,
           'link', f.link,
           'blueprint', NULL, -- OPTIMIZATION: Remove blueprint
           'header', NULL, -- OPTIMIZATION: Remove header
           'header_off', f.header_off,
           'updated_at', f.updated_at
         )
         FROM public.forms f
         WHERE f.occasion = o.id
         ORDER BY f.id
         LIMIT 1
      )
    )
    ORDER BY o.start_time DESC
  )
  INTO occasion_data
  FROM visible_occasions o

  -- Ticket Stats
  LEFT JOIN (
      SELECT
          occasion,
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE state = 'storno') AS storno,
          COUNT(*) FILTER (WHERE state IN ('paid', 'sent')) AS paid_or_sent,
          COUNT(*) FILTER (WHERE state = 'ordered') AS ordered,
          COUNT(*) FILTER (WHERE state = 'used') AS used
      FROM eshop.tickets
      WHERE occasion IN (SELECT id FROM visible_occasions)
      GROUP BY occasion
  ) AS ticket_stats ON o.id = ticket_stats.occasion

  -- User Stats
  LEFT JOIN (
      SELECT
          ou.occasion,
          COUNT(*) as user_count
      FROM public.occasion_users ou
      LEFT JOIN public.organization_users org_u
          ON ou."user" = org_u."user"
          AND org_u.organization = org_id
      WHERE ou.occasion IN (SELECT id FROM visible_occasions)
        AND (org_u.is_hidden IS NOT TRUE)
      GROUP BY ou.occasion
  ) AS user_stats ON o.id = user_stats.occasion
;

  IF occasion_data IS NULL THEN
    occasion_data := '[]'::jsonb;
  END IF;

  RETURN occasion_data;
END;
$function$
;

-- Source: database/functions/units/occasion_dashboard.sql
-- The unit context and refresh read share this single authorized projection.
CREATE OR REPLACE FUNCTION public.get_unit_occasion_dashboard_internal(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_org bigint; v_drafts jsonb := '[]'; v_landing jsonb := NULL;
 v_demos jsonb := '{"hasOwnWork":false,"items":[]}';
BEGIN
 IF NOT public.can_read_unit_occasion_catalog(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Unit dashboard access denied';
 END IF;
 SELECT organization INTO v_org FROM public.units WHERE id=p_unit;
 IF public.can_create_occasion(p_unit) THEN
  v_drafts := public.get_occasion_setup_drafts(p_unit);
 END IF;
 IF public.can_read_unit_app_landing(p_unit) THEN
  v_landing := public.get_unit_app_landing(p_unit);
 END IF;
 IF EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=v_org) THEN
  v_demos := public.get_demo_occasions(v_org);
 END IF;
 RETURN jsonb_build_object('unit_id',p_unit,
  'occasions',public.get_all_occasions_for_edit_v212(p_unit),
  'drafts',v_drafts,'app_landing',v_landing,'demo_catalog',v_demos);
END $$;
REVOKE ALL ON FUNCTION public.get_unit_occasion_dashboard_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/units/get_unit_edit_data.sql
CREATE OR REPLACE FUNCTION get_unit_edit_data(p_unit_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_unit_data jsonb;
BEGIN
    -- 1. Call get_unit_for_edit to get the unit details
    SELECT get_unit_for_edit(p_unit_id) INTO v_unit_data;

    -- Check if get_unit_for_edit returned an error (code != 200)
    IF (v_unit_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_unit_for_edit failed: %', v_unit_data->>'message';
    END IF;

    RETURN public.get_unit_occasion_dashboard_internal(p_unit_id) ||
        jsonb_build_object('unit',v_unit_data->'data');
END;
$$;

REVOKE ALL ON FUNCTION public.get_unit_edit_data(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_edit_data(bigint) TO authenticated;

-- Source: database/functions/others/get_app_config_v219.sql
-- Transition-only capability bootstrap. v217/v218 remain unchanged for
-- released clients; a context selects legacy or client_sync_v1 exactly once.
CREATE OR REPLACE FUNCTION public.get_app_config_v219(data_in jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
  v_occasion bigint;
  v_enabled boolean := false;
BEGIN
  v_result := public.get_app_config_v218(data_in);
  v_occasion := (v_result#>>'{occasion,id}')::bigint;
  IF v_occasion IS NOT NULL THEN
    SELECT COALESCE((o.data->>'client_sync_v1')::boolean, false)
      AND NOT EXISTS (
        SELECT 1 FROM public.client_sync_component_sources s
        WHERE s.registry_version=(SELECT max(v.registry_version)
          FROM public.client_sync_component_sources v)
          AND NOT s.cutover_ready)
      INTO v_enabled
    FROM public.occasions o
    WHERE o.id = v_occasion;
  END IF;
  -- A direct unit route receives its catalogue and screen metadata in the
  -- existing context request. Occasion/public contexts keep their old payload.
  IF (v_result->>'code')::integer=200 AND data_in->>'unit_id' IS NOT NULL
     AND public.can_read_unit_occasion_catalog((data_in->>'unit_id')::bigint) THEN
    v_result := v_result || jsonb_build_object('unit_dashboard',
      public.get_unit_occasion_dashboard_internal((data_in->>'unit_id')::bigint));
  END IF;
  RETURN v_result || jsonb_build_object('client_sync_v1', v_enabled);
END;
$$;

REVOKE ALL ON FUNCTION public.get_app_config_v219(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config_v219(jsonb)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
