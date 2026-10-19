-- Preserve existing ticket-container offers and participant product fields.
-- Development only: rejected production rollout remains rolled back.
BEGIN;
-- One admission preflight for the complete atomic unit. These are the same
-- offered fields, maximum counts and physical/context quantities as checkout.
CREATE OR REPLACE FUNCTION public.blueprint_hold_admission_internal(p_form bigint,p_spots bigint[],p_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE item record; counts jsonb; requested bigint; occupied bigint; physical bigint; cap bigint;
BEGIN
 -- Serialize all products and required inventory contexts in canonical ID order.
 PERFORM 1 FROM eshop.products WHERE id IN (SELECT product FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN (SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN (SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic
  JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 FOR item IN SELECT p.*,count(*) AS requested FROM eshop.spots s JOIN eshop.products p ON p.id=s.product
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>statement_timestamp(),false)
  GROUP BY p.id ORDER BY p.id LOOP
  IF item.is_hidden THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_HIDDEN'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=p_form AND ff.product_type=item.product_type
   AND (ff.type='ticket' OR (ff.type='product_type' AND ff.is_ticket_field)) AND NOT ff.is_hidden) THEN
   RETURN jsonb_build_object('code',409,'reason','PRODUCT_NOT_IN_FORM'); END IF;
  IF coalesce(item.maximum,0)>0 THEN
   SELECT count(*) INTO occupied FROM eshop.order_product_ticket WHERE product=item.id;
   SELECT occupied+count(*) INTO occupied FROM eshop.spots WHERE product=item.id AND order_product_ticket IS NULL
    AND secret IS NOT NULL AND secret_expiration_time>statement_timestamp();
   IF occupied+item.requested>item.maximum THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
  END IF;
  counts:=public.blueprint_product_availability_internal(item.id);
  IF (counts->>'available')::bigint<item.requested THEN RETURN jsonb_build_object('code',409,'reason',coalesce(counts->>'reason','PRODUCT_CAPACITY_EXCEEDED')); END IF;
 END LOOP;
 -- Two differently priced products can consume the same context. Sum their
 -- quantities before holding either member, rather than checking them alone.
 FOR item IN SELECT pic.inventory_context,ip.sellable_capacity,sum(pic.quantity)::bigint AS requested
  FROM eshop.spots s JOIN eshop.product_inventory_contexts pic ON pic.product=s.product
  JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>statement_timestamp(),false)
  GROUP BY pic.inventory_context,ip.sellable_capacity ORDER BY pic.inventory_context LOOP
  SELECT count(*),count(*) FILTER(WHERE order_product_ticket IS NOT NULL OR
   (secret IS NOT NULL AND secret_expiration_time>statement_timestamp())) INTO physical,occupied
   FROM eshop.spots WHERE inventory_context=item.inventory_context;
  -- Addressed seats usually have no inventory_context. Their existing spot
  -- holds nevertheless promise all PIC quantities at checkout. Count that
  -- same hold record, subtracting any physical occupancy already counted.
  SELECT occupied+coalesce(sum(greatest(pic.quantity-CASE
    WHEN held.inventory_context=item.inventory_context THEN 1 ELSE 0 END,0)),0)
   INTO occupied FROM eshop.spots held JOIN eshop.product_inventory_contexts pic ON pic.product=held.product
   WHERE pic.inventory_context=item.inventory_context AND held.blueprint IS NOT NULL
    AND held.order_product_ticket IS NULL AND held.secret IS NOT NULL
    AND held.secret_expiration_time>statement_timestamp();
  cap:=least(physical,coalesce(item.sellable_capacity,physical));
  IF occupied+item.requested>cap THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
 END LOOP;
 RETURN jsonb_build_object('code',200);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_hold_admission_internal(bigint,bigint[],uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.select_spot_single_internal_v1(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; occ bigint; org bigint; un bigint; s eshop.spots; policy jsonb; scopes jsonb; costs jsonb; r jsonb; held bigint; duration_seconds integer; form_data jsonb; form_open boolean; fid bigint;
BEGIN
 IF secret_id IS NULL OR selecting IS NULL THEN RETURN jsonb_build_object('code',400,'message','Invalid reservation'); END IF;
 SELECT f.blueprint,f.occasion,o.organization,o.unit,f.id,f.is_open INTO bp,occ,org,un,fid,form_open FROM public.forms f
 JOIN public.occasions o ON o.id=f.occasion WHERE f.key=form_key;
 IF bp IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form blueprint not found'); END IF;
 PERFORM public.check_occasion_writable(occ);
 -- A buyer's active inventory is serialized before the individual spot lock.
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=bp FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Spot not found'); END IF;
 IF s.order_product_ticket IS NOT NULL THEN RETURN jsonb_build_object('code',409,'message','Spot is already ordered'); END IF;
 IF s.secret_expiration_time<=statement_timestamp() THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=spot_id;
  s.secret:=NULL; s.secret_expiration_time:=NULL;
 END IF;
 IF s.secret IS NOT NULL AND s.secret IS DISTINCT FROM secret_id THEN
  RETURN jsonb_build_object('code',403,'message','Spot is held by another buyer'); END IF;
 IF NOT selecting THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now() WHERE id=spot_id;
  RETURN jsonb_build_object('code',200,'message','Spot deselected');
 END IF;
 -- A retry cannot move the original expiration, including after another tab reload.
 IF s.secret=secret_id THEN RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time); END IF;
 r:=public.blueprint_hold_admission_internal(fid,ARRAY[s.id],secret_id);
 IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
 IF selecting AND public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN
  form_data:=public.get_effective_form_data(fid);
  IF form_open IS NOT TRUE OR
   (coalesce(form_data#>>'{schedule,start_time}',form_data->>'start_time'))::timestamptz>statement_timestamp() OR
   (coalesce(form_data#>>'{schedule,end_time}',form_data->>'end_time'))::timestamptz<statement_timestamp() THEN
   RETURN jsonb_build_object('code',403,'message','Form is not open'); END IF;
 END IF;
 policy:=public.abuse_effective_rules_v1('spot.hold',un,org);
 scopes:=jsonb_build_object('recipient',secret_id,'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT count(*) INTO held FROM eshop.spots WHERE secret=secret_id AND secret_expiration_time>statement_timestamp() AND order_product_ticket IS NULL;
 costs:=jsonb_build_object('hold.active.buyer',held+1);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 SELECT (x->>'base_limit')::integer INTO duration_seconds FROM jsonb_array_elements(public.abuse_effective_rules_v1('hold.duration',un,org)->'rules') x;
 IF duration_seconds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 UPDATE eshop.spots SET secret=secret_id,secret_expiration_time=statement_timestamp()+make_interval(secs=>duration_seconds),updated_at=now() WHERE id=spot_id RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time);
END $$;
REVOKE ALL ON FUNCTION public.select_spot_single_internal_v1(uuid,uuid,bigint,boolean) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.select_spot(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; member_id bigint; r jsonb; occ bigint; bp bigint; fid bigint;
BEGIN
 SELECT occasion,blueprint,id INTO occ,bp,fid FROM public.forms WHERE key=form_key;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 ids:=public.blueprint_selection_unit_spots_internal(spot_id);
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 BEGIN
  IF selecting AND EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
   WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL)
    AND NOT coalesce(s.secret=secret_id AND s.secret_expiration_time>statement_timestamp(),false)) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
  IF selecting THEN
   r:=public.blueprint_hold_admission_internal(fid,ids,secret_id);
   IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
  END IF;
  FOREACH member_id IN ARRAY ids LOOP
   r:=public.select_spot_single_internal_v1(form_key,secret_id,member_id,selecting);
   IF coalesce((r->>'code')::integer,500)<>200 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_HOLD_REJECTED'; END IF;
  END LOOP;
 EXCEPTION WHEN check_violation THEN
  RETURN coalesce(r,jsonb_build_object('code',409,'reason',SQLERRM,'message',SQLERRM));
 END;
 RETURN r||jsonb_build_object('spotIds',to_jsonb(ids));
END $$;
REVOKE ALL ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) TO anon,authenticated;

-- Source: database/functions/blueprint/staged_tenant_readers.sql
-- Temporary staged rollout: only organization 3 is released first.
-- Retire both private legacy readers after the remaining tenants are migrated.
-- The canonical layout readers remain authoritative for every converted row.

CREATE OR REPLACE FUNCTION public.get_blueprint_legacy_rollout_internal(
    my_secret UUID,
    form_key UUID,
    blueprint_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    valid_spots JSONB;
BEGIN
    -- Validate the form and blueprint association
    IF NOT EXISTS (
        SELECT 1
        FROM public.forms f
        WHERE f.key = form_key
          AND (NOT public.is_demo_occasion(f.occasion) OR public.can_read_demo_occasion(f.occasion))
          AND (f.is_open = true OR public.get_is_editor_order_view_on_occasion(f.occasion))
          AND EXISTS (
              SELECT 1
              FROM eshop.blueprints b
              WHERE b.id = blueprint_id
                AND f.blueprint = blueprint_id
          )
    ) THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Invalid form key or blueprint association.'
        );
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
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
        (SELECT b.objects FROM eshop.blueprints b WHERE b.id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    -- Fetch enriched spots data
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN
                CASE
                    WHEN s.secret = my_secret THEN 'selected_by_me'
                    ELSE 'selected'
                END
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

    -- Fetch product data for all spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.spots s ON s.product = p.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

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

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_blueprint_legacy_rollout_internal(uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION get_blueprint(
    my_secret UUID,
    form_key UUID,
    blueprint_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    valid_spots JSONB;
    form_bundle JSONB;
BEGIN
    -- Validate the form and blueprint association
    IF NOT EXISTS (
        SELECT 1
        FROM public.forms f
        WHERE f.key = form_key
          AND (NOT public.is_demo_occasion(f.occasion) OR public.can_read_demo_occasion(f.occasion))
          AND (f.is_open = true OR public.get_is_editor_order_view_on_occasion(f.occasion))
          AND EXISTS (
              SELECT 1
              FROM eshop.blueprints b
              WHERE b.id = blueprint_id
                AND f.blueprint = blueprint_id
          )
    ) THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Invalid form key or blueprint association.'
        );
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL AND organization<>3) THEN
      RETURN public.get_blueprint_legacy_rollout_internal(my_secret,form_key,blueprint_id);
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN
                CASE
                    WHEN s.secret = my_secret THEN 'selected_by_me'
                    ELSE 'selected'
                END
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

    -- Reuse the form's public catalog projection, including current wave-applied
    -- price, visible offers, product maximum and inventory availability.
    form_bundle:=public.get_form_bundle_internal((SELECT id FROM public.forms WHERE key=form_key),true)::jsonb;
    SELECT coalesce(jsonb_agg(product||jsonb_build_object('isAvailable',
        coalesce((product->>'is_dynamically_available')::boolean,true) AND
        (coalesce((product->>'maximum')::bigint,0)<=0 OR
         coalesce((product->>'ordered_count')::bigint,0)<(product->>'maximum')::bigint))),'[]')
    INTO productsData
    FROM (SELECT DISTINCT ON (offered_product.value->>'id') offered_product.value AS product
      FROM jsonb_array_elements(coalesce(nullif(form_bundle#>'{data,fields}','null'::jsonb),'[]'::jsonb)) field
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(field#>'{product_type_data,products}','null'::jsonb),'[]'::jsonb)) AS offered_product(value)
      WHERE (field->>'type'='ticket' OR ((field->>'is_ticket_field')::boolean AND field->>'type'='product_type'))
        AND (offered_product.value->>'id')::bigint IN (
          SELECT s.product FROM eshop.spots s WHERE s.id=ANY(SELECT jsonb_array_elements_text(valid_spots)::bigint)
          UNION SELECT ab.product FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=blueprint_id)
      ORDER BY offered_product.value->>'id') offered;

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

    blueprintData:=blueprintData||public.blueprint_public_binding_projection_internal(blueprint_id,my_secret);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,(SELECT id FROM public.forms WHERE key=form_key)));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit_legacy_rollout_internal(
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
REVOKE ALL ON FUNCTION public.get_blueprint_for_edit_legacy_rollout_internal(text) FROM PUBLIC,anon,authenticated,service_role;

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

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL AND organization<>3) THEN
      RETURN public.get_blueprint_for_edit_legacy_rollout_internal(occasion_link);
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

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
        'data', jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note', 'note_hidden', coalesce(o.note_hidden,o.data->>'note_hidden'))
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

    blueprintData:=blueprintData||public.blueprint_binding_projection_internal(blueprint_id);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,NULL));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;
COMMIT;
