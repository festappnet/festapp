-- Keep canonical seating in creation history; compare legacy group labels only when historically recorded.

-- SOURCE: eshop_orders/get_order_change_summary_v1.sql
-- Internal read model shared by the editor preview and email preparation.
CREATE OR REPLACE FUNCTION public.get_order_change_summary_v1(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
 v_current jsonb; v_currency text; v_current_price numeric; v_reference eshop.orders_history; v_latest bigint;
 v_sent_at timestamptz; v_ref_tickets jsonb; v_cur_tickets jsonb;
 v_ref jsonb; v_cur jsonb; v_ticket jsonb; v_symbol text; v_state text;
 v_before jsonb; v_after jsonb; v_added jsonb; v_removed jsonb; v_changed jsonb;
 v_cancelled jsonb:='[]'; v_removed_tickets jsonb:='[]'; v_added_tickets jsonb:='[]';
 v_product_changes jsonb:='[]'; v_old_total numeric:=0; v_new_total numeric:=0;
 i integer; j integer; v_has_changes boolean;
BEGIN
 SELECT data,currency_code,price INTO v_current,v_currency,v_current_price FROM eshop.orders WHERE id=p_order_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
 SELECT id INTO v_latest FROM eshop.orders_history WHERE "order"=p_order_id
 ORDER BY created_at DESC,id DESC LIMIT 1;
 SELECT * INTO v_reference FROM eshop.orders_history WHERE "order"=p_order_id
 AND data->>'is_sent_to_customer'='true' ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN v_sent_at:=v_reference.created_at;
 ELSE
  SELECT * INTO v_reference FROM eshop.orders_history WHERE "order"=p_order_id
  ORDER BY created_at ASC,id ASC LIMIT 1;
 END IF;
 v_ref_tickets:=coalesce(v_reference.data->'tickets','[]');
 v_cur_tickets:=coalesce(v_current->'tickets','[]');
 SELECT coalesce(sum(coalesce((p->>'price')::numeric,0)),0) INTO v_old_total
 FROM jsonb_array_elements(v_ref_tickets) t,jsonb_array_elements(coalesce(t->'products','[]')) p;
 SELECT coalesce(sum(coalesce((p->>'price')::numeric,0)),0) INTO v_new_total
 FROM jsonb_array_elements(v_cur_tickets) t,jsonb_array_elements(coalesce(t->'products','[]')) p;
 v_old_total:=coalesce(v_reference.price,v_old_total);
 v_new_total:=coalesce(v_current_price,v_new_total);
 -- Without history there is no evidence from which to invent a change.
 IF v_reference.id IS NOT NULL THEN
  FOR v_ref IN SELECT value FROM jsonb_array_elements(v_ref_tickets) LOOP
   SELECT value INTO v_cur FROM jsonb_array_elements(v_cur_tickets)
   WHERE (v_ref->>'id' IS NOT NULL AND value->>'id'=v_ref->>'id')
      OR (v_ref->>'id' IS NULL AND value=v_ref) LIMIT 1;
   v_symbol:=NULL; v_state:=NULL;
   -- Order membership prevents historical/foreign IDs leaking ticket metadata.
   SELECT t.ticket_symbol,t.state INTO v_symbol,v_state FROM eshop.tickets t
   WHERE t.id::text=v_ref->>'id' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket opt
      WHERE opt.ticket=t.id AND opt."order"=p_order_id);
   v_ticket:=jsonb_build_object('id',v_ref->'id','ticket_symbol',
     coalesce(nullif(v_ref->>'ticket_symbol',''),v_symbol),'products',coalesce(v_ref->'products','[]'));
   IF v_cur IS NULL THEN
    IF v_state='storno' THEN v_cancelled:=v_cancelled||jsonb_build_array(v_ticket);
    ELSE v_removed_tickets:=v_removed_tickets||jsonb_build_array(v_ticket); END IF;
    CONTINUE;
   END IF;
   v_before:=coalesce(v_ref->'products','[]'); v_after:=coalesce(v_cur->'products','[]');
   v_added:='[]'; v_removed:='[]'; v_changed:='[]';
   -- Preserve duplicate instances; never pair products across different tickets.
   IF jsonb_array_length(v_after)>0 THEN
    FOR i IN REVERSE jsonb_array_length(v_after)-1..0 LOOP
     SELECT ordinality::integer-1 INTO j FROM jsonb_array_elements(v_before) WITH ORDINALITY
     WHERE value->>'id' IS NOT DISTINCT FROM v_after->i->>'id'
       AND value->>'title' IS NOT DISTINCT FROM v_after->i->>'title'
       AND value->>'currency_code' IS NOT DISTINCT FROM v_after->i->>'currency_code'
       AND nullif(value->>'spot_title', '') IS NOT DISTINCT FROM nullif(v_after->i->>'spot_title', '')
       -- A missing historical group was never captured, so enrichment cannot prove a change.
       AND (nullif(value->>'spot_group_title', '') IS NULL
         OR nullif(value->>'spot_group_title', '') IS NOT DISTINCT FROM nullif(v_after->i->>'spot_group_title', ''))
       AND abs(coalesce((value->>'price')::numeric,0)-coalesce((v_after->i->>'price')::numeric,0))<0.001
     ORDER BY ordinality LIMIT 1;
     IF j IS NOT NULL THEN v_before:=v_before-j; v_after:=v_after-i; END IF;
    END LOOP;
   END IF;
   IF jsonb_array_length(v_after)>0 THEN
    FOR i IN REVERSE jsonb_array_length(v_after)-1..0 LOOP
     SELECT ordinality::integer-1 INTO j FROM jsonb_array_elements(v_before) WITH ORDINALITY
     WHERE value->>'id' IS NOT DISTINCT FROM v_after->i->>'id' ORDER BY ordinality LIMIT 1;
     IF j IS NOT NULL THEN
      v_changed:=v_changed||jsonb_build_array(jsonb_build_object('from',v_before->j,'to',v_after->i));
      v_before:=v_before-j; v_after:=v_after-i;
     END IF;
    END LOOP;
   END IF;
   v_added:=v_after; v_removed:=v_before;
   IF jsonb_array_length(v_added)+jsonb_array_length(v_removed)+jsonb_array_length(v_changed)>0 THEN
    v_product_changes:=v_product_changes||jsonb_build_array(v_ticket||jsonb_build_object(
     'added',v_added,'removed',v_removed,'changed',v_changed));
   END IF;
  END LOOP;
  FOR v_cur IN SELECT value FROM jsonb_array_elements(v_cur_tickets) LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_ref_tickets) r
     WHERE (v_cur->>'id' IS NOT NULL AND r->>'id'=v_cur->>'id') OR (v_cur->>'id' IS NULL AND r=v_cur)) THEN
    v_added_tickets:=v_added_tickets||jsonb_build_array(v_cur);
   END IF;
  END LOOP;
 END IF;
 v_has_changes:=v_reference.id IS NOT NULL AND (jsonb_array_length(v_cancelled)+jsonb_array_length(v_removed_tickets)
   +jsonb_array_length(v_added_tickets)+jsonb_array_length(v_product_changes)>0 OR v_old_total<>v_new_total);
 RETURN jsonb_build_object('version',1,'cancelledTickets',v_cancelled,'removedTickets',v_removed_tickets,
   'addedTickets',v_added_tickets,'productChanges',v_product_changes,'referenceTotal',v_old_total,
   'currentTotal',v_new_total,'currencyCode',coalesce(v_currency,'CZK'),'hasChanges',v_has_changes,'referenceOrder',to_jsonb(v_reference),
   'referenceHistoryId',v_reference.id,'latestHistoryId',v_latest,'latestSentAt',v_sent_at);
END $$;
REVOKE ALL ON FUNCTION public.get_order_change_summary_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_change_summary_v1(bigint) TO service_role;

-- SOURCE: eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
<<checkout>>
DECLARE
    result JSONB;
    selected_payment_options jsonb;
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
    form_blueprint BIGINT;
    selected_spots BIGINT[];
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
    v_payment_method text;
    v_payment_instructions jsonb;
    v_provider_payment jsonb;
    v_payment_policy jsonb;
    v_discount jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid)]);
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(coalesce(input_data->'ticket','[]')) t WHERE t->>'spot' IS NOT NULL));
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
        PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.forms f
          JOIN public.occasions oc ON oc.id=f.occasion WHERE f.key=form_key;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open, blueprint
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val, form_blueprint
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.can_write_orders(occasion_id);

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF unit_id IS NULL THEN RAISE EXCEPTION 'PAYMENT_POLICY_SCOPE_MISMATCH'; END IF;
        PERFORM public.resolve_payment_method_policy_internal(organization_id,unit_id);

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
        SELECT coalesce(array_agg((t->>'spot')::bigint),'{}') INTO selected_spots
        FROM jsonb_array_elements(input_data->'ticket') t WHERE t->>'spot' IS NOT NULL;
        IF cardinality(selected_spots)<>(SELECT count(DISTINCT id) FROM unnest(selected_spots) id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',1007,'message','Duplicate spot')::text; END IF;
        -- Admission locks product/inventory parents before any seat row. The
        -- occasion scope is acquired by every caller before form/order parents.
        PERFORM 1 FROM eshop.spots WHERE id=ANY(selected_spots) ORDER BY id FOR UPDATE;
        now:=clock_timestamp();
        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS NOT TRUE THEN
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

        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Identity is explicit: offers reuse the waiting ticket; checkout creates it.
        FOR ticket_data IN SELECT * FROM jsonb_array_elements(input_data->'ticket') LOOP
            SELECT value->>'note' INTO ticket_note FROM jsonb_array_elements(coalesce(ticket_data->'fields','[]'))
              WHERE value ? 'note' LIMIT 1;
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
            result:=public.materialize_ticket_products_internal_v1(order_id,form_id,ticket_id,ticket_data,(input_data->>'secret')::uuid);
            IF first_currency_code IS NULL THEN first_currency_code:=result->>'currency_code';
            ELSIF first_currency_code IS DISTINCT FROM result->>'currency_code' THEN
              RAISE EXCEPTION '%',jsonb_build_object('code',1014,'message','Products in the order must have the same currency',
                'expected_currency',first_currency_code,'actual_currency',result->>'currency_code')::text;
            END IF;
            calculated_price:=calculated_price+(result->>'price')::numeric;
            v_total_deposit:=v_total_deposit+(result->>'deposit')::numeric;
            IF result->>'spot' IS NOT NULL THEN used_spots:=used_spots||jsonb_build_array((result->>'spot')::bigint); END IF;
            ticket_details:=ticket_details||jsonb_build_object('id',ticket_id,'ticket_symbol',v_ticket_symbol,
              'note',ticket_note,'products',result->'products');
        END LOOP;

        IF input_data ? 'discount' THEN
          v_discount:=public.apply_order_discount_internal(order_id,input_data,ticket_details);
          calculated_price:=(v_discount->>'price')::numeric;
          ticket_details:=v_discount->'tickets';
        END IF;

        -- Persist the same canonical placement snapshot in the order and its creation history.
        ticket_details := public.order_tickets_with_seating_internal(order_id, ticket_details);
        order_data := public.strip_payment_sources_internal(input_data) - ARRAY['ticket','discount','discount_command_id'] || JSONB_BUILD_OBJECT('tickets', ticket_details);

        IF v_discount IS NOT NULL THEN order_data:=order_data||jsonb_build_object('discount',v_discount->'discount'); END IF;

        v_payment_method:=input_data->>'payment_method';
        IF v_payment_method IS NULL THEN
          IF calculated_price=0 THEN
            -- Released no-money registration rows retain their bank-shaped storage
            -- identity only. No bank service, account, reference or action is issued.
            v_payment_method:=CASE WHEN form_data#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' ELSE 'bank' END;
          ELSE
            selected_payment_options:=public.form_payment_availability_internal(form_id)->'available';
            IF jsonb_array_length(selected_payment_options)<>1 THEN RAISE EXCEPTION 'PAYMENT_METHOD_REQUIRED'; END IF;
            v_payment_method:=selected_payment_options->>0;
          END IF;
        END IF;
        IF NOT public.payment_method_registered_internal(v_payment_method) THEN RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
        -- Selection exclusivity applies to free orders too; repricing must retain
        -- a method that the form actually offered. Online readiness and recipient
        -- changes remain owned by the provider's locked initialization below.
        IF coalesce(form_data#>'{payments,cashEnabled}'='true'::jsonb,false)
             IS DISTINCT FROM (v_payment_method='cash') THEN
          RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
        v_payment_policy:=public.resolve_form_payment_policy_internal(form_id,v_payment_method);
        PERFORM public.check_payment_client_capabilities_internal(v_payment_policy,v_payment_method,input_data->'client_capabilities');
        IF calculated_price>0 AND NOT public.payment_method_is_online_internal(v_payment_method)
          AND NOT (public.form_payment_availability_internal(form_id)->'available' ? v_payment_method) THEN
          RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
        IF v_payment_method='cash' THEN v_total_deposit:=0; END IF;
        IF calculated_price=0 THEN
          IF public.payment_method_is_online_internal(v_payment_method) THEN
            IF public.payment_provider_connection_internal(form_data->'payments',v_payment_method) IS NULL THEN RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
            -- A selected hosted method still needs no provider identity for a
            -- no-money registration. Reuse the bounded released storage shape.
            v_payment_method:='bank';
          END IF;
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method) VALUES(0,first_currency_code,now,v_payment_method) RETURNING id INTO payment_info_id;
        ELSE
          v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'initialize_payment',jsonb_build_object(
            'formId',form_id,'input',input_data,'amount',calculated_price,'currency',first_currency_code,'deposit',v_total_deposit,'createdAt',now));
          payment_info_id:=(v_provider_payment->>'paymentInfoId')::bigint;
          IF payment_info_id IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.payment_info provider_payment
            WHERE provider_payment.id=payment_info_id AND provider_payment.payment_method=v_payment_method
              AND provider_payment.amount=calculated_price AND provider_payment.currency_code=first_currency_code) THEN
            RAISE EXCEPTION 'PAYMENT_PROVIDER_PREPARATION_INVALID'; END IF;
          bank_account_id:=NULL;
        END IF;

        -- The locked connector first validates its original recipient identity,
        -- preserving the released stale-recipient rejection. Full configuration
        -- validation still runs before the order/attempt commits; failure rolls
        -- back the local preparation and never dispatches a remote request.
        PERFORM public.validate_form_payment_configuration_internal(form_id);

        UPDATE eshop.payment_info SET data=coalesce(data,'{}')||jsonb_build_object('no_money_registration',calculated_price=0,'payment_policy',v_payment_policy-'durationSeconds') WHERE id=payment_info_id;
        PERFORM public.notification_center_prepared_invalidate_order(order_id);
        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        v_payment_instructions:=public.ensure_order_payment_instructions_internal(order_id);
        bank_account_id:=(v_payment_instructions->>'bank_account')::bigint;
        generated_variable_symbol:=(v_payment_instructions->>'variable_symbol')::bigint;
        generated_creditor_reference:=v_payment_instructions->>'creditor_reference';
        account_number:=v_payment_instructions->>'account_number';
        account_number_human_readable:=v_payment_instructions->>'account_number_human_readable';
        creditor_name:=v_payment_instructions->>'creditor_name';

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          IF public.payment_method_is_online_internal(v_payment_method) THEN
              v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'create_attempt',jsonb_build_object('orderId',order_id));
              deadline:=(v_provider_payment->>'expiresAt')::timestamptz;
              IF deadline IS NULL THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_DEADLINE_INVALID'; END IF;
          ELSIF v_payment_policy->>'mode'='custom' THEN
              deadline:=now+make_interval(secs=>(v_payment_policy->>'durationSeconds')::bigint);
              UPDATE eshop.payment_info SET deadline=checkout.deadline WHERE id=payment_info_id;
              PERFORM public.queue_payment_reminders_internal(occasion_id,payment_info_id);
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 AND v_payment_policy->>'mode'<>'none' THEN
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
                    PERFORM public.queue_payment_reminders_internal(occasion_id,payment_info_id);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data-ARRAY['discount','discount_command_id'], 'discount',v_discount->'discount', 'tickets', ticket_details,'payment_policy',v_payment_policy-'durationSeconds'),
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
            'payment',public.customer_order_payment_internal(order_id),
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
                    'payment_method',v_payment_method,
                    'data',jsonb_build_object('payment_policy',v_payment_policy-'durationSeconds'),
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

        IF v_discount IS NOT NULL THEN result:=result||jsonb_build_object('paymentPreparationPolicy','leased_keep_pending'); END IF;

    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM='DISCOUNT_INVALID' THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID'); END IF;
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN SQLERRM = 'STRIPE_RECIPIENT_CHANGED' THEN
                JSONB_BUILD_OBJECT('code',409,'errorCode','STRIPE_RECIPIENT_CHANGED',
                    'message','The payment recipient changed. Review the current form.')
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    PERFORM public.notification_center_order_capacity_internal(order_id);
    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;
