-- Scanner credentials and navigation are bound to one occasion.

-- SOURCE: scanning/credential_revocations.sql
-- A previously shared bearer credential must never become valid again merely
-- because one of its occasions was deleted or an old hidden row was removed.
CREATE TABLE IF NOT EXISTS public.scanner_revoked_credentials (
 secret_hash text PRIMARY KEY CHECK(secret_hash ~ '^[0-9a-f]{64}$'),
 revoked_at timestamptz NOT NULL DEFAULT now(),
 reason text NOT NULL CHECK(reason='historical_shared')
);
ALTER TABLE public.scanner_revoked_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.scanner_revoked_credentials FROM PUBLIC,anon,authenticated,service_role;

-- Security metadata only: no occasion, ticket, session or credential is changed.
-- Freeze the rejection of every currently ambiguous secret across this shared
-- backend, including identical secret text on separate historical hidden rows.
INSERT INTO public.scanner_revoked_credentials(secret_hash,reason)
 SELECT encode(extensions.digest(h.secret,'sha256'),'hex'),'historical_shared'
 FROM public.occasions o JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
 WHERE h.secret IS NOT NULL
 GROUP BY h.secret HAVING count(*)>1
 ON CONFLICT(secret_hash) DO NOTHING;

-- SOURCE: user_permissions/technical_operations.sql
-- One live scan-link proof owner for session bootstrap and retained legacy
-- readers. The actual occasion comes from the stored secret relationship;
-- NULL is never a proof. This resolver does not grant editor capabilities.
CREATE OR REPLACE FUNCTION public.get_scanner_occasion_for_scan_code_internal(p_code text)
RETURNS SETOF public.occasions LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=public,extensions AS $$
 -- Legacy copies can share a hidden row. Ambiguity is never a scan proof.
 SELECT (candidate.occasion).* FROM (
   SELECT occasion, count(*) OVER () AS matches
   FROM public.occasions occasion
   JOIN public.occasions_hidden hidden ON hidden.id=occasion.occasion_hidden
   WHERE p_code IS NOT NULL AND p_code<>'' AND hidden.secret=p_code
   AND NOT EXISTS (SELECT 1 FROM public.scanner_revoked_credentials revoked
       WHERE revoked.secret_hash=encode(extensions.digest(p_code,'sha256'),'hex'))
 ) candidate WHERE candidate.matches=1;
$$;
REVOKE ALL ON FUNCTION public.get_scanner_occasion_for_scan_code_internal(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_occasion_for_scan_code_internal(text) TO postgres;

-- SOURCE: eshop_orders/update_scan_code.sql
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
    v_occasion_id BIGINT;
    occasions_hidden_id BIGINT;
BEGIN
    -- 1. Retrieve occasion_id using occasion_link
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- 2. Check if occasion_link is valid
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion link does not exist.'
        );
    END IF;

    -- 3. Verify if the user is an editor on the occasion
    IF NOT can_write_orders(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to edit this occasion.'
        );
    END IF;

    IF new_scan_code IS NULL OR btrim(new_scan_code)='' THEN
        RETURN jsonb_build_object('code',400,'message','Scan code must not be empty.');
    END IF;

    -- Per-event locking owns rotation; the unique index arbitrates cross-event collisions.
    PERFORM 1 FROM public.occasions WHERE id=v_occasion_id FOR UPDATE;
    PERFORM 1 FROM public.scanner_settings WHERE scanner_settings.occasion_id=v_occasion_id FOR UPDATE;
    -- 4. Check if occasions_hidden exists for the occasion
    SELECT o.occasion_hidden
    INTO occasions_hidden_id
    FROM public.occasions o
    WHERE o.id = v_occasion_id;

    PERFORM 1 FROM public.occasions_hidden WHERE id=occasions_hidden_id FOR UPDATE;
    -- Do not gradually revive a credential that every copied event already knows.
    -- Historical groups need one explicit repair that retires their shared proof.
    IF EXISTS (SELECT 1 FROM public.occasions o
        WHERE o.occasion_hidden=occasions_hidden_id AND o.id<>v_occasion_id) THEN
        RETURN jsonb_build_object('code',409,'reason','shared_scan_credential',
            'message','Copied occasions require separate scanner links from an administrator.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.scanner_revoked_credentials revoked
        WHERE revoked.secret_hash=encode(extensions.digest(new_scan_code,'sha256'),'hex')) THEN
        RETURN jsonb_build_object('code',409,'reason','scan_code_collision','message','Scan code is already in use.');
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.occasions_hidden h WHERE h.secret=new_scan_code
        AND (h.id IS DISTINCT FROM occasions_hidden_id OR EXISTS (
            SELECT 1 FROM public.occasions o
            WHERE o.occasion_hidden=h.id AND o.id<>v_occasion_id
        ))
    ) THEN
        RETURN jsonb_build_object('code',409,'reason','scan_code_collision','message','Scan code is already in use.');
    END IF;

    IF occasions_hidden_id IS NOT NULL THEN
        -- The existing record is exclusively owned by this event.
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
        WHERE id = v_occasion_id;
    END IF;

    UPDATE public.scanner_settings SET epoch=epoch+1 WHERE scanner_settings.occasion_id=v_occasion_id;

    -- 5. Return a success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Scan code updated successfully.'
    );

EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object('code',409,'reason','scan_code_collision','message','Scan code is already in use.');
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;

REVOKE ALL ON FUNCTION public.update_scan_code(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_scan_code(text,text) TO authenticated,service_role;

-- SOURCE: scanning/access_codes.sql
-- Secret uniqueness is enforced across all events, including simultaneous writers.
CREATE UNIQUE INDEX IF NOT EXISTS occasions_hidden_scan_secret_unique_idx
 ON public.occasions_hidden(secret) WHERE secret IS NOT NULL;

-- Both initialization and explicit rotation use the same stored occasion lock
-- and the existing authorized write owner. Clients never allocate credentials.
CREATE OR REPLACE FUNCTION public.get_or_create_scan_code(occasion_link text, p_rotate boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE oc public.occasions; existing text; candidate text; bytes bytea;
 ch integer; i integer; attempt integer; result jsonb;
BEGIN
 p_rotate:=coalesce(p_rotate,false);
 SELECT * INTO oc FROM public.occasions WHERE id=public.resolve_occasion_link_internal(occasion_link);
 IF oc.id IS NULL THEN RETURN jsonb_build_object('code',404,'message','Occasion link does not exist.'); END IF;
 IF (p_rotate AND NOT public.can_write_orders(oc.id))
    OR (NOT p_rotate AND NOT public.can_read_orders(oc.id)) THEN
   RETURN jsonb_build_object('code',403,'message','User is not authorized for this occasion.');
 END IF;
 SELECT * INTO oc FROM public.occasions WHERE id=oc.id FOR UPDATE;
 SELECT h.secret INTO existing FROM public.occasions_hidden h WHERE h.id=oc.occasion_hidden;
 IF NOT p_rotate AND existing IS NOT NULL AND EXISTS (
   SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(existing) proof WHERE proof.id=oc.id
 ) THEN RETURN jsonb_build_object('code',200,'scan_code',existing); END IF;
 IF NOT public.can_write_orders(oc.id) THEN
   RETURN jsonb_build_object('code',403,'message','User is not authorized to initialize this scanner.');
 END IF;
 FOR attempt IN 1..32 LOOP
   candidate:='';
   WHILE length(candidate)<5 LOOP
     bytes:=gen_random_bytes(16);
     FOR i IN 0..15 LOOP
       ch:=get_byte(bytes,i);
       IF ch<252 THEN candidate:=candidate||substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',1+(ch%36),1); END IF;
       EXIT WHEN length(candidate)=5;
     END LOOP;
   END LOOP;
   -- A rotation must actually replace the old credential, even on a random hit.
   IF candidate IS NOT DISTINCT FROM existing THEN CONTINUE; END IF;
   result:=public.update_scan_code(occasion_link,candidate);
   IF result->>'code'='200' THEN RETURN result||jsonb_build_object('scan_code',candidate); END IF;
   IF result->>'reason' IS DISTINCT FROM 'scan_code_collision' THEN RETURN result; END IF;
 END LOOP;
 RETURN jsonb_build_object('code',503,'message','Unable to allocate a unique scan code.');
END $$;
REVOKE ALL ON FUNCTION public.get_or_create_scan_code(text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_scan_code(text,boolean) TO authenticated,service_role;

-- SOURCE: eshop_orders/get_occasion_by_scan_code.sql
CREATE OR REPLACE FUNCTION public.get_occasion_by_scan_code(scan_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    found_occasion_record RECORD;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1(NULL) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    SELECT o.id, o.title, o.features
    INTO found_occasion_record
    FROM public.get_scanner_occasion_for_scan_code_internal(scan_code) o;

    IF found_occasion_record IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code',401,'message','invalid_scan_code');
    END IF;

    IF NOT public.admit_scan_access_v1(found_occasion_record.id,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    RETURN jsonb_build_object(
        'id', found_occasion_record.id,
        'title', found_occasion_record.title,
        'features', found_occasion_record.features,
        'scanner_field_mappings', (SELECT coalesce(jsonb_object_agg(f->>'field_id',f->>'label'),'{}'::jsonb)
         FROM jsonb_array_elements((SELECT config->'fields' FROM public.scanner_settings WHERE occasion_id=found_occasion_record.id)) f
         WHERE f->>'source'='order_field' AND coalesce((f->>'default_visible')::boolean,true))
    );
END;
$$;

-- SOURCE: eshop_orders/get_all_tickets_for_scan.sql
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
    FROM public.get_scanner_occasion_for_scan_code_internal(scan_code) o;

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
            'batch', (SELECT jsonb_build_object('title',b.title) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id AND b.occasion=occasion_id_val),
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
          AND NOT public.provider_ticket_requires_online_internal(t.id)
        ORDER BY t.id
    ) t;

    IF octet_length(result::text)>max_bytes THEN RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded'); END IF;
    RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- SOURCE: eshop_orders/scan_ticket.sql
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
    IF scanned_code IS DISTINCT FROM expected_scan_code OR NOT EXISTS (
        SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(scanned_code) proof
        WHERE proof.id=occasion_id
    ) THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object('code', 401, 'message', 'Scan code is not correct');
    END IF;

    -----------------------------------------------------
    -- 6. Fetch order, products, spot, AND GROUPS
    -----------------------------------------------------

    IF NOT public.admit_scan_access_v1(occasion_id,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    IF NOT public.provider_ticket_admission_allowed_internal(ticket_row.id) THEN
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
    SELECT pi.deposit_amount, coalesce(pi.paid,0)-coalesce(pi.returned,0), pi.amount
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
        'ticket', to_jsonb(ticket_row)||jsonb_build_object('online_required',public.provider_ticket_requires_online_internal(ticket_row.id),'batch',(SELECT jsonb_build_object('title',b.title) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=ticket_row.id AND b.occasion=occasion_id)),
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

-- SOURCE: eshop_orders/update_ticket_to_used.sql
CREATE OR REPLACE FUNCTION public.update_ticket_to_used(
    ticket_id bigint,
    scan_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    current_state text;
    expected_scan_code text;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1((SELECT occasion FROM eshop.tickets WHERE id=ticket_id)) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    -- 1. Validate Ticket Existence
    IF NOT EXISTS (
        SELECT 1 FROM eshop.tickets WHERE id = ticket_id
    ) THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Ticket not found.'
        );
    END IF;

    -- 2. Retrieve Associated Occasion ID AND Current State
    SELECT occasion, state
    INTO occasion_id, current_state
    FROM eshop.tickets
    WHERE id = ticket_id;

    -- Check if occasion_id is present (Integrity check)
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion associated with ticket not found.'
        );
    END IF;

    -- 3. Retrieve Expected Scan Code from occasions_hidden via foreign key
    SELECT oh.secret
    INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    -- Check if scan_code is defined
    IF expected_scan_code IS NULL THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Scan code not defined for occasion.'
        );
    END IF;

    -- 4. Validate Provided Scan Code
    IF scan_code IS DISTINCT FROM expected_scan_code OR NOT EXISTS (
        SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(scan_code) proof
        WHERE proof.id=occasion_id
    ) THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object(
            'code', 401,
            'message', 'Scan code is not correct.'
        );
    END IF;

    IF NOT public.admit_scan_access_v1(occasion_id,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;

    PERFORM public.scanner_lock_ticket_internal(ticket_id);
    SELECT state INTO current_state FROM eshop.tickets WHERE id=ticket_id;

    -- 2a. Validate Ticket State (New Check)
    IF current_state = 'used' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket has already been used.'
        );
    ELSIF current_state = 'storno' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket is cancelled (storno).'
        );
    END IF;

    PERFORM public.check_ticket_is_mutable(ticket_id);

    -- 5. Update Ticket State to 'used' AND update timestamp
    PERFORM public.scanner_admit_ticket_internal(ticket_id);

    -- 6. Return Success Message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Ticket state updated to used successfully.'
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

-- SOURCE: eshop_orders/reset_password_via_scan.sql
CREATE OR REPLACE FUNCTION public.reset_password_via_scan(
    ticket_id bigint,
    password text,
    scan_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_expected_scan_code text;
    v_target_user_id uuid;
    v_target_email text;
    v_encrypted_pw text;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1((SELECT occasion FROM eshop.tickets WHERE id=ticket_id)) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    -- =================================================================
    -- 1. INPUT VALIDATION
    -- =================================================================
    IF ticket_id IS NULL THEN
         RETURN jsonb_build_object('code', 400, 'message', 'Ticket ID is missing.');
    END IF;

    IF password IS NULL OR trim(password) = '' THEN
         RETURN jsonb_build_object('code', 400, 'message', 'Password cannot be empty.');
    END IF;

    -- =================================================================
    -- 2. VALIDATE TICKET AND SCAN CODE
    -- =================================================================

    -- Get Occasion ID from Ticket
    SELECT occasion INTO v_occasion_id
    FROM eshop.tickets
    WHERE id = ticket_id;

    IF v_occasion_id IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found or no occasion assigned.');
    END IF;

    -- Get Expected Scan Code (Secret) from Occasions Hidden
    SELECT oh.secret INTO v_expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = v_occasion_id
    LIMIT 1;

    IF v_expected_scan_code IS NULL THEN
        PERFORM public.admit_scan_access_v1(v_occasion_id,false);
        RETURN jsonb_build_object('code', 400, 'message', 'Scan code not defined for this occasion.');
    END IF;

    -- Verify Code Matches
    IF scan_code IS DISTINCT FROM v_expected_scan_code OR NOT EXISTS (
        SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(scan_code) proof
        WHERE proof.id=v_occasion_id
    ) THEN
        PERFORM public.admit_scan_access_v1(v_occasion_id,false);
        RETURN jsonb_build_object('code', 401, 'message', 'Invalid scan code.');
    END IF;

    -- =================================================================
    -- 3. IDENTIFY TARGET USER
    -- =================================================================

    -- Find the user attached to this ticket via occasion_users
    SELECT "user" INTO v_target_user_id
    FROM public.occasion_users
    WHERE ticket = ticket_id;

    IF v_target_user_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No user found associated with this ticket.');
    END IF;

    -- =================================================================
    -- 4. SECURITY CHECK: PREVENT RESET FOR PRIVILEGED USERS
    -- =================================================================
    BEGIN
        PERFORM public.check_is_scan_password_reset_target_allowed(
            v_target_user_id
        );
    EXCEPTION
        WHEN insufficient_privilege THEN
            RETURN jsonb_build_object(
                'code', 403,
                'message', 'Security Restriction: Cannot reset password for privileged users via scan.'
            );
    END;

    -- =================================================================
    -- 5. PERFORM PASSWORD RESET
    -- =================================================================

    IF NOT public.admit_scan_password_reset_v1(v_occasion_id,v_target_user_id) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;

    -- Generate encrypted password
    v_encrypted_pw := crypt(password, gen_salt('bf'));

    -- Update auth.users
    UPDATE auth.users
    SET encrypted_password = v_encrypted_pw
    WHERE id = v_target_user_id
    RETURNING email INTO v_target_email;

    IF v_target_email IS NULL THEN
         -- Fallback if email wasn't returned (unlikely if ID exists)
         RETURN jsonb_build_object('code', 500, 'message', 'Password updated, but failed to retrieve email.');
    END IF;

    -- =================================================================
    -- 6. SUCCESS RESPONSE
    -- =================================================================
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Password successfully reset.',
        'email', v_target_email
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;

REVOKE ALL ON FUNCTION public.reset_password_via_scan(bigint, text, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_password_via_scan(bigint, text, text)
  TO anon, authenticated, service_role;

-- SOURCE: scanning/sessions.sql
CREATE OR REPLACE FUNCTION public.scanner_session_internal(p_session uuid,p_token text,p_allow_expired boolean DEFAULT false)
RETURNS public.scanner_sessions LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; secret text;
BEGIN
 -- Shared policy then session locks also serialize revocation and settings changes.
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=(SELECT occasion_id FROM public.scanner_sessions WHERE id=p_session) FOR SHARE;
 SELECT * INTO s FROM public.scanner_sessions WHERE id=p_session FOR SHARE;
 IF s.id IS NULL OR p_token IS NULL OR s.token_hash<>encode(digest(p_token,'sha256'),'hex') THEN
  RAISE SQLSTATE 'PT401' USING MESSAGE='invalid_scanner_session'; END IF;
 IF s.actor_user_id IS NOT NULL AND (auth.uid() IS DISTINCT FROM s.actor_user_id OR NOT public.scanner_can_manage_settings_internal(s.occasion_id)) THEN
  RAISE SQLSTATE 'PT403' USING MESSAGE='scanner_actor_changed'; END IF;
 SELECT oh.secret INTO secret FROM public.occasions o JOIN public.occasions_hidden oh ON oh.id=o.occasion_hidden WHERE o.id=s.occasion_id;
 IF NOT p_allow_expired AND (s.revoked_at IS NOT NULL OR s.expires_at<=now() OR s.epoch<>cfg.epoch
 OR (s.access_origin='scan_link' AND (
   s.scan_secret_hash IS DISTINCT FROM encode(digest(secret,'sha256'),'hex')
   OR NOT EXISTS (SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(secret) proof WHERE proof.id=s.occasion_id)
 ))) THEN
  RAISE SQLSTATE 'PT401' USING MESSAGE='scanner_session_expired'; END IF;
 RETURN s;
END $$;
CREATE OR REPLACE FUNCTION public.open_scanner_session(p_scan_code text DEFAULT NULL,p_occasion bigint DEFAULT NULL,p_device_name text DEFAULT 'Hlavní vstup')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; s public.scanner_sessions; cfg public.scanner_settings; token text; origin text; sec text;
BEGIN
 IF NOT public.check_scan_attempt_budget_v1(p_occasion) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now()); END IF;
 IF p_scan_code IS NOT NULL THEN
  SELECT * INTO oc FROM public.get_scanner_occasion_for_scan_code_internal(p_scan_code) LIMIT 1;
  -- record assignment above must match the occasion row exactly
  origin:='scan_link'; sec:=p_scan_code;
 ELSE
  PERFORM public.scanner_require_settings_editor_internal(p_occasion);
  SELECT * INTO oc FROM public.occasions WHERE id=p_occasion; origin:='authenticated';
 END IF;
 IF oc.id IS NULL THEN PERFORM public.admit_scan_access_v1(NULL,false); RETURN jsonb_build_object('code',401,'reason','invalid_scan_code','server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(oc.id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 INSERT INTO public.scanner_settings(occasion_id,config) VALUES(oc.id,public.scanner_default_settings_internal(oc.id)) ON CONFLICT DO NOTHING;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=oc.id FOR SHARE;
 token:=encode(gen_random_bytes(32),'hex');
 INSERT INTO public.scanner_sessions(occasion_id,actor_user_id,access_origin,token_hash,scan_secret_hash,epoch,device_name,expires_at,offline_until)
 VALUES(oc.id,CASE WHEN origin='authenticated' THEN auth.uid() END,origin,encode(digest(token,'sha256'),'hex'),encode(digest(sec,'sha256'),'hex'),cfg.epoch,left(p_device_name,80),now()+interval '12 hours',
 now()+make_interval(hours=>CASE WHEN (cfg.config#>>'{offline,enabled}')::boolean THEN (cfg.config#>>'{offline,max_hours}')::integer ELSE 0 END)) RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'server_time',now(),'data',jsonb_build_object('session_id',s.id,'token',token,'occasion_id',oc.id,'organization_id',oc.organization,
 'title',oc.title,'occasion_link',oc.link,'epoch',s.epoch,'expires_at',s.expires_at,'offline_until',s.offline_until,'settings_revision',cfg.revision,'settings',cfg.config,'device_name',s.device_name,
 'capabilities',jsonb_build_object('search_tickets',(cfg.config#>>'{manual_search,tickets}')::boolean,'search_users',(cfg.config#>>'{manual_search,users}')::boolean,
 'settings',public.scanner_can_manage_settings_internal(oc.id),'event_history',auth.uid() IS NOT NULL AND public.can_write_orders(oc.id),'offline',(cfg.config#>>'{offline,enabled}')::boolean)));
END $$;
CREATE OR REPLACE FUNCTION public.revoke_scanner_session(p_session uuid,p_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions;
BEGIN
 SELECT * INTO s FROM public.scanner_sessions WHERE id=p_session;
 IF p_token IS NOT NULL THEN s:=public.scanner_session_internal(p_session,p_token,true);
 ELSE PERFORM public.check_is_editor_order_on_occasion(s.occasion_id); END IF;
 UPDATE public.scanner_sessions SET revoked_at=now() WHERE id=p_session;
 RETURN jsonb_build_object('code',200,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.scanner_session_internal(uuid,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.open_scanner_session(text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.open_scanner_session(text,bigint,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.revoke_scanner_session(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_scanner_session(uuid,text) TO anon,authenticated,service_role;
