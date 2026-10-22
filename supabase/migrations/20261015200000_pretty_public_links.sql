-- Generated from canonical database/functions sources listed below.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.occasions,public.forms IN SHARE ROW EXCLUSIVE MODE;
DO $$ DECLARE conflicts text; BEGIN
 SELECT string_agg(ids, '; ') INTO conflicts FROM (
  SELECT 'occasion IDs: '||string_agg(id::text,',') ids FROM public.occasions
   WHERE link IS NOT NULL AND link<>'' GROUP BY organization,link HAVING count(*)>1
  UNION ALL SELECT 'form IDs: '||string_agg(id::text,',') FROM public.forms
   WHERE link IS NOT NULL AND link<>'' GROUP BY link HAVING count(*)>1) duplicates;
 IF conflicts IS NOT NULL THEN RAISE EXCEPTION 'Conflicting public links: %',conflicts; END IF;
 RAISE NOTICE 'Empty occasion IDs: %, empty form IDs: %',
  (SELECT array_agg(id) FROM public.occasions WHERE coalesce(link,'')=''),
  (SELECT array_agg(id) FROM public.forms WHERE coalesce(link,'')='');
END $$;

-- Source: database/functions/public_links/registry.sql
-- Stable identity reservations survive deletion as tombstones. No application triggers.
CREATE TABLE IF NOT EXISTS public.occasion_link_reservations (
 slug text PRIMARY KEY, occasion bigint REFERENCES public.occasions(id) ON DELETE SET NULL
);
CREATE TABLE IF NOT EXISTS public.form_link_reservations (
 slug text PRIMARY KEY, form bigint REFERENCES public.forms(id) ON DELETE SET NULL
);
-- Frozen bindings for pre-existing cross-tenant duplicates. Their slug remains
-- globally blocked in occasion_link_reservations; new writers never add bindings.
CREATE TABLE IF NOT EXISTS public.legacy_occasion_link_bindings (
 slug text NOT NULL REFERENCES public.occasion_link_reservations(slug),
 organization bigint NOT NULL REFERENCES public.organizations(id),
 occasion bigint REFERENCES public.occasions(id) ON DELETE SET NULL,
 PRIMARY KEY(slug,organization)
);
ALTER TABLE public.legacy_occasion_link_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.legacy_occasion_link_bindings FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.occasion_link_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.form_link_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_link_reservations, public.form_link_reservations FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.resolve_occasion_link_internal(p_slug text,p_organization bigint)
RETURNS bigint LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT coalesce(r.occasion,b.occasion)
 FROM public.occasion_link_reservations r
 LEFT JOIN public.legacy_occasion_link_bindings b
   ON b.slug=r.slug AND b.organization=p_organization
 WHERE r.slug=p_slug;
$$;
CREATE OR REPLACE FUNCTION public.resolve_occasion_link_internal(p_slug text)
RETURNS bigint LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT public.resolve_occasion_link_internal(p_slug,
   (SELECT organization FROM public.user_info WHERE id=auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.resolve_occasion_link_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.resolve_form_link_internal(p_slug text)
RETURNS bigint LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT form FROM public.form_link_reservations WHERE slug=p_slug;
$$;

CREATE OR REPLACE FUNCTION public.random_public_link_internal()
RETURNS text LANGUAGE plpgsql VOLATILE SET search_path = public, extensions AS $$
DECLARE alphabet constant text := '23456789abcdefghjkmnpqrstuvwxyz'; result text := ''; b integer;
BEGIN
 -- Rejection sampling avoids modulo bias (31 symbols).
 WHILE length(result)<8 LOOP
  b := get_byte(extensions.gen_random_bytes(1),0);
  IF b < 248 THEN result := result || substr(alphabet,b % 31 + 1,1); END IF;
 END LOOP;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.occasion_reserved_public_paths_internal()
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
 SELECT ARRAY['resetPassword','forgotPassword','reset-password','forgot-password','login','signup','settings','install','unit','admin','form','scan','transfer','app','privacy','terms','support','delete-account','google-auth','assets','icons','flutter','index.html','flutter.html','favicon.ico','manifest.json','robots.txt','version.json','backend-activation.json'];
$$;

CREATE OR REPLACE FUNCTION public.reserve_public_link_internal(p_kind text,p_id bigint,p_slug text,p_create boolean DEFAULT false)
RETURNS text LANGUAGE plpgsql VOLATILE SET search_path = public, extensions AS $$
DECLARE current_slug text; candidate text; owner_id bigint; attempt integer; automatic boolean;
BEGIN
 IF p_kind='occasion' THEN
  SELECT link INTO current_slug FROM public.occasions WHERE id=p_id FOR UPDATE;
 ELSIF p_kind='form' THEN
  SELECT link INTO current_slug FROM public.forms WHERE id=p_id FOR UPDATE;
 ELSE RAISE invalid_parameter_value USING MESSAGE='Invalid public link kind'; END IF;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='Public link target missing'; END IF;
 automatic := p_create AND coalesce(p_slug,'')='';
 IF NOT p_create AND p_slug IS NULL THEN RETURN current_slug; END IF;
 -- Exact legacy no-op before new syntax validation.
 IF NOT p_create AND p_slug=current_slug THEN RETURN current_slug; END IF;
 IF NOT automatic AND (p_slug IS NULL OR length(p_slug)>80 OR p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid public link';
 END IF;
 FOR attempt IN 1..20 LOOP
  candidate := CASE WHEN automatic THEN public.random_public_link_internal() ELSE p_slug END;
  IF p_kind='occasion' AND candidate=ANY(public.occasion_reserved_public_paths_internal()) THEN
   RAISE invalid_parameter_value USING MESSAGE='Reserved public link'; END IF;
  -- Unique insert serializes contenders, including historical reservations.
  IF p_kind='occasion' THEN
   INSERT INTO public.occasion_link_reservations(slug,occasion) VALUES(candidate,p_id) ON CONFLICT DO NOTHING;
   SELECT occasion INTO owner_id FROM public.occasion_link_reservations WHERE slug=candidate;
   -- Only an original owner may return to its own grandfathered alias.
   IF owner_id IS NULL AND EXISTS(SELECT 1 FROM public.legacy_occasion_link_bindings
     WHERE slug=candidate AND occasion=p_id) THEN owner_id:=p_id; END IF;
  ELSE
   INSERT INTO public.form_link_reservations(slug,form) VALUES(candidate,p_id) ON CONFLICT DO NOTHING;
   SELECT form INTO owner_id FROM public.form_link_reservations WHERE slug=candidate;
  END IF;
  IF owner_id=p_id THEN
   RETURN candidate;
  END IF;
  IF NOT automatic THEN RAISE unique_violation USING MESSAGE='Public link is already in use'; END IF;
 END LOOP;
 RAISE unique_violation USING MESSAGE='Public link allocation exhausted';
END $$;
REVOKE ALL ON FUNCTION public.resolve_occasion_link_internal(text), public.resolve_form_link_internal(text),
 public.random_public_link_internal(), public.occasion_reserved_public_paths_internal(),
 public.reserve_public_link_internal(text,bigint,text,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- All domain writers are definer RPCs. RLS alone cannot reserve a URL.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON public.forms,public.occasions FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/public_links/backfill.sql
-- One-time adoption of exact stored URLs; never changes canonical links/titles.
INSERT INTO public.occasion_link_reservations(slug,occasion)
 SELECT link,CASE WHEN count(*)=1 THEN min(id) END FROM public.occasions
 WHERE link IS NOT NULL AND link<>'' GROUP BY link;
INSERT INTO public.legacy_occasion_link_bindings(slug,organization,occasion)
 SELECT o.link,o.organization,o.id FROM public.occasions o
 JOIN public.occasion_link_reservations r ON r.slug=o.link
 WHERE r.occasion IS NULL;
INSERT INTO public.form_link_reservations(slug,form)
 SELECT link,id FROM public.forms WHERE link IS NOT NULL AND link<>'';


-- Source: database/functions/public_links/copy_title.sql
CREATE OR REPLACE FUNCTION public.copy_occasion_title_internal(p_title text,p_locale text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE suffix text; base text := coalesce(p_title,'');
BEGIN
 suffix := CASE split_part(replace(lower(coalesce(p_locale,'en')),'_','-'),'-',1)
  WHEN 'cs' THEN 'kopie' WHEN 'sk' THEN 'kópia' WHEN 'de' THEN 'kopie'
  WHEN 'pl' THEN 'kopia' WHEN 'uk' THEN 'копія' ELSE 'copy' END;
 base := regexp_replace(base, '(\s*\((copy|kopie|kópia|kopia|копія)\))+$', '', 'i');
 RETURN left(rtrim(base),500-length(suffix)-3) || ' (' || suffix || ')';
END $$;
REVOKE ALL ON FUNCTION public.copy_occasion_title_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop_forms/create_form_internal_v1.sql
CREATE OR REPLACE FUNCTION public.create_form_internal_v1(p_occasion_id bigint, p_link text, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    now TIMESTAMPTZ := NOW();
BEGIN
    PERFORM public.check_occasion_writable(p_occasion_id);
    IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion_id)
      OR public.get_is_editor_on_unit((SELECT unit FROM public.occasions WHERE id=p_occasion_id))) THEN
      RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
    -- Create the new form
    INSERT INTO public.forms(
        title,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        NULL,
        p_occasion_id,
        now,
        now,
        604800, -- Default to 7 days
        '{"is_reminder_enabled": true}'::jsonb -- Default reminder setting
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,p_link,true) WHERE id=new_form_id;
    SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Ensure 'spot' product type exists for the occasion
    IF NOT EXISTS (SELECT 1 FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot') THEN
        INSERT INTO eshop.product_types(title, type, occasion)
        VALUES ('Spot', 'spot', p_occasion_id)
        RETURNING id INTO new_product_type_id;
    ELSE
        SELECT id INTO new_product_type_id FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot' LIMIT 1;
    END IF;

    -- Ensure the 'spot' product type has at least one product
    IF NOT EXISTS (SELECT 1 FROM eshop.products WHERE occasion = p_occasion_id AND product_type = new_product_type_id) THEN
        INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
        VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    -- Return the raw data of the newly created form
    RETURN new_form;
END;
$function$;
REVOKE ALL ON FUNCTION public.create_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop_forms/create_form_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_form_client_sync_v1(
  p_occasion_link text,p_link text,p_title text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_form jsonb;
BEGIN
  SELECT o.id,o.unit INTO v_occasion,v_unit FROM public.occasions o
    WHERE o.id=public.resolve_occasion_link_internal(p_occasion_link);
  IF v_actor IS NULL OR v_occasion IS NULL
    OR length(p_link)>80 OR length(COALESCE(p_title,''))>500
    OR NOT (public.get_is_editor_on_unit(v_unit)
      OR public.get_is_editor_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'link',p_link,'title',p_title)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.create',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_form:=public.create_form_internal_v1(v_occasion,p_link,p_title);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.create',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form->>'id','operation','insert',
      'safeLabel',left(p_title,240),'changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('form',v_form));
END; $$;
REVOKE ALL ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid) TO authenticated;


-- Source: database/functions/others/get_occasion_for_edit_v1.sql
-- Canonical merges can contain the same legacy occasion link in more than one
-- organization. Resolve the edit reader inside the authenticated user's tenant
-- before checking occasion-level permissions.
CREATE OR REPLACE FUNCTION public.get_occasion_for_edit_v1(p_link text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_occasion bigint;
  v_result jsonb;
BEGIN
  SELECT o.id
  INTO v_occasion
  FROM public.occasions o
  WHERE o.id = public.resolve_occasion_link_internal(p_link)
    AND o.organization = (
      SELECT ui.organization
      FROM public.user_info ui
      WHERE ui.id = auth.uid()
    );

  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE = 'occasion not found';
  END IF;

  IF NOT (
    public.get_is_editor_view_on_occasion(v_occasion)
    OR public.get_is_manager_on_occasion(v_occasion)
    OR public.get_is_admin_on_occasion(v_occasion)
  ) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor view required';
  END IF;

  SELECT to_jsonb(o) || jsonb_build_object(
    'aggregate_version', COALESCE(v.version, 0)
  )
  INTO v_result
  FROM public.occasions o
  LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type = 'occasion'
    AND v.scope_type = 'occasion'
    AND v.scope_id = o.id
    AND v.aggregate_id = o.id::text
  WHERE o.id = v_occasion;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_occasion_for_edit_v1(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_for_edit_v1(text) TO authenticated;


-- Source: database/functions/eshop_forms/update_form.sql
CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic
        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Ensure user is authorized to edit this occasion
        IF NOT COALESCE(get_is_editor_order_on_occasion(occasion_id), false) THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 403, 'message', 'User is not authorized to edit this occasion')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT (public.get_is_editor_on_unit(occasion_unit) OR public.get_is_editor_on_occasion(occasion_id)) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        form_id := NULLIF(input_data->>'id','')::bigint;
        IF form_id IS NULL THEN
          INSERT INTO public.forms(created_at,occasion) VALUES(now_ts,occasion_id) RETURNING id INTO form_id;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',true);
        ELSE
          IF NOT EXISTS (SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN
            RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',false);
        END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
            WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                field_id := NULLIF(field_data->>'id', '')::BIGINT;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = field_data->'data',
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = field_product_type,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = input_data->>'title',
               data = input_data->'data',
               header = input_data->>'header',
               header_off = input_data->>'header_off',
               link = link_param,
               blueprint = NULLIF(input_data->>'blueprint','')::BIGINT,
               bank_account = bank_account_val,
               deadline_duration_seconds = deadline_val,
               is_open = COALESCE((input_data->>'is_open')::BOOLEAN, true)
         WHERE id = form_id;

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        IF v_seconds_before_deadline IS NOT NULL THEN
            PERFORM public.queue_payment_reminders(occasion_id, v_seconds_before_deadline);
        END IF;

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'link', link_param,
            'form_fields', form_fields_data
        );

    EXCEPTION WHEN OTHERS THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;


-- Source: database/functions/others/update_occasion.sql
CREATE OR REPLACE FUNCTION public.update_occasion_internal_v1(input_data JSONB)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 AS $$
 DECLARE
     updated_occ public.occasions;
     occ_id BIGINT;
     now TIMESTAMPTZ := NOW();
     final_unit BIGINT;

     -- Variable for the determined support flag
     is_app_supported BOOLEAN;

     -- Variable to help find the organization to check settings
     v_org_id BIGINT;

     -- Variables for feature handling
     new_blueprint_id BIGINT;
     v_form_id BIGINT;
     v_form_blueprint BIGINT;
     v_form_settings JSONB;
     v_form_link TEXT;
     v_reminder_interval_seconds BIGINT;
     v_email_order record;

     input_features JSONB;
     old_features JSONB;
     processed_features JSONB;
     feature JSONB;
     form_feature_found BOOLEAN;
 BEGIN
     -- Validate input data. Raise an exception if it's missing or empty.
     IF input_data IS NULL OR input_data = '{}'::jsonb THEN
         RAISE EXCEPTION 'Input data is missing or empty';
     END IF;

     -- 1. Identify the Organization ID
     IF (input_data->>'id') IS NOT NULL THEN
         -- Case A: UPDATE - Get organization from the existing occasion
         SELECT organization INTO v_org_id
         FROM public.occasions
         WHERE id = (input_data->>'id')::BIGINT;
     ELSE
         -- Case B: INSERT - Try to get organization from input
         v_org_id := (input_data->>'organization')::BIGINT;

         -- Case C: INSERT fallback - If org is missing, try to get it via the Unit
         IF v_org_id IS NULL AND (input_data->>'unit') IS NOT NULL THEN
            SELECT organization INTO v_org_id
            FROM public.units
            WHERE id = (input_data->>'unit')::BIGINT;
         END IF;
     END IF;

     -- 2. Fetch the setting from public.organizations.data
     -- Defaults to TRUE if the organization or the key is not found to ensure backward compatibility
     IF v_org_id IS NOT NULL THEN
         SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
         INTO is_app_supported
         FROM public.organizations
         WHERE id = v_org_id;
     ELSE
         is_app_supported := false;
     END IF;

     -- Ensure is_app_supported is not null (redundant safety check)
     is_app_supported := COALESCE(is_app_supported, false);

     --
     -- Prepare features based on is_app_supported flag
     --
     input_features := COALESCE(input_data->'features', '[]'::jsonb);
     processed_features := '[]'::jsonb;

     IF NOT is_app_supported THEN
         -- If the app is not supported, we must enable the 'form' feature.
         form_feature_found := false;
         -- Loop through existing features to find and enable the form feature
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             IF feature->>'code' = 'form' THEN
                 -- If form feature exists, ensure it is enabled
                 feature := feature || '{"is_enabled": true}';
                 form_feature_found := true;
             END IF;
             processed_features := processed_features || feature;
         END LOOP;

         -- If the form feature was not found in the original array, add it.
         IF NOT form_feature_found THEN
             processed_features := processed_features || '{"code": "form", "is_enabled": true}';
         END IF;
     ELSE
         -- If app is supported, use features as they were provided.
         processed_features := input_features;
     END IF;

     -- Determine if this is an UPDATE or INSERT based on the presence of an 'id'
     occ_id := (input_data->>'id')::BIGINT;

     IF occ_id IS NOT NULL THEN
         PERFORM public.check_occasion_writable(occ_id);
         -- This is an UPDATE operation

         -- Check for the existence of the occasion and get its current unit
         SELECT unit, features INTO final_unit, old_features FROM public.occasions WHERE id = occ_id FOR UPDATE;
         IF NOT FOUND THEN
             RAISE EXCEPTION 'Occasion with ID % not found', occ_id;
         END IF;

         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;
         processed_features := public.merge_ticket_layout_features(old_features, processed_features, input_data->'ticket_layout_change');
         PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';

         -- Determine the final unit, allowing it to be updated.
         final_unit := COALESCE((input_data->>'unit')::BIGINT, final_unit);

         -- Security check: ensure the current user has editor rights on the target unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         IF (input_data ? 'organization' AND (input_data->>'organization')::bigint IS DISTINCT FROM v_org_id)
           OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=final_unit AND organization=v_org_id) THEN
           RAISE insufficient_privilege USING MESSAGE='Occasion tenant cannot change'; END IF;

         UPDATE public.occasions
            SET updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',false),
                data        = COALESCE(input_data->'data', data),
                is_hidden   = COALESCE((input_data->>'is_hidden')::BOOLEAN, is_hidden),
                is_open     = COALESCE((input_data->>'is_open')::BOOLEAN, is_open),
                is_promoted = COALESCE((input_data->>'is_promoted')::BOOLEAN, is_promoted),
                start_time  = COALESCE((input_data->>'start_time')::TIMESTAMPTZ, start_time),
                end_time    = COALESCE((input_data->>'end_time')::TIMESTAMPTZ, end_time),
                organization = COALESCE((input_data->>'organization')::BIGINT, organization),
                services    = COALESCE(input_data->'services', services),
                unit        = final_unit,
                is_order_synchronization_enabled=COALESCE((input_data->>'is_order_synchronization_enabled')::boolean,is_order_synchronization_enabled),
                features    = processed_features -- Use the processed features
          WHERE id = occ_id
          RETURNING * INTO updated_occ;

     ELSE
         -- This is an INSERT operation

         -- For new occasions, the 'unit' field is mandatory.
         final_unit := (input_data->>'unit')::BIGINT;
         IF final_unit IS NULL THEN
             RAISE EXCEPTION 'The "unit" field is required for new occasions';
         END IF;

         -- Security check for the new occasion's unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         -- We still need to default 'reminder_is_enabled' for the 'form' feature if not specified.
         -- We do this on the already processed_features array.
         input_features := processed_features; -- Use the result from the is_app_supported logic
         processed_features := '[]'::jsonb;
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             -- If the current feature is the 'form' feature
             IF feature->>'code' = 'form' THEN
                 -- And if 'reminder_is_enabled' is NOT specified, default it to true.
                 IF NOT (feature ? 'reminder_is_enabled') THEN
                     feature := feature || '{"reminder_is_enabled": true}';
                 END IF;
             END IF;
             processed_features := processed_features || feature::jsonb;
         END LOOP;

         processed_features := public.merge_ticket_layout_features('[]', processed_features, input_data->'ticket_layout_change', true);

         INSERT INTO public.occasions(
             created_at, updated_at, title, description, link, data,
             is_hidden, is_open, is_promoted, start_time, end_time, organization,
             services, unit, features
         )
         VALUES(
             now, now,
             COALESCE(input_data->>'title', ''),
             COALESCE(input_data->>'description', ''),
             '',
             COALESCE(input_data->'data', '{}'::jsonb),
             COALESCE((input_data->>'is_hidden')::BOOLEAN, false),
             COALESCE((input_data->>'is_open')::BOOLEAN, true),
             COALESCE((input_data->>'is_promoted')::BOOLEAN, false),
             (input_data->>'start_time')::TIMESTAMPTZ,
             (input_data->>'end_time')::TIMESTAMPTZ,
             (input_data->>'organization')::BIGINT,
             COALESCE(input_data->'services', '{}'::jsonb),
             final_unit,
             processed_features
         )
         RETURNING * INTO updated_occ;

         -- Set the occ_id from the newly created record for subsequent logic
         occ_id := updated_occ.id;
         UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',true) WHERE id=occ_id RETURNING * INTO updated_occ;
     END IF;

     -- Enabling the blueprint feature must not bypass form capacity/waitlist guards,
     -- including when the stored blueprint already exists.
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
       FOR v_form_id IN SELECT id FROM public.forms WHERE occasion=occ_id ORDER BY id LOOP
         PERFORM public.check_form_capacity_settings_internal(v_form_id, '{"blueprint":1}'::jsonb);
       END LOOP;
     END IF;

     PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
     --
     -- Post-update/insert feature handling
     --

     -- Check if form feature is enabled and handle related logic.
     -- This will now be triggered if is_app_supported was false (based on organization settings).
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "form" && @.is_enabled == true)') THEN
         -- Extract the settings for the 'form' feature from the newly saved data
         SELECT elem INTO v_form_settings
         FROM jsonb_array_elements(updated_occ.features) AS elem
         WHERE elem->>'code' = 'form';

         -- Create a default form if one doesn't exist for the occasion
         IF NOT EXISTS (SELECT 1 FROM public.forms WHERE occasion = occ_id) THEN
             v_form_link := NULLIF(btrim(input_data->>'form_link'), '');
             PERFORM create_form(occ_id, v_form_link, 'Registration');
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders

         END IF;
     END IF;

     -- Revalidate in-flight reminders after every relevant occasion update.
     PERFORM public.queue_payment_reminders(occ_id,coalesce(v_reminder_interval_seconds,86400));
     IF updated_occ.is_order_synchronization_enabled THEN
       FOR v_email_order IN SELECT id FROM eshop.orders WHERE occasion=occ_id AND state='paid' LOOP
         PERFORM public.enqueue_paid_order_tickets(v_email_order.id);
       END LOOP;
     END IF;
     -- Check if the blueprint feature is enabled in the final, saved state
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         -- Find the associated form to attach the blueprint to
         SELECT id, blueprint INTO v_form_id, v_form_blueprint
           FROM public.forms
          WHERE occasion = occ_id
          LIMIT 1;

         -- If a form exists and it doesn't already have a blueprint, create one.
         IF FOUND AND v_form_blueprint IS NULL THEN
             INSERT INTO eshop.blueprints(configuration, occasion, organization, created_at, updated_at)
             VALUES ('{"dimensions": {"width": 28, "height": 52}}'::jsonb, occ_id, COALESCE(updated_occ.organization, 1), now, now)
             RETURNING id INTO new_blueprint_id;

             UPDATE public.forms
                SET blueprint = new_blueprint_id,
                    updated_at = now
              WHERE id = v_form_id;
         END IF;
     END IF;
 END;
 $$;

CREATE OR REPLACE FUNCTION public.update_occasion_203(input_data jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_occasion bigint; v_version bigint; v_response jsonb;
BEGIN
  v_occasion:=NULLIF(input_data->>'id','')::bigint;
  IF v_occasion IS NULL THEN
    PERFORM public.create_occasion_client_sync_v1(
      extensions.gen_random_uuid(),input_data);
    RETURN;
  END IF;
  SELECT COALESCE(v.version,0) INTO v_version
    FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='occasion' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=v_occasion::text;
  v_response:=public.save_occasion_client_sync_v1(v_occasion,
    extensions.gen_random_uuid(),v_version,input_data);
  IF v_response->>'status'='conflict' THEN
    RAISE serialization_failure USING MESSAGE='Occasion changed; reload before saving';
  ELSIF v_response->>'status' IS DISTINCT FROM 'applied' THEN
    RAISE invalid_parameter_value USING MESSAGE='Occasion save rejected';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.update_occasion_203(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion_203(jsonb) TO authenticated;


-- Source: database/functions/others/duplicate_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint, p_target_unit bigint, p_locale text)
RETURNS bigint
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  new_occ         bigint;
  rec             record;
  new_info_id     bigint;
  v_new_id        bigint;
  new_place_id    bigint;
  new_event_id    bigint;
  new_bp_id       bigint;
  new_pt_id       bigint;
  new_product_id  bigint;
  new_form_id     bigint;
  v_source_unit bigint;
  v_target_unit bigint;
  v_organization bigint;
  v_demo boolean;
BEGIN
  SELECT unit, organization INTO v_source_unit, v_organization
  FROM public.occasions WHERE id = oc;
  v_target_unit := COALESCE(p_target_unit, v_source_unit);
  v_demo := public.is_demo_occasion(oc);
  IF auth.uid() IS NULL OR v_source_unit IS NULL OR v_target_unit IS NULL
     OR NOT public.can_copy_occasion_source(oc)
     OR public.is_demo_unit(v_target_unit)
     OR NOT public.get_is_manager_on_unit(v_target_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units
       WHERE id = v_target_unit AND organization = v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE = 'source and target unit manager required within one organization';
  END IF;

  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, CASE WHEN v_demo THEN true ELSE is_hidden END,
         CASE WHEN v_demo THEN false ELSE is_open END, CASE WHEN v_demo THEN false ELSE is_promoted END, start_time, end_time,
         '' AS link,
         public.copy_occasion_title_internal(title,p_locale), v_organization, services, v_target_unit, features, CASE WHEN v_demo THEN NULL ELSE occasion_hidden END, description
  FROM public.occasions
  WHERE id = oc
  RETURNING id INTO new_occ;

  UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',new_occ,NULL,true) WHERE id=new_occ;

  ------------------------------------------------------------------
  -- 2. Create temporary mapping tables (old id → new id)
  ------------------------------------------------------------------
  CREATE TEMP TABLE tmp_places (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_events (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_exclusive_groups (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprints (old_id bigint, new_id bigint) ON COMMIT DROP;
  PERFORM 1 FROM public.occasions WHERE id=oc FOR UPDATE;
  CREATE TEMP TABLE tmp_product_types (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_products (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_spots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_pools (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_contexts (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resources (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resource_slots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_forms (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_information_hidden (old_id bigint, new_id bigint) ON COMMIT DROP;

  ------------------------------------------------------------------
  -- 3. Duplicate tables that reference the occasion directly
  ------------------------------------------------------------------

  -- 3a. Email Templates
  INSERT INTO public.email_templates (html, occasion, unit, subject, organization, code, title)
  SELECT DISTINCT ON (code) html, new_occ, v_target_unit, subject, v_organization, code, title
  FROM public.email_templates
  WHERE occasion = oc
  ORDER BY code, (unit IS NOT DISTINCT FROM v_source_unit) DESC,
    (organization IS NOT DISTINCT FROM v_organization) DESC, id DESC;

  -- 3b. Duplicate information_hidden rows using a loop and record mapping.
  FOR rec IN
    SELECT id, data
    FROM public.information_hidden
    WHERE occasion = oc AND NOT v_demo
  LOOP
    INSERT INTO public.information_hidden (created_at, data, occasion)
    VALUES (now(), rec.data, new_occ)
    RETURNING id INTO new_info_id;

    INSERT INTO tmp_information_hidden (old_id, new_id)
    VALUES (rec.id, new_info_id);
  END LOOP;

  -- 3c. Information – update its foreign key to information_hidden using the mapping.
  INSERT INTO public.information
    (created_at, title, description, is_hidden, "order", updated_at, type, occasion, data, information_hidden, unit)
  SELECT now(), title, description, is_hidden, "order", now(), type, new_occ, data,
         CASE WHEN information_hidden IS NOT NULL
              THEN (SELECT tih.new_id FROM tmp_information_hidden AS tih WHERE tih.old_id = information_hidden)
              ELSE NULL END,
         v_target_unit
  FROM public.information
  WHERE occasion = oc;

  -- 3d. Role Info
  INSERT INTO public.role_info (title, occasion)
  SELECT title, new_occ
  FROM public.role_info
  WHERE occasion = oc;

  ------------------------------------------------------------------
  -- 4. Duplicate tables with additional foreign keys (using loops)
  ------------------------------------------------------------------

  -- 4a. Places
  FOR rec IN
    SELECT id, title, description, type, created_at, coordinates, is_hidden, "order", icon, unit
    FROM public.places
    WHERE occasion = oc
  LOOP
    INSERT INTO public.places
      (title, description, type, created_at, coordinates, is_hidden, updated_at, occasion, "order", icon, unit)
    VALUES (rec.title, rec.description, rec.type, rec.created_at, rec.coordinates, rec.is_hidden, now(), new_occ, rec."order", rec.icon, v_target_unit)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_places (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4b. Exclusive Groups
  FOR rec IN
    SELECT id, title
    FROM public.exclusive_groups
    WHERE occasion = oc
  LOOP
    INSERT INTO public.exclusive_groups (title, occasion)
    VALUES (rec.title, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_exclusive_groups (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4c. Events – adjust the "place" foreign key using tmp_places.
  FOR rec IN
    SELECT id, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, is_hidden, type
    FROM public.events
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_place_id
      FROM tmp_places AS t
      WHERE t.old_id = rec.place;

    INSERT INTO public.events
      (created_at, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, updated_at, is_hidden, occasion, type)
    VALUES (now(), rec.title, rec.start_time, rec.end_time, rec.max_participants, rec.description,
            COALESCE(new_place_id, rec.place), rec.split_for_men_women, rec.is_group_event, now(), rec.is_hidden, new_occ, rec.type)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_events (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4d. Event Groups – update both parent and child using the event mapping.
  INSERT INTO public.event_groups (event_parent, event_child)
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_parent),
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_child)
  FROM public.event_groups eg
  WHERE eg.event_parent IN (SELECT old_id FROM tmp_events)
    AND eg.event_child IN (SELECT old_id FROM tmp_events);

  -- 4e. Event Roles – update event using mapping.
  INSERT INTO public.event_roles (event, role)
  SELECT (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = er.event), er.role
  FROM public.event_roles er
  WHERE er.event IN (SELECT old_id FROM tmp_events);

  -- 4f. Exclusive Events – update both event and group using mappings.
  INSERT INTO public.exclusive_events (event, "group")
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = ee.event),
    (SELECT teg.new_id FROM tmp_exclusive_groups AS teg WHERE teg.old_id = ee."group")
  FROM public.exclusive_events ee
  WHERE ee.event IN (SELECT old_id FROM tmp_events)
    AND ee."group" IN (SELECT old_id FROM tmp_exclusive_groups);

  ------------------------------------------------------------------
  -- 5. Duplicate ESHOP tables (using loops)
  ------------------------------------------------------------------

  -- 5a. Blueprints
  FOR rec IN
    SELECT id, data, title, organization, configuration, objects, groups, background_svg
    FROM eshop.blueprints
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, configuration, objects, groups, occasion, updated_at, background_svg)
    VALUES (now(), rec.data, rec.title, v_organization, rec.configuration, rec.objects, rec.groups, new_occ, now(), rec.background_svg)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_blueprints (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5b. Product Types
  FOR rec IN
    SELECT id, title, description, type, data
    FROM eshop.product_types
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.product_types
      (created_at, updated_at, title, description, type, data, occasion)
    VALUES (now(), now(), rec.title, rec.description, rec.type, rec.data, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_product_types (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5c. Products – adjust product_type via mapping.
  FOR rec IN
    SELECT id, title, description, price, data, product_type, is_hidden, currency_code, "order", maximum
    FROM eshop.products
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_pt_id
      FROM tmp_product_types AS t
      WHERE t.old_id = rec.product_type;

    INSERT INTO eshop.products
      (created_at, updated_at, title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
    VALUES (now(), now(), rec.title, rec.description, rec.price, rec.data,
            COALESCE(new_pt_id, rec.product_type), new_occ, rec.is_hidden, rec.currency_code, rec."order", rec.maximum)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_products (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- Inventory configuration is copied, never its allocations or reservations.
  FOR rec IN SELECT * FROM public.inventory_pools WHERE occasion=oc LOOP
    INSERT INTO public.inventory_pools(title,description,type,data,sellable_capacity,occasion)
    VALUES(rec.title,rec.description,rec.type,rec.data,rec.sellable_capacity,new_occ)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_pools VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT c.* FROM public.inventory_contexts c
    JOIN tmp_inventory_pools m ON m.old_id=c.inventory_pool LOOP
    INSERT INTO public.inventory_contexts(inventory_pool,block_date,title,"order",data)
    VALUES((SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      rec.block_date,rec.title,rec."order",rec.data) RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_contexts VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resources r
    JOIN tmp_inventory_pools m ON m.old_id=r.inventory_pool LOOP
    INSERT INTO public.resources(title,description,capacity,booking_rules,inventory_pool,place,occasion,unit,data)
    VALUES(rec.title,rec.description,rec.capacity,rec.booking_rules,
      (SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      (SELECT new_id FROM tmp_places WHERE old_id=rec.place),new_occ,v_target_unit,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resources VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resource_slots r JOIN tmp_resources m ON m.old_id=r.resource LOOP
    INSERT INTO public.resource_slots(resource,title,data)
    VALUES((SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),rec.title,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resource_slots VALUES(rec.id,v_new_id);
  END LOOP;
  INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity)
    SELECT p.new_id,c.new_id,x.quantity FROM eshop.product_inventory_contexts x
    JOIN tmp_products p ON p.old_id=x.product
    JOIN tmp_inventory_contexts c ON c.old_id=x.inventory_context;

  -- 5d. Spots – adjust foreign keys for product and blueprint.
  FOR rec IN
    SELECT id, product, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot
    FROM eshop.spots
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_product_id
      FROM tmp_products AS t
      WHERE t.old_id = rec.product;

    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO eshop.spots
      (created_at, occasion, product, updated_at, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot)
    VALUES (now(), new_occ, COALESCE(new_product_id, rec.product), now(), null, null, rec.title, null, COALESCE(new_bp_id, rec.blueprint),
      (SELECT new_id FROM tmp_inventory_contexts WHERE old_id=rec.inventory_context),
      (SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),
      (SELECT new_id FROM tmp_resource_slots WHERE old_id=rec.resource_slot))
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- 6. Update blueprints “objects” JSON column if it contains spot objects.
  --    For each blueprint, if its "objects" JSON array contains an object with "type" = 'spot',
  --    replace its "id" with the corresponding new spot id.
  ------------------------------------------------------------------
  FOR rec IN
    SELECT tb.old_id AS old_bp, tb.new_id AS new_bp, b.objects
    FROM tmp_blueprints tb
    JOIN eshop.blueprints b ON b.id = tb.new_id
  LOOP
    IF rec.objects IS NOT NULL THEN
      UPDATE eshop.blueprints
      SET objects = (
        SELECT jsonb_agg(
          CASE
            WHEN obj->>'type' = 'spot' THEN
              obj || jsonb_build_object(
                'id',
                COALESCE(
                  (SELECT ts.new_id FROM tmp_spots ts WHERE ts.old_id = (obj->>'id')::bigint),
                  (obj->>'id')::int
                )
              )
            ELSE obj
          END
        )
        FROM jsonb_array_elements(rec.objects) AS obj
      )
      WHERE id = rec.new_bp;
    END IF;
  END LOOP;


  ------------------------------------------------------------------
  -- 7. Duplicate Forms and Form Fields
  ------------------------------------------------------------------

  -- 7a. Forms – adjust the blueprint foreign key via mapping and update the link to be unique.
  FOR rec IN
    SELECT id, data, key, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds
    FROM public.forms
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO public.forms
      (created_at, data, key, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, updated_at, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds)
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type,
            CASE WHEN v_demo THEN NULL WHEN v_source_unit = v_target_unit OR EXISTS (
              SELECT 1 FROM eshop.unit_bank_accounts uba
              WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN rec.bank_account ELSE NULL END,
            rec.deadline_duration_seconds,
            CASE WHEN v_demo THEN false WHEN v_source_unit <> v_target_unit AND rec.bank_account IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts uba
                WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN false ELSE rec.is_open END,
            NULL,
            COALESCE(new_bp_id, rec.blueprint), rec.header, rec.header_off, now(), rec.title, rec.participant_capacity, rec.waitlist_enabled, rec.show_remaining_capacity, rec.waitlist_offer_duration_seconds)
    RETURNING id INTO v_new_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',v_new_id,NULL,true) WHERE id=v_new_id;

    INSERT INTO tmp_forms (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 7b. Form Fields – update the "form" foreign key and product_type via mapping tables.
  INSERT INTO public.form_fields
    (created_at, title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
  SELECT now(), title, description, data, type, is_required,
         (SELECT tf.new_id FROM tmp_forms AS tf WHERE tf.old_id = form),
         is_hidden, "order",
         CASE WHEN product_type IS NOT NULL
              THEN (SELECT tp.new_id FROM tmp_product_types AS tp WHERE tp.old_id = product_type)
              ELSE NULL END,
         is_ticket_field
  FROM public.form_fields
  WHERE form IN (SELECT old_id FROM tmp_forms);

  ------------------------------------------------------------------
  -- 8. Return the new occasion id
  ------------------------------------------------------------------
  -- References are remapped only after the complete type map exists.
  UPDATE public.occasions o SET features=(SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' AND f ? 'layout'
    THEN jsonb_set(f,'{layout,templates}',(SELECT jsonb_object_agg(t.key,jsonb_set(t.value,'{elements}',
      (SELECT jsonb_agg(CASE WHEN e->>'binding'='productType' THEN jsonb_set(e,'{productTypeId}',
        to_jsonb((SELECT m.new_id FROM tmp_product_types m WHERE m.old_id=(e->>'productTypeId')::bigint))) ELSE e END ORDER BY n)
       FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)))) FROM jsonb_each(f->'layout'->'templates') t)) ELSE f END ORDER BY n)
    FROM jsonb_array_elements(o.features) WITH ORDINALITY x(f,n)) WHERE o.id=new_occ;
  PERFORM public.validate_ticket_layout_references(new_occ,f->'layout') FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=new_occ AND f->>'code'='ticket' AND f ? 'layout';
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden,
    tmp_inventory_pools,tmp_inventory_contexts,tmp_resources,tmp_resource_slots;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint)
  FROM PUBLIC, anon, authenticated;

-- Existing internal callers retain same-unit semantics.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_internal_v1(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint,p_target_unit bigint)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT public.duplicate_occasion_internal_v1(oc,p_target_unit,'en');
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop_forms/duplicate_form_to_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_internal_v1(
    source_form_id BIGINT,
    target_occasion_link TEXT
)
RETURNS BIGINT -- Returns the ID of the new form
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    user_id UUID := auth.uid();
    target_occasion_id BIGINT;
    target_organization_id BIGINT;
    source_occasion_id BIGINT;
    source_unit_id BIGINT;
    has_source_permission BOOLEAN;
    has_target_permission BOOLEAN;
    new_form_id BIGINT;
    v_new_form_link TEXT;
    form_field_record RECORD;
    new_product_type_id BIGINT;
    product_record RECORD;
BEGIN
    -- Step 1: Resolve the target occasion ID and its organization ID from its link.
    SELECT id, organization INTO target_occasion_id, target_organization_id
    FROM public.occasions WHERE id = public.resolve_occasion_link_internal(target_occasion_link);
    IF target_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Target occasion not found for link: %', target_occasion_link;
    END IF;

    PERFORM public.check_occasion_writable(target_occasion_id);

    -- Step 2: Get the source occasion and unit IDs for permission checking.
    SELECT f.occasion, o.unit
    INTO source_occasion_id, source_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = source_form_id;

    IF source_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Source form not found.';
    END IF;

    -- Step 3: Check if the user has editor_view rights on the source occasion or its unit.
    SELECT EXISTS (
        SELECT 1 FROM public.occasion_users
        WHERE occasion = source_occasion_id AND "user" = user_id AND is_editor_view = TRUE
    ) OR EXISTS (
        SELECT 1 FROM public.unit_users
        WHERE unit = source_unit_id AND "user" = user_id AND is_editor_view = TRUE
    )
    INTO has_source_permission;

    IF NOT has_source_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to view the source form.';
    END IF;

    -- Step 4: Check if the user has editor rights on the target occasion.
    SELECT EXISTS (
        SELECT 1 FROM public.occasion_users
        WHERE occasion = target_occasion_id AND "user" = user_id AND is_editor = TRUE
    )
    INTO has_target_permission;

    IF NOT has_target_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to create a form in the target occasion.';
    END IF;

    -- Step 6: Copy the main form record to the target occasion.
    INSERT INTO public.forms (title, data, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds)
    SELECT
        public.copy_occasion_title_internal(title,'en'),
        data,
        target_occasion_id,
        type,
        bank_account,
        deadline_duration_seconds,
        is_open,
        NULL,
        blueprint,
        header,
        header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds
    FROM public.forms
    WHERE id = source_form_id
    RETURNING id INTO new_form_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,NULL,true) WHERE id=new_form_id;

    -- Step 7: Loop through each field of the source form and perform a deep copy.
    FOR form_field_record IN
        SELECT * FROM public.form_fields WHERE form = source_form_id
    LOOP
        -- Check if the field is linked to a product type.
        IF form_field_record.product_type IS NOT NULL THEN
            -- A) If yes, perform a deep copy of the product type and its products.
            INSERT INTO eshop.product_types (title, description, type, data, occasion, maximum)
            SELECT title, description, type, data, target_occasion_id, maximum
            FROM eshop.product_types
            WHERE id = form_field_record.product_type
            RETURNING id INTO new_product_type_id;

            FOR product_record IN
                SELECT * FROM eshop.products WHERE product_type = form_field_record.product_type
            LOOP
                INSERT INTO eshop.products (title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
                VALUES (
                    product_record.title, product_record.description, product_record.price, product_record.data,
                    new_product_type_id, target_occasion_id, product_record.is_hidden, product_record.currency_code,
                    product_record.order, product_record.maximum
                );
            END LOOP;

            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                new_product_type_id, form_field_record.is_ticket_field
            );
        ELSE
            -- B) If not, perform a simple copy of the form field.
            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                NULL, form_field_record.is_ticket_field
            );
        END IF;
    END LOOP;

    -- Step 8: Return the ID of the newly created form.
    RETURN new_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_internal_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion(source_form_id bigint,target_occasion_link text)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (public.duplicate_form_to_occasion_client_sync_v1(source_form_id,target_occasion_link,gen_random_uuid())#>>'{data,formId}')::bigint;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion(bigint,text) TO authenticated;


-- Source: database/functions/others/duplicate_occasion_client_sync_v1.sql
-- The duplicate command must use the audit operation accepted by
-- client_commit_items_operation_check. The old value, 'create', rolled back
-- every attempted occasion copy before it returned an occasion ID.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid, p_target_unit bigint, p_locale text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unit bigint;
  v_title text;
  v_source_unit bigint;
  v_org bigint;
  v_new bigint;
  v_begin jsonb;
  v_hash text;
  v_commit public.client_commits%ROWTYPE;
BEGIN
  SELECT o.unit, o.title, o.organization INTO v_source_unit, v_title, v_org
  FROM public.occasions o WHERE o.id = p_occasion;
  v_unit := COALESCE(p_target_unit, v_source_unit);
  IF v_actor IS NULL OR v_source_unit IS NULL OR v_unit IS NULL
     OR NOT public.can_copy_occasion_source(p_occasion)
     OR public.is_demo_unit(v_unit)
     OR NOT public.get_is_manager_on_unit(v_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units WHERE id=v_unit AND organization=v_org) THEN
    RAISE insufficient_privilege USING MESSAGE = 'unit manager required';
  END IF;
  v_hash := encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion', p_occasion) || CASE WHEN v_unit = v_source_unit THEN '{}'::jsonb
        ELSE jsonb_build_object('targetUnit', v_unit) END || CASE WHEN p_locale IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('locale',p_locale) END)::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_unit_client_mutation_v1(
    p_command_id, 'occasion.duplicate', v_unit, v_actor, v_hash);
  IF v_begin->>'disposition' = 'replay' THEN RETURN v_begin->'response'; END IF;

  v_new := public.duplicate_occasion_internal_v1(p_occasion, v_unit,coalesce(p_locale,'en'));
  INSERT INTO public.occasion_users
    (occasion, "user", is_manager, is_editor, is_editor_view, is_editor_order, is_editor_order_view)
  VALUES (v_new, v_actor, true, true, true, true, true);
  UPDATE public.occasions SET data = jsonb_set(COALESCE(data, '{}'::jsonb),
    '{client_sync_v1}', 'false'::jsonb, true) WHERE id = v_new;
  INSERT INTO public.client_commits
    (unit, actor_id, actor_display, actor_kind, source, change_class)
  SELECT v_unit, v_actor, nullif(concat_ws(' ', ui.name, ui.surname), ''),
    'user', 'occasion.duplicate', 'configuration'
  FROM public.user_info ui WHERE ui.id = v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id, item_index, entity_type, entity_id, operation, safe_label,
     changed_fields)
  VALUES (v_commit.commit_id, 0, 'occasion', v_new::text, 'insert',
    (SELECT left(title,240) FROM public.occasions WHERE id=v_new), ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id, v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id, jsonb_build_object(
    'status', 'applied', 'code', 200,
    'data', jsonb_build_object('occasionId', v_new),
    'mutation', jsonb_build_object('commandId', p_command_id,
      'receiptId', p_command_id, 'commitId', v_commit.commit_id,
      'replayed', false, 'occurredAt', v_commit.occurred_at),
    'sync', jsonb_build_object('replacements', '[]'::jsonb)),
    v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid, bigint, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid, bigint, text)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(p_occasion bigint,p_command_id uuid,p_target_unit bigint)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT public.duplicate_occasion_client_sync_v1(p_occasion,p_command_id,p_target_unit,NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid,bigint) TO authenticated;
-- Keep existing client signatures routed through the same canonical command.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_client_sync_v1(p_occasion, p_command_id, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint, p_target_unit bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_response jsonb;
BEGIN
  v_response := public.duplicate_occasion_client_sync_v1(oc, gen_random_uuid(), p_target_unit);
  RETURN (v_response #>> '{data,occasionId}')::bigint;
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint) TO authenticated;

-- Return only authorized destinations. The navigation unit list does not carry
-- membership flags and may include units visible only through an occasion.
CREATE OR REPLACE FUNCTION public.get_occasion_copy_units(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_org bigint; v_unit bigint;
BEGIN
  SELECT organization, unit INTO v_org, v_unit FROM public.occasions WHERE id=p_occasion;
  IF auth.uid() IS NULL OR v_unit IS NULL
     OR NOT public.can_copy_occasion_source(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='source unit manager required';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id', u.id, 'title', u.title, 'organization', u.organization) ORDER BY u.title,u.id)
    FROM public.units u WHERE u.organization=v_org AND public.get_is_manager_on_unit(u.id) AND NOT public.is_demo_unit(u.id)), '[]'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.get_occasion_copy_units(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_copy_units(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint,p_target_unit bigint,p_locale text)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT (public.duplicate_occasion_client_sync_v1(oc,gen_random_uuid(),p_target_unit,p_locale)#>>'{data,occasionId}')::bigint;
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint,bigint,text) TO authenticated;


-- Source: database/functions/eshop_forms/get_all_form_fields.sql
CREATE OR REPLACE FUNCTION get_all_form_fields(form_link TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_form_id BIGINT;
    v_occasion_id BIGINT;
    formFieldsData JSONB;
BEGIN
    -- Retrieve form ID and occasion ID
    SELECT id, occasion INTO v_form_id, v_occasion_id
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(form_link);

    -- Check if form exists
    IF v_form_id IS NULL THEN
        RAISE EXCEPTION 'Form not found.';
    END IF;

    -- Check permissions
    IF NOT public.get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RAISE EXCEPTION 'Access Denied';
    END IF;

    -- Fetch form fields
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ff.id,
            'created_at', ff.created_at,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'form', ff.form,
            'is_hidden', ff.is_hidden,
            'order', ff."order",
            'product_type', ff.product_type,
            'is_ticket_field', ff.is_ticket_field
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    WHERE ff.form = v_form_id
      AND ff.is_ticket_field = false
      AND ff.type <> 'ticket';

    RETURN formFieldsData;
END;
$$;


-- Source: database/functions/eshop_forms/get_form_for_edit.sql
-- Fix get_form_for_edit: Remove bigint = uuid comparison and add can_delete
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_form_id BIGINT;
    v_occasion_id BIGINT;
    v_unit_id BIGINT;
    formData JSONB;
    formFieldsData JSONB;
    productTypesData JSONB;
    productsData JSONB;
    availableBankAccountsData JSONB;
    canDelete BOOLEAN;
BEGIN
    SELECT
        f.id,
        f.occasion,
        o.unit
    INTO
        v_form_id,
        v_occasion_id,
        v_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = public.resolve_form_link_internal(form_link);

    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    PERFORM check_is_editor_order_view_via_form_link(form_link);

    -- Calculate can_delete
    -- FIXED: Compare form (bigint) with v_form_id (bigint) directly
    SELECT NOT EXISTS (
        SELECT 1 FROM eshop.orders WHERE form = v_form_id
    ) INTO canDelete;

    SELECT jsonb_build_object(
        'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
        'key', f.key,
        'is_open', f.is_open,
        'created_at', f.created_at,
        'data', f.data,
        'type', f.type,
        'title', f.title,
        'header', f.header,
        'header_off', f.header_off,
        'occasion', f.occasion,
        'blueprint', f.blueprint,
        'link', f.link,
        'bank_account', f.bank_account,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'can_delete', canDelete -- Added field
    )
    INTO formData
    FROM public.forms f
    WHERE f.id = v_form_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', pt.id,
            'title', pt.title,
            'description', pt.description,
            'type', pt.type,
            'data', pt.data,
            'occasion', pt.occasion
        ) ORDER BY pt.title
    ), '[]'::jsonb)
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Materialize occasion history once rather than scanning it for every
    -- product and every field. Only current orders and current references determine eligibility.
    WITH occasion_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE occasion = v_occasion_id
    ), snapshots AS MATERIALIZED (
      SELECT data FROM occasion_orders
    ), used_products AS MATERIALIZED (
      SELECT opt.product::text AS product FROM eshop.order_product_ticket opt
      JOIN eshop.products p ON p.id = opt.product WHERE p.occasion = v_occasion_id
      UNION
      SELECT value #>> '{}' FROM snapshots s
      CROSS JOIN LATERAL jsonb_path_query(s.data, '$.tickets[*].products[*].id') ids(value)
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'occasion', p.occasion,
            'title', p.title,
            'description', p.description,
            'price', p.price,
            'currency_code', p.currency_code,
            'is_hidden', p.is_hidden,
            'order', p."order",
            'product_type', p.product_type,
            'ordered_count', (
                SELECT count(*)
                FROM eshop.order_product_ticket opt
                JOIN eshop.orders o ON opt."order" = o.id
                WHERE opt.product = p.id AND o.state <> 'storno'
            ),
            'maximum', p.maximum,
            'data', p.data
        ) ORDER BY COALESCE(p."order", 0)
    ), '[]'::jsonb)
    INTO productsData
    FROM eshop.products p
    CROSS JOIN LATERAL (SELECT CASE
      WHEN EXISTS (SELECT 1 FROM used_products u WHERE u.product = p.id::text) THEN 'orders'
      WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
      WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
      WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
    END AS reason) usage
    WHERE p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id);

    WITH form_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE form = v_form_id
    ), form_snapshots AS MATERIALIZED (
      SELECT data FROM form_orders
    ), form_tickets AS MATERIALIZED (
      SELECT t.note FROM eshop.order_product_ticket opt
      JOIN form_orders o ON o.id = opt."order"
      JOIN eshop.tickets t ON t.id = opt.ticket
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ff.id,
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'form', ff.form,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'is_hidden', ff.is_hidden,
            'is_ticket_field', ff.is_ticket_field,
            'order', ff."order",
            'product_type', ff.product_type
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    CROSS JOIN LATERAL (SELECT CASE WHEN EXISTS (
      SELECT 1 FROM form_snapshots s WHERE
        EXISTS (SELECT 1 FROM jsonb_array_elements(
          CASE WHEN jsonb_typeof(s.data->'fields') = 'array' THEN s.data->'fields' ELSE '[]'::jsonb END) answer
          WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
        OR (ff.type = 'ticket' AND jsonb_path_exists(s.data, '$.tickets[*]'))
        OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(s.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
    ) OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM form_tickets))
      OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (SELECT 1 FROM form_tickets WHERE NULLIF(note, '') IS NOT NULL))
      OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
        WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
      OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form))
    THEN 'responses' ELSE (
      SELECT p->>'delete_blocked_reason' FROM public.form_fields member
      JOIN jsonb_array_elements(productsData) p ON (p->>'product_type')::bigint = member.product_type
      WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
        AND p->>'delete_blocked_reason' IS NOT NULL
      ORDER BY (p->>'id')::bigint LIMIT 1
    ) END AS reason) usage
    WHERE ff.form = v_form_id;

    -- FIX: Exclude CASH accounts and ensure deterministic sorting by Priority
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ba.id,
            'account_number', ba.account_number,
            'account_number_human_readable', ba.account_number_human_readable,
            'title', ba.title,
            'supported_currencies', ba.supported_currencies,
            'type', ba.type,
            'bank_sync_warning', public.bank_sync_warning(ba.id),
            'bank_sync', (SELECT jsonb_build_object('state',c.state,'mode',c.mode) FROM eshop.bank_sync_connections c
              WHERE c.bank_account_id=ba.id OR c.id IN (SELECT a.connection_id FROM eshop.bank_sync_account_aliases a WHERE a.bank_account_id=ba.id))
        ) ORDER BY uba.priority ASC, ba.id ASC
    ), '[]'::jsonb)
    INTO availableBankAccountsData
    FROM eshop.unit_bank_accounts uba
    JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
    WHERE uba.unit = v_unit_id
      AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'form', formData,
            'form_fields', formFieldsData,
            'product_types', productTypesData,
            'products', productsData,
            'available_bank_accounts', availableBankAccountsData
        )
    );
END;
$$;


-- Source: database/functions/eshop_forms/get_form_by_link.sql
CREATE OR REPLACE FUNCTION public.get_form_bundle_internal(p_form_id bigint,p_allow_closed boolean DEFAULT false)
RETURNS JSON LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
    allData JSON;
    generated_secret UUID := gen_random_uuid();
    form_exists BOOLEAN;
    is_editor_view BOOLEAN := false;
    occ_id BIGINT;
BEGIN
    -- Check if the form exists
    SELECT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id
    ) INTO form_exists;

    IF NOT form_exists THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form does not exist.'
        );
    END IF;

    SELECT occasion INTO occ_id FROM public.forms WHERE id = p_form_id;
    IF public.is_demo_occasion(occ_id) AND NOT public.can_read_demo_occasion(occ_id) THEN
        RETURN jsonb_build_object('code',404,'message','Form does not exist.');
    END IF;
    is_editor_view := public.get_is_editor_order_view_on_occasion(occ_id);


    IF NOT p_allow_closed AND NOT is_editor_view AND NOT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id AND is_open = true
    ) THEN
        -- If the form is closed, retrieve only the 'header_off' message
        SELECT jsonb_build_object(
            'code', 400,
            'data', jsonb_build_object(
                'header_off', f.header_off,
                'is_open', f.is_open
            )
        )
        INTO allData
        FROM public.forms f
        WHERE f.id = p_form_id;

        RETURN allData;
    END IF;

    -- If the form is open, retrieve the full form data including dynamic product availability
    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'demo_simulation', public.is_demo_occasion(f.occasion),
            'capacity', public.get_form_capacity_snapshot_internal(f.id),
            'registrationMode',public.get_form_registration_mode_internal(f.id),
            'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'id', f.id,
            'link', f.link,
            'key', f.key,
            'created_at', f.created_at,
            'data', public.get_effective_form_data(f.id),
            'type', f.type,
            'title', f.title,
            'is_open', f.is_open,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', jsonb_build_object(
                'id', o.id,
                'title', o.title,
                'features', o.features,
                'start_time', o.start_time
            ),
            'blueprint', CASE WHEN jsonb_path_exists(o.features,
                '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN f.blueprint END,
            'deadline_duration_seconds', f.deadline_duration_seconds,
            'account_number', ba.account_number,
            'secret', generated_secret,
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'data', p.data,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum,
                                                    'is_dynamically_available', is_product_dynamically_available(p.id)
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                              AND NOT p.is_hidden
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id AND ff.is_hidden = false
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    LEFT JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    RETURN allData;
END;
$$;

REVOKE ALL ON FUNCTION public.get_form_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_form_by_link(form_link text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT public.get_form_bundle_internal(public.resolve_form_link_internal(form_link),false);
$$;


-- Source: database/functions/others/check_is_editor_order_view_via_form_link.sql
CREATE OR REPLACE FUNCTION public.check_is_editor_order_view_via_form_link(form_link text)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
BEGIN
    -- Get occasion ID from form link
    SELECT f.occasion INTO occasion_id
    FROM public.forms f
    WHERE f.id = public.resolve_form_link_internal(form_link);

    -- Check if order/occasion exists
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Form not found or no associated occasion.';
    END IF;

    -- Verify editor permissions using existing helper function
    IF NOT public.get_is_editor_order_view_on_occasion(occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to edit this occasion.';
    END IF;
END;
$$;

-- Source: database/functions/others/get_app_config.sql
CREATE OR REPLACE FUNCTION public.get_app_config_v218(data_in jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    org_id bigint := (data_in->>'organization')::bigint;
    link_txt text := data_in->>'link';
    form_link text := data_in->>'form_link';
    unit_id bigint := (data_in->>'unit_id')::bigint;
    platform_info jsonb := data_in->'platform';
    platform_name text := platform_info->>'platform';
    occasionId bigint;
    default_unit bigint;
    editor_unit_id bigint;
    is_open_bool BOOLEAN;
    is_app_supported_bool BOOLEAN := FALSE;
    occasion_user occasion_users%rowtype;
    unit_user unit_users%rowtype;
    is_admin_bool BOOLEAN;
    occasion_link text;
    occasion_unit bigint;
    bank_account_ids bigint[];
    occasion_json jsonb;
    unit_json jsonb;
    user_info_json jsonb;
    org_json jsonb;
    user_groups_json jsonb;
    is_editor_view_on_occasion_bool BOOLEAN;
    user_occasions_json jsonb;
    user_units_json jsonb;
    current_user_id UUID := auth.uid();
BEGIN
    -- A direct unit link must stay inside the requested tenant.
    IF unit_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.units u
        WHERE u.id = unit_id AND u.organization = org_id
    ) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
    END IF;

    -- Log the request details in log_app_config table
    INSERT INTO public.log_app_config (organization, platform)
    VALUES (org_id, platform_info);

    -- Map "pwa" to "web" for platform consistency
    IF platform_name = 'pwa' THEN
        platform_name := 'web';
    END IF;

    -- =========================================================
    -- RESOLVE CONTEXT (Occasion vs Unit)
    -- Priority: Form/Link > Representative Occasion > Unit ID > Default Occasion
    -- =========================================================

    -- 1. Try to find occasion via form_link
    IF form_link IS NOT NULL AND form_link <> '' THEN
        SELECT f.occasion, o.link
          INTO occasionId, occasion_link
        FROM public.forms f
        JOIN public.occasions o ON f.occasion = o.id
        WHERE f.id = public.resolve_form_link_internal(form_link)
          AND o.organization = org_id;
        IF occasionId IS NULL THEN
            RETURN json_build_object('code',404,'message','Form not found');
        END IF;
    END IF;

    -- 2. If no occasion found yet, try via link_txt
    IF occasionId IS NULL AND link_txt IS NOT NULL AND link_txt <> '' THEN
        SELECT id, link
          INTO occasionId, occasion_link
        FROM occasions
        WHERE id = public.resolve_occasion_link_internal(link_txt,org_id)
          AND organization = org_id;

        -- If link_txt is provided but *not* found, this is a hard 404.
        IF occasionId IS NULL THEN
            RETURN json_build_object(
                'code', 404,
                'message', 'Occasion not found'
            );
        END IF;
    END IF;

    -- 3. If no specific link found, check for REPRESENTATIVE OCCASION
    IF occasionId IS NULL AND unit_id IS NULL THEN
        SELECT (data->>'REPRESENTATIVE_OCCASION')::bigint
          INTO occasionId
        FROM organizations
        WHERE id = org_id;

        -- If found, fetch its link for consistency
        IF occasionId IS NOT NULL THEN
            SELECT link INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    END IF;

    -- 4. If no occasion (and no Representative Occasion), try to use unit_id
    IF occasionId IS NULL AND unit_id IS NOT NULL THEN
        occasionId := NULL; -- Ensure no occasion is loaded.

        default_unit := unit_id;

        SELECT json_build_object('id', u.id, 'title', u.title, 'data', u.data)
            INTO unit_json
        FROM units u
        WHERE u.id = default_unit;

        SELECT *
            INTO unit_user
        FROM unit_users
        WHERE unit = default_unit
            AND "user" = current_user_id;

    -- If no occasion and no unit found yet, try Default Occasion
    ELSIF occasionId IS NULL THEN
        -- Try to get the DEFAULT_OCCASION (Representative was already checked in step 3)
        SELECT (data->>'DEFAULT_OCCASION')::bigint
          INTO occasionId
        FROM organizations
        WHERE id = org_id;

        IF occasionId IS NOT NULL THEN
            -- Default occasion exists; fetch its link
            SELECT link
              INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    END IF;

    -- =========================================================
    -- GATHER DATA
    -- =========================================================

    IF occasionId IS NOT NULL THEN
        -- Process occasion-related queries only if an occasion was determined

        IF public.is_demo_occasion(occasionId) AND NOT public.can_read_demo_occasion(occasionId) THEN
            RETURN jsonb_build_object('code',403,'message','Demo access denied');
        END IF;

        -- Get the is_open status for the occasion
        SELECT is_open
          INTO is_open_bool
        FROM occasions
        WHERE id = occasionId;

        -- Get the occasion user record if it exists
        SELECT *
          INTO occasion_user
        FROM occasion_users
        WHERE occasion = occasionId
          AND "user" = current_user_id;

        -- Retrieve the unit ID from the occasion
        SELECT unit
          INTO occasion_unit
        FROM occasions
        WHERE id = occasionId;

        -- Get the unit user record if it exists
        SELECT *
          INTO unit_user
        FROM unit_users
        WHERE unit = occasion_unit
          AND "user" = current_user_id;

        -- Check if the current user is an admin on the occasion
        is_admin_bool := get_is_admin_on_occasion(occasionId);

        -- Check if the current user has editor_view permissions on the occasion
        is_editor_view_on_occasion_bool := get_is_editor_view_on_occasion(occasionId);

        -- Retrieve IS_APP_SUPPORTED from Organization data. Defaults to FALSE.
        SELECT COALESCE((data->>'IS_APP_SUPPORTED')::boolean, FALSE)
          INTO is_app_supported_bool
        FROM organizations
        WHERE id = org_id;

        -- If the occasion is not open, enforce access restrictions
        -- BUT bypass this check if is_app_supported_bool is FALSE.
        IF is_open_bool = FALSE AND is_app_supported_bool = TRUE THEN
            IF is_editor_view_on_occasion_bool <> TRUE
               AND (SELECT get_is_editor_order_view_on_occasion(occasionId)) <> TRUE
               AND (SELECT get_is_editor_on_unit(occasion_unit)) <> TRUE THEN
                RETURN json_build_object(
                    'code', 403,
                    'message', 'Access forbidden',
                    'link', occasion_link,
                    'unit_user', COALESCE(row_to_json(unit_user)::jsonb, NULL)
                );
            END IF;
        END IF;

        -- If the occasion user record is not found and the user is authenticated, add the user to the occasion
        IF occasion_user IS NULL AND current_user_id IS NOT NULL AND NOT public.is_demo_occasion(occasionId) THEN
            IF is_app_supported_bool IS TRUE
               OR (unit_user.is_manager IS TRUE OR unit_user.is_editor IS TRUE OR unit_user.is_editor_view IS TRUE) THEN
                PERFORM add_user_to_occasion(occasionId, current_user_id);

                SELECT *
                  INTO occasion_user
                FROM occasion_users
                WHERE occasion = occasionId
                  AND "user" = current_user_id;
            END IF;
        END IF;
    ELSE
        -- If no occasion is set (because a specific unit was used and no Rep Occasion existed), use the unit as the context
        occasion_unit := default_unit;
        is_admin_bool := false;
    END IF;

    -- Retrieve unit_user again in case the user was added and now belongs to the unit
    IF unit_user IS NULL AND occasion_unit IS NOT NULL AND current_user_id IS NOT NULL THEN
        SELECT *
          INTO unit_user
        FROM unit_users
        WHERE unit = occasion_unit
          AND "user" = current_user_id;
    END IF;

    -- Fetch list of bank account IDs where the user is an admin
    SELECT array_agg(bank_account)
      INTO bank_account_ids
    FROM eshop.bank_account_users
    WHERE "user" = current_user_id
      AND is_admin = true;

    -- Fetch full occasion details as a JSON object if an occasion is set
    IF occasionId IS NOT NULL THEN
        SELECT row_to_json(o)
          INTO occasion_json
        FROM occasions o
        WHERE o.id = occasionId;
    ELSE
        occasion_json := '{}'::jsonb;
    END IF;

    -- Fetch full unit details as a JSON object
    IF occasion_unit IS NOT NULL THEN
        SELECT json_build_object('id', u.id, 'title', u.title, 'data', u.data)
          INTO unit_json
        FROM units u
        WHERE u.id = occasion_unit;
    ELSE
        IF unit_json IS NULL THEN
            unit_json := '{}'::jsonb;
        END IF;
    END IF;

    -- Fetch occasions for the user based on the specified logic
    IF occasion_unit IS NOT NULL AND current_user_id IS NOT NULL THEN
        IF is_editor_view_on_occasion_bool OR (current_user_id IS NOT NULL AND (SELECT get_is_editor_on_unit(occasion_unit))) THEN
            -- If user is an editor or unit editor, get all occasions for the unit
            SELECT json_agg(json_build_object('id', o.id, 'title', o.title, 'link', o.link, 'start_time', o.start_time, 'end_time', o.end_time) ORDER BY o.start_time DESC)
            INTO user_occasions_json
            FROM (
                SELECT * FROM public.occasions
                WHERE unit = occasion_unit
                ORDER BY start_time DESC
                LIMIT 100
            ) o;
        ELSE
            -- Otherwise, get only occasions the user is explicitly on for that unit
            -- AND where they have privileged access (manager, editor, etc.)
            SELECT json_agg(
                json_build_object(
                    'id', o.id,
                    'title', o.title,
                    'link', o.link,
                    'start_time', o.start_time,
                    'end_time', o.end_time
                ) ORDER BY o.start_time DESC
            )
            INTO user_occasions_json
            FROM (
                 SELECT o.*
                 FROM public.occasions o
                 JOIN public.occasion_users ou ON ou.occasion = o.id
                 WHERE ou."user" = current_user_id
                 AND o.unit = occasion_unit
                 AND (
                     ou.is_manager IS TRUE
                     OR ou.is_editor IS TRUE
                     OR ou.is_editor_view IS TRUE
                     OR ou.is_editor_order IS TRUE
                     OR ou.is_editor_order_view IS TRUE
                 )
                 ORDER BY o.start_time DESC
                 LIMIT 100
            ) o;
        END IF;
    END IF;

    -- Fetch units for the user based on unit rights or occasion rights
    SELECT json_agg(jsonb_build_object('id', u.id, 'title', u.title) ORDER BY u.title)
    INTO user_units_json
    FROM public.units u
    WHERE u.organization = org_id AND (
        EXISTS (
            SELECT 1
            FROM public.unit_users uu
            WHERE uu.unit = u.id
            AND uu."user" = current_user_id
            AND uu.is_editor_view = TRUE
        )
        OR
        EXISTS (
            SELECT 1
            FROM public.occasions o
            JOIN public.occasion_users ou ON ou.occasion = o.id
            WHERE o.unit = u.id
            AND ou."user" = current_user_id
            AND (
                ou.is_manager IS TRUE
                OR ou.is_editor IS TRUE
                OR ou.is_editor_view IS TRUE
                OR ou.is_editor_order IS TRUE
                OR ou.is_editor_order_view IS TRUE
            )
        )
    );

    -- Fetch user information along with associated units and occasions
    SELECT row_to_json(ui)::jsonb || jsonb_build_object(
            'units', COALESCE(user_units_json, '[]'::jsonb),
            'occasions', COALESCE(user_occasions_json, '[]'::jsonb)
          )
      INTO user_info_json
    FROM public.user_info ui
    WHERE ui.id = current_user_id;

    -- Fetch organization info
    SELECT json_build_object(
        'title', title,
        'APP_NAME', data->>'APP_NAME',
        'PLATFORMS', data->'PLATFORMS',
        'DEFAULT_URL', data->>'DEFAULT_URL',
        'DEFAULT_LANGUAGE', data->>'DEFAULT_LANGUAGE',
        'IS_REGISTRATION_ENABLED', (data->>'IS_REGISTRATION_ENABLED')::boolean,
        'IS_UNIT_CREATION_ENABLED', (data->>'IS_UNIT_CREATION_ENABLED')::boolean,
        'IS_APP_SUPPORTED', (data->>'IS_APP_SUPPORTED')::boolean,
        'DEFAULT_UNIT', (data->>'DEFAULT_UNIT')::int,
        'REPRESENTATIVE_OCCASION', (data->>'REPRESENTATIVE_OCCASION')::int
    ) INTO org_json
    FROM public.organizations
    WHERE id = org_id;

    -- Fetch the user's groups for the specific occasion
    IF occasionId IS NOT NULL THEN
        user_groups_json := public.get_user_groups(occasionId);
    END IF;

    RETURN json_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'demo_read_only', public.can_read_demo_occasion(occasionId),
        'occasion_user', COALESCE(row_to_json(occasion_user)::jsonb, NULL),
        'unit_user', COALESCE(row_to_json(unit_user)::jsonb, NULL),
        'occasion', COALESCE(occasion_json, '{}'::jsonb),
        'unit', COALESCE(unit_json, '{}'::jsonb),
        'bank_accounts_admin', COALESCE(bank_account_ids, '{}'),
        'user_info', COALESCE(user_info_json, '{}'::jsonb),
        'organization', COALESCE(org_json::jsonb, '{}'::jsonb),
        'groups', COALESCE(user_groups_json, '{}'::jsonb)
    );
END;
$$;


-- Source: database/functions/others/get_occasion_by_link.sql
-- Create a function to get occasion by link and check for active orders
CREATE OR REPLACE FUNCTION public.get_occasion_by_link(link_param text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occ_record public.occasions;
    has_orders boolean;
    result jsonb;
BEGIN
    -- Legacy links may repeat across tenants after the canonical merge.
    -- This RPC supplies editor data, so resolve only inside the caller's tenant.
    SELECT o.* INTO occ_record
    FROM public.occasions o
    WHERE o.id = public.resolve_occasion_link_internal(link_param)
      AND o.organization = (
          SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()
      );

    -- Return null if not found
    IF occ_record IS NULL THEN
        RETURN NULL;
    END IF;

    IF public.is_demo_occasion(occ_record.id) AND NOT public.can_read_demo_occasion(occ_record.id) THEN
        RAISE insufficient_privilege USING MESSAGE='Demo access denied';
    END IF;

    IF NOT (public.get_is_editor_view_on_occasion(occ_record.id)
        OR public.get_is_manager_on_occasion(occ_record.id)
        OR public.get_is_admin_on_occasion(occ_record.id)) THEN
        RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
    END IF;

    -- 2. Check for active orders
    SELECT EXISTS (
        SELECT 1
        FROM eshop.orders
        WHERE occasion = occ_record.id
    ) INTO has_orders;

    -- 3. Merge the occasion record with the new boolean flag
    result := to_jsonb(occ_record) || jsonb_build_object('has_orders', has_orders);

    RETURN result;
END;
$$;


-- Source: database/functions/others/get_all_email_templates_via_occasion_link.sql
CREATE OR REPLACE FUNCTION public.get_all_email_templates_via_occasion_link(occasion_link text)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
BEGIN
    -- Canonical merges may contain the same legacy link in multiple tenants.
    SELECT o.id
    INTO v_occasion_id
    FROM public.occasions o
    WHERE o.id = public.resolve_occasion_link_internal(occasion_link)
      AND o.organization = (
        SELECT ui.organization
        FROM public.user_info ui
        WHERE ui.id = auth.uid()
      );

    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion not found for link: %', occasion_link;
    END IF;

    -- Call Unified Function
    RETURN public.get_entity_email_templates('occasion', v_occasion_id);
END;
$$;


-- Source: database/functions/eshop/get_report_ws.sql
CREATE OR REPLACE FUNCTION public.get_report_ws(occasion_link text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE r jsonb; invalid_payment boolean;
BEGIN
  WITH scope AS MATERIALIZED (
    SELECT o.id, o.title FROM public.occasions o
    JOIN public.user_info u ON u.organization = o.organization AND u.id = auth.uid()
    WHERE o.id = public.resolve_occasion_link_internal(occasion_link) AND public.get_is_editor_order_view_on_occasion(o.id)
  ), orders_scope AS MATERIALIZED (
    SELECT o.* FROM eshop.orders o JOIN scope s ON s.id = o.occasion
  ), payments AS MATERIALIZED (
    SELECT p.* FROM eshop.payment_info p
    WHERE p.id IN (SELECT payment_info FROM orders_scope)
  ), invalid AS (
    SELECT EXISTS (SELECT 1 FROM payments p JOIN eshop.orders o ON o.payment_info = p.id
      WHERE o.occasion IS DISTINCT FROM (SELECT id FROM scope)
         OR o.currency_code IS DISTINCT FROM p.currency_code) AS value
  ), transactions_scope AS MATERIALIZED (
    SELECT t.* FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info
    WHERE t.currency=p.currency_code
  ), order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM orders_scope GROUP BY 1,2
  ), payment_days AS (
    SELECT date::date AS day,currency::text AS currency,
      coalesce(sum(amount) FILTER (WHERE amount>0),0)::text AS received,
      coalesce(-sum(amount) FILTER (WHERE amount<0),0)::text AS returned
    FROM transactions_scope GROUP BY 1,2
  ), manual AS (
    SELECT t.payment_info, sum(t.amount) FILTER (WHERE t.transaction_type = 'manual' AND t.amount > 0) AS received
    FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info GROUP BY t.payment_info
  ), order_money AS (
    SELECT currency_code AS currency, sum(coalesce(price,0)) AS value
    FROM orders_scope GROUP BY currency_code
  ), payment_money AS (
    SELECT p.currency_code AS currency, sum(coalesce(p.paid,0)) AS received,
      sum(coalesce(p.returned,0)) AS returned, sum(coalesce(m.received,0)) AS manual,
      bool_or(p.deposit_amount IS NOT NULL) AS deposits,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(p.paid,0),p.deposit_amount) ELSE 0 END) AS deposit,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(p.paid,0)-p.deposit_amount,0) ELSE 0 END) AS beyond
    FROM payments p LEFT JOIN manual m ON m.payment_info=p.id GROUP BY p.currency_code
  ), money AS (
    SELECT coalesce(o.currency,p.currency)::text AS currency, coalesce(o.value,0) AS value,
      coalesce(p.received,0) AS received, coalesce(p.returned,0) AS returned,
      coalesce(p.manual,0) AS manual, coalesce(p.deposits,false) AS deposits,
      coalesce(p.deposit,0) AS deposit, coalesce(p.beyond,0) AS beyond
    FROM order_money o FULL JOIN payment_money p USING(currency)
  ), ticket_scope AS (
    SELECT t.* FROM eshop.tickets t JOIN scope s ON s.id=t.occasion
    WHERE EXISTS (SELECT 1 FROM eshop.order_product_ticket i WHERE i.ticket=t.id)
  ), valid_orders AS MATERIALIZED (
    SELECT * FROM orders_scope WHERE state IS DISTINCT FROM 'storno' AND state IS DISTINCT FROM 'waitlisted'
  ), valid_tickets AS MATERIALIZED (
    SELECT t.* FROM ticket_scope t
    WHERE t.state IS DISTINCT FROM 'storno' AND EXISTS (
      SELECT 1 FROM eshop.order_product_ticket i JOIN valid_orders o ON o.id=i."order"
      WHERE i.ticket=t.id
    )
  ), valid_order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM valid_orders GROUP BY 1,2
  ), order_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM orders_scope GROUP BY 1
  ), ticket_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM ticket_scope GROUP BY 1
  ), spots AS (
    SELECT count(*) AS total,count(*) FILTER (WHERE order_product_ticket IS NOT NULL) AS occupied,
      count(*) FILTER (WHERE order_product_ticket IS NULL) AS free
    FROM eshop.spots WHERE occasion IN (SELECT id FROM scope)
  ), products AS (
    SELECT p.id::text AS product_id,coalesce(p.title,'') AS product_title,
      pt.id::text AS type_id,pt.title AS type_title,count(*) AS confirmed_count
    FROM orders_scope o JOIN eshop.order_product_ticket i ON i."order"=o.id
    JOIN eshop.products p ON p.id=i.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
    WHERE o.state IN ('paid','sent','used') GROUP BY p.id,pt.id
  ), warnings AS (
    SELECT 'missing_order_price' AS code,count(*) AS count FROM orders_scope WHERE price IS NULL AND state IS DISTINCT FROM 'waitlisted' HAVING count(*)>0
    UNION ALL SELECT 'transaction_currency_mismatch',count(*) FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info WHERE t.currency<>p.currency_code HAVING count(*)>0
    UNION ALL SELECT 'negative_other_received',count(*) FROM money WHERE received-manual<0 HAVING count(*)>0
  )
  SELECT jsonb_build_object(
    'schema_version',1,'occasion',jsonb_build_object('id',s.id::text,'title',coalesce(s.title,'')),
    'generated_at',to_char(statement_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'spots',(SELECT to_jsonb(spots) FROM spots),
    'orders',jsonb_build_object('total',(SELECT count(*) FROM orders_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM order_states x),'[]'::jsonb)),
    'tickets',jsonb_build_object('total',(SELECT count(*) FROM ticket_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM ticket_states x),'[]'::jsonb)),
    'valid',jsonb_build_object(
      'orders',jsonb_build_object('total',(SELECT count(*) FROM valid_orders),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_orders GROUP BY 1) x),'[]'::jsonb)),
      'tickets',jsonb_build_object('total',(SELECT count(*) FROM valid_tickets),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_tickets GROUP BY 1) x),'[]'::jsonb)),
      'order_days',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM valid_order_days d),'[]'::jsonb)
    ),
    'money_by_currency',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'currency',currency,'current_order_value',value::text,'received',received::text,'returned',returned::text,
      'net_received',(received-returned)::text,'manual_received',manual::text,'other_received',(received-manual)::text,
      'has_deposits',deposits,'deposit_received_gross',deposit::text,'beyond_deposit_received_gross',beyond::text
    ) ORDER BY currency) FROM money),'[]'::jsonb),
    'timeline',jsonb_build_object(
      'order_timezone','Europe/Prague','payment_date_basis','transaction_date',
      'orders',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day) FROM order_days d),'[]'::jsonb),
      'payments',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM payment_days d),'[]'::jsonb)
    ),
    'products',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY type_id,product_id) FROM products p),'[]'::jsonb),
    'warnings',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY code) FROM warnings w),'[]'::jsonb)
  ), invalid.value INTO r,invalid_payment FROM scope s CROSS JOIN invalid;
  IF r IS NULL THEN RETURN jsonb_build_object('code',403,'message','Report unavailable or access denied.'); END IF;
  IF invalid_payment THEN RETURN jsonb_build_object('code',409,'message','Report payment allocation is inconsistent.'); END IF;
  RETURN jsonb_build_object('code',200,'data',public.format_occasion_report_text(r),'report',r);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('code',500,'message','Report could not be generated.');
END;
$$;
REVOKE ALL ON FUNCTION public.get_report_ws(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_report_ws(text) TO authenticated;


-- Source: database/functions/inventory/get_inventory_pools_by_occasion_link.sql
CREATE OR REPLACE FUNCTION public.get_inventory_pools_by_occasion_link(p_occasion_link text)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_occasion_data jsonb;
    v_pools_data jsonb;
    v_inventory_contexts_data jsonb;
    v_spots_data jsonb;
    result jsonb;
BEGIN
    -- Canonical merges may contain the same legacy link in multiple tenants.
    SELECT o.id
    INTO v_occasion_id
    FROM public.occasions o
    WHERE o.id = public.resolve_occasion_link_internal(p_occasion_link)
      AND o.organization = (
        SELECT ui.organization
        FROM public.user_info ui
        WHERE ui.id = auth.uid()
      );
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion with link % not found.', p_occasion_link;
    END IF;

    -- Permission check to ensure the user can view data for this occasion.
    IF NOT COALESCE((
        SELECT ou.is_editor_order_view
        FROM public.occasion_users ou
        WHERE ou."user" = auth.uid()
          AND ou.occasion = v_occasion_id
    ), false) THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Get the full occasion object
    SELECT to_jsonb(o) INTO v_occasion_data FROM public.occasions o WHERE id = v_occasion_id;

    -- Aggregate all inventory pools for the occasion, sorted by creation date.
    SELECT COALESCE(jsonb_agg(to_jsonb(ip) ORDER BY ip.created_at), '[]'::jsonb)
    INTO v_pools_data
    FROM public.inventory_pools ip
    WHERE ip.occasion = v_occasion_id;

    -- Aggregate all inventory_contexts for all pools of the occasion, sorted by the 'order' column.
    SELECT COALESCE(jsonb_agg(to_jsonb(ic) ORDER BY ic.order), '[]'::jsonb)
    INTO v_inventory_contexts_data
    FROM public.inventory_contexts ic
    WHERE ic.inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion = v_occasion_id);

    -- Aggregate all spots that belong to any context within the occasion's pools
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'secret', s.secret,
        'secret_expiration_time', s.secret_expiration_time,
        'order_product_ticket', s.order_product_ticket,
        'inventory_context', s.inventory_context,
        'resource', s.resource,
        'state', s.state
    ) ORDER BY s.id), '[]'::jsonb)
    INTO v_spots_data
    FROM eshop.spots s
    WHERE s.inventory_context IN (
        SELECT id FROM public.inventory_contexts WHERE inventory_pool IN (
            SELECT id FROM public.inventory_pools WHERE occasion = v_occasion_id
        )
    );

    -- Construct the final bundle object with the new data
    result := jsonb_build_object(
        'occasion', v_occasion_data,
        'pools', v_pools_data,
        'inventory_contexts', v_inventory_contexts_data,
        'spots', v_spots_data
    );

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;


-- Source: database/functions/eshop_forms/get_forms_by_link.sql
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
    IF NOT (get_is_editor_view_on_occasion(v_occasion_id) OR get_is_editor_order_view_on_occasion(v_occasion_id)) THEN
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
    LEFT JOIN (
        -- This subquery calculates all required counts in a single pass over the orders table.
        SELECT
            (data->>'form')::uuid AS form_key,
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE state = 'storno') AS storno,
            COUNT(*) FILTER (WHERE state IN ('paid', 'sent')) AS paid_or_sent,
            COUNT(*) FILTER (WHERE state = 'ordered') AS ordered
        FROM eshop.orders
        WHERE data->>'form' IS NOT NULL -- Ensure the key exists before casting
        GROUP BY form_key
    ) AS order_stats ON f.key = order_stats.form_key
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


-- Source: database/functions/eshop_forms/get_all_forms_with_fields.sql
CREATE OR REPLACE FUNCTION public.get_all_forms_with_fields(
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
    -- Find the ID of the occasion using its unique link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link)
      AND organization=(SELECT organization FROM public.user_info WHERE id=auth.uid());

    -- Step 2: If no occasion is found, return a 404 'Not Found' error.
    -- This handles cases where the occasion_link does not exist.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion not found'
        );
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- This assumes a function `get_is_editor_view_on_occasion` exists to check permissions.
    IF NOT public.get_is_editor_view_on_occasion(v_occasion_id)
       AND NOT public.get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view forms for this occasion.'
        );
    END IF;

    -- Step 4: Aggregate forms and their associated fields for the occasion into a JSONB array.
    -- For each form, a subquery aggregates its related form_fields.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
                'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
                'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'response_count', (
                -- Subquery to count the number of responses (orders) for each form.
                SELECT COUNT(*)
                FROM eshop.orders o
                WHERE (o.data->>'form')::uuid = f.key
            ),
            'fields', (
                -- Subquery to aggregate all form_fields associated with the current form.
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'type', ff.type,
                        'is_ticket_field', ff.is_ticket_field
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                WHERE ff.form = f.id
            )
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found for the occasion, return an empty JSON array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the aggregated JSON response with a 200 'OK' status code.
    RETURN jsonb_build_object(
        'code', 200,
        'data', forms_data
    );
END;
$$;


-- Source: database/functions/eshop_forms/duplicate_form_to_occasion_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_client_sync_v1(
  p_source_form_id bigint,p_target_occasion_link text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_source_occasion bigint; v_source_unit bigint;
  v_target bigint; v_begin jsonb; v_hash text; v_form bigint;
BEGIN
  SELECT f.occasion,o.unit INTO v_source_occasion,v_source_unit
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    WHERE f.id=p_source_form_id;
  SELECT o.id INTO v_target FROM public.occasions o
    WHERE o.id=public.resolve_occasion_link_internal(p_target_occasion_link);
  IF v_actor IS NULL OR v_source_occasion IS NULL OR v_target IS NULL
    OR NOT (public.get_is_editor_view_on_occasion(v_source_occasion)
      OR public.get_is_editor_view_on_unit(v_source_unit))
    OR NOT public.get_is_editor_on_occasion(v_target) THEN
    RAISE insufficient_privilege USING MESSAGE='form copy permission required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'sourceFormId',p_source_form_id,'targetOccasion',v_target)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.duplicate',v_target,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_form:=public.duplicate_form_to_occasion_internal_v1(
    p_source_form_id,p_target_occasion_link);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_target,
    'inventory.form.duplicate',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','insert',
      'safeLabel','Duplicated form','changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('formId',v_form));
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(bigint,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(bigint,text,uuid) TO authenticated;


-- Source: database/functions/others/get_occasion_seo_data.sql
-- Add RPC for SEO Data Retrieval
-- Accessed by public (anon) role to generate OG tags
CREATE OR REPLACE FUNCTION get_occasion_seo_data(p_link_slug TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with permissions of creator to access potentially restricted org data (for just title)
SET search_path = public, extensions
AS $$
DECLARE
    v_result JSON;
    v_occasion_id BIGINT;
    v_form_header TEXT;
BEGIN
    -- 1. Try to find occasion via Form Link
    SELECT occasion, header INTO v_occasion_id, v_form_header
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(p_link_slug)
    LIMIT 1;

    -- 2. If not found, try to find occasion via Occasion Link
    IF v_occasion_id IS NULL THEN
        SELECT id INTO v_occasion_id
        FROM occasions
        WHERE id = public.resolve_occasion_link_internal(p_link_slug)
        LIMIT 1;
    END IF;

    -- 3. If occasion found, fetch SEO data
    IF v_occasion_id IS NOT NULL THEN
        SELECT json_build_object(
            'title', o.title,
            'description', o.description,
            'form_description', v_form_header,
            'image', o.data->>'image',
            'org_title', org.title,
            'unit_title', u.title
        )
        INTO v_result
        FROM occasions o
        JOIN organizations org ON o.organization = org.id
        LEFT JOIN units u ON o.unit = u.id
        WHERE o.id = v_occasion_id;
    END IF;

    RETURN v_result;
END;
$$;

-- Grant access to anon
GRANT EXECUTE ON FUNCTION get_occasion_seo_data(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION get_occasion_seo_data(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_occasion_seo_data(TEXT) TO service_role;


-- Source: database/functions/synchronization/sync_source_via_http.sql
-- Sync occasions from remote Supabase instances via HTTP (replaces dblink version).
-- Uses the `http` PostgreSQL extension to call the remote's get_sync_occasions RPC.
-- No database password needed — only the public Supabase URL and anon key.
CREATE OR REPLACE FUNCTION public.sync_source_via_http(p_target_source_name TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    r_source RECORD;
    r_map RECORD;
    r_occ RECORD;
    v_response extensions.http_response;
    v_body jsonb;
    v_external_link TEXT;
    v_features JSONB;
    v_local_data JSONB;
    v_remaining_places INTEGER;
    v_local_id bigint;
    v_old_org bigint;
    v_count INTEGER := 0;
    v_synced_ids BIGINT[];
BEGIN
    -- Security Check
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    FOR r_source IN
        SELECT * FROM public.external_sync_sources
        WHERE (p_target_source_name IS NULL OR source_name = p_target_source_name)
    LOOP
        v_synced_ids := ARRAY[]::BIGINT[];

        FOR r_map IN SELECT * FROM public.external_sync_maps WHERE source_name = r_source.source_name
        LOOP
            -- Call remote RPC via HTTP
            SELECT * INTO v_response FROM extensions.http((
                'POST',
                format('%s/rest/v1/rpc/get_sync_occasions', r_source.supabase_url),
                ARRAY[
                    extensions.http_header('apikey', r_source.anon_key),
                    extensions.http_header('Authorization', format('Bearer %s', r_source.anon_key))
                ],
                'application/json',
                json_build_object(
                    'p_organization_id', r_map.remote_org_id,
                    'p_unit_id', r_map.remote_unit_id
                )::text
            )::extensions.http_request);

            IF v_response.status <> 200 THEN
                RAISE NOTICE 'HTTP call failed for source % map %: status=%, body=%',
                    r_source.source_name, r_map.id, v_response.status, left(v_response.content, 200);
                CONTINUE;
            END IF;

            v_body := v_response.content::jsonb;

            -- Iterate over returned occasions
            FOR r_occ IN
                SELECT
                    (elem->>'id')::bigint AS id,
                    elem->>'link' AS link,
                    elem->>'title' AS title,
                    elem->>'description' AS description,
                    (elem->'data') AS data,
                    (elem->>'start_time')::timestamptz AS start_time,
                    (elem->>'end_time')::timestamptz AS end_time,
                    (elem->>'is_open')::boolean AS is_open,
                    (elem->>'is_hidden')::boolean AS is_hidden,
                    (elem->>'is_promoted')::boolean AS is_promoted,
                    (elem->'features') AS features,
                    (elem->>'created_at')::timestamptz AS created_at,
                    elem->>'form_link' AS form_link
                FROM jsonb_array_elements(v_body) AS elem
            LOOP
                v_synced_ids := array_append(v_synced_ids, r_occ.id);
                v_remaining_places := (r_occ.data->>'remaining_places')::INTEGER;

                -- CACHE UPDATE
                INSERT INTO public.external_occasions_cache (external_id, link, remaining_places, raw_data, last_synced_at, source_name)
                VALUES (r_occ.id, r_occ.link, v_remaining_places, row_to_json(r_occ)::jsonb, NOW(), r_source.source_name)
                ON CONFLICT (source_name, external_id) DO UPDATE SET
                    link = EXCLUDED.link,
                    remaining_places = EXCLUDED.remaining_places,
                    raw_data = EXCLUDED.raw_data,
                    last_synced_at = NOW();

                -- Preserve Features (keep all except form)
                SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_features
                FROM jsonb_array_elements(r_occ.features) elem
                WHERE elem->>'code' <> 'form';

                -- Find existing form feature
                SELECT elem INTO v_local_data
                FROM jsonb_array_elements(r_occ.features) elem
                WHERE elem->>'code' = 'form'
                LIMIT 1;

                -- Determine external form link
                IF (v_local_data->>'use_external_form')::boolean = true OR
                   (v_local_data->>'formUseExternal')::boolean = true OR
                   (v_local_data->'data'->>'use_external_form')::boolean = true OR
                   (v_local_data->'data'->>'formUseExternal')::boolean = true
                THEN
                    v_external_link := COALESCE(
                        v_local_data->>'external_form_link',
                        v_local_data->>'formExternalLink',
                        v_local_data->'data'->>'external_form_link',
                        v_local_data->'data'->>'formExternalLink'
                    );
                ELSE
                    v_external_link := r_map.remote_link_base || '/form/' || COALESCE(r_occ.form_link, r_occ.link);
                END IF;

                -- Append enforced external form feature
                v_features := v_features || jsonb_build_array(jsonb_build_object(
                    'code', 'form',
                    'is_enabled', true,
                    'data', jsonb_build_object(
                        'use_external_form', true,
                        'external_form_link', v_external_link
                    )
                ));

                v_local_data := r_occ.data;
                IF v_local_data IS NULL THEN v_local_data := '{}'::jsonb; END IF;
                IF v_remaining_places IS NOT NULL THEN
                    v_local_data := jsonb_set(v_local_data, '{remaining_places}', to_jsonb(v_remaining_places));
                END IF;

                SELECT id, organization INTO v_local_id,v_old_org FROM public.occasions
                  WHERE external_source=r_source.source_name AND external_id=r_occ.id FOR UPDATE;
                IF v_local_id IS NOT NULL AND v_old_org IS DISTINCT FROM r_map.target_org_id THEN
                  RAISE EXCEPTION 'External occasion tenant cannot change'; END IF;
                -- OCCASION UPSERT
                INSERT INTO public.occasions (
                    link, title, description, data, start_time, end_time,
                    is_open, is_hidden, is_promoted,
                    organization, unit, features,
                    created_at, updated_at,
                    external_source, external_id
                )
                VALUES (
                    '', r_occ.title, r_occ.description, v_local_data,
                    r_occ.start_time, r_occ.end_time,
                    r_occ.is_open, r_occ.is_hidden, r_occ.is_promoted,
                    r_map.target_org_id, r_map.target_unit_id, v_features,
                    r_occ.created_at, NOW(),
                    r_source.source_name, r_occ.id
                )
                ON CONFLICT (external_source, external_id) DO UPDATE SET
                    title = EXCLUDED.title,
                    description = EXCLUDED.description,
                    data = EXCLUDED.data,
                    start_time = EXCLUDED.start_time,
                    end_time = EXCLUDED.end_time,
                    is_open = EXCLUDED.is_open,
                    is_hidden = EXCLUDED.is_hidden,
                    features = EXCLUDED.features,
                    organization = EXCLUDED.organization,
                    unit = EXCLUDED.unit,
                    updated_at = NOW()
                RETURNING id INTO v_local_id;
                UPDATE public.occasions SET link=public.reserve_public_link_internal(
                  'occasion',v_local_id,r_occ.link,link IS NULL OR link='') WHERE id=v_local_id;
                v_count := v_count + 1;
            END LOOP;
        END LOOP;

        -- DELETION: Remove occasions no longer present in remote
        IF array_length(v_synced_ids, 1) > 0 THEN
            DELETE FROM public.occasions
            WHERE external_source = r_source.source_name
              AND NOT (external_id = ANY(v_synced_ids));

            DELETE FROM public.external_occasions_cache
            WHERE source_name = r_source.source_name
              AND NOT (external_id = ANY(v_synced_ids));
        ELSE
            DELETE FROM public.occasions WHERE external_source = r_source.source_name;
            DELETE FROM public.external_occasions_cache WHERE source_name = r_source.source_name;
        END IF;

    END LOOP;
    RETURN format('Synced %s occasions from %s.', v_count, COALESCE(p_target_source_name, 'ALL Sources'));
EXCEPTION WHEN OTHERS THEN
    RETURN format('Error: %s', SQLERRM);
END;
$$;

-- Security Hardening
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.sync_source_via_http(text) TO service_role;


-- Source: database/functions/occasion_setup/drafts.sql
-- Drafts are private workspace objects, never public occasions.
CREATE TABLE IF NOT EXISTS public.occasion_setup_drafts (
  id uuid PRIMARY KEY,
  unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  author uuid NOT NULL REFERENCES auth.users(id),
  data jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(data) = 'object' AND octet_length(data::text) <= 262144),
  revision bigint NOT NULL DEFAULT 1,
  current_step integer NOT NULL DEFAULT 0 CHECK (current_step BETWEEN 0 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.occasion_setup_drafts DROP CONSTRAINT IF EXISTS occasion_setup_drafts_current_step_check;
ALTER TABLE public.occasion_setup_drafts ADD CONSTRAINT occasion_setup_drafts_current_step_check CHECK (current_step BETWEEN 0 AND 6);
CREATE INDEX IF NOT EXISTS occasion_setup_drafts_unit_idx ON public.occasion_setup_drafts(unit);
ALTER TABLE public.occasion_setup_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_setup_drafts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_drafts(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY updated_at DESC)
    FROM public.occasion_setup_drafts d WHERE unit = p_unit), '[]'::jsonb);
END $$;

-- Run the canonical creator inside a rollback-only subtransaction. Its
-- complete configuration survives in a PL/pgSQL variable, but no occasion,
-- form, product, reminders or other rows escape into the normal application.
-- PostgreSQL sequences may advance; those IDs are draft-local references.
CREATE OR REPLACE FUNCTION public.build_occasion_setup_configuration(p_unit bigint, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE configuration jsonb; organization_id bigint;
  provisional_link text := 'draft-' || p_id::text;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT organization INTO organization_id FROM public.units WHERE id = p_unit;
  BEGIN
    PERFORM public.update_occasion_internal_v1(jsonb_build_object(
      'unit',p_unit,'organization',organization_id,'title','',
      'link',provisional_link,'is_hidden',true,'is_open',false,
      'start_time',now()+interval '30 days','end_time',now()+interval '33 days'));
    SELECT item INTO configuration
      FROM jsonb_array_elements(public.get_occasion_setup_sources(p_unit)) item
      WHERE item->'occasion'->>'link' = provisional_link;
    IF configuration IS NULL THEN RAISE EXCEPTION 'Creation configuration missing'; END IF;
    RAISE EXCEPTION 'Rollback provisional creation' USING ERRCODE = 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN
    -- Variables retain their values while all writes in the block roll back.
    NULL;
  END;
  configuration := jsonb_set(configuration,'{occasion,link}','""'::jsonb);
  configuration := jsonb_set(configuration,'{forms}',coalesce((SELECT jsonb_agg(jsonb_set(f,'{link}','""'::jsonb))
    FROM jsonb_array_elements(configuration->'forms') f),'[]'::jsonb));
  RETURN configuration;
END $$;
REVOKE ALL ON FUNCTION public.build_occasion_setup_configuration(bigint,uuid) FROM PUBLIC,anon,authenticated;

-- Client-generated UUID makes canonical draft initialization safe to retry.
CREATE OR REPLACE FUNCTION public.create_occasion_setup_draft(p_id uuid, p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.occasion_setup_drafts(id,unit,organization,author)
    SELECT p_id,id,organization,auth.uid() FROM public.units WHERE id = p_unit
    ON CONFLICT (id) DO NOTHING;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id;
  IF d.unit IS DISTINCT FROM p_unit OR d.author IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (d.data ? 'defaultConfiguration') THEN
    configuration := public.build_occasion_setup_configuration(p_unit,p_id);
    UPDATE public.occasion_setup_drafts SET data =
      jsonb_build_object('defaultConfiguration',configuration,
        'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true)
      || d.data WHERE id = p_id RETURNING * INTO d;
  END IF;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.initialize_occasion_setup_draft_defaults(p_id uuid, p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'defaultConfiguration' THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  configuration := public.build_occasion_setup_configuration(d.unit,p_id);
  UPDATE public.occasion_setup_drafts SET data =
    jsonb_build_object('defaultConfiguration',configuration,
      'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true)
    || d.data, revision = revision+1, updated_at=now()
    WHERE id=p_id RETURNING * INTO d;
  RETURN to_jsonb(d);
END $$;
REVOKE ALL ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_occasion_setup_draft(p_id uuid, p_expected_revision bigint, p_data jsonb, p_step integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
  p_data := p_data - 'finalizedOccasion' - 'finalizeResponse';
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' OR octet_length(p_data::text) > 262144 OR p_step IS NULL OR p_step NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Invalid draft' USING ERRCODE = '22023'; END IF;
  IF d.data ? 'copy_locale' THEN p_data := jsonb_set(p_data,'{copy_locale}',d.data->'copy_locale'); END IF;
  IF p_data ? 'copy_locale' AND p_data->>'sourceId' IS NOT NULL
     AND coalesce((p_data->>'copy_title_edited')::boolean,false)=false AND coalesce(p_data->>'title','')='' THEN
    IF NOT public.can_copy_occasion_source((p_data->>'sourceId')::bigint) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint AND organization=d.organization) THEN
      RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
    IF d.revision=p_expected_revision+1 AND d.data->>'sourceId'=p_data->>'sourceId' THEN
      p_data := jsonb_set(p_data,'{title}',d.data->'title');
    ELSE
      p_data := jsonb_set(p_data,'{title}',to_jsonb(public.copy_occasion_title_internal(
        (SELECT title FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint),p_data->>'copy_locale')));
    END IF;
  END IF;
  IF d.revision = p_expected_revision + 1 AND d.data = p_data AND d.current_step = p_step THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001'; END IF;
  UPDATE public.occasion_setup_drafts SET data = p_data, current_step = p_step,
    revision = revision + 1, updated_at = now() WHERE id = p_id RETURNING * INTO d;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.delete_occasion_setup_draft(p_id uuid, p_unit bigint, p_expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF d.unit <> p_unit THEN RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501'; END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  DELETE FROM public.occasion_setup_drafts WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) TO authenticated;


-- Source: database/functions/eshop_forms/create_form_ws.sql
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


-- Source: database/functions/eshop/product_price_waves.sql
-- Shared terms only. The existing planned_changes queue remains the executor input.
CREATE TABLE IF NOT EXISTS eshop.product_price_waves (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  change_time timestamptz NOT NULL,
  revision bigint NOT NULL DEFAULT 1,
  UNIQUE(occasion,change_time)
);
ALTER TABLE eshop.product_price_waves ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE eshop.product_price_waves FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE eshop.product_price_waves_id_seq FROM PUBLIC,anon,authenticated;
ALTER TABLE eshop.planned_changes ADD COLUMN IF NOT EXISTS wave_id bigint
  REFERENCES eshop.product_price_waves(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS planned_product_wave_target_unique
  ON eshop.planned_changes(wave_id,subject_id,change_type)
  WHERE wave_id IS NOT NULL AND NOT applied;

CREATE OR REPLACE FUNCTION public.check_product_wave_editor(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.occasions o
    JOIN public.user_info ui ON ui.organization=o.organization
    WHERE o.id=p_occasion AND ui.id=auth.uid()) THEN
    RAISE insufficient_privilege USING MESSAGE='ORDER_EDITOR_REQUIRED';
  END IF;
  PERFORM public.check_is_editor_order_on_occasion(p_occasion);
END; $$;
REVOKE ALL ON FUNCTION public.check_product_wave_editor(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_product_price_wave(p_occasion_link text,p_change_time timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occasion bigint; v_wave eshop.product_price_waves%ROWTYPE;
BEGIN
  SELECT o.id INTO STRICT v_occasion FROM public.occasions o JOIN public.user_info ui
    ON ui.organization=o.organization WHERE o.id=public.resolve_occasion_link_internal(p_occasion_link) AND ui.id=auth.uid();
  PERFORM public.check_product_wave_editor(v_occasion);
  IF p_change_time IS NULL OR NOT isfinite(p_change_time) OR p_change_time<=clock_timestamp() THEN
    RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  INSERT INTO eshop.product_price_waves(occasion,change_time) VALUES(v_occasion,p_change_time)
    ON CONFLICT(occasion,change_time) DO NOTHING;
  SELECT * INTO STRICT v_wave FROM eshop.product_price_waves
    WHERE occasion=v_occasion AND change_time=p_change_time FOR UPDATE;
  -- Adopt existing unambiguous targets at this shared term without repricing.
  PERFORM 1 FROM eshop.products p WHERE p.occasion=v_occasion AND EXISTS(
    SELECT 1 FROM eshop.planned_changes pc WHERE pc.subject_id=p.id AND pc.occasion=v_occasion
      AND pc.change_time=p_change_time AND pc.change_type IN('products.price','products.is_hidden') AND NOT pc.applied)
    ORDER BY p.id FOR UPDATE;
  UPDATE eshop.planned_changes pc SET wave_id=v_wave.id
    WHERE pc.occasion=v_occasion AND pc.change_time=p_change_time AND NOT pc.applied AND pc.wave_id IS NULL
      AND pc.change_type IN('products.price','products.is_hidden') AND EXISTS(
        SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
        WHERE p.id=pc.subject_id AND p.occasion=v_occasion AND pt.occasion=v_occasion)
      AND (SELECT count(*) FROM eshop.planned_changes other WHERE other.subject_id=pc.subject_id
        AND other.change_type=pc.change_type AND other.change_time=pc.change_time AND NOT other.applied)=1;
  IF p_change_time<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  RETURN to_jsonb(v_wave);
END; $$;
REVOKE ALL ON FUNCTION public.create_product_price_wave(text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_product_price_wave(text,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_product_wave_target(
  p_wave_id bigint,p_product_id bigint,p_expected_wave_revision bigint,p_price numeric,p_is_hidden boolean,
  p_expected_price_revision bigint DEFAULT NULL,p_expected_visibility_revision bigint DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_wave eshop.product_price_waves%ROWTYPE; v_product eshop.products%ROWTYPE;
  v_price eshop.planned_changes%ROWTYPE; v_visibility eshop.planned_changes%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_wave FROM eshop.product_price_waves WHERE id=p_wave_id FOR UPDATE;
  PERFORM public.check_product_wave_editor(v_wave.occasion);
  IF v_wave.revision IS DISTINCT FROM p_expected_wave_revision THEN RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  IF v_wave.change_time<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  SELECT * INTO STRICT v_product FROM eshop.products WHERE id=p_product_id FOR UPDATE;
  IF v_product.occasion IS DISTINCT FROM v_wave.occasion OR NOT EXISTS(
    SELECT 1 FROM eshop.product_types WHERE id=v_product.product_type AND occasion=v_wave.occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='PRODUCT_OCCASION_MISMATCH'; END IF;
  IF v_wave.change_time<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  -- Lock in the same subject/plan order as the executor and single-product editor.
  PERFORM 1 FROM eshop.planned_changes WHERE subject_id=p_product_id AND wave_id=p_wave_id
    AND NOT applied ORDER BY id FOR UPDATE;
  SELECT * INTO v_price FROM eshop.planned_changes WHERE subject_id=p_product_id
    AND wave_id=p_wave_id AND change_type='products.price' AND NOT applied;
  SELECT * INTO v_visibility FROM eshop.planned_changes WHERE subject_id=p_product_id
    AND wave_id=p_wave_id AND change_type='products.is_hidden' AND NOT applied;
  IF v_price.revision IS DISTINCT FROM p_expected_price_revision OR
    v_visibility.revision IS DISTINCT FROM p_expected_visibility_revision THEN
    RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.planned_changes WHERE subject_id=p_product_id
    AND change_time=v_wave.change_time AND NOT applied AND wave_id IS DISTINCT FROM p_wave_id
    AND ((change_type='products.price' AND p_price IS NOT NULL) OR
         (change_type='products.is_hidden' AND p_is_hidden IS NOT NULL))) THEN
    RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  IF p_price IS NOT NULL THEN
    PERFORM public.validate_product_price(p_price,v_product.data,v_product.currency_code);
    IF v_price.id IS NULL THEN
      INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion,wave_id)
        VALUES('products.price',p_product_id,p_price::text,v_wave.change_time,v_wave.occasion,p_wave_id);
    ELSE
      UPDATE eshop.planned_changes SET new_value=p_price::text,failed_at=NULL,failure_code=NULL,revision=revision+1 WHERE id=v_price.id;
    END IF;
  ELSIF v_price.id IS NOT NULL THEN DELETE FROM eshop.planned_changes WHERE id=v_price.id;
  END IF;
  IF p_is_hidden IS NOT NULL THEN
    IF v_visibility.id IS NULL THEN
      INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion,wave_id)
        VALUES('products.is_hidden',p_product_id,p_is_hidden::text,v_wave.change_time,v_wave.occasion,p_wave_id);
    ELSE
      UPDATE eshop.planned_changes SET new_value=p_is_hidden::text,failed_at=NULL,failure_code=NULL,revision=revision+1 WHERE id=v_visibility.id;
    END IF;
  ELSIF v_visibility.id IS NOT NULL THEN DELETE FROM eshop.planned_changes WHERE id=v_visibility.id;
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.save_product_wave_target(bigint,bigint,bigint,numeric,boolean,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_product_wave_target(bigint,bigint,bigint,numeric,boolean,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.move_product_price_wave(p_wave_id bigint,p_expected_revision bigint,p_change_time timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_wave eshop.product_price_waves%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_wave FROM eshop.product_price_waves WHERE id=p_wave_id FOR UPDATE;
  PERFORM public.check_product_wave_editor(v_wave.occasion);
  IF v_wave.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  IF p_change_time IS NULL OR NOT isfinite(p_change_time) OR p_change_time<=clock_timestamp() THEN
    RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.planned_changes WHERE wave_id=p_wave_id AND applied) THEN
    RAISE invalid_parameter_value USING MESSAGE='WAVE_ALREADY_APPLIED'; END IF;
  PERFORM 1 FROM eshop.products WHERE id IN(SELECT subject_id FROM eshop.planned_changes
    WHERE wave_id=p_wave_id AND NOT applied) ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eshop.planned_changes WHERE wave_id=p_wave_id AND NOT applied ORDER BY subject_id,id FOR UPDATE;
  IF EXISTS(SELECT 1 FROM eshop.planned_changes target JOIN eshop.planned_changes other
    ON other.subject_id=target.subject_id AND other.change_type=target.change_type
    WHERE target.wave_id=p_wave_id AND NOT target.applied AND NOT other.applied
      AND other.wave_id IS DISTINCT FROM p_wave_id AND other.change_time=p_change_time) THEN
    RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.planned_changes WHERE wave_id=p_wave_id AND applied) THEN
    RAISE invalid_parameter_value USING MESSAGE='WAVE_ALREADY_APPLIED'; END IF;
  IF p_change_time<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  UPDATE eshop.product_price_waves SET change_time=p_change_time,revision=revision+1 WHERE id=p_wave_id RETURNING * INTO v_wave;
  UPDATE eshop.planned_changes SET change_time=p_change_time,revision=revision+1,failed_at=NULL,failure_code=NULL
    WHERE wave_id=p_wave_id AND NOT applied;
  RETURN to_jsonb(v_wave);
END; $$;
REVOKE ALL ON FUNCTION public.move_product_price_wave(bigint,bigint,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.move_product_price_wave(bigint,bigint,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_product_price_wave(p_wave_id bigint,p_expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_wave eshop.product_price_waves%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_wave FROM eshop.product_price_waves WHERE id=p_wave_id FOR UPDATE;
  PERFORM public.check_product_wave_editor(v_wave.occasion);
  IF v_wave.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  PERFORM 1 FROM eshop.products WHERE id IN(SELECT subject_id FROM eshop.planned_changes
    WHERE wave_id=p_wave_id AND NOT applied) ORDER BY id FOR UPDATE;
  DELETE FROM eshop.planned_changes WHERE wave_id=p_wave_id AND NOT applied;
  DELETE FROM eshop.product_price_waves WHERE id=p_wave_id;
END; $$;
REVOKE ALL ON FUNCTION public.cancel_product_price_wave(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_product_price_wave(bigint,bigint) TO authenticated;


-- Source: database/functions/eshop/get_blueprint_for_edit.sql
CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprint_id BIGINT;
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    valid_spots JSONB;
    occasion_id BIGINT;
BEGIN
    -- Resolve occasion_id using occasion_link
    SELECT id
    INTO occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Check if occasion_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion link does not exist');
    END IF;

    -- Authorization check
    IF (SELECT get_is_editor_order_view_on_occasion(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    -- Fetch the first blueprint_id for the occasion
    SELECT id
    INTO blueprint_id
    FROM eshop.blueprints
    WHERE occasion = occasion_id
    ORDER BY id
    LIMIT 1;

    -- Check if a blueprint exists for the occasion
    IF blueprint_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No blueprint found for this occasion');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Fetch valid spot IDs
    SELECT jsonb_agg((obj->>'id')::BIGINT)
    INTO valid_spots
    FROM jsonb_array_elements(
        (SELECT objects FROM eshop.blueprints WHERE id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    -- Fetch enriched spots data
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
          WHEN t.state = 'used' THEN 'used'
          WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
          WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
          ELSE 'available'
        END
      )
    )
    INTO spotsData
    FROM eshop.spots s
    LEFT JOIN eshop.order_product_ticket opt ON s.order_product_ticket = opt.id
    LEFT JOIN eshop.tickets t ON opt.ticket = t.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = occasion_id;

    -- Fetch all products of type "spot", "taxi", "food"
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'type', pt.type,
        'description', pt.description,
        'product_type', p.product_type,
        'currency_code', p.currency_code
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    -- Fetch relevant tickets associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND t.occasion = occasion_id;

    -- Fetch relevant orders associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'order_symbol', o.order_symbol,
        'order_sequence', o.order_sequence,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note')
    ))
    INTO ordersData
    FROM eshop.orders o
    JOIN eshop.order_product_ticket opt ON opt."order" = o.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
            'id', opt.id,
            'order', opt."order",
            'product', opt.product,
            'ticket', opt.ticket,
            'created_at', opt.created_at
        ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    -- Add relevant tickets data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{tickets}',
        COALESCE(ticketsData, '[]'::jsonb)
    );

    -- Add relevant orders data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{orders}',
        COALESCE(ordersData, '[]'::jsonb)
    );

    -- Add relevant order-product-ticket data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{order_product_ticket}',
        COALESCE(orderProductTicketsData, '[]'::jsonb)
    );

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

-- Source: database/functions/eshop/get_products_and_types_for_occasion.sql
CREATE OR REPLACE FUNCTION public.get_products_and_types_for_edit(occasion_link text)
RETURNS json LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  product_types json;
  products json;
  inventory_pools_data json;
  inventory_contexts_data json;
  product_inventory_contexts_data json;
  forms_data json;
  occ_id bigint;
BEGIN
  -- Resolve occasion_id from the provided occasion_link
  SELECT id
    INTO occ_id
  FROM public.occasions
  WHERE id = public.resolve_occasion_link_internal(occasion_link)
    AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());

  -- If the occasion link is invalid, raise an exception.
  IF occ_id IS NULL THEN
    RAISE EXCEPTION 'Occasion not found for link: %', occasion_link;
  END IF;

  -- Verify if the current user is an editor for the order's occasion
  IF NOT get_is_editor_order_view_on_occasion(occ_id) THEN
      RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this.');
  END IF;

-- Fetch all product types for the given occasion
  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type,
             'title', pt.title
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = occ_id;

  -- Fetch all products for the given occasion, including form IDs
  SELECT json_agg(
           json_build_object(
             'id', p.id,
             'title', p.title,
             'description', p.description,
             'short_title', p.data->>'short_title',
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'price_changes', (SELECT COALESCE(json_agg(pc ORDER BY pc.change_time,pc.id),'[]'::json)
               FROM eshop.planned_changes pc WHERE pc.subject_id=p.id AND pc.change_type='products.price' AND NOT pc.applied),
             'visibility_changes', (SELECT COALESCE(json_agg(pc ORDER BY pc.change_time,pc.id),'[]'::json)
               FROM eshop.planned_changes pc WHERE pc.subject_id=p.id AND pc.change_type='products.is_hidden' AND NOT pc.applied),
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'order', p."order",
             'maximum', p.maximum,
             'form_ids', (
               SELECT COALESCE(json_agg(DISTINCT ff.form), '[]'::json)
               FROM public.form_fields ff
               WHERE ff.product_type = p.product_type
             ),
             'ordered_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               WHERE opt.product = p.id
             ),
             'paid_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'paid'
             ),
             'sent_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'sent'
             )
           )
         )
    INTO products
  FROM eshop.products p
  WHERE p.product_type IN (
    SELECT pt.id
    FROM eshop.product_types pt
    WHERE pt.occasion = occ_id
  );

  -- Fetch all inventory pools for the occasion
  SELECT json_agg(ip.*)
  INTO inventory_pools_data
  FROM public.inventory_pools ip
  WHERE ip.occasion = occ_id;

  -- Fetch all inventory contexts for the occasion
  SELECT json_agg(ic.*)
  INTO inventory_contexts_data
  FROM public.inventory_contexts ic
  JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
  WHERE ip.occasion = occ_id;

  -- Fetch all links between products and inventory contexts for the occasion
  SELECT json_agg(pic.*)
  INTO product_inventory_contexts_data
  FROM eshop.product_inventory_contexts pic
  JOIN eshop.products p ON pic.product = p.id
  JOIN eshop.product_types pt ON p.product_type = pt.id
  WHERE pt.occasion = occ_id;

  -- Fetch only the id, title, and link for each form associated with the occasion
  SELECT json_agg(
           json_build_object(
             'id', f.id,
             'title', f.title,
             'link', f.link
           )
         )
    INTO forms_data
  FROM public.forms f
  WHERE f.occasion = occ_id;

  RETURN json_build_object(
    'server_time', clock_timestamp(),
    'price_waves', (SELECT COALESCE(json_agg(w ORDER BY w.change_time,w.id),'[]'::json)
      FROM eshop.product_price_waves w WHERE w.occasion=occ_id AND (w.change_time>clock_timestamp() OR
        EXISTS(SELECT 1 FROM eshop.planned_changes pc WHERE pc.wave_id=w.id AND NOT pc.applied))),
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json),
    'inventory_pools', COALESCE(inventory_pools_data, '[]'::json),
    'inventory_contexts', COALESCE(inventory_contexts_data, '[]'::json),
    'product_inventory_contexts', COALESCE(product_inventory_contexts_data, '[]'::json),
    'forms', COALESCE(forms_data, '[]'::json)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_products_and_types_for_edit(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_products_and_types_for_edit(text) TO authenticated;


-- Source: database/functions/eshop_orders/update_scan_code.sql
DROP FUNCTION IF EXISTS update_scan_code(text, text);

CREATE OR REPLACE FUNCTION update_scan_code(
    occasion_link TEXT,
    new_scan_code TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id BIGINT;
    occasions_hidden_id BIGINT;
BEGIN
    -- 1. Retrieve occasion_id using occasion_link
    SELECT id
    INTO occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- 2. Check if occasion_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion link does not exist.'
        );
    END IF;

    -- 3. Verify if the user is an editor on the occasion
    IF NOT get_is_editor_order_on_occasion(occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to edit this occasion.'
        );
    END IF;

    -- 4. Check if occasions_hidden exists for the occasion
    SELECT o.occasion_hidden
    INTO occasions_hidden_id
    FROM public.occasions o
    WHERE o.id = occasion_id;

    IF occasions_hidden_id IS NOT NULL THEN
        -- Update existing scan_code
        UPDATE public.occasions_hidden
        SET secret = new_scan_code
        WHERE id = occasions_hidden_id;
    ELSE
        -- Insert new occasions_hidden record
        INSERT INTO public.occasions_hidden (secret)
        VALUES (new_scan_code)
        RETURNING id INTO occasions_hidden_id;

        -- Update the occasion to link to the new occasions_hidden
        UPDATE public.occasions
        SET occasion_hidden = occasions_hidden_id
        WHERE id = occasion_id;
    END IF;

    -- 5. Return a success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Scan code updated successfully.'
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;


-- Source: database/functions/eshop_orders/get_scan_code.sql
DROP FUNCTION IF EXISTS  get_scan_code(text);

CREATE OR REPLACE FUNCTION get_scan_code(
    occasion_link TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id BIGINT;
    current_scan_code TEXT;
BEGIN
    -- 1. Retrieve occasion_id using occasion_link
    SELECT id
    INTO occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- 2. Check if occasion_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion link does not exist.'
        );
    END IF;

    -- 3. Verify if the user is an editor on the occasion
    IF NOT get_is_editor_order_view_on_occasion(occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view scan code for this occasion.'
        );
    END IF;

    -- 4. Retrieve the scan_code from the occasions_hidden table via the foreign key
    SELECT oh.secret
    INTO current_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    -- 4.a. Handle case where scan_code is not found
    IF current_scan_code IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Scan code not found for the specified occasion.'
        );
    END IF;

    -- 5. Return the scan_code
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Scan code retrieved successfully.',
        'scan_code', current_scan_code
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;


-- Source: database/functions/eshop_orders/get_orders.sql
CREATE OR REPLACE FUNCTION public.get_orders(
    p_occasion_link TEXT,
    p_form_link TEXT DEFAULT NULL,
    p_options JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_form_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    ordersHistoryData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
    usersData JSONB; -- ADDED: Variable for user info data
BEGIN
    -- This function retrieves order and reservation details for a given occasion.
    -- It can conditionally include related data like spots, history, and users.
    --
    -- 'include_orders_history': If true, it fetches 'orders_history' and the
    --                           associated 'users' who created those history records.

    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE id = public.resolve_occasion_link_internal(p_occasion_link)
          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());
    ELSE
        SELECT occasion, id
        INTO v_occasion_id, v_form_id
        FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_form_link)
          AND occasion IN (SELECT o.id FROM public.occasions o WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()));
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT get_is_editor_order_view_on_occasion(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Conditionally fetch spots based on p_options for optimization
    IF (p_options->>'include_spots')::BOOLEAN = TRUE THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'title', s.title,
            'product', s.product,
            'order_product_ticket', s.order_product_ticket,
            'state', CASE
                WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
                WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
                ELSE 'available'
            END
        ))
        INTO spotsData
        FROM eshop.spots s
        WHERE s.occasion = v_occasion_id
          AND s.order_product_ticket IS NOT NULL;
    END IF;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden,
        'data', t.data
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'participant_capacity',f.participant_capacity,
        'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,
        'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),
        'registrationMode',public.get_form_registration_mode_internal(f.id),
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Fetch orders, conditionally filtering by form link
    IF v_form_id IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',public.get_waitlist_summary_internal(o.id)->'allowedActions',
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id AND o.form = v_form_id;
    ELSE
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',public.get_waitlist_summary_internal(o.id)->'allowedActions',
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id;
    END IF;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object('id', opt.id, 'order', opt."order", 'product', opt.product, 'ticket', opt.ticket))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
        'deposit_deadline', pi.deposit_deadline, 'paid', pi.paid, 'returned', pi.returned, 'deadline', pi.deadline, 'currency_code', pi.currency_code, 'data', pi.data,
        'bank_sync_warning', public.bank_sync_warning(pi.bank_account)
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        WHERE order_obj->>'payment_info' IS NOT NULL
    );

    -- Conditionally fetch orders history and related users based on p_options
    IF (p_options->>'include_orders_history')::BOOLEAN = TRUE THEN
        -- First, fetch the history records
        WITH order_ids AS (
            SELECT (order_obj->>'id')::BIGINT AS id
            FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', oh.id, 'created_at', oh.created_at, 'created_by', oh.created_by, 'data', oh.data,
            'order', oh."order", 'order_symbol', (SELECT o.order_symbol FROM eshop.orders o WHERE o.id=oh."order"), 'order_sequence', (SELECT o.order_sequence FROM eshop.orders o WHERE o.id=oh."order"), 'state', oh.state, 'price', oh.price, 'currency_code', oh.currency_code
        ))
        INTO ordersHistoryData
        FROM eshop.orders_history oh
        WHERE oh."order" IN (SELECT id FROM order_ids);

        -- Second, fetch the unique users who created those history records
        WITH user_ids AS (
            SELECT DISTINCT (history_obj->>'created_by')::UUID AS id
            FROM jsonb_array_elements(COALESCE(ordersHistoryData, '[]'::jsonb)) history_obj
            WHERE history_obj->>'created_by' IS NOT NULL
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', ui.id,
            'name', ui.name,
            'surname', ui.surname,
            'email_readonly', ui.email_readonly
        ))
        INTO usersData
        FROM public.user_info ui
        WHERE ui.id IN (SELECT id FROM user_ids);
    END IF;


    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'occasion_id', v_occasion_id,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb),
            'orders_history', COALESCE(ordersHistoryData, '[]'::jsonb),
            'users', COALESCE(usersData, '[]'::jsonb)
        )
    );
END;
$$;


-- Source: database/functions/eshop_orders/get_orders_tab_data.sql
CREATE OR REPLACE FUNCTION public.get_orders_tab_data(
    p_occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
BEGIN

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    -- No orders means no delivery status. Do not resolve an ambiguous event slug.
    RETURN (v_orders_data->'data') || jsonb_build_object('forms', v_forms_data->'data', 'email_delivery',
      CASE WHEN jsonb_array_length(v_orders_data#>'{data,orders}') = 0
        THEN '{}'::jsonb
        ELSE public.get_order_email_summaries(
          (v_orders_data->>'occasion_id')::bigint,
          ARRAY(SELECT (ord->>'id')::bigint
            FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord))
      END);
END;
$$;


-- Source: database/functions/others/create_occasion_domain_command_internal_v1.sql
CREATE OR REPLACE FUNCTION public.create_occasion_domain_command_internal_v1(p_command_id uuid, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_unit bigint; v_organization bigint;
  v_occasion bigint; v_begin jsonb; v_hash text; v_commit public.client_commits%ROWTYPE;
  v_entity jsonb;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config)<>'object'
    OR octet_length(p_config::text)>1048576
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_config) key WHERE key NOT IN
      ('id','start_time','end_time','is_open','is_hidden','is_promoted','link','title',
       'description','data','services','organization','unit','features','form_link',
       'has_orders','stats'))
    OR p_config->>'id' IS NOT NULL
    OR nullif(btrim(p_config->>'title'),'') IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid occasion aggregate'; END IF;
  v_unit:=NULLIF(p_config->>'unit','')::bigint;
  v_organization:=NULLIF(p_config->>'organization','')::bigint;
  IF v_actor IS NULL OR v_unit IS NULL OR v_organization IS NULL
    OR NOT EXISTS (SELECT 1 FROM public.units u
      WHERE u.id=v_unit AND u.organization=v_organization)
    OR NOT (public.get_is_manager_on_unit(v_unit)
      OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(p_config::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'occasion.create',v_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.update_occasion_internal_v1(p_config);
  SELECT o.id,to_jsonb(o)||jsonb_build_object('aggregate_version',1)
    INTO v_occasion,v_entity FROM public.occasions o
    WHERE o.id=currval(pg_get_serial_sequence('public.occasions','id'));
  IF v_occasion IS NULL THEN
    RAISE data_exception USING MESSAGE='occasion create returned no aggregate'; END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion','occasion',v_occasion,v_occasion::text,1);
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT v_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'occasion.create','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'occasion',v_occasion::text,'insert',
    left(v_entity->>'title',240),ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object(
      'occasionId',v_occasion,'occasion',v_entity),
    'mutation',jsonb_build_object('commandId',p_command_id,
      'receiptId',p_command_id,'commitId',v_commit.commit_id,'replayed',false,
      'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $function$;
REVOKE ALL ON FUNCTION public.create_occasion_domain_command_internal_v1(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/occasion_setup/finalize.sql
-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 blueprint_id bigint; objects jsonb := '[]'; obj jsonb; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := d.data;
 source_id := (payload->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 IF payload->'ticketDraft' IS NOT NULL AND payload->'ticketDraft'<>'null'::jsonb THEN features := features || jsonb_build_array((payload->'ticketDraft')-'layout'); END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN features := features || '[{"code":"form","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'features',features,'data',jsonb_build_object('client_sync_v1',false));
 PERFORM public.update_occasion_internal_v1(config);
 new_id := currval(pg_get_serial_sequence('public.occasions','id'));
 SELECT o.features INTO features FROM public.occasions o WHERE o.id=new_id;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view)
 VALUES(new_id,auth.uid(),true,true,true,true,true);
 form_data := payload->'formDraft';
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Every field/product is newly owned by this occasion. Retain a local mapping
  -- for seats that referred to draft/source product IDs.
  FOR field IN SELECT value FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) LOOP
   pt := coalesce(nullif(field->'product_type_data','null'::jsonb),field->'product_type');
   IF jsonb_typeof(pt)<>'object' THEN pt := NULL; END IF;
   field := field - 'id' - 'form' - 'product_type';
   IF pt IS NOT NULL AND pt<>'null'::jsonb THEN
    old_products := old_products || coalesce(pt->'products','[]');
    products := '[]';
    FOR product IN SELECT value FROM jsonb_array_elements(coalesce(pt->'products','[]')) LOOP
     products := products || jsonb_build_array(product-'id'-'occasion'-'product_type');
    END LOOP;
    field := (field-'product_type_data') || jsonb_build_object('product_type',(pt-'id'-'occasion') || jsonb_build_object('products',products));
   END IF;
   old_types := old_types || jsonb_build_array(pt->'id');
   fields := fields || jsonb_build_array(field);
  END LOOP;
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint'-'bank_account') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(nullif(form_data->>'link',''),(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',false,'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  IF jsonb_array_length(old_types)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_types)-1 LOOP
    IF old_types->>idx IS NOT NULL THEN type_map := type_map || jsonb_build_object(old_types->>idx,result->'form_fields'->idx->'product_type'->'id'); END IF;
   END LOOP;
  END IF;
  SELECT coalesce(jsonb_agg(p ORDER BY field_order,product_order),'[]') INTO new_products
  FROM (SELECT p,ff.ordinality field_order,pp.ordinality product_order
   FROM jsonb_array_elements(result->'form_fields') WITH ORDINALITY ff(f,ordinality)
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(ff.f->'product_type'->'products','[]')) WITH ORDINALITY pp(p,ordinality)) x;
  IF jsonb_array_length(old_products)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_products)-1 LOOP
    IF old_products->idx->>'id' IS NOT NULL THEN product_map := product_map || jsonb_build_object(old_products->idx->>'id',new_products->idx->'id'); END IF;
   END LOOP;
  END IF;
  IF jsonb_array_length(coalesce(payload->'blueprintObjects','[]'))>0 THEN
   FOR obj IN SELECT value FROM jsonb_array_elements(payload->'blueprintObjects') LOOP
    obj := obj-'id'-'order_product_ticket'-'secret';
    IF obj->>'product' IS NOT NULL THEN obj := jsonb_set(obj,'{product}',coalesce(product_map->(obj->>'product'),'null'::jsonb)); END IF;
    objects := objects || jsonb_build_array(obj);
   END LOOP;
   result := public.update_blueprint_internal_v1(jsonb_build_object('occasion',new_id,'organization',d.organization,
    'title',payload->>'blueprintTitle','configuration',jsonb_build_object('dimensions',jsonb_build_object(
     'width',coalesce((payload->>'blueprintWidth')::numeric,12),'height',coalesce((payload->>'blueprintHeight')::numeric,8))),
    'groups',coalesce(payload->'blueprintGroups','[]'),'objects',objects,'background_svg',payload->>'blueprintBackground'));
   IF (result->>'code')::int NOT IN (200,201) THEN RAISE EXCEPTION '%',result; END IF;
   blueprint_id := (result->>'blueprint_id')::bigint;
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features := features || '[{"code":"blueprint","is_enabled":true}]';
  END IF;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft';
  SELECT jsonb_set(pt,'{layout,templates}',jsonb_object_agg(t.key,
    jsonb_set(t.value,'{elements}',coalesce((SELECT jsonb_agg(CASE WHEN e->>'binding'='productType'
      THEN jsonb_set(e,'{productTypeId}',coalesce(type_map->(e->>'productTypeId'),'null'::jsonb)) ELSE e END ORDER BY n)
      FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)),'[]'::jsonb))))
   INTO pt FROM jsonb_each(pt->'layout'->'templates') t;
  features := (SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN pt ELSE f END) FROM jsonb_array_elements(features) f);
 END IF;
 PERFORM public.validate_ticket_layout_references(new_id,f->'layout') FROM jsonb_array_elements(features) f WHERE f ? 'layout';
 final_features := features;
 UPDATE public.occasions SET features=final_features WHERE id=new_id;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN
  INSERT INTO public.events(occasion,title,start_time,end_time,description)
  SELECT new_id,e->>'title',(e->>'start_time')::timestamptz,(e->>'end_time')::timestamptz,e->>'description'
  FROM jsonb_array_elements(coalesce(payload->'sourceProgram','[]')) e;
 END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN
  INSERT INTO public.information(occasion,unit,title,description,type,data)
  SELECT new_id,d.unit,i->>'title',i->>'description',i->>'type',i->'data'
  FROM jsonb_array_elements(coalesce(payload->'sourceInformation','[]')) i;
 END IF;
 IF coalesce((payload->>'copyEmails')::boolean,false) AND source_id IS NOT NULL THEN
  INSERT INTO public.email_templates(occasion,unit,organization,code,title,subject,html)
  SELECT new_id,d.unit,d.organization,code,title,subject,html FROM public.email_templates WHERE occasion=source_id;
 END IF;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id)));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;


-- Source: database/functions/eshop_waitlist/capabilities.sql
-- Only visible name/surname definitions in this form can label a ticket.
CREATE OR REPLACE FUNCTION public.get_waitlist_ticket_display_name_internal(p_form bigint,p_answers jsonb,p_contact jsonb DEFAULT '{}')
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(nullif((SELECT string_agg(btrim(answer.value#>>'{}'),' ' ORDER BY CASE definition.type WHEN 'name' THEN 0 ELSE 1 END,definition."order" NULLS LAST,definition.id)
 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_answers->'fields')='array' THEN p_answers->'fields' ELSE '[]' END) field
 CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(field)='object' THEN field ELSE '{}' END) answer
 JOIN public.form_fields definition ON definition.id::text=answer.key
 WHERE definition.form=p_form AND definition.is_ticket_field AND NOT definition.is_hidden
 AND definition.type IN ('name','surname') AND jsonb_typeof(answer.value)='string' AND btrim(answer.value#>>'{}')<>''),''),
 nullif(btrim(concat_ws(' ',nullif(btrim(p_contact->>'name'),''),nullif(btrim(p_contact->>'surname'),''))),''));
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_ticket_display_name_internal(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_effective_waitlist_ticket_lifecycle_internal(p_ticket bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN t.state='storno' THEN CASE WHEN t.ticket_symbol IS NULL THEN 'withdrawn' ELSE 'cancelled' END
 WHEN t.state IS DISTINCT FROM 'waitlisted' THEN 'admitted'
 WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id WHERE s.ticket_id=t.id AND s.outcome='pending' AND w.expires_at>clock_timestamp()) THEN 'offered'
 ELSE coalesce((SELECT CASE s.outcome WHEN 'expired' THEN 'offer_expired' WHEN 'declined' THEN 'offer_declined' WHEN 'cancelled' THEN 'offer_cancelled' WHEN 'pending' THEN 'offer_expired' ELSE 'waiting' END
 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id WHERE s.ticket_id=t.id ORDER BY w.created_at DESC,s.updated_at DESC,s.id DESC LIMIT 1),'waiting') END
 FROM eshop.tickets t WHERE t.id=p_ticket;
$$;
REVOKE ALL ON FUNCTION public.get_effective_waitlist_ticket_lifecycle_internal(bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.check_waitlist_scope_internal(p_order bigint,p_offer uuid,p_token text,p_actor uuid,p_operation text)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; c eshop.waitlist_capabilities; occ public.occasions;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order; SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 IF o.id IS NULL OR o.form IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_actor IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=o.occasion AND "user"=p_actor AND is_editor_order) THEN
  IF p_offer IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=p_offer AND order_id=p_order AND form_id=o.form) THEN
   RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF; RETURN o.form;
 END IF;
 IF p_operation IN ('send','cancel','proposal') OR p_token IS NULL OR length(p_token)<>64 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO c FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND organization_id=occ.organization AND form_id=o.form AND order_id=o.id AND (revoked_at IS NULL OR p_operation='read')
 AND ((p_operation='withdraw' AND kind='manage' AND o.state='waitlisted') OR
 (p_operation IN ('read','accept','decline') AND kind='offer' AND offer_id=p_offer));
 IF c.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Expired offer links may read their own terminal state; writers recheck time under locks.
 IF p_operation<>'read' AND c.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 RETURN o.form;
END $$;
CREATE OR REPLACE FUNCTION public.get_waitlist_summary_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH effective AS (SELECT public.get_effective_waitlist_ticket_lifecycle_internal(person.id) lifecycle
 FROM public.get_order_tickets_internal(p_order) person), p AS (SELECT lifecycle,count(*) n FROM effective GROUP BY lifecycle),
 s AS (SELECT count(*) n,min(w.expires_at) expiry FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers w ON w.id=x.offer_id
 JOIN public.get_order_tickets_internal(p_order) person ON person.id=x.ticket_id WHERE true AND x.outcome='pending' AND w.expires_at>clock_timestamp())
 SELECT jsonb_build_object('counts',coalesce((SELECT jsonb_object_agg(lifecycle,n) FROM p),'{}'),
 'pendingPlaces',s.n,'earliestExpiry',s.expiry,'isActive',CASE WHEN o.state='waitlisted' THEN
  coalesce((SELECT n>0 FROM p WHERE lifecycle='waiting'),false) OR s.n>0 ELSE o.state IS DISTINCT FROM 'storno' END,
 'allowedActions',CASE WHEN o.state='waitlisted' THEN jsonb_build_array('view','note','offer','withdraw')
 WHEN o.state IN ('storno','preparing_payment') THEN jsonb_build_array('view')
 WHEN o.state='ordered' THEN jsonb_build_array('view','note','edit','cancel','paid')
 ELSE jsonb_build_array('view','note','edit','cancel','send') END)
 FROM eshop.orders o CROSS JOIN s WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_form(p_token text DEFAULT NULL,p_offer_id uuid DEFAULT NULL,p_order_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oid bigint; fid bigint; bundle jsonb; w eshop.waitlist_offers;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO w FROM eshop.waitlist_offers WHERE id=p_offer_id;
 oid:=coalesce(w.order_id,p_order_id);
 fid:=public.check_waitlist_scope_internal(oid,p_offer_id,p_token,auth.uid(),CASE WHEN p_offer_id IS NULL THEN 'withdraw' ELSE 'read' END);
 -- Terminal links explain their own outcome without exposing form answers,
 -- contact data, products, or payment details after capability revocation.
 IF p_offer_id IS NOT NULL AND (w.expires_at<=clock_timestamp() OR NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending')) THEN
  RETURN jsonb_build_object('code',200,'registrationMode','offer',
   'occasionTitle',(SELECT title FROM public.occasions WHERE id=(SELECT occasion FROM eshop.orders WHERE id=oid)),
   'orderSymbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),
   'timeZone',public.get_waitlist_form_timezone_internal(fid),
   'communicationTone',public.get_effective_form_data(fid)->>'communication_tone',
   'form',NULL,'formLink',(SELECT link FROM public.forms WHERE id=fid),
   'offerId',w.id,'pendingCount',0,'expiresAt',w.expires_at,'serverTime',clock_timestamp(),
   'offerStatus',CASE
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='declined') THEN 'declined'
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='cancelled') THEN 'cancelled'
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND (outcome='expired' OR outcome='pending' AND w.expires_at<=clock_timestamp())) THEN 'expired'
    ELSE 'accepted' END,'tickets','[]'::jsonb,'slots','[]'::jsonb);
 END IF;
 -- A revoked token can explain a terminal outcome above, never reopen live data.
 IF p_token IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.waitlist_capabilities
  WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND revoked_at IS NOT NULL) THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY';
 END IF;
 bundle:=public.get_form_bundle_internal(fid,true)::jsonb;
 bundle:=jsonb_set(bundle,'{data,registrationMode}',to_jsonb(CASE WHEN p_offer_id IS NOT NULL THEN 'offer'::text ELSE 'waitlist' END),true);
 RETURN jsonb_build_object('code',200,'form',bundle->'data','registrationMode',CASE WHEN p_offer_id IS NOT NULL THEN 'offer' ELSE 'waitlist' END,
  'timeZone',public.get_waitlist_form_timezone_internal(fid),
  'orderSymbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),
  'occasionTitle',(SELECT occ.title FROM public.occasions occ JOIN eshop.orders source ON source.occasion=occ.id WHERE source.id=oid),
  'orderData',(SELECT data FROM eshop.orders WHERE id=oid),'pendingCount',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending' AND w.expires_at>clock_timestamp()),
  'orderId',oid,'offerId',p_offer_id,'serverTime',clock_timestamp(),'expiresAt',w.expires_at,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'displayName',public.get_waitlist_ticket_display_name_internal(fid,data,CASE WHEN (SELECT count(*) FROM public.get_order_tickets_internal(oid))=1 THEN (SELECT source.data FROM eshop.orders source WHERE source.id=oid) ELSE '{}'::jsonb END),'answers',public.extract_ticket_answers_internal(fid,data),'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(id)) ORDER BY created_at,id),'[]')
   FROM public.get_order_tickets_internal(oid)),
  'slots',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'ticketId',ticket_id,'outcome',CASE WHEN outcome='pending' AND w.expires_at<=clock_timestamp() THEN 'expired' ELSE outcome END)),'[]')
   FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id),'waitlistSummary',public.get_waitlist_summary_internal(oid));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.check_waitlist_scope_internal(bigint,uuid,text,uuid,text),public.get_waitlist_summary_internal(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_waitlist_order_detail(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
 IF NOT public.get_is_editor_order_view_on_occasion(o.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Order viewer required'; END IF;
 RETURN jsonb_build_object('orderId',o.id,'sourceOrderId',o.source_waitlist_order_id,
 'occasionTitle',(SELECT title FROM public.occasions WHERE id=o.occasion),'waitlistSummary',public.get_waitlist_summary_internal(o.id),
 'capacity',public.get_form_capacity_snapshot_internal(o.form),
 'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'displayName',public.get_waitlist_ticket_display_name_internal(o.form,p.data,CASE WHEN (SELECT count(*) FROM public.get_order_tickets_internal(o.id))=1 THEN o.data ELSE '{}'::jsonb END),'createdAt',p.created_at,'waitlistQueueAt',p.waitlist_queue_at,'answers',public.extract_ticket_answers_internal(o.form,p.data),
  'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(p.id)) ORDER BY created_at,id),'[]') FROM public.get_order_tickets_internal(o.id) p),
 'offers',(SELECT coalesce(jsonb_agg(to_jsonb(w)||jsonb_build_object('slots',(SELECT coalesce(jsonb_agg((to_jsonb(s)-'ticket_id')||jsonb_build_object('ticketId',s.ticket_id)),'[]') FROM eshop.waitlist_offer_slots s WHERE offer_id=w.id)) ORDER BY created_at),'[]')
 FROM eshop.waitlist_offers w WHERE order_id=o.id),
 'linkedOrders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'orderSymbol',order_symbol,'state',state)),'[]') FROM eshop.orders WHERE source_waitlist_order_id=o.id));
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_order_detail(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_order_detail(bigint) TO authenticated;


-- Source: database/functions/public_links/legacy_readers.sql
-- Older public read contracts keep their response/access semantics and resolve
-- the same stable IDs. Do not restore link-column predicates here.

CREATE OR REPLACE FUNCTION public.check_occasion_link(link_txt text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasionId bigint;
    is_open_bool BOOLEAN;
    occasion_user occasion_users%rowtype;
    is_admin_bool BOOLEAN;
BEGIN
    -- If no link is provided, get the first open and non-hidden occasion's link
    IF link_txt = '' THEN
        SELECT link INTO link_txt FROM occasions WHERE occasions.is_open = true AND occasions.is_hidden = false LIMIT 1;
    END IF;

    -- Get the occasion ID for the provided link
    SELECT id INTO occasionId FROM occasions WHERE occasions.id = public.resolve_occasion_link_internal(link_txt) AND occasions.is_hidden = false;

    -- If the occasion ID is not found, return a 404 response
    IF occasionId IS NULL THEN
        RETURN json_build_object('code', 404);
    END IF;

    -- Get the is_open status for the occasion
    SELECT is_open INTO is_open_bool FROM occasions WHERE occasions.id = public.resolve_occasion_link_internal(link_txt);

    -- Get the occasion user record if it exists
    SELECT * INTO occasion_user FROM occasion_users WHERE occasion = occasionId AND "user" = auth.uid();

    -- Check if the current user is an admin on the occasion
    is_admin_bool := get_is_admin_on_occasion(occasionId);

    -- If the occasion is not open, enforce access restrictions
    IF is_open_bool = FALSE THEN
        IF auth.uid() IS NULL THEN
            RETURN json_build_object('code', 403);
        END IF;
        IF occasion_user IS NULL AND NOT is_admin_bool THEN
            RETURN json_build_object('code', 403);
        END IF;
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'occasion_user', COALESCE(row_to_json(occasion_user)::jsonb, NULL),
            'occasion', occasionId
        );
    END IF;

    -- If the occasion user record is not found and the user is not an admin, return basic occasion data
    IF occasion_user IS NULL THEN
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'link', link_txt,
            'occasion', occasionId
        );
    END IF;

    -- Return full occasion data including the user and admin status
    RETURN json_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'occasion_user', row_to_json(occasion_user)::jsonb,
        'link', link_txt,
        'occasion', occasionId
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_is_editor_view_via_form_link(form_link text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id bigint;
BEGIN
    -- Get occasion ID from form link
    SELECT f.occasion INTO occasion_id
    FROM public.forms f
    WHERE f.id = public.resolve_form_link_internal(form_link);

    -- Check if order/occasion exists
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Form not found or no associated occasion.';
    END IF;

    -- Verify editor permissions using existing helper function
    IF NOT public.get_is_editor_view_on_occasion(occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to edit this occasion.';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_products_and_types_from_occasion(form_link text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  product_types json;
  products json;
  occ_id bigint;
BEGIN
  PERFORM check_is_editor_order_view_via_form_link(form_link);

  SELECT f.occasion
    INTO occ_id
  FROM public.forms f
  WHERE f.id = public.resolve_form_link_internal(form_link);

  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = occ_id;

  SELECT json_agg(
           json_build_object(
             'id', p.id,
             'title', p.title,
             'title_short', p.title_short,
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'order', p."order",
             'maximum', p.maximum,
             'ordered_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               WHERE opt.product = p.id
             ),
             'paid_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'paid'
             ),
             'sent_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'sent'
             )
           )
         )
    INTO products
  FROM eshop.products p
  WHERE p.product_type IN (
    SELECT pt.id
    FROM eshop.product_types pt
    WHERE pt.occasion = occ_id
  );

  RETURN json_build_object(
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_reservations(p_occasion_link text, p_form_link text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id BIGINT;
    v_form_key UUID;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
BEGIN
    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    -- occasion_link has priority.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE id = public.resolve_occasion_link_internal(p_occasion_link);
    ELSE -- If occasion_link is NULL, use form_link
        SELECT occasion, key
        INTO v_occasion_id, v_form_key
        FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_form_link);
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT get_is_editor_order_view_on_occasion(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Fetch spots where order_product_ticket is not NULL
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.occasion = v_occasion_id
      AND s.order_product_ticket IS NOT NULL;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type,
        'description', pt.description
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'created_at', f.created_at,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title,
        'header', f.header,
        'header_off', f.header_off,
        'updated_at', f.updated_at
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Fetch orders - this is the conditional part.
    -- If v_form_key is not NULL, it means we are filtering by form.
    IF v_form_key IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id,
            'created_at', o.created_at,
            'updated_at', o.updated_at,
            'price', o.price,
            'state', o.state,
            'currency_code', o.currency_code,
            'data', o.data,
            'payment_info', o.payment_info,
            'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id
          AND o.data->>'form' = v_form_key::TEXT; -- Filter by the form's key
    ELSE
        -- Original query if not filtering by form
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id,
            'created_at', o.created_at,
            'updated_at', o.updated_at,
            'price', o.price,
            'state', o.state,
            'currency_code', o.currency_code,
            'data', o.data,
            'payment_info', o.payment_info,
            'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id;
    END IF;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
        'id', opt.id,
        'order', opt."order",
        'product', opt.product,
        'ticket', opt.ticket,
        'created_at', opt.created_at
    ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id,
        'created_at', pi.created_at,
        'bank_account', pi.bank_account,
        'variable_symbol', pi.variable_symbol,
        'amount', pi.amount,
        'paid', pi.paid,
        'returned', pi.returned,
        'deadline', pi.deadline,
        'currency_code', pi.currency_code,
        'data', pi.data
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        WHERE order_obj->>'payment_info' IS NOT NULL
    );

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb)
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_app_config_v203(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_app_config_v216(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_all_email_templates_via_form_link(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id   bigint;
    v_unit        bigint;
    v_org         bigint;
    email_data    jsonb;
    context       jsonb;
    occasion_data jsonb;
    unit_data     jsonb;
    org_data      jsonb;
    final_result  jsonb;
BEGIN
    -- Retrieve the occasion ID from the forms table using the provided form link.
    SELECT f.occasion
      INTO occasion_id
      FROM public.forms f
      WHERE f.id = public.resolve_form_link_internal(form_link);

    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Form not found or no associated occasion.';
    END IF;

    -- Retrieve unit and organization IDs from the occasion.
    SELECT o.unit, o.organization
      INTO v_unit, v_org
      FROM public.occasions o
      WHERE o.id = occasion_id;

    -- Build a JSON context with the occasion, unit, and organization.
    context := jsonb_build_object(
                  'occasion', occasion_id,
                  'unit', v_unit,
                  'organization', v_org
               );

    -- Call the updated function with the context parameter to retrieve templates.
    email_data := public.get_all_email_templates(context);

    -- Retrieve occasion details (id and title).
    SELECT jsonb_build_object('id', o.id, 'title', o.title)
      INTO occasion_data
      FROM public.occasions o
      WHERE o.id = occasion_id;

    -- Retrieve unit details (id and title).
    SELECT jsonb_build_object('id', u.id, 'title', u.title)
      INTO unit_data
      FROM public.units u
      WHERE u.id = v_unit;

    -- Retrieve organization details (id and title).
    SELECT jsonb_build_object('id', org.id, 'title', org.title)
      INTO org_data
      FROM public.organizations org
      WHERE org.id = v_org;

    -- Build final result JSON object containing the separate objects.
    final_result := jsonb_build_object(
                      'occasion',     occasion_data,
                      'unit',         unit_data,
                      'organization', org_data,
                      'templates',    email_data
                    );

    RETURN final_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_app_config_v217(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_app_config_v182(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_app_config_v2(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_inclusion_type_groups_by_link(p_occasion_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id bigint;
    v_occasion_data jsonb;
    v_groups_data jsonb;
    result jsonb;
BEGIN
    -- Find the occasion ID from the provided link.
    SELECT id INTO v_occasion_id FROM public.occasions WHERE id = public.resolve_occasion_link_internal(p_occasion_link);
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion with link % not found.', p_occasion_link;
    END IF;

    -- Permission check to ensure the user can view data for this occasion.
    IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Get the occasion details.
    SELECT to_jsonb(o) INTO v_occasion_data FROM public.occasions o WHERE id = v_occasion_id;

    -- Aggregate all groups for the occasion, and for each group, aggregate its inclusion types.
    SELECT COALESCE(jsonb_agg(groups_with_types), '[]'::jsonb)
    INTO v_groups_data
    FROM (
        SELECT
            jsonb_build_object(
                'id', g.id,
                'created_at', g.created_at,
                'updated_at', g.updated_at,
                'title', g.title,
                'type', g.type,
                'occasion', g.occasion,
                'inclusion_types', (
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'id', t.id,
                            'created_at', t.created_at,
                            'updated_at', t.updated_at,
                            'title', t.title,
                            'inclusion_type_group', t.inclusion_type_group,
                            'data', t.data
                        ) ORDER BY t.created_at
                    ), '[]'::jsonb)
                    FROM public.inclusion_types t
                    WHERE t.inclusion_type_group = g.id
                )
            ) AS groups_with_types
        FROM public.inclusion_type_groups g
        WHERE g.occasion = v_occasion_id
        ORDER BY g.created_at
    ) AS subquery;

    -- Construct the final bundle.
    result := jsonb_build_object(
        'occasion', v_occasion_data,
        'groups', v_groups_data
    );

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_products_and_types_for_occasion(form_link text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  product_types json;
  products json;
  occ_id bigint;
BEGIN
  PERFORM check_is_editor_order_view_via_form_link(form_link);

  SELECT f.occasion
    INTO occ_id
  FROM public.forms f
  WHERE f.id = public.resolve_form_link_internal(form_link);

  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type,
             'title', pt.title
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = occ_id;

  SELECT json_agg(
           json_build_object(
             'id', p.id,
             'title', p.title,
             'description', p.description,
             'title_short', p.title_short,
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'order', p."order",
             'maximum', p.maximum,
             'ordered_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               WHERE opt.product = p.id
             ),
             'paid_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'paid'
             ),
             'sent_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'sent'
             )
           )
         )
    INTO products
  FROM eshop.products p
  WHERE p.product_type IN (
    SELECT pt.id
    FROM eshop.product_types pt
    WHERE pt.occasion = occ_id
  );

  RETURN json_build_object(
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json)
  );
END;
$function$;

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
            'response_count', (
                SELECT COUNT(*)
                FROM eshop.orders o
                WHERE (o.data->>'form')::uuid = f.key -- Correctly join forms.key with the UUID in orders.data
            )
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
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

CREATE OR REPLACE FUNCTION public.get_app_config(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_blueprint_editor(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    blueprint_id BIGINT;
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    valid_spots JSONB;
    occasion_id BIGINT;
BEGIN
    -- Resolve blueprint_id using form_link
    SELECT blueprint
    INTO blueprint_id
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(form_link);

    -- Check if form_link is valid
    IF blueprint_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form key does not exist or is not linked to a blueprint');
    END IF;

    -- Fetch occasion_id for the blueprint
    SELECT occasion
    INTO occasion_id
    FROM eshop.blueprints
    WHERE id = blueprint_id;

    -- Authorization check
    IF (SELECT get_is_editor_order_view_on_occasion(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Fetch valid spot IDs
    SELECT jsonb_agg((obj->>'id')::BIGINT)
    INTO valid_spots
    FROM jsonb_array_elements(
        (SELECT objects FROM eshop.blueprints WHERE id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    -- Fetch enriched spots data
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
          WHEN t.state = 'used' THEN 'used'
          WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
          WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
          ELSE 'available'
        END
      )
    )
    INTO spotsData
    FROM eshop.spots s
    LEFT JOIN eshop.order_product_ticket opt ON s.order_product_ticket = opt.id
    LEFT JOIN eshop.tickets t ON opt.ticket = t.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = occasion_id;

    -- Fetch all products of type "spot", "taxi", "food"
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'type', pt.type,
        'description', pt.description
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    -- Fetch relevant tickets associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note
    ))
    INTO ticketsData
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND t.occasion = occasion_id;

    -- Fetch relevant orders associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', o.data
    ))
    INTO ordersData
    FROM eshop.orders o
    JOIN eshop.order_product_ticket opt ON opt."order" = o.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
            'id', opt.id,
            'order', opt."order",
            'product', opt.product,
            'ticket', opt.ticket,
            'created_at', opt.created_at
        ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    -- Add relevant tickets data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{tickets}',
        COALESCE(ticketsData, '[]'::jsonb)
    );

    -- Add relevant orders data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{orders}',
        COALESCE(ordersData, '[]'::jsonb)
    );

    -- Add relevant order-product-ticket data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{order_product_ticket}',
        COALESCE(orderProductTicketsData, '[]'::jsonb)
    );

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_form_fields(p_form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    form_id INT;
    fieldsData JSONB;
    productTypesData JSONB;
BEGIN
    PERFORM public.check_is_editor_order_view_via_form_link(p_form_link);
    -- Retrieve the form ID from the form link.
    SELECT id
    INTO form_id
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(p_form_link);

    -- Validate that the form exists.
    IF form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found');
    END IF;

    -- Retrieve the form fields associated with the form.
    -- (Filtering out ticket fields by checking a Boolean column and a specific type value)
    SELECT jsonb_agg(
         jsonb_build_object(
            'id', ff.id,
            'created_at', ff.created_at,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'form', ff.form,
            'is_hidden', ff.is_hidden,
            'order', ff.order,
            'product_type', ff.product_type,
            'is_ticket_field', ff.is_ticket_field
         )
    )
    INTO fieldsData
    FROM public.form_fields ff
    WHERE ff.form = form_id
      AND ff.is_ticket_field = FALSE
      AND ff.type <> 'ticket';

    -- Retrieve product types for those fields.
    SELECT jsonb_agg(
         jsonb_build_object(
            'id', pt.id,
            'name', pt.title,
            'description', pt.description
         )
    )
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.id IN (
        SELECT DISTINCT ff.product_type
        FROM public.form_fields ff
        WHERE ff.form = form_id
    );

    -- Return combined data as JSON.
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'fields', COALESCE(fieldsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb)
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_form_from_link(form_link text)
RETURNS json LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_form_by_link(form_link);
$$;

CREATE OR REPLACE FUNCTION public.get_form_from_link_for_edit(form_link text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    allData JSON;
BEGIN

    PERFORM check_is_editor_order_view_via_form_link(form_link);

    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'id', f.id,
            'key', f.key,
            'is_open', f.is_open,
            'created_at', f.created_at,
            'data', f.data,
            'type', f.type,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', f.occasion,
            'blueprint', f.blueprint,
            'link', f.link,
            -- Return full bank_account details as JSON instead of just the id:
            'bank_account', jsonb_build_object(
                                'account_number', ba.account_number,
                                'account_number_human_readable', ba.account_number_human_readable,
                                'title', ba.title,
                                'supported_currencies', ba.supported_currencies
                            ),
            'deadline_duration_seconds', f.deadline_duration_seconds,
            -- Optionally, if you want to keep the account_number separately, you can leave it:
            'account_number', ba.account_number,
            'available_bank_accounts', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'account_number', ba_inner.account_number,
                        'account_number_human_readable', ba_inner.account_number_human_readable,
                        'title', ba_inner.title,
                        'supported_currencies', ba_inner.supported_currencies
                    )
                )
                FROM eshop.unit_bank_accounts uba
                JOIN eshop.bank_accounts ba_inner ON uba.bank_account = ba_inner.id
                WHERE uba.unit = (
                    SELECT o.unit
                    FROM public.occasions o
                    WHERE o.id = f.occasion
                )
            ),
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'occasion', p.occasion,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'is_hidden', p.is_hidden,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    WHERE f.id = public.resolve_form_link_internal(form_link);

    RETURN allData;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_occasion_from_link(org_id bigint, link_txt text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasionId bigint;
    is_open_bool BOOLEAN;
    occasion_user occasion_users%rowtype;
    is_admin_bool BOOLEAN;
    occasion_link text;
    version_recommended text;
BEGIN
    -- If no link is provided, get the default occasion from the organization
    IF link_txt = '' THEN
        -- Get the default occasion ID from the organization's data
        SELECT data->>'DEFAULT_OCCASION' INTO occasionId
        FROM organizations
        WHERE id = org_id;

        -- If no default occasion is set, get the first open and non-hidden occasion within the organization
        IF occasionId IS NULL THEN
            SELECT id, link INTO occasionId, occasion_link
            FROM occasions
            WHERE is_open = true
              AND is_hidden = false
              AND organization = org_id
            LIMIT 1;

            -- If no open occasion is found, return a 404 response
            IF occasionId IS NULL THEN
                RETURN json_build_object('code', 404, 'message', 'No open occasion found for the organization');
            END IF;
        ELSE
            -- Get the link for the default occasion
            SELECT link INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    ELSE
        -- Get the occasion ID and link for the provided link within the specified organization
        SELECT id, link INTO occasionId, occasion_link
        FROM occasions
        WHERE id = public.resolve_occasion_link_internal(link_txt,org_id)
          AND is_hidden = false
          AND organization = org_id;

        -- If the occasion ID is not found, return a 404 response
        IF occasionId IS NULL THEN
            RETURN json_build_object('code', 404, 'message', 'Occasion not found');
        END IF;
    END IF;

     -- Retrieve version_recommended from organization's data
    SELECT data->>'VERSION_RECOMMENDED' INTO version_recommended
    FROM organizations
    WHERE id = org_id;

    -- Get the is_open status for the occasion
    SELECT is_open INTO is_open_bool
    FROM occasions
    WHERE id = occasionId;

    -- Get the occasion user record if it exists
    SELECT * INTO occasion_user
    FROM occasion_users
    WHERE occasion = occasionId
      AND "user" = auth.uid();

    -- Check if the current user is an admin on the occasion
    is_admin_bool := get_is_admin_on_occasion(occasionId);

    -- If the occasion is not open, enforce access restrictions
    IF is_open_bool = FALSE THEN
        IF auth.uid() IS NULL THEN
            RETURN json_build_object('code', 403, 'message', 'Access forbidden', 'link', occasion_link, 'version_recommended', version_recommended);
        END IF;
        IF occasion_user IS NULL AND NOT is_admin_bool THEN
            RETURN json_build_object('code', 403, 'message', 'Access forbidden', 'link', occasion_link, 'version_recommended', version_recommended);
        END IF;
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'occasion_user', COALESCE(row_to_json(occasion_user)::jsonb, NULL),
            'link', occasion_link,
            'occasion', occasionId,
            'version_recommended', version_recommended
        );
    END IF;

    -- If the occasion user record is not found, the user is authenticated, and the occasion is open
    IF occasion_user IS NULL AND auth.uid() IS NOT NULL THEN
        -- Add the user to the occasion
        PERFORM add_user_to_occasion(occasionId, auth.uid());

        -- Fetch the updated occasion user record
        SELECT * INTO occasion_user
        FROM occasion_users
        WHERE occasion = occasionId
          AND "user" = auth.uid();
    END IF;

    -- If the occasion user record is still not found and the user is not an admin, return basic occasion data
    IF occasion_user IS NULL THEN
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'link', occasion_link,
            'occasion', occasionId,
            'version_recommended', version_recommended
        );
    END IF;

    -- Return full occasion data including the user and admin status
    RETURN json_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'occasion_user', row_to_json(occasion_user)::jsonb,
        'link', occasion_link,
        'occasion', occasionId,
        'version_recommended', version_recommended
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_orders(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
BEGIN
    -- Get the occasion_id based on the provided form_link
    SELECT occasion
    INTO occasion_id
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(form_link);

    -- Check if form_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form key does not exist or is not linked to an occasion');
    END IF;

    -- Authorization check
    IF (SELECT get_is_editor_order_view_on_occasion(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Fetch spots where order_product_ticket is not NULL
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.occasion = occasion_id
      AND s.order_product_ticket IS NOT NULL;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type,
        'description', pt.description
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = occasion_id;

    -- Fetch orders linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', o.data,
        'payment_info', o.payment_info,
        'note_hidden', o.note_hidden
    ))
    INTO ordersData
    FROM eshop.orders o
    WHERE o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
        'id', opt.id,
        'order', opt."order",
        'product', opt.product,
        'ticket', opt.ticket,
        'created_at', opt.created_at
    ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id,
        'created_at', pi.created_at,
        'bank_account', pi.bank_account,
        'variable_symbol', pi.variable_symbol,
        'amount', pi.amount,
        'paid', pi.paid,
        'returned', pi.returned,
        'deadline', pi.deadline,
        'currency_code', pi.currency_code
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(ordersData) order_obj
    );

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'created_at', f.created_at,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'header', f.header,
        'header_off', f.header_off,
        'updated_at', f.updated_at
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = occasion_id;

    -- Return combined data, including the new product_types key
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb)
        )
    );
END;
$function$;


-- Source: database/functions/public_links/legacy_writers.sql
-- Supported old entrypoints delegate to command receipts and never own slugs.
CREATE OR REPLACE FUNCTION public.update_occasion(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; id bigint; version bigint;
BEGIN
 id:=nullif(input_data->>'id','')::bigint;
 IF id IS NULL THEN result:=public.create_occasion_client_sync_v1(gen_random_uuid(),input_data);
 ELSE
  SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
   ON v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=id AND v.aggregate_id=id::text;
  result:=public.save_occasion_client_sync_v1(id,gen_random_uuid(),version,input_data);
 END IF;
 RETURN jsonb_build_object('code',result->'code','occasion',result#>'{data,occasion}');
END $$;
CREATE OR REPLACE FUNCTION public.update_occasion_182(input_data jsonb)
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.update_occasion_203(input_data);
$$;
CREATE OR REPLACE FUNCTION public.duplicate_form(p_old_form_id bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target text;
BEGIN
 SELECT o.link INTO target FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_old_form_id;
 RETURN public.duplicate_form_to_occasion(p_old_form_id,target);
END $$;
CREATE OR REPLACE FUNCTION public.copy_form_with_fields(p_source_form_id bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.duplicate_form(p_source_form_id);
$$;
REVOKE ALL ON FUNCTION public.update_occasion(jsonb),public.update_occasion_182(jsonb),
 public.duplicate_form(bigint),public.copy_form_with_fields(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion(jsonb),public.update_occasion_182(jsonb),
 public.duplicate_form(bigint),public.copy_form_with_fields(bigint) TO authenticated;
-- Abandoned implementations have no remaining callers after the cutover.
DROP FUNCTION IF EXISTS public.create_form_ws_obsolete_v1(jsonb);
DROP FUNCTION IF EXISTS public.sync_source_via_http_internal_v1(text);

DROP FUNCTION IF EXISTS public.duplicate_occasion_domain_command_internal_v1(bigint,uuid);


-- Close abandoned pre-cutover entrypoints as well as the active internals.
REVOKE ALL ON FUNCTION public.create_form_internal_v1(bigint,text,text),
 public.update_form_internal_v1(jsonb),public.update_occasion_internal_v1(jsonb),
 public.create_occasion_domain_command_internal_v1(uuid,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
