-- Form payment defaults: nullable inheritance and explicit zero, one canonical email queue.
CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND coalesce(v_pi.paid,0)<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.queue_payment_reminders(p_occasion_id BIGINT, p_seconds_before_deadline BIGINT)
RETURNS VOID
SET search_path = public, extensions AS $$
-- The interval argument is retained for callers; persisted form/occasion settings own scheduling.
BEGIN

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='reminder_superseded',lease_token=NULL,lease_until=NULL
  WHERE (occasion=p_occasion_id OR order_id IN (SELECT id FROM eshop.orders WHERE payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))) AND message_kind='order_reminder' AND workflow_state IN ('pending','retry_wait','blocked','preparing');
  UPDATE eshop.payment_info pi SET email_reminder_version=email_reminder_version+1
  WHERE EXISTS(SELECT 1 FROM eshop.orders o WHERE o.payment_info=pi.id AND o.occasion=p_occasion_id);

  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id
    ),occ.organization,o.occasion,occ.unit,pi.deadline - make_interval(secs=>coalesce((f.data->>'reminder_interval_seconds')::bigint,(form_settings.feature->>'reminder_interval_seconds')::bigint,86400))) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE

  LEFT JOIN public.forms f ON f.id = o.form
  WHERE
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    AND o.state = 'ordered'
    AND pi.deadline IS NOT NULL

    AND (pi.data->>'current_version_reminded')::boolean IS NOT TRUE

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE

    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;

  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id,
      'is_deposit_reminder', true
    ),occ.organization,o.occasion,occ.unit,(occ.start_time - make_interval(days => (deposit_settings.feature->>'deposit_deadline_days')::int)) - make_interval(secs=>coalesce((f.data->>'reminder_interval_seconds')::bigint,(form_settings.feature->>'reminder_interval_seconds')::bigint,86400))) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'deposit'
  ) deposit_settings ON TRUE

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE
  LEFT JOIN public.forms f ON f.id = o.form
  WHERE
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    -- Schedule the balance reminder before deposit payment, as order creation always did.
    AND o.state IN ('ordered','paid')
    AND pi.deposit_amount IS NOT NULL
    AND coalesce(pi.paid,0) < pi.amount

    AND (deposit_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (deposit_settings.feature->>'deposit_deadline') IS DISTINCT FROM 'on_site'

    AND (deposit_settings.feature->>'deposit_deadline_days') IS NOT NULL

    AND occ.start_time IS NOT NULL

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE
    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.set_payment_deadline(p_payment_info_id bigint,p_new_deadline timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE o record;
BEGIN
 PERFORM public.check_payment_info_is_mutable(p_payment_info_id);
 UPDATE eshop.payment_info SET deadline=p_new_deadline,data=coalesce(data,'{}')||'{"current_version_reminded":false}'::jsonb,
 email_reminder_version=email_reminder_version+1 WHERE id=p_payment_info_id;
 FOR o IN SELECT DISTINCT occ.id FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion WHERE ord.payment_info=p_payment_info_id LOOP
  PERFORM public.queue_payment_reminders(o.id,0);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    v_ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_ticket_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id AND (NOT p_offer OR product IS NOT NULL)) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT * INTO spot_data
                FROM eshop.spots
                WHERE id = (ticket_data->>'spot')::BIGINT
                  AND occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            v_ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            IF p_offer THEN
              ticket_id:=(ticket_data->>'ticketId')::bigint;
              UPDATE eshop.tickets t SET state='ordered',ticket_symbol=v_ticket_symbol,
                note=ticket_note,data=public.extract_ticket_answers_internal(form_id,ticket_data),updated_at=now
              WHERE t.id=ticket_id AND t.state='waitlisted' AND t.ticket_symbol IS NULL
                AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=order_id AND x.product IS NULL)
                AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots x WHERE x.ticket_id=t.id AND x.outcome='accepted');
              IF NOT FOUND THEN RAISE EXCEPTION 'Invalid waiting ticket finalization'; END IF;
              DELETE FROM eshop.order_product_ticket WHERE "order"=order_id AND ticket=ticket_id AND product IS NULL;
            ELSE
              IF ticket_data ? 'ticketId' THEN RAISE EXCEPTION 'Ticket identity is server assigned'; END IF;
              INSERT INTO eshop.tickets (state,occasion,ticket_symbol,note,data,created_at,updated_at)
              VALUES('ordered',occasion_id,v_ticket_symbol,ticket_note,public.extract_ticket_answers_internal(form_id,ticket_data),now,now) RETURNING id INTO ticket_id;
            END IF;
            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=order_id AND x.ticket=ticket_id) THEN
              INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,NULL);
            END IF;
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', v_ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        generated_variable_symbol := generate_payment_variable_symbol(bank_account_id, form_id);
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- NULL inherits the occasion default; zero is an explicit immediate deadline.
          form_deadline_duration := coalesce(form_deadline_duration,
            (SELECT (feature->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) feature WHERE feature->>'code'='form'),604800);
          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- One queue boundary resolves form and occasion reminder settings.
                    PERFORM public.queue_payment_reminders(occasion_id,0);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;
