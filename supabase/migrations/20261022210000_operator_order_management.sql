-- Shared action projection for administration and delegated order tools.
CREATE OR REPLACE FUNCTION public.get_order_allowed_actions_internal_v1(p_order bigint,p_summary jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT (coalesce(p_summary,(CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
    THEN public.get_waitlist_summary_internal(o.id) ELSE public.get_order_action_summary_internal(o.state) END))->'allowedActions')
    - CASE WHEN p.payment_method='stripe' THEN ARRAY['cancel','paid']::text[] ELSE ARRAY[]::text[] END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

REVOKE ALL ON FUNCTION public.get_order_allowed_actions_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
    IF (SELECT can_read_orders(v_occasion_id)) <> TRUE THEN
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

    -- Ordinary orders need only activity/actions. Resolve ticket/offer lifecycles
    -- once only for orders that expose a full waitlist summary.
    WITH selected_orders AS MATERIALIZED (
        SELECT o.*, CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
          OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
          THEN public.get_waitlist_summary_internal(o.id)
          ELSE public.get_order_action_summary_internal(o.state)
        END AS waitlist_summary
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id
          AND (v_form_id IS NULL OR o.form = v_form_id)
    )
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN o.waitlist_summary END,
            'isActive',(o.waitlist_summary->>'isActive')::boolean,
            'allowedActions',public.get_order_allowed_actions_internal_v1(o.id,o.waitlist_summary),
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data || jsonb_build_object('tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM selected_orders o;

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
        'id', pi.id, 'payment_method', pi.payment_method, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
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

-- Thin delegated adapters over the existing order, payment, report and mail owners.
-- Scope is locked in the same transaction as every read, write and receipt replay.
CREATE OR REPLACE FUNCTION public.check_operator_order_scope_internal_v1(
  p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.organization=o.organization AND ui.id=auth.uid()
    WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
  IF NOT FOUND OR public.can_read_orders(p_occasion) IS DISTINCT FROM TRUE OR (p_write AND public.can_write_orders(p_occasion) IS DISTINCT FROM TRUE) THEN
    RAISE insufficient_privilege USING MESSAGE='order context unavailable'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.operator_order_revision_internal_v1(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('order',to_jsonb(o),
   'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE p.id=o.payment_info),
   'items',(SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i WHERE i."order"=o.id),
   'tickets',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id)))::text,'UTF8'),'sha256'),'hex')
 FROM eshop.orders o WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_snapshot_internal_v1(p_order bigint,p_detail boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('id',o.id,'occasionId',o.occasion,'symbol',o.order_symbol,'state',o.state,
   'createdAt',o.created_at,'updatedAt',o.updated_at,'revision',public.operator_order_revision_internal_v1(o.id),
   'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),
   'ticketCount',(SELECT count(DISTINCT i.ticket) FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket WHERE i."order"=o.id AND o.state IS DISTINCT FROM 'storno' AND o.state IS DISTINCT FROM 'waitlisted' AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'),
   'price',o.price::text,'currency',o.currency_code,'allowedActions',public.get_order_allowed_actions_internal_v1(o.id),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('method',p.payment_method,'amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'variableSymbol',p.variable_symbol::text,'deadline',p.deadline) END)
   || CASE WHEN p_detail THEN jsonb_build_object('note',o.note_hidden,'responses',coalesce(o.data->'fields','[]'),
     'formFields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'type',f.type) ORDER BY f.id),'[]') FROM public.form_fields f WHERE f.form=o.form),
     'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'state',t.state,
        'products',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',pr.id,'title',pr.title,'price',jsonb_path_query_first(o.data,'$.tickets[*] ? (@.id == $ticket).products[*] ? (@.id == $product).price',jsonb_build_object('ticket',t.id,'product',pr.id))#>>'{}','currentPrice',pr.price::text) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i JOIN eshop.products pr ON pr.id=i.product WHERE i."order"=o.id AND i.ticket=t.id)) ORDER BY t.id),'[]')
       FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id))) ELSE '{}'::jsonb END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.get_operator_order_report_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb; v_link text;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 SELECT link INTO v_link FROM public.occasions WHERE id=p_occasion;
 r:=public.get_report_ws(v_link);
 IF (r->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order report unavailable'; END IF;
 RETURN jsonb_build_object('occasionId',p_occasion,'report',r->'report',
   'waitingTickets',(SELECT count(*) FROM eshop.tickets WHERE occasion=p_occasion AND state='waitlisted'));
END $$;

CREATE OR REPLACE FUNCTION public.get_operator_orders_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_search text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR coalesce(length(p_search),0)>200 THEN RAISE invalid_parameter_value USING MESSAGE='invalid order page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_snapshot_internal_v1(p_order,true)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (nullif(p_search,'') IS NULL OR position(lower(p_search) IN lower(concat_ws(' ',order_symbol,data->>'name',data->>'surname',data->>'email')))>0)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_snapshot_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

CREATE OR REPLACE FUNCTION public.manage_operator_order_v1(p_occasion bigint,p_organization bigint,p_unit bigint,
  p_order bigint,p_command_id uuid,p_expected_revision text,p_action text,p_changes jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_unit bigint; v_begin jsonb; v_hash text; v_child uuid;
 v_result jsonb; v_actions jsonb; v_item jsonb; v_products jsonb; v_message jsonb; v_users uuid[]; v_data jsonb;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,true);
 IF p_action IS NULL OR p_expected_revision IS NULL OR p_action NOT IN('update','cancel','mark_paid','record_payment','send_tickets') OR p_expected_revision !~ '^[a-f0-9]{64}$'
   OR p_changes IS NULL OR jsonb_typeof(p_changes)<>'object' OR octet_length(p_changes::text)>65536 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order command'; END IF;
 IF p_action NOT IN('update','record_payment') AND p_changes<>'{}'::jsonb THEN RAISE invalid_parameter_value USING MESSAGE='unexpected order changes'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('order',p_order,'occasion',p_occasion,'organization',p_organization,'unit',p_unit,'revision',p_expected_revision,'action',p_action,'changes',p_changes)::text,'UTF8'),'sha256'),'hex');
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 v_begin:=public.begin_client_mutation_v1(p_command_id,'orders.operator.'||p_action,p_occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN jsonb_set(v_begin->'response','{mutation,replayed}','true'); END IF;
 -- Preserve the domain lock order, including form -> order and blueprint scope.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_order AND occasion=p_occasion FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion;
 IF public.operator_order_revision_internal_v1(p_order) IS DISTINCT FROM p_expected_revision THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('orderId',p_order,'reason','ORDER_CHANGED_RELOAD_REQUIRED')); END IF;
 v_actions:=public.get_order_allowed_actions_internal_v1(p_order);
 IF NOT (v_actions ? CASE p_action WHEN 'update' THEN CASE WHEN p_changes ? 'note' AND p_changes - 'note'='{}'::jsonb THEN 'note' ELSE 'edit' END WHEN 'cancel' THEN 'cancel' WHEN 'mark_paid' THEN 'paid' WHEN 'record_payment' THEN 'edit' ELSE 'send' END) THEN
   RAISE insufficient_privilege USING MESSAGE='order action unavailable'; END IF;
 v_child:=md5(p_command_id::text||':domain')::uuid;
 IF p_action='cancel' THEN
   v_result:=public.storno_order_client_sync_v1(p_order,v_child);
 ELSIF p_action='update' THEN
   IF p_changes - ARRAY['responses','note','tickets']::text[]<>'{}'::jsonb OR p_changes='{}' THEN RAISE invalid_parameter_value USING MESSAGE='invalid order changes'; END IF;
   IF p_changes ? 'responses' THEN PERFORM public.update_order_responses(p_order,p_changes->'responses'); END IF;
   IF p_changes ? 'note' THEN
     v_result:=public.update_order_note_hidden(p_order,p_changes->>'note');
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order note rejected'; END IF;
   END IF;
   FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_changes->'tickets','[]')) LOOP
     IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=p_order AND ticket=(v_item->>'ticketId')::bigint) THEN RAISE insufficient_privilege USING MESSAGE='ticket unavailable'; END IF;
     SELECT coalesce(jsonb_agg(jsonb_build_object('id',x->'productId','price',x->'price')),'[]') INTO v_products FROM jsonb_array_elements(v_item->'products') x;
     v_result:=public.update_ticket_products_client_sync_v1((v_item->>'ticketId')::bigint,v_products,md5(p_command_id::text||':ticket:'||(v_item->>'ticketId'))::uuid);
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='ticket products rejected'; END IF;
   END LOOP;
 ELSIF p_action='mark_paid' THEN
   v_result:=public.update_order_and_tickets_to_paid_ws(p_order);
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='payment state rejected'; END IF;
   v_result:=NULL;
 ELSIF p_action='record_payment' THEN
   IF NOT (p_changes ?& ARRAY['amount','currency','receivedAt']) OR p_changes - ARRAY['amount','currency','receivedAt','note']::text[]<>'{}'::jsonb
     OR jsonb_typeof(p_changes->'amount') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'currency') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'receivedAt') IS DISTINCT FROM 'string'
     OR v_pi.id IS NULL OR v_pi.payment_method='stripe' OR (p_changes->>'currency') IS DISTINCT FROM trim(v_order.currency_code)
     OR (p_changes->>'amount') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR (p_changes->>'amount')::numeric<=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='manual payment unavailable'; END IF;
   PERFORM public.insert_manual_transaction((p_changes->>'amount')::double precision,p_changes->>'currency',v_unit::int,v_pi.variable_symbol::text,
     p_changes->>'receivedAt',p_changes->>'note',v_pi.id::int);
 ELSIF p_action='send_tickets' THEN
   v_message:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',p_order,'requested_by',auth.uid()),p_organization,p_occasion,v_unit,now(),'operator:'||p_command_id);
 END IF;
 v_data:=jsonb_build_object('orderId',p_order,'occasionId',p_occasion,'revision',public.operator_order_revision_internal_v1(p_order))
   ||CASE WHEN v_message IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('delivery','queued','messageId',v_message->'message_id') END;
 IF v_result ? 'mutation' THEN
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='cancellation rejected'; END IF;
   v_result:=jsonb_set(v_result,'{data}',v_data);
   v_result:=jsonb_set(v_result,'{mutation,commandId}',to_jsonb(p_command_id));v_result:=jsonb_set(v_result,'{mutation,receiptId}',to_jsonb(p_command_id));
   RETURN public.finish_client_mutation_v1(p_command_id,v_result,(v_result#>>'{mutation,commitId}')::uuid);
 END IF;
 IF p_action='send_tickets' THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,v_data);
 END IF;
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=p_occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,'orders.operator.'||p_action,
   jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,'operation','update','safeLabel','Order management','changedFields',jsonb_build_array(p_action))),v_users,v_data);
END $$;

REVOKE ALL ON FUNCTION public.check_operator_order_scope_internal_v1(bigint,bigint,bigint,boolean),public.operator_order_revision_internal_v1(bigint),
 public.operator_order_snapshot_internal_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) TO authenticated;
