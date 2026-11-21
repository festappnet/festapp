-- Reconcile legacy form UUIDs before switching catalog readers to orders.form.
-- A UUID has to identify one form within the order's saved occasion.
DO $$
DECLARE
 legacy_missing bigint;
 conflicts bigint;
 repaired bigint;
BEGIN
 SELECT audit.legacy_missing,audit.conflicts INTO legacy_missing,conflicts
 FROM (
 -- BEGIN FORM CATALOG PREFLIGHT
 WITH form_keys AS (
  SELECT occasion,key,min(id) AS form_id,count(*) AS matches
  FROM public.forms GROUP BY occasion,key
 ), links AS (
  SELECT o.form,f.form_id AS matched_form,f.matches
  FROM eshop.orders o
  LEFT JOIN form_keys f ON f.occasion=o.occasion AND f.key=CASE
   WHEN o.data->>'form' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   THEN (o.data->>'form')::uuid END
  WHERE o.data->>'form' IS NOT NULL
 )
 SELECT count(*) FILTER(WHERE form IS NULL AND matches=1) AS legacy_missing,
  count(*) FILTER(WHERE matches IS DISTINCT FROM 1::bigint
   OR (form IS NOT NULL AND form IS DISTINCT FROM matched_form)) AS conflicts
 FROM links
 -- END FORM CATALOG PREFLIGHT
 ) audit;

 IF conflicts<>0 THEN
  RAISE EXCEPTION 'Form catalog migration requires reconciliation of % order/form conflicts',conflicts;
 END IF;

 WITH unique_form_keys AS (
  SELECT occasion,key,min(id) AS form_id FROM public.forms GROUP BY occasion,key HAVING count(*)=1
 )
 UPDATE eshop.orders o SET form=f.form_id
 FROM unique_form_keys f
 WHERE o.form IS NULL AND o.occasion=f.occasion AND f.key=CASE
  WHEN o.data->>'form' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  THEN (o.data->>'form')::uuid END;
 GET DIAGNOSTICS repaired=ROW_COUNT;
 IF repaired<>legacy_missing THEN
  RAISE EXCEPTION 'Form associations changed during reconciliation (expected %, repaired %)',legacy_missing,repaired;
 END IF;
 RAISE NOTICE 'Form catalog associations repaired: %, unresolved conflicts: %',repaired,conflicts;
END $$;

-- SOURCE: eshop_waitlist/form_capacity.sql
CREATE OR REPLACE FUNCTION public.get_form_capacity_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH counts AS (
 SELECT f.*, (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted' AND o.state IS DISTINCT FROM 'storno') occupied,
 (SELECT count(*) FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.form_id=f.id AND s.outcome='pending' AND w.expires_at>p_at) reserved,
 (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND o.state='waitlisted' AND public.get_effective_waitlist_ticket_lifecycle_internal(t.id)='waiting') waiting
 FROM public.forms f WHERE f.id=p_form), free AS (
 SELECT *,greatest(participant_capacity-occupied-reserved,0) available FROM counts)
 SELECT jsonb_build_object('enabled',participant_capacity IS NOT NULL,'limit',participant_capacity,
 'remainingPublic',CASE WHEN participant_capacity IS NOT NULL THEN greatest(available-waiting,0) END,
 'showRemaining',show_remaining_capacity,'occupiedPeople',occupied,'offeredPlaces',reserved,'waitingPeople',waiting,
 'offerablePlaces',available,'heldForWaiting',least(available,waiting),'revision',capacity_revision,
 'canSendOffers',waitlist_enabled AND available>0,'blockedReason',CASE WHEN NOT waitlist_enabled THEN 'WAITLIST_NOT_AVAILABLE'
 WHEN available=0 THEN 'FORM_CAPACITY_EXCEEDED' END,'serverTime',p_at) FROM free;
$$;
CREATE OR REPLACE FUNCTION public.get_form_registration_mode_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 IF NOT (public.get_form_availability_snapshot_internal(p_form,p_at)->>'isWindowOpen')::boolean THEN RETURN 'closed'; END IF;
 IF f.blueprint IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
 ) THEN RETURN 'blueprint'; END IF;
 -- The availability window and blueprint have already been checked. Unlimited
 -- forms have no capacity threshold, so they do not need another inventory read.
 IF f.participant_capacity IS NULL THEN RETURN 'regular'; END IF;
 c:=public.get_form_capacity_snapshot_internal(p_form,p_at);
 IF (c->>'remainingPublic')::bigint>0 THEN RETURN 'regular'; END IF;
 RETURN CASE WHEN f.waitlist_enabled THEN 'waitlist' ELSE 'full' END;
END $$;
CREATE OR REPLACE FUNCTION public.check_form_capacity_settings_internal(p_form bigint,p_input jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; n integer; enabled boolean; bp bigint;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 c:=public.get_form_capacity_snapshot_internal(p_form);
 n:=CASE WHEN p_input ? 'participant_capacity' THEN (p_input->>'participant_capacity')::integer ELSE f.participant_capacity END;
 enabled:=CASE WHEN p_input ? 'waitlist_enabled' THEN (p_input->>'waitlist_enabled')::boolean ELSE f.waitlist_enabled END;
 bp:=CASE WHEN p_input ? 'blueprint' THEN nullif(p_input->>'blueprint','')::bigint ELSE f.blueprint END;
 -- Switching or disabling a selector cannot abandon sold places or live holds.
 IF bp IS DISTINCT FROM f.blueprint AND f.blueprint IS NOT NULL AND (
   EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
     JOIN eshop.orders o ON o.id=x."order" WHERE o.form=f.id AND s.blueprint=f.blueprint)
   OR EXISTS(SELECT 1 FROM eshop.spots WHERE blueprint=f.blueprint AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp())) THEN
   RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
 -- A retained blueprint is inactive when the occasion feature is disabled.
 IF NOT EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN bp:=NULL; END IF;
 IF n IS NOT NULL AND n<(c->>'occupiedPeople')::bigint+(c->>'offeredPlaces')::bigint+coalesce((c->>'heldForWaiting')::bigint,0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','CAPACITY_BELOW_COMMITTED','capacity',c)::text; END IF;
 IF ((NOT enabled) OR n IS NULL OR bp IS NOT NULL) AND
 ((c->>'waitingPeople')::bigint>0 OR (c->>'offeredPlaces')::bigint>0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','WAITLIST_HAS_ACTIVE_ENTRIES','capacity',c)::text; END IF;
 IF bp IS NOT NULL AND (n IS NOT NULL OR enabled) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','BLUEPRINT_CONFLICT')::text; END IF;
END $$;
REVOKE ALL ON FUNCTION public.get_form_capacity_snapshot_internal(bigint,timestamptz),
 public.get_form_registration_mode_internal(bigint,timestamptz),public.check_form_capacity_settings_internal(bigint,jsonb)
 FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_orders/order_catalog_counts.sql
-- Catalog counts cover all created orders in the authorized scope, including
-- stock and waitlist. The occasion sales report has its own sales population.
-- A NULL form list selects occasion totals. A non-NULL list selects form totals.
CREATE OR REPLACE FUNCTION public.get_order_catalog_counts_internal(p_occasions bigint[],p_forms bigint[])
RETURNS TABLE(occasion_id bigint,form_id bigint,total bigint,storno bigint,paid_or_sent bigint,ordered bigint,used bigint)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT o.occasion,CASE WHEN p_forms IS NOT NULL THEN f.id END,
  count(*),count(*) FILTER (WHERE o.state='storno'),
  count(*) FILTER (WHERE o.state IN ('paid','sent')),
  count(*) FILTER (WHERE o.state='ordered'),count(*) FILTER (WHERE o.state='used')
 FROM eshop.orders o
 LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion AND p_forms IS NOT NULL
 WHERE o.occasion=ANY(p_occasions) AND (p_forms IS NULL OR f.id=ANY(p_forms))
 GROUP BY 1,2;
$$;
REVOKE ALL ON FUNCTION public.get_order_catalog_counts_internal(bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/get_forms_by_link.sql
CREATE OR REPLACE FUNCTION public.get_forms_by_link(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    forms_data JSONB;
BEGIN
    -- Step 1: Resolve the occasion ID from the provided link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link)
      AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());

    -- Step 2: If no occasion is found, throw a 'no_data_found' exception.
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion not found for link: %', occasion_link USING ERRCODE = 'PGRST001'; -- Custom error for PostgREST
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- If not, throw an 'insufficient_privilege' exception.
    IF NOT public.can_read_form_catalog(v_occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to view forms for this occasion.' USING ERRCODE = '42501'; -- insufficient_privilege
    END IF;

    -- Step 4: Aggregate forms for the occasion into a JSONB array.
    -- The order statistics are nested within a 'stats' JSON object.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
            'created_at', f.created_at,
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'updated_at', f.updated_at,
            'stats', jsonb_build_object(
                'total', COALESCE(order_stats.total, 0),
                'storno', COALESCE(order_stats.storno, 0),
                'paid_or_sent', COALESCE(order_stats.paid_or_sent, 0),
                'ordered', COALESCE(order_stats.ordered, 0)
            )
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    LEFT JOIN public.get_order_catalog_counts_internal(
      ARRAY[v_occasion_id], ARRAY(SELECT id FROM public.forms WHERE occasion=v_occasion_id)
    ) AS order_stats ON f.id=order_stats.form_id
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found, ensure an empty JSON array is returned.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the data directly.
    RETURN forms_data;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_forms_by_link(occasion_link text, form_link text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE forms jsonb; target bigint;
BEGIN
 forms := public.get_forms_by_link(occasion_link);
 target := public.resolve_form_link_internal(form_link);
 RETURN (SELECT coalesce(jsonb_agg(f || CASE WHEN (f->>'id')::bigint=target
   THEN jsonb_build_object('requested_link',form_link) ELSE '{}'::jsonb END),'[]')
   FROM jsonb_array_elements(forms) f);
END $$;
REVOKE ALL ON FUNCTION public.get_forms_by_link(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_forms_by_link(text,text) TO authenticated;

-- SOURCE: eshop_forms/get_all_viewable_forms_for_copying.sql
CREATE OR REPLACE FUNCTION public.get_all_viewable_forms_for_copying()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    forms_data JSONB;
    user_id UUID := auth.uid();
BEGIN
    -- Step 1: Aggregate forms into a JSONB array based on the user's combined permissions.
    -- The user can see forms from occasions where they are a direct editor,
    -- or from any occasion within a unit where they are a unit editor.
    WITH visible_occasions AS MATERIALIZED (
        SELECT ou.occasion
        FROM public.occasion_users ou
        WHERE ou.user = user_id AND ou.is_editor_view = TRUE
        UNION
        SELECT o.id
        FROM public.occasions o
        JOIN public.unit_users uu ON o.unit=uu.unit
        WHERE uu.user = user_id AND uu.is_editor_view = TRUE
    ), visible_forms AS MATERIALIZED (
        SELECT f.* FROM public.forms f JOIN visible_occasions v ON v.occasion=f.occasion
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,
            'created_at', f.created_at,
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', jsonb_build_object(
                'id', o.id,
                'title', o.title,
                'link', o.link,
                'start_time', o.start_time,
                'end_time', o.end_time
            ),
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'updated_at', f.updated_at,
            'stats', jsonb_build_object(
                'total', COALESCE(order_stats.total, 0),
                'storno', COALESCE(order_stats.storno, 0),
                'paid_or_sent', COALESCE(order_stats.paid_or_sent, 0),
                'ordered', COALESCE(order_stats.ordered, 0)
            )
        ) ORDER BY o.start_time DESC, f.created_at DESC
    )
    INTO forms_data
    FROM visible_forms f
    JOIN public.occasions o ON f.occasion=o.id
    LEFT JOIN public.get_order_catalog_counts_internal(
        ARRAY(SELECT occasion FROM visible_occasions),ARRAY(SELECT id FROM visible_forms)
    ) AS order_stats ON f.id=order_stats.form_id;

    -- Step 2: If no forms are found, return an empty JSON array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 3: Return the aggregated data.
    RETURN forms_data;
END;
$$;

-- SOURCE: eshop_forms/legacy_form_catalog.sql
CREATE OR REPLACE FUNCTION public.get_all_forms(occasion_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id BIGINT;
    forms_data JSONB;
BEGIN
    -- Step 1: Resolve the occasion ID from the provided link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Step 2: If no occasion is found, return a 404 error.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion not found'
        );
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- This assumes a function `get_is_editor_on_occasion` exists.
    IF NOT get_is_editor_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view forms for this occasion.'
        );
    END IF;

    -- Step 4: Aggregate forms for the occasion into a JSONB array.
    -- The subquery for 'response_count' is now corrected to count responses from the 'eshop.orders' table.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,
            'created_at', f.created_at,
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'updated_at', f.updated_at,
            'response_count',COALESCE(order_stats.total,0)
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    LEFT JOIN public.get_order_catalog_counts_internal(
      ARRAY[v_occasion_id], ARRAY(SELECT id FROM public.forms WHERE occasion=v_occasion_id)
    ) AS order_stats ON f.id=order_stats.form_id
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found, return an empty array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the aggregated JSON response with a 200 code.
    RETURN jsonb_build_object(
        'code', 200,
        'data', forms_data
    );
END;
$function$;

-- SOURCE: others/legacy_occasion_catalogs.sql
-- External catalogue versions retain their distinct original payloads.
-- Their unit-only admission has one typed owner, separate from V212.

CREATE OR REPLACE FUNCTION public.get_all_occasions_for_edit(unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  occasion_data jsonb;
BEGIN
  -- Step 1: Verify that the unit exists
  IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = unit_id) THEN
    RETURN jsonb_build_object(
      'code', 404,
      'message', 'Unit not found'
    );
  END IF;

  -- Step 2: Check if the caller is a manager or editor of the unit
  IF NOT public.can_read_legacy_unit_occasion_catalog(unit_id) THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Step 3: Aggregate occasions for the unit including the first form for each occasion.
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'title', o.title,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'data', o.data,
      'description', o.description,
      'is_hidden', o.is_hidden,
      'is_open', o.is_open,
      'start_time', o.start_time,
      'end_time', o.end_time,
      'link', o.link,
      'organization', o.organization,
      'services', o.services,
      'unit', o.unit,
      'features', o.features,
      'form', (
         SELECT jsonb_build_object(
           'id', f.id,
           'created_at', f.created_at,
           'data', f.data,
           'key', f.key,
           'occasion', f.occasion,
           'type', f.type,
           'is_open', f.is_open,
           'link', f.link,
           'blueprint', f.blueprint,
           'header', f.header,
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
  FROM public.occasions o
  WHERE o.unit = unit_id;

  -- Step 4: If no occasions were found, return an empty array.
  IF occasion_data IS NULL THEN
    occasion_data := '[]'::jsonb;
  END IF;

  -- Step 5: Return the aggregated JSON response with a 200 code.
  RETURN jsonb_build_object(
    'code', 200,
    'data', occasion_data
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_all_occasions_for_edit_v182(unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  occasion_data jsonb;
BEGIN
  -- Step 1: Verify that the unit exists. If not, raise a 'not found' exception.
  IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = unit_id) THEN
    RAISE EXCEPTION 'Unit not found' USING ERRCODE = 'PGRST001';
  END IF;

  -- Step 2: Check if the caller has sufficient permissions. If not, raise an 'insufficient privilege' exception.
  IF NOT public.can_read_legacy_unit_occasion_catalog(unit_id) THEN
    RAISE EXCEPTION 'Insufficient permissions for this unit' USING ERRCODE = '42501';
  END IF;

  -- Step 3: Aggregate occasions for the unit, including forms, order stats, and user data.
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'title', o.title,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'data', o.data,
      'is_hidden', o.is_hidden,
      'is_open', o.is_open,
      'start_time', o.start_time,
      'end_time', o.end_time,
      'link', o.link,
      'organization', o.organization,
      'services', o.services,
      'unit', o.unit,
      'features', o.features,
      'stats', jsonb_build_object(
          'total', COALESCE(order_stats.total, 0),
          'storno', COALESCE(order_stats.storno, 0),
          'paid_or_sent', COALESCE(order_stats.paid_or_sent, 0),
          'ordered', COALESCE(order_stats.ordered, 0),
          'used', COALESCE(order_stats.used, 0),
          'users', COALESCE(user_stats.user_count, 0)
      ),
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
           'blueprint', f.blueprint,
           'header', f.header,
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
  FROM public.occasions o
  LEFT JOIN public.get_order_catalog_counts_internal(
    ARRAY(SELECT id FROM public.occasions WHERE unit=unit_id),NULL
  ) AS order_stats ON o.id=order_stats.occasion_id
  LEFT JOIN (
      SELECT ou.occasion,COUNT(*) as user_count
      FROM public.occasion_users ou
      JOIN public.occasions scoped ON scoped.id=ou.occasion AND scoped.unit=unit_id
      GROUP BY ou.occasion
  ) AS user_stats ON o.id=user_stats.occasion
  WHERE o.unit = unit_id;

  -- Step 4: If no occasions were found, return an empty JSON array.
  IF occasion_data IS NULL THEN
    occasion_data := '[]'::jsonb;
  END IF;

  -- Step 5: Return the aggregated JSON data directly.
  RETURN occasion_data;
END;
$function$
;
REVOKE ALL ON FUNCTION public.get_all_occasions_for_edit(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_all_occasions_for_edit(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_all_occasions_for_edit_v182(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_all_occasions_for_edit_v182(bigint) TO anon,authenticated,service_role;

-- SOURCE: eshop_forms/admin_form_reads.sql
-- Deletion still checks every order reference, including legacy UUIDs.
CREATE OR REPLACE FUNCTION public.get_form_usage_rows_internal(p_forms bigint[])
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH selected AS MATERIALIZED (SELECT id,key FROM public.forms WHERE id=ANY(p_forms)), refs AS (
  SELECT q.form form_id,q.id order_id FROM eshop.orders q WHERE q.form=ANY(p_forms)
  UNION
  SELECT f.id,q.id FROM eshop.orders q JOIN selected f ON q.data->>'form'=f.key::text
 ), totals AS (
  SELECT form_id,count(*) blocking_orders FROM refs GROUP BY form_id
 )
 SELECT coalesce(jsonb_object_agg(f.id::text,jsonb_build_object('blocking_orders',coalesce(t.blocking_orders,0))),
  '{}') FROM selected f LEFT JOIN totals t ON t.form_id=f.id;
$$;
REVOKE ALL ON FUNCTION public.get_form_usage_rows_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_form_usage_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.get_form_usage_rows_internal(ARRAY[p_form])->p_form::text;
$$;
REVOKE ALL ON FUNCTION public.get_form_usage_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Private projection shared by current editor acknowledgements and MCP. Public
-- keys/links and bank-account details are not part of this authoring snapshot.
CREATE OR REPLACE FUNCTION public.get_form_authoring_snapshot_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('form',(bundle->'data'->'form')-ARRAY['key','link','organizationIdentity','created_at'],
  'fields',bundle->'data'->'form_fields','productTypes',bundle->'data'->'product_types','products',bundle->'data'->'products',
  'productVersions',(SELECT coalesce(jsonb_object_agg(p->>'id',p->'aggregate_version'),'{}') FROM jsonb_array_elements(bundle->'data'->'products') p),
  'productTypeVersions',(SELECT coalesce(jsonb_object_agg(p->>'id',p->'aggregate_version'),'{}') FROM jsonb_array_elements(bundle->'data'->'product_types') p))
 FROM (SELECT public.get_form_editor_bundle_internal(p_form,true) bundle) b WHERE (bundle->>'code')::int=200;
$$;
REVOKE ALL ON FUNCTION public.get_form_authoring_snapshot_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Apply the page before capacity/history/field work. Unbounded mode exists only
-- for the existing full administration list, using the identical row projection.
CREATE OR REPLACE FUNCTION public.get_form_catalog_rows_internal(p_occasion bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH selected AS MATERIALIZED (
  SELECT * FROM public.forms WHERE occasion=p_occasion AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT p_limit
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'data',f.data,'key',f.key,'link',f.link,
  'occasion',f.occasion,'type',f.type,'is_open',f.is_open,'blueprint',f.blueprint,
  'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
  'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
  'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
  'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions v WHERE v.aggregate_type='form' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=f.id::text),0),
  'response_count',coalesce(stats.total,0),
  'fields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',ff.id,'type',ff.type,'is_ticket_field',ff.is_ticket_field) ORDER BY coalesce(ff."order",0),ff.id),'[]') FROM public.form_fields ff WHERE ff.form=f.id)) ORDER BY f.id),'[]')
 FROM selected f LEFT JOIN public.get_order_catalog_counts_internal(
  ARRAY[p_occasion],ARRAY(SELECT id FROM selected)
 ) stats ON stats.form_id=f.id;
$$;
REVOKE ALL ON FUNCTION public.get_form_catalog_rows_internal(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_form_authoring_scope_internal(p_occasion bigint,p_organization bigint,p_unit bigint,p_operation text,p_lock boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE allowed boolean;
BEGIN
 IF p_lock THEN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
 ELSE
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization
   WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit);
 END IF;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='form hierarchy unavailable'; END IF;
 allowed:=CASE p_operation WHEN 'list' THEN public.can_read_form_catalog(p_occasion)
  WHEN 'inspect' THEN public.can_read_form_catalog(p_occasion)
  WHEN 'source' THEN public.can_copy_form_source(p_occasion)
  WHEN 'duplicate' THEN public.can_copy_form_target(p_occasion)
  WHEN 'create' THEN public.can_author_forms(p_occasion)
  WHEN 'save' THEN public.can_author_forms(p_occasion)
  WHEN 'delete' THEN public.can_author_forms(p_occasion) ELSE false END;
 IF allowed IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='form operation denied'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_form_authoring_scope_internal(bigint,bigint,bigint,text,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_form_catalog_page(p_occasion bigint,p_organization bigint,p_unit bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; last_id bigint; next_id bigint; result jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR (p_after IS NOT NULL AND p_after<1) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form page'; END IF;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,'list',true);
 rows:=public.get_form_catalog_rows_internal(p_occasion,p_after,p_limit);
 SELECT max((r->>'id')::bigint) INTO last_id FROM jsonb_array_elements(rows) r;
 IF EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion AND id>last_id) THEN next_id:=last_id; END IF;
 SELECT coalesce(jsonb_agg(r-ARRAY['key','link','data'] ORDER BY (r->>'id')::bigint),'[]') INTO rows FROM jsonb_array_elements(rows) r;
 result:=jsonb_build_object('occasionId',p_occasion,'forms',rows,'nextCursor',next_id);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='form page too large'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_catalog_page(bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_catalog_page(bigint,bigint,bigint,bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_form_for_authoring(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,'inspect',true);
 IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
 result:=public.get_form_authoring_snapshot_internal(p_form);
 IF octet_length(result::text)>1048576 OR jsonb_array_length(result->'fields')>500 THEN RAISE program_limit_exceeded USING MESSAGE='form snapshot too large'; END IF;
 RETURN jsonb_build_object('occasionId',p_occasion,'authoring',result);
END $$;
REVOKE ALL ON FUNCTION public.get_form_for_authoring(bigint,bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_for_authoring(bigint,bigint,bigint,bigint) TO authenticated;

-- Explicit link intent, never part of generic authoring or customer DTOs.
CREATE OR REPLACE FUNCTION public.get_form_public_link(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,'save');
 SELECT jsonb_build_object('occasionId',p_occasion,'formId',id,'slug',link) INTO result
 FROM public.forms WHERE id=p_form AND occasion=p_occasion;
 IF result IS NULL THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_public_link(bigint,bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_public_link(bigint,bigint,bigint,bigint) TO authenticated;
