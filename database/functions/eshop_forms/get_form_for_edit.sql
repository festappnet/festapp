-- Canonical editor projection shared by the checked UI and MCP boundaries.
CREATE OR REPLACE FUNCTION public.get_form_editor_bundle_internal(p_form_id bigint,p_related_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE
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
    WHERE f.id = p_form_id;

    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    -- Private projection; the checked public reader/command owns authorization.

    -- Use the same reference guard as deletion, including retained history.
    canDelete := (public.get_form_usage_internal(v_form_id)->>'blocking_orders')::bigint=0;

    SELECT jsonb_build_object(
        'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=f.occasion AND aggregate_id=f.id::text),0),
        'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'organizationIdentity',(SELECT CASE WHEN o.organization=u.organization THEN public.get_verified_unit_identity_internal(u.id) END FROM public.occasions o JOIN public.units u ON u.id=o.unit WHERE o.id=f.occasion),
        'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
        'key', f.key,
        'is_open', f.is_open,
        'created_at', f.created_at,
        'data', public.normalize_form_metadata_internal(f.data),
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
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product_type' AND scope_type='occasion' AND scope_id=pt.occasion AND aggregate_id=pt.id::text),0),
            'title', pt.title,
            'description', pt.description,
            'type', pt.type,
            'data', pt.data,
            'occasion', pt.occasion
        ) ORDER BY pt.title
    ), '[]'::jsonb)
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id
      AND (NOT p_related_only OR pt.id IN (SELECT product_type FROM public.form_fields WHERE form=v_form_id));

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
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=p.occasion AND aggregate_id=p.id::text),0),
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
      WHEN public.primary_product_delete_blocked_internal(p.id) THEN 'primary_product'
      WHEN EXISTS (SELECT 1 FROM used_products u WHERE u.product = p.id::text) THEN 'orders'
      WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
      WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
      WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
    END AS reason) usage
    WHERE p.occasion=v_occasion_id AND p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id)
      AND (NOT p_related_only OR p.product_type IN (SELECT product_type FROM public.form_fields WHERE form=v_form_id));

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
    CROSS JOIN LATERAL (SELECT CASE
      WHEN EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=ff.product_type AND pt.type='spot')
        OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM public.form_fields child
          JOIN eshop.product_types pt ON pt.id=child.product_type
          WHERE child.form=ff.form AND child.is_ticket_field AND pt.type='spot')) THEN 'primary_product'
      WHEN EXISTS (
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

    availableBankAccountsData:=CASE WHEN p_related_only THEN '[]'::jsonb
        ELSE public.get_form_bank_accounts_internal(v_unit_id) END;

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
REVOKE ALL ON FUNCTION public.get_form_editor_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Released link-based entry remains a checked boundary on the same projection.
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE form_id bigint;
BEGIN
 form_id:=public.resolve_form_link_internal(form_link);
 IF form_id IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form not found for the provided link.'); END IF;
 IF public.can_read_form_catalog((SELECT occasion FROM public.forms WHERE id=form_id)) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='form catalog reader required'; END IF;
 RETURN public.get_form_editor_bundle_internal(form_id);
END $$;
REVOKE ALL ON FUNCTION public.get_form_for_edit(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_for_edit(text) TO anon,authenticated,service_role;
