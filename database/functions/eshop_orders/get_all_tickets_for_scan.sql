CREATE OR REPLACE FUNCTION public.get_all_tickets_for_scan(scan_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id_val bigint;
    result jsonb; policy jsonb; max_items bigint; max_bytes bigint; found_items bigint;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1(NULL) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    SELECT o.id
    INTO occasion_id_val
    FROM public.occasions o
    JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
    WHERE oh.secret = scan_code
    LIMIT 1;

    IF occasion_id_val IS NULL THEN
         PERFORM public.admit_scan_access_v1(NULL,false);
         RETURN jsonb_build_object('code',401,'message','invalid_scan_code');
    END IF;

    IF NOT public.admit_scan_access_v1(occasion_id_val,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    policy:=public.abuse_effective_rules_v1('scan.export',(SELECT unit FROM public.occasions WHERE id=occasion_id_val),(SELECT organization FROM public.occasions WHERE id=occasion_id_val));
    SELECT (r->>'base_limit')::bigint INTO max_items FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.items';
    SELECT (r->>'base_limit')::bigint INTO max_bytes FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.bytes';
    IF max_items IS NULL OR max_bytes IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
    SELECT count(*) INTO found_items FROM (SELECT id FROM eshop.tickets WHERE occasion=occasion_id_val LIMIT max_items+1) bounded;
    IF found_items>max_items THEN RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded'); END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', t.id,
            'ticket_symbol', t.ticket_symbol,
            'state', t.state,
            'related_order', jsonb_build_object(
                 'data', t.data
            )
        ) 
    )
    INTO result
    FROM (
        SELECT DISTINCT ON (t.id) t.id, t.ticket_symbol, t.state, o.data
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE o.occasion = occasion_id_val
          AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'
          AND t.ticket_symbol IS NOT NULL AND o.state IS DISTINCT FROM 'waitlisted'
          AND NOT public.stripe_ticket_requires_online_internal(t.id)
        ORDER BY t.id
    ) t;

    IF octet_length(result::text)>max_bytes THEN RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded'); END IF;
    RETURN COALESCE(result, '[]'::jsonb);
END;
$$;
