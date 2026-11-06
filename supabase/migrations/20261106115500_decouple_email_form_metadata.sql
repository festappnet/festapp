-- Keep email preparation independent of private measurement configuration.
-- Pure shared metadata owner: email preparation must not depend on analytics policy tables.
CREATE OR REPLACE FUNCTION public.effective_form_metadata_internal(p_form_data jsonb,p_unit_data jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT (public.normalize_form_metadata_internal(p_form_data)-'analytics') || jsonb_build_object(
  'communication_tone',CASE
   WHEN p_form_data->>'communication_tone' IN ('formal','informal') THEN p_form_data->>'communication_tone'
   WHEN p_unit_data->>'communication_tone' IN ('formal','informal') THEN p_unit_data->>'communication_tone'
   ELSE 'formal' END);
$$;
REVOKE ALL ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) TO service_role;
-- The normalizer is a pure JSON transformation, with no table access.
GRANT EXECUTE ON FUNCTION public.normalize_form_metadata_internal(jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.get_effective_form_data(p_form_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT public.effective_form_metadata_internal(f.data,u.data) || jsonb_build_object(
        'analytics',public.form_measurement_runtime_internal(f.id)
    )
    FROM public.forms f
    JOIN public.occasions o ON o.id = f.occasion
    JOIN public.units u ON u.id = o.unit
    WHERE f.id = p_form_id;
$$;

REVOKE ALL ON FUNCTION public.get_effective_form_data(bigint)
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_order_details_for_email(p_order_id bigint)
RETURNS jsonb
STABLE
SET search_path = public, extensions AS $$
DECLARE
    result_data jsonb;
    v_changes jsonb;
    form_fields_data jsonb;
    form_data jsonb;
    form_key uuid;
    latest_history_id bigint;
    v_reply_to_email TEXT;
BEGIN
    -- Retrieve the order, occasion, payment info, and bank account as separate objects
    SELECT jsonb_build_object(
        'order', to_jsonb(o.*) || jsonb_build_object('data', o.data || jsonb_build_object(
          'tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))),
        'occasion', to_jsonb(occ.*)||jsonb_build_object('locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=occ.organization),'cs')),
        'payment_info', to_jsonb(pi.*),
        'bank_account', CASE
            WHEN upper(o.currency_code) = 'EUR'
              AND ba.id IS NOT NULL
              AND nullif(trim(ba.creditor_name), '') IS NULL
            THEN jsonb_set(
              to_jsonb(ba.*),
              '{creditor_name}',
              to_jsonb(left(trim(regexp_replace(org.title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70))
            )
            ELSE to_jsonb(ba.*)
        END
    )
    INTO result_data
    FROM eshop.orders AS o
    LEFT JOIN public.occasions AS occ ON o.occasion = occ.id
    LEFT JOIN public.organizations AS org ON occ.organization = org.id
    LEFT JOIN eshop.payment_info AS pi ON o.payment_info = pi.id
    LEFT JOIN eshop.bank_accounts AS ba ON pi.bank_account = ba.id
    WHERE o.id = p_order_id;

    -- Check if the order was found
    IF result_data IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found.');
    END IF;

    -- Call the function you provided to get the email
    SELECT get_reply_to_email_for_order(p_order_id) INTO v_reply_to_email;

    -- Add the email to the result data. jsonb_build_object handles NULLs gracefully.
    result_data := result_data || jsonb_build_object('reply_to', v_reply_to_email);


    v_changes := public.get_order_change_summary_v1(p_order_id);
    latest_history_id := (v_changes->>'latestHistoryId')::bigint;
    result_data := result_data || jsonb_build_object(
      'latest_history_id', latest_history_id,
      'reference_history', v_changes#>'{referenceOrder,data}',
      'order_changes', v_changes);

    -- Extract the form's unique key from the order's data
    form_key := (result_data->'order'->'data'->>'form')::uuid;

    -- If a form key exists, fetch all associated form fields
    IF form_key IS NOT NULL THEN
        -- 2. Modified query to fetch both form_fields and form_data at the same time
        SELECT
            jsonb_object_agg(ff.id, to_jsonb(ff.*)), -- All fields
            public.effective_form_metadata_internal(f.data, u.data) -- Communication metadata without analytics policy
        INTO
            form_fields_data,
            form_data
        FROM
            public.form_fields AS ff
        JOIN
            public.forms AS f ON ff.form = f.id
        JOIN public.occasions form_occasion ON form_occasion.id = f.occasion
        JOIN public.units u ON u.id = form_occasion.unit
        WHERE
            f.key = form_key
        GROUP BY
            f.id, u.data; -- Group by the form used for effective data

        -- If form fields were found, add them to the result data
        IF form_fields_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_fields', form_fields_data);
        END IF;

        -- 3. Added this block to merge the form_data
        IF form_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_data', form_data);
        END IF;
    END IF;

    -- Return a success response with the collected data
    RETURN jsonb_build_object('code', 200, 'data', result_data);

END;
$$ LANGUAGE plpgsql;
