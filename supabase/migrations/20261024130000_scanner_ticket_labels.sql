-- Scanner ticket labels. Canonical sources are listed below.
BEGIN;

-- Source: database/functions/scanning/projection.sql
-- Set based, minimal projection shared by lookup, search and immutable snapshots.
CREATE OR REPLACE FUNCTION public.scanner_ticket_projection_internal(p_occasion bigint,p_config jsonb,p_ticket bigint DEFAULT NULL)
RETURNS TABLE(ticket_id bigint,dto jsonb) LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH base AS MATERIALIZED (
 SELECT t.*,o.id oid,o.form,o.state order_state,o.updated_at order_updated,o.data order_data,o.note_hidden order_note_hidden,
 pi.amount,pi.paid,public.stripe_ticket_requires_online_internal(t.id) online_required,
 coalesce(td.value,'{}'::jsonb) ticket_data,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders oz ON oz.id=z."order"
 WHERE z.ticket=t.id AND (oz.occasion IS DISTINCT FROM t.occasion OR oz.state IN ('stock','storno','waitlisted','preparing_payment'))) bad_order
 FROM eshop.tickets t
 JOIN LATERAL (SELECT x."order" FROM eshop.order_product_ticket x WHERE x.ticket=t.id ORDER BY x."order" LIMIT 1) x ON true
 JOIN eshop.orders o ON o.id=x."order"
 LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
 LEFT JOIN LATERAL (SELECT value FROM jsonb_array_elements(coalesce(o.data->'tickets','[]'::jsonb)) WHERE value->>'id'=t.id::text LIMIT 1) td ON true
 WHERE t.occasion=p_occasion AND (p_ticket IS NULL OR t.id=p_ticket)
 ), projected AS (
 SELECT b.*,coalesce(nullif(trim(concat_ws(' ',nullif(trim(b.order_data->>'name'),''),nullif(trim(b.order_data->>'surname'),''))),''),
 (SELECT string_agg(nullif(trim(a.value#>>'{}'),''),' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.order_data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND NOT ff.is_ticket_field WHERE ff.type IN ('name','surname'))) purchaser_name,
 coalesce((SELECT string_agg(a.value#>>'{}',' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND ff.is_ticket_field WHERE ff.type IN ('name','surname')),
 (SELECT string_agg(v.value#>>'{}',' ' ORDER BY v.key) FROM jsonb_each(b.ticket_data) v WHERE v.key IN ('name','surname')),
 (SELECT concat_ws(' ',u.name,u.surname) FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user" WHERE ou.ticket=b.id AND ou.occasion=p_occasion LIMIT 1),b.ticket_symbol) holder_name,
 (b.state IN ('sent','paid','ordered') AND b.ticket_symbol IS NOT NULL AND NOT b.bad_order AND b.order_state NOT IN ('stock','storno','waitlisted','preparing_payment') AND public.stripe_ticket_admission_allowed_internal(b.id)) eligible
 FROM base b)
 SELECT b.id,jsonb_strip_nulls(jsonb_build_object('ticket_id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated_at',b.updated_at,
 'batch_title',(SELECT tb.title FROM eshop.ticket_batch_items bi JOIN eshop.ticket_batches tb ON tb.id=bi.batch_id
     WHERE bi.ticket_id=b.id AND tb.occasion=p_occasion),
 'order_id',b.oid,'purchaser_name',b.purchaser_name,'holder_name',b.holder_name,'admission_allowed',coalesce(b.eligible AND (b.state<>'ordered' OR (p_config#>>'{admission,allow_unpaid_online}')::boolean),false),
 'requires_unpaid_confirmation',b.state='ordered' AND NOT b.bad_order AND b.order_state<>'stock',
 'unavailable_reason',CASE WHEN b.order_state='stock' THEN 'not_sold' END,'online_required',b.online_required,
 'eligibility_fingerprint',encode(digest(jsonb_build_object('v',1,'id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated',b.updated_at,
 'parents',(SELECT jsonb_agg(CASE WHEN pi.payment_method='stripe' THEN jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid,pi.returned,pi.payment_method,o.email_payment_version) ELSE jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid) END ORDER BY o.id) FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE z.ticket=b.id))::text,'sha256'),'hex'),
 'remaining_amount',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN greatest(0,coalesce(b.amount,0)-coalesce(b.paid,0)) END,
 'order_note',nullif(trim(b.order_data->>'note'),''),'note',nullif(trim(b.note),''),
 'order_note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.order_note_hidden END,
 'note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.note_hidden END,
 'products',coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',p.id,'title',p.title,'short_title',nullif(trim(p.data->>'short_title'),''),'type_id',p.product_type,'type',pt.type,'type_title',pt.title,
 'price',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN p.price END)) ORDER BY array_position(ARRAY(SELECT value::text::bigint FROM jsonb_array_elements(p_config#>'{products,order}')),p.id) NULLS LAST,p."order",p.id)
 FROM eshop.products p LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.occasion=p_occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=b.id AND z.product=p.id)
 AND ((p_config#>>'{products,mode}')='all' OR ((p_config#>>'{products,mode}')='selected' AND (p_config#>'{products,ids}') @> to_jsonb(ARRAY[p.id])))),'[]'::jsonb),
 'spot',(SELECT s.title FROM eshop.spots s JOIN eshop.order_product_ticket z ON z.id=s.order_product_ticket WHERE z.ticket=b.id ORDER BY s.id LIMIT 1),
 'spot_group',(SELECT jsonb_build_object('blueprint_id',bp.id,'id',g->>'id','title',g->>'title')
 FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket
 JOIN eshop.blueprints bp ON bp.id=sp.blueprint
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(bp.objects,'[]'::jsonb)) obj
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(bp.groups,'[]'::jsonb)) g
 WHERE z.ticket=b.id AND sp.occasion=p_occasion AND obj->>'type'='spot' AND obj->>'id'=sp.id::text AND g->>'id'=obj->>'group'
 AND bp.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) ORDER BY sp.id LIMIT 1),
 'fields',coalesce((SELECT jsonb_agg(jsonb_build_object('key',f->>'key','label',f->>'label','value',
 CASE f->>'source' WHEN 'builtin' THEN CASE f->>'key' WHEN 'holder_name' THEN to_jsonb(b.holder_name) WHEN 'note' THEN to_jsonb(b.note)
 WHEN 'spot' THEN (SELECT to_jsonb(sp.title) FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket WHERE z.ticket=b.id ORDER BY sp.id LIMIT 1)
 WHEN 'groups' THEN (SELECT jsonb_agg(gi.title ORDER BY gi.id) FROM public.occasion_users ou JOIN public.user_groups ug ON ug."user"=ou."user" JOIN public.user_group_info gi ON gi.id=ug."group" WHERE ou.ticket=b.id AND ou.occasion=p_occasion AND gi.occasion=p_occasion) END
 ELSE (SELECT e->(f->>'field_id') FROM jsonb_array_elements(CASE WHEN f->>'source'='order_field' THEN coalesce(b.order_data->'fields','[]'::jsonb) ELSE coalesce(b.data->'fields','[]'::jsonb) END) e WHERE e ? (f->>'field_id') LIMIT 1) END,
 'missing',CASE WHEN f->>'source'='builtin' THEN false ELSE NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.id=(f->>'field_id')::bigint AND ff.form=b.form) END,
 'hide_empty',coalesce((f->>'hide_empty')::boolean,true),'default_visible',coalesce((f->>'default_visible')::boolean,true)) ORDER BY idx)
 FROM jsonb_array_elements(p_config->'fields') WITH ORDINALITY a(f,idx) WHERE f->>'source'='builtin' OR (f->>'form_id')::bigint=b.form),'[]'::jsonb)))
 FROM projected b;
$$;

-- Source: database/functions/eshop_orders/scan_ticket.sql
CREATE OR REPLACE FUNCTION public.scan_ticket(scanned_id TEXT, scanned_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ticket_row RECORD;
    order_json JSONB;
    products_json JSONB;
    spot_json JSONB;
    groups_json JSONB; -- New variable for groups
    order_id BIGINT;
    occasion_id BIGINT;
    hide_price BOOLEAN := FALSE;
    target_user_id UUID; -- New variable to store the resolved User ID
    expected_scan_code TEXT;
    is_uuid BOOLEAN;
    -- Deposit info variables
    v_deposit_amount NUMERIC;
    v_paid NUMERIC;
    v_amount NUMERIC;
    v_deposit_deadline_days INT;
    v_deposit_deadline TEXT;
    v_occ_start_time TIMESTAMPTZ;
    v_occ_features JSONB;
    v_deposit_feature JSONB;
    v_deposit_info JSONB;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1((SELECT occasion FROM eshop.tickets WHERE ticket_symbol=scanned_id LIMIT 1)) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    -----------------------------------------------------
    -- 1. Attempt to find ticket by Ticket Symbol
    -----------------------------------------------------
    SELECT *
      INTO ticket_row
    FROM eshop.tickets
    WHERE ticket_symbol = scanned_id
    LIMIT 1;

    -----------------------------------------------------
    -- 1.a. Fallback: Scan by User ID if Ticket Symbol not found
    -----------------------------------------------------
    IF ticket_row IS NULL THEN
        -- Check if the scanned_id is a valid UUID format
        is_uuid := scanned_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

        IF is_uuid THEN
            -- If scanned by UUID, we know the user immediately
            target_user_id := scanned_id::UUID;

            SELECT t.*
              INTO ticket_row
            FROM public.occasion_users ou
            JOIN public.occasions o ON ou.occasion = o.id
            JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
            JOIN eshop.tickets t ON ou.ticket = t.id
            WHERE ou.user = target_user_id
              AND oh.secret = scanned_code
            LIMIT 1;
        END IF;
    END IF;

    -----------------------------------------------------
    -- 1.b. Final Check if Ticket is still missing
    -----------------------------------------------------
    IF ticket_row IS NULL OR ticket_row.state='waitlisted' OR ticket_row.ticket_symbol IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket or User with valid ticket not found');
    END IF;

    -----------------------------------------------------
    -- 2. Retrieve the associated order ID
    -----------------------------------------------------
    SELECT opt."order" INTO order_id
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ticket_row.id
    LIMIT 1;

    IF order_id IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code', 404, 'message', 'Order for ticket not found');
    END IF;

    -----------------------------------------------------
    -- 3. Retrieve the occasion ID from the order
    -----------------------------------------------------
    SELECT o.occasion, NOT coalesce((ss.config#>>'{sensitive,price}')::boolean,true)
      INTO occasion_id, hide_price
    FROM eshop.orders o
    JOIN public.occasions occ ON occ.id = o.occasion
    LEFT JOIN public.scanner_settings ss ON ss.occasion_id=occ.id
    WHERE o.id = order_id
    LIMIT 1;

    PERFORM public.check_occasion_writable(occasion_id);
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion for order not found');
    END IF;

    -----------------------------------------------------
    -- 3.b. Resolve User ID if not already found via UUID scan
    -----------------------------------------------------
    -- If we found the ticket via Symbol (Step 1), we need to find who holds it
    IF target_user_id IS NULL THEN
        SELECT "user" INTO target_user_id
        FROM public.occasion_users
        WHERE ticket = ticket_row.id
          AND occasion = occasion_id
        LIMIT 1;
    END IF;

    -----------------------------------------------------
    -- 4. Retrieve the expected scan_code
    -----------------------------------------------------
    SELECT oh.secret
      INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    IF expected_scan_code IS NULL THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object('code', 400, 'message', 'Scan code not defined for this occasion');
    END IF;

    -----------------------------------------------------
    -- 5. Validate the scanned_code
    -----------------------------------------------------
    IF scanned_code IS DISTINCT FROM expected_scan_code THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object('code', 401, 'message', 'Scan code is not correct');
    END IF;

    -----------------------------------------------------
    -- 6. Fetch order, products, spot, AND GROUPS
    -----------------------------------------------------

    IF NOT public.admit_scan_access_v1(occasion_id,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    IF NOT public.stripe_ticket_admission_allowed_internal(ticket_row.id) THEN
        RETURN jsonb_build_object('code',403,'message','stripe_admission_hold');
    END IF;

    -- A. Fetch Order
    SELECT CASE
             WHEN hide_price THEN
               (to_jsonb(o) - 'price') || jsonb_build_object(
                 'data',
                 CASE
                   WHEN jsonb_typeof(o.data->'tickets') = 'array' THEN
                     jsonb_set(
                       o.data,
                       '{tickets}',
                       COALESCE(
                         (
                           SELECT jsonb_agg(
                             CASE
                               WHEN jsonb_typeof(ticket->'products') = 'array' THEN
                                 jsonb_set(
                                   ticket,
                                   '{products}',
                                   COALESCE(
                                     (
                                       SELECT jsonb_agg(product - 'price')
                                       FROM jsonb_array_elements(ticket->'products') AS product
                                     ),
                                     '[]'::jsonb
                                   ),
                                   FALSE
                                 )
                               ELSE ticket
                             END
                           )
                           FROM jsonb_array_elements(o.data->'tickets') AS ticket
                         ),
                         '[]'::jsonb
                       ),
                       FALSE
                     )
                   ELSE o.data
                 END
               )
             ELSE to_jsonb(o)
           END
      INTO order_json
    FROM eshop.orders o
    WHERE o.id = order_id;

    -- B. Fetch Products
    SELECT jsonb_agg(
             CASE
               WHEN hide_price THEN
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
               ELSE
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'price', p.price,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
             END
           )
      INTO products_json
    FROM eshop.products p
    WHERE p.id IN (
        SELECT opt.product
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    );

    -- C. Fetch Spot
    SELECT row_to_json(s) INTO spot_json
    FROM eshop.spots s
    WHERE s.order_product_ticket IN (
        SELECT opt.id
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    )
    LIMIT 1;

    -- D. Fetch User Groups (New Logic)
    IF target_user_id IS NOT NULL THEN
        -- We construct a JSON object compatible with UserGroupInfoModel
        -- We join user_groups -> user_group_info -> places to get full context
        SELECT jsonb_agg(
                 to_jsonb(ugi) ||
                 jsonb_build_object(
                    'place_object', row_to_json(p)
                 )
               )
        INTO groups_json
        FROM public.user_groups ug
        JOIN public.user_group_info ugi ON ug."group" = ugi.id
        LEFT JOIN public.places p ON ugi.place = p.id
        WHERE ug."user" = target_user_id
          AND ugi.occasion = occasion_id;
    END IF;

    -----------------------------------------------------
    -- 6E. Fetch deposit info for deposit orders
    -----------------------------------------------------
    SELECT pi.deposit_amount, pi.paid, pi.amount
    INTO v_deposit_amount, v_paid, v_amount
    FROM eshop.payment_info pi
    JOIN eshop.orders o ON o.payment_info = pi.id
    WHERE o.id = order_id;

    IF v_deposit_amount IS NOT NULL THEN
        -- Get occasion features and start_time for deposit deadline
        SELECT occ.features, occ.start_time
        INTO v_occ_features, v_occ_start_time
        FROM public.occasions occ
        WHERE occ.id = occasion_id;

        -- Read deposit deadline from deposit feature in features JSONB
        SELECT elem INTO v_deposit_feature
        FROM jsonb_array_elements(v_occ_features) elem
        WHERE elem->>'code' = 'deposit';

        v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
        v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

        v_deposit_info := jsonb_build_object(
            'remaining_amount', GREATEST(0, COALESCE(v_amount, 0) - COALESCE(v_paid, 0)),
            'is_fully_paid', COALESCE(v_paid, 0) >= COALESCE(v_amount, 0),
            'deadline_type', CASE
                WHEN v_deposit_deadline = 'on_site' THEN 'on_site'
                WHEN v_deposit_deadline_days IS NOT NULL THEN 'date'
                ELSE NULL
            END,
            'deadline_date', CASE
                WHEN v_deposit_deadline_days IS NOT NULL AND v_deposit_deadline IS DISTINCT FROM 'on_site'
                THEN (v_occ_start_time - make_interval(days => v_deposit_deadline_days))::text
                ELSE NULL
            END,
            'deposit_amount', v_deposit_amount,
            'total_amount', v_amount,
            'paid_amount', COALESCE(v_paid, 0)
        );
    END IF;

    -----------------------------------------------------
    -- 7. Return the compiled JSONB response
    -----------------------------------------------------
    RETURN jsonb_build_object(
        'code', 200,
        'ticket', to_jsonb(ticket_row)||jsonb_build_object('online_required',public.stripe_ticket_requires_online_internal(ticket_row.id),
            'batch',(SELECT jsonb_build_object('title',b.title) FROM eshop.ticket_batch_items i
                JOIN eshop.ticket_batches b ON b.id=i.batch_id
                WHERE i.ticket_id=ticket_row.id AND b.occasion=occasion_id)),
        'order', order_json,
        'products', products_json,
        'spot', spot_json,
        'groups', COALESCE(groups_json, '[]'::jsonb),
        'deposit_info', v_deposit_info
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred: ' || SQLERRM
        );
END;
$$;

-- Source: database/functions/eshop_orders/get_all_tickets_for_scan.sql
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
            'batch', (SELECT jsonb_build_object('title',b.title) FROM eshop.ticket_batch_items i
                JOIN eshop.ticket_batches b ON b.id=i.batch_id
                WHERE i.ticket_id=t.id AND b.occasion=occasion_id_val),
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

-- Source: database/functions/scanning/admission.sql (search_scanner_tickets)
CREATE OR REPLACE FUNCTION public.search_scanner_tickets(p_session uuid,p_token text,p_query text,p_after bigint DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token); SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT coalesce((cfg.config#>>'{manual_search,tickets}')::boolean,false) THEN RAISE insufficient_privilege USING MESSAGE='manual_search_disabled'; END IF;
 IF length(p_query) NOT BETWEEN 2 AND 100 THEN RETURN jsonb_build_object('code',400,'reason','invalid_query','server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT coalesce(jsonb_agg(dto ORDER BY ticket_id),'[]'::jsonb) INTO result FROM (
 SELECT * FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config) WHERE ticket_id>p_after
 AND (strpos(lower(dto->>'batch_title'),lower(p_query))>0 OR strpos(lower(dto->>'holder_name'),lower(p_query))>0 OR strpos(lower(dto->>'symbol'),lower(p_query))>0) ORDER BY ticket_id LIMIT 30) found;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;

COMMIT;
