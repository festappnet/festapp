-- Validate new contact writes only; no historical rewrite or delivery change.
-- Source: database/functions/forms/email_address_is_valid.sql
-- Syntax only. Conformance cases are shared with Dart and JavaScript.
CREATE OR REPLACE FUNCTION public.email_address_is_valid(p_email text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE SECURITY INVOKER
SET search_path=pg_catalog AS $email$
DECLARE parts text[]; labels text[]; label text;
BEGIN
 IF p_email IS NULL OR length(p_email)>254 OR p_email ~ '[[:space:]]' THEN RETURN false; END IF;
 parts:=string_to_array(p_email,'@');
 IF cardinality(parts)<>2 OR length(parts[1]) NOT BETWEEN 1 AND 64
 OR parts[1] !~ '^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+$'
 OR left(parts[1],1)='.' OR right(parts[1],1)='.' OR strpos(parts[1],'..')>0 THEN RETURN false; END IF;
 labels:=string_to_array(parts[2],'.');
 IF cardinality(labels)<2 OR labels[cardinality(labels)] ~ '^[0-9]+$' THEN RETURN false; END IF;
 FOREACH label IN ARRAY labels LOOP
  IF label !~ '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$' THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END $email$;
REVOKE ALL ON FUNCTION public.email_address_is_valid(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_address_is_valid(text) TO anon,authenticated,service_role;

-- Source: database/functions/eshop_waitlist/accept_offer.sql
CREATE OR REPLACE FUNCTION public.validate_waitlist_answers_internal(p_form bigint,p_input jsonb,p_people jsonb,p_waitlist boolean)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.form_fields; person jsonb; values jsonb; k text; max_people integer; email text;
BEGIN
 IF nullif(p_input->>'email','') IS NOT NULL AND NOT public.email_address_is_valid(p_input->>'email') THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL')::text; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND type='email' AND NOT is_hidden
 AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  FOR email IN
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE NOT f.is_ticket_field AND answer ? k
   UNION ALL
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_people,'[]')) participant(value),
    LATERAL jsonb_array_elements(coalesce(participant.value->'fields','[]')) answer WHERE f.is_ticket_field AND answer ? k
  LOOP
   IF nullif(email,'') IS NOT NULL AND NOT public.email_address_is_valid(email) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL','fieldId',f.id)::text; END IF;
  END LOOP;
 END LOOP;
 IF jsonb_typeof(p_people)<>'array' OR jsonb_array_length(p_people)<1 OR jsonb_array_length(p_people)>public.ticket_order_limit() THEN
  RAISE EXCEPTION 'Invalid participant count'; END IF;
 SELECT min((data->>'max_tickets')::integer) INTO max_people FROM public.form_fields WHERE form=p_form AND type='ticket';
 IF jsonb_array_length(p_people)>coalesce(max_people,public.ticket_order_limit()) THEN RAISE EXCEPTION 'Maximum participants exceeded'; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND is_required AND NOT is_hidden
 AND type NOT IN ('ticket','html','product_type') AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  IF f.is_ticket_field THEN
   FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
    -- Selected seats use the ticket's top-level spot transport. The finalizer
    -- checks occasion ownership, availability and reservation secret afterward.
    IF f.type='spot' AND (p_waitlist OR nullif(person->>'spot','') IS NOT NULL) THEN
     CONTINUE;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(person->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
     RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
   END LOOP;
  ELSE
   IF nullif(p_input->>f.type,'') IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
  END IF;
 END LOOP;
END $$;

-- Source: database/functions/eshop_orders/repair_order_email_client_sync_v1.sql
-- Shared recipient validation. Preserve aliases and local-part spelling.
CREATE OR REPLACE FUNCTION public.normalize_order_email_contact(p_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,extensions AS $$
DECLARE v_email text:=btrim(p_email);
BEGIN
 IF NOT public.email_address_is_valid(v_email) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 RETURN v_email;
END $$;
REVOKE ALL ON FUNCTION public.normalize_order_email_contact(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_order_email_contact(text) TO service_role;


-- Source: database/functions/eshop_orders/update_order_responses.sql
CREATE OR REPLACE FUNCTION public.update_order_responses(
    p_order_id BIGINT,
    responses JSONB
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_order_form_id BIGINT;
    v_current_state text;
    v_current_data JSONB;
    v_new_data JSONB;
    v_field_definitions JSONB;
    v_current_fields_map JSONB;
    v_merged_fields_map JSONB;
    v_new_fields_array JSONB;

    v_field_id_text TEXT;
    v_field_type TEXT;
    v_new_value JSONB;

    v_updated_order_state TEXT;
    v_updated_order_price NUMERIC(10, 2);
    v_updated_order_data JSONB;
BEGIN
    -- Fetch the order's current data, occasion, and form ID
    SELECT
        o.data,
        o.occasion,
        o.form,
        o.state
    INTO
        v_current_data,
        v_occasion_id,
        v_order_form_id,
        v_current_state
    FROM eshop.orders o
    WHERE o.id = p_order_id;

    -- Raise an exception if the SELECT INTO returned no row
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    -- Check if the current user has order editing permissions for this occasion
    IF (SELECT can_write_orders(v_occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User does not have permission to edit this order.';
    END IF;

    -- Reject the terminal state before form validation, without reversing
    -- the form -> order lock order used by form-field removal.
    IF v_current_state='storno' THEN
        RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
    END IF;

    -- Raise an exception if the order is not linked to a form
    IF v_order_form_id IS NULL THEN
        RAISE EXCEPTION 'Order % has no associated form.', p_order_id;
    END IF;

    -- Coordinate response validation/writes with form saves and field removal.
    PERFORM 1 FROM public.forms WHERE id = v_order_form_id FOR SHARE;
    PERFORM public.check_order_is_mutable(p_order_id);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=p_order_id));
    SELECT data INTO v_current_data FROM eshop.orders WHERE id=p_order_id;

    -- Fetch all field definitions for this form into a JSONB map { "field_id": "field_type" }
    SELECT jsonb_object_agg(ff.id::text, ff.type)
    INTO v_field_definitions
    FROM public.form_fields ff
    WHERE ff.form = v_order_form_id;

    -- Raise an exception if the form has no fields
    IF v_field_definitions IS NULL THEN
        RAISE EXCEPTION 'No form fields found for form %', v_order_form_id;
    END IF;

    -- FIX: Use a LATERAL join to explicitly reference the columns from jsonb_each,
    -- resolving the "ambiguous column 'value'" error.
    SELECT jsonb_object_agg(je.key, je.value)
    INTO v_current_fields_map
    FROM jsonb_array_elements(v_current_data -> 'fields') AS jae(field_object),
         LATERAL jsonb_each(jae.field_object) AS je(key, value);

    -- Start with the current order data
    v_new_data := v_current_data;

    -- Merge the existing fields map with the new responses. New responses overwrite old ones.
    v_merged_fields_map := COALESCE(v_current_fields_map, '{}'::jsonb) || responses;

    -- Iterate through only the *incoming* responses to handle updates and nulls
    FOR v_field_id_text, v_new_value IN SELECT * FROM jsonb_each(responses)
    LOOP
        -- Get the type of the field being updated
        v_field_type := v_field_definitions ->> v_field_id_text;

        -- Validate that the field ID exists on this order's form
        IF v_field_type IS NULL THEN
            RAISE EXCEPTION 'Field ID % not found on form %', v_field_id_text, v_order_form_id;
        END IF;

        -- Handle null values: remove the key from the top level and from the merged map
        IF v_new_value IS NULL OR v_new_value = 'null'::jsonb THEN

            -- Remove from the map that will build the 'fields' array
            v_merged_fields_map := v_merged_fields_map - v_field_id_text;

            -- Remove top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data - 'name';
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data - 'surname';
            ELSIF v_field_type = 'email' THEN
                v_new_data := v_new_data - 'email';
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data - 'phone';
            END IF;

        -- Handle non-null values: update the top-level keys
        ELSE

            -- Update top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data || jsonb_build_object('name', v_new_value);
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data || jsonb_build_object('surname', v_new_value);
            ELSIF v_field_type = 'email' THEN
                IF NOT public.email_address_is_valid(v_new_value #>> '{}') THEN
                    RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact';
                END IF;
                v_new_data := v_new_data || jsonb_build_object('email', v_new_value);
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data || jsonb_build_object('phone', v_new_value);
            END IF;

        END IF;
    END LOOP;

    -- Rebuild the 'fields' array from the (now null-stripped) merged map
    -- It converts { "id": "val" } back to [ {"id": "val"} ]
    SELECT jsonb_agg(jsonb_build_object(key, value))
    INTO v_new_fields_array
    FROM jsonb_each(v_merged_fields_map);

    -- Set the new 'fields' array in the main data object
    v_new_data := jsonb_set(
        v_new_data,
        '{fields}',
        COALESCE(v_new_fields_array, '[]'::jsonb)
    );

    -- Update the order in the database
    UPDATE eshop.orders
    SET
        data = v_new_data,
        updated_at = NOW()
    WHERE
        id = p_order_id
    RETURNING
        state, price, data
    INTO
        v_updated_order_state, v_updated_order_price, v_updated_order_data;

    -- Save the change to the orders_history table
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        p_order_id,
        v_updated_order_state,
        v_updated_order_price,
        v_updated_order_data,
        NOW()
    );

END;
$$;
-- Source: database/functions/eshop_ticket_batches/sales.sql
-- A sale moves existing OPT parents. It never allocates inventory or generates QR.
CREATE OR REPLACE FUNCTION public.sell_ticket_batch_items_client_sync_v1(
 p_batch uuid,p_tickets bigint[],p_contact jsonb,p_send_tickets boolean,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; occ public.occasions; claimed jsonb; oid bigint; pi bigint; tx bigint;
 v_amount numeric; tickets jsonb; sale_data jsonb; ids bigint[]; email text;
BEGIN
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=b.occasion;
 IF auth.uid() IS NULL OR public.can_write_orders(b.occasion) IS NOT TRUE
 OR public.get_is_manager_on_unit(occ.unit) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id ORDER BY id);
 IF cardinality(ids) NOT BETWEEN 1 AND 20 OR array_position(ids,NULL) IS NOT NULL
 OR cardinality(ids) IS NULL OR p_send_tickets IS NULL
 OR jsonb_typeof(coalesce(p_contact,'{}'))<>'object' OR octet_length(coalesce(p_contact,'{}')::text)>8192
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(coalesce(p_contact,'{}')) k WHERE k NOT IN ('email','name','surname','phone')) THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_SALE_SELECTION_INVALID'; END IF;
 sale_data:=jsonb_strip_nulls(coalesce(p_contact,'{}'));
 email:=nullif(trim(sale_data->>'email'),'');
 IF email IS NULL THEN sale_data:=sale_data-'email';
 ELSIF NOT public.email_address_is_valid(email) THEN RAISE EXCEPTION 'BATCH_CONTACT_INVALID';
 ELSE sale_data:=jsonb_set(sale_data,'{email}',to_jsonb(email)); END IF;
 IF p_send_tickets AND email IS NULL THEN RAISE EXCEPTION 'BATCH_DELIVERY_EMAIL_REQUIRED'; END IF;
 claimed:=public.begin_client_mutation_v1(p_command_id,'inventory.ticket_batch.sell',b.occasion,auth.uid(),
 encode(extensions.digest(jsonb_build_object('batch',b.id,'tickets',ids,'contact',sale_data,'sendTickets',p_send_tickets)::text,'sha256'),'hex'));
 IF claimed->>'disposition'='replay' THEN RETURN claimed->'response'; END IF;
 BEGIN
 PERFORM public.check_ticket_batch_cash_unit_internal(b.occasion);
 PERFORM public.admit_order_mutation_v1(b.occasion,cardinality(ids));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[b.stock_order_id]);
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch FOR UPDATE;
 IF b.manifest_hash IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND kind='print')
 OR EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND state<>'ready') THEN
  RAISE EXCEPTION 'BATCH_PRINT_NOT_READY'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF (SELECT count(*) FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id
  WHERE i.batch_id=b.id AND t.id=ANY(ids) AND i.sale_order_id IS NULL AND t.state='ordered'
  AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=b.stock_order_id)
  AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"<>b.stock_order_id))<>cardinality(ids) THEN
  RAISE EXCEPTION 'ITEM_NOT_IN_STOCK'; END IF;
 SELECT jsonb_agg(t ORDER BY (t->>'id')::bigint) INTO tickets FROM jsonb_array_elements(b.snapshot->'tickets') t WHERE (t->>'id')::bigint=ANY(ids);
 SELECT sum((p->>'price')::numeric) INTO v_amount FROM jsonb_array_elements(tickets) t CROSS JOIN LATERAL jsonb_array_elements(t->'products') p;
 IF v_amount IS NULL OR v_amount<0 THEN RAISE EXCEPTION 'BATCH_SNAPSHOT_INVALID'; END IF;
 oid:=public.allocate_ticket_order_identity_internal(b.form);
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method) VALUES(v_amount,b.currency_code,'bank') RETURNING id INTO pi;
 sale_data:=sale_data||jsonb_build_object('tickets',tickets,'ticketBatchOrigin',jsonb_build_object('batchId',b.id,'sendTickets',p_send_tickets));
 UPDATE eshop.orders SET price=v_amount,currency_code=b.currency_code,payment_info=pi,data=sale_data,updated_at=clock_timestamp() WHERE id=oid;
 UPDATE eshop.order_product_ticket SET "order"=oid WHERE ticket=ANY(ids) AND "order"=b.stock_order_id;
 UPDATE eshop.ticket_batch_items SET sale_order_id=oid WHERE batch_id=b.id AND ticket_id=ANY(ids) AND sale_order_id IS NULL;
 UPDATE eshop.orders stock SET data=jsonb_set(stock.data,'{tickets}',coalesce((SELECT jsonb_agg(t) FROM jsonb_array_elements(stock.data->'tickets') t
  WHERE NOT (t->>'id')::bigint=ANY(ids)),'[]')),updated_at=clock_timestamp() WHERE id=b.stock_order_id;
 tx:=public.insert_manual_transaction_internal_v1(v_amount,b.currency_code,occ.unit,NULL,clock_timestamp(),'Ticket batch cash sale',pi);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND state='paid')
 OR NOT EXISTS(SELECT 1 FROM eshop.transactions tr WHERE tr.id=tx AND tr.payment_info=pi AND tr.amount=v_amount) THEN
  RAISE EXCEPTION 'BATCH_PAYMENT_NOT_COMMITTED'; END IF;
 INSERT INTO eshop.orders_history("order",state,data,price,currency_code) VALUES
 (b.stock_order_id,'stock',jsonb_build_object('saleOrderId',oid,'ticketIds',ids),NULL,b.currency_code),
 (oid,'paid',jsonb_build_object('batchId',b.id,'transactionId',tx,'ticketIds',ids),v_amount,b.currency_code);
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=b.form;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,b.occasion,'inventory.ticket_batch.sell',
 jsonb_build_array(jsonb_build_object('entityType','order','entityId',b.stock_order_id,'operation','update','safeLabel','Ticket batch',
 'changedFields',jsonb_build_array('tickets','parent')),jsonb_build_object('entityType','order','entityId',oid,'operation','insert',
 'safeLabel','Cash sale','changedFields',jsonb_build_array('tickets','payment','parent'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=b.occasion AND is_editor_order_view),
 jsonb_build_object('batchId',b.id,'orderId',oid,'transactionId',tx,'amount',v_amount,'currency',b.currency_code,'ticketIds',ids));
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM=ANY(ARRAY['ITEM_NOT_IN_STOCK','BATCH_PRINT_NOT_READY','CASH_SALE_INVOICE_WORKFLOW_REQUIRED']) THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('errorCode',SQLERRM));
  END IF;
  RAISE;
 END;
END $$;
CREATE OR REPLACE FUNCTION public.void_ticket_batch_items_client_sync_v1(p_batch uuid,p_tickets bigint[],p_reason text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; ids bigint[]; claimed jsonb;
BEGIN
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch;
 IF auth.uid() IS NULL OR public.can_write_orders(b.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id ORDER BY id);
 IF cardinality(ids) NOT BETWEEN 1 AND 200 OR cardinality(ids) IS NULL OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 OR p_reason IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_VOID_SELECTION_INVALID'; END IF;
 claimed:=public.begin_client_mutation_v1(p_command_id,'inventory.ticket_batch.void',b.occasion,auth.uid(),
 encode(extensions.digest(jsonb_build_object('batch',b.id,'tickets',ids,'reason',p_reason)::text,'sha256'),'hex'));
 IF claimed->>'disposition'='replay' THEN RETURN claimed->'response'; END IF;
 BEGIN
 PERFORM public.admit_order_mutation_v1(b.occasion,cardinality(ids));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[b.stock_order_id]);
 PERFORM 1 FROM eshop.ticket_batches WHERE id=b.id FOR UPDATE;
 PERFORM 1 FROM eshop.tickets WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF (SELECT count(*) FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id
  WHERE i.batch_id=b.id AND t.id=ANY(ids) AND i.sale_order_id IS NULL AND t.state='ordered'
  AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=b.stock_order_id))<>cardinality(ids) THEN
  RAISE EXCEPTION 'ITEM_NOT_IN_STOCK'; END IF;
 PERFORM public.internal_storno_tickets_221(ids);
 INSERT INTO eshop.orders_history("order",state,data,currency_code)
 VALUES(b.stock_order_id,'stock',jsonb_build_object('voidedTicketIds',ids,'reason',p_reason),b.currency_code);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,b.occasion,'inventory.ticket_batch.void',
 jsonb_build_array(jsonb_build_object('entityType','order','entityId',b.stock_order_id,'operation','update','safeLabel','Ticket batch',
 'changedFields',jsonb_build_array('tickets','allocations'))),ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=b.occasion AND is_editor_order_view),
 jsonb_build_object('batchId',b.id,'ticketIds',ids));
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='ITEM_NOT_IN_STOCK' THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('errorCode',SQLERRM));
  END IF;
  RAISE;
 END;
END $$;
REVOKE ALL ON FUNCTION public.sell_ticket_batch_items_client_sync_v1(uuid,bigint[],jsonb,boolean,uuid),
 public.void_ticket_batch_items_client_sync_v1(uuid,bigint[],text,uuid) FROM PUBLIC,anon,authenticated,service_role;
