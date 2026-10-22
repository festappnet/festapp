-- Canonical bank synchronization monitoring and authorized UI health summaries.

-- SOURCE: database/functions/eshop_bank_sync/bank_sync_health.sql
-- BankSync observations and one durable notification incident per connection.
CREATE TABLE IF NOT EXISTS eshop.bank_sync_health (
  connection_id bigint PRIMARY KEY REFERENCES eshop.bank_sync_connections(id) ON DELETE CASCADE,
  checked_at timestamptz NOT NULL DEFAULT now(),
  ingest_enabled boolean,
  polling_enabled boolean,
  token_present boolean,
  warning_code text,
  warning_since timestamptz,
  incident_id uuid,
  notified_at timestamptz
);
ALTER TABLE eshop.bank_sync_health ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_health FROM PUBLIC,anon,authenticated,service_role;

-- Internal read helper. Only authorized domain RPCs may expose these details.
CREATE OR REPLACE FUNCTION public.bank_sync_problem(p_connection_id bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT CASE
    WHEN c.state='suspended' THEN 'suspended'
    WHEN c.state IN ('provisioning','shadow') THEN 'not_configured'
    WHEN c.mode='email' AND c.pairing_code IS NULL THEN 'email_missing'
    WHEN c.mode='api' AND h.token_present IS FALSE THEN 'token_missing'
    WHEN h.ingest_enabled IS FALSE OR (c.mode='api' AND h.polling_enabled IS FALSE) THEN 'bank_error'
    WHEN c.last_error IS NOT NULL OR c.state='degraded' THEN 'bank_error'
    WHEN c.mode='api' AND COALESCE(c.bank_pull_at,c.created_at)<now()-interval '30 minutes' THEN 'stale'
    ELSE NULL END
  FROM eshop.bank_sync_connections c LEFT JOIN eshop.bank_sync_health h ON h.connection_id=c.id
  WHERE c.id=p_connection_id;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_problem(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_warning(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE v_title text; v_type text; v_connection bigint; v_code text; v_contacts jsonb;
BEGIN
  SELECT title,type INTO v_title,v_type FROM eshop.bank_accounts WHERE id=p_bank_account_id;
  IF NOT FOUND OR v_type='CASH' THEN RETURN NULL; END IF;
  SELECT c.id INTO v_connection FROM eshop.bank_sync_connections c WHERE c.bank_account_id=p_bank_account_id
    OR c.id IN (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id);
  v_code:=CASE WHEN v_connection IS NULL THEN 'not_configured' ELSE public.bank_sync_problem(v_connection) END;
  IF v_code IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name',NULLIF(btrim(concat_ws(' ',ui.name,ui.surname)),''),
    'email',public.get_user_delivery_email(ui.id)) ORDER BY ui.name,ui.surname,ui.id),'[]'::jsonb)
    INTO v_contacts FROM eshop.bank_account_users bau JOIN public.user_info ui ON ui.id=bau."user"
    WHERE bau.bank_account=p_bank_account_id AND bau.is_admin;
  RETURN jsonb_build_object('code',v_code,'bank_account_title',v_title,'contacts',v_contacts);
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_warning(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_health_targets(p_organization_id bigint)
RETURNS TABLE(connection_id bigint,remote_bank_account_id text,mode text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN QUERY SELECT c.id,c.remote_bank_account_id,c.mode FROM eshop.bank_sync_connections c
    WHERE c.legacy_blocked_at IS NOT NULL AND c.state IN ('connected','degraded','suspended')
      AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
        WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id
          OR ub.bank_account IN (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id)))
    ORDER BY (SELECT h.checked_at FROM eshop.bank_sync_health h WHERE h.connection_id=c.id) NULLS FIRST,c.id LIMIT 100;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_health_targets(bigint) FROM PUBLIC,anon,authenticated;


CREATE OR REPLACE FUNCTION public.record_bank_sync_health(p_organization_id bigint,p_connection_id bigint,
 p_success_at timestamptz,p_error text,p_ingest_enabled boolean,p_polling_enabled boolean,p_token_present boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_code text;
BEGIN
  PERFORM public.require_service_role();
  SELECT c.* INTO STRICT v_connection FROM eshop.bank_sync_connections c
    WHERE c.id=p_connection_id AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
      WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id OR ub.bank_account IN
        (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id))) FOR UPDATE;
  IF p_error IS NOT NULL AND p_error NOT IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch','bank_sync_retry_required') THEN
    RAISE EXCEPTION 'BANK_SYNC_HEALTH_ERROR_INVALID';
  END IF;
  PERFORM public.record_bank_sync_pull(p_connection_id,p_success_at,p_error);
  INSERT INTO eshop.bank_sync_health(connection_id,checked_at,ingest_enabled,polling_enabled,token_present)
    VALUES(p_connection_id,now(),p_ingest_enabled,p_polling_enabled,p_token_present)
    ON CONFLICT(connection_id) DO UPDATE SET checked_at=now(),
      ingest_enabled=COALESCE(EXCLUDED.ingest_enabled,eshop.bank_sync_health.ingest_enabled),
      polling_enabled=COALESCE(EXCLUDED.polling_enabled,eshop.bank_sync_health.polling_enabled),
      token_present=COALESCE(EXCLUDED.token_present,eshop.bank_sync_health.token_present);
  IF v_connection.mode='email' AND v_connection.state='degraded' AND p_error IS NULL AND p_ingest_enabled IS TRUE THEN
    UPDATE eshop.bank_sync_connections SET state='connected' WHERE id=p_connection_id;
  END IF;
  v_code:=CASE WHEN v_connection.state IN ('connected','degraded') THEN public.bank_sync_problem(p_connection_id) END;
  UPDATE eshop.bank_sync_health SET warning_code=v_code,
    warning_since=CASE WHEN v_code IS NULL THEN NULL ELSE COALESCE(warning_since,now()) END,
    incident_id=CASE WHEN v_code IS NULL THEN NULL ELSE COALESCE(incident_id,gen_random_uuid()) END,
    notified_at=CASE WHEN v_code IS NULL THEN NULL ELSE notified_at END WHERE connection_id=p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_bank_sync_health(bigint,bigint,timestamptz,text,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated;


CREATE OR REPLACE FUNCTION public.enqueue_bank_sync_health_alerts(p_organization_id bigint)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r record; a record; v_count integer:=0; v_sent integer; v_message jsonb;
BEGIN
  PERFORM public.require_service_role();
  FOR r IN SELECT h.*,c.bank_account_id,b.title FROM eshop.bank_sync_health h
    JOIN eshop.bank_sync_connections c ON c.id=h.connection_id JOIN eshop.bank_accounts b ON b.id=c.bank_account_id
    WHERE h.warning_code IS NOT NULL AND h.warning_since<=now()-interval '10 minutes' AND h.notified_at IS NULL
      AND h.checked_at>now()-interval '10 minutes' AND c.state IN ('connected','degraded')
      AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
        WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id OR ub.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))
    ORDER BY h.warning_since FOR UPDATE OF h SKIP LOCKED
  LOOP
    v_sent:=0;
    FOR a IN SELECT DISTINCT ui.id,public.get_user_delivery_email(ui.id) AS email,
      COALESCE(ui.data->>'locale','cs') AS language
      FROM eshop.bank_account_users bau JOIN public.user_info ui ON ui.id=bau."user"
      WHERE bau.is_admin AND (bau.bank_account=r.bank_account_id OR bau.bank_account IN
        (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=r.connection_id))
    LOOP
      IF a.email IS NULL THEN CONTINUE; END IF;
      v_message:=public.enqueue_email('custom',jsonb_build_object('organization',p_organization_id,'recipient_user',a.id),a.email,
        jsonb_build_object('connection_id',r.connection_id,'incident_id',r.incident_id,'warning_code',r.warning_code,
          'account_title',r.title,'language',a.language),
        'bank-sync:'||r.connection_id||':'||r.incident_id||':'||a.id,'BANK_SYNC_WARNING',now(),now()+interval '1 day');
      UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(v_message->>'message_id')::uuid;
      v_sent:=v_sent+1;
    END LOOP;
    IF v_sent>0 THEN UPDATE eshop.bank_sync_health SET notified_at=now() WHERE connection_id=r.connection_id; END IF;
    v_count:=v_count+v_sent;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_bank_sync_health_alerts(bigint) FROM PUBLIC,anon,authenticated;


CREATE OR REPLACE FUNCTION public.configure_bank_sync_health_monitor(p_organization_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization_id) THEN RAISE EXCEPTION 'ORGANIZATION_NOT_FOUND'; END IF;
  SELECT regexp_replace(worker_url,'/process-email-queue$','/bank-sync-reconcile') INTO v_url FROM public.email_capacity;
  IF v_url IS NULL OR v_url !~ '^https://[^/]+/functions/v1/bank-sync-reconcile$' THEN RAISE EXCEPTION 'BANK_SYNC_MONITOR_URL_REQUIRED'; END IF;
  PERFORM cron.schedule('festapp_bank_sync_health_'||p_organization_id,'*/5 * * * *',
    format('SELECT net.http_post(url:=%L,body:=jsonb_build_object(''requestSecret'',public.generate_request_secret(3600),''monitor_organization_id'',%s),timeout_milliseconds:=360000)',v_url,p_organization_id));
END;
$$;
REVOKE ALL ON FUNCTION public.configure_bank_sync_health_monitor(bigint) FROM PUBLIC,anon,authenticated;


-- Explicit administrator remediation starts a new observation window. Pending
-- incident mail becomes invalid immediately when synchronization is changed.
CREATE OR REPLACE FUNCTION public.reset_bank_sync_control_health(p_connection_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM eshop.bank_sync_health WHERE connection_id=p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION public.reset_bank_sync_control_health(bigint) FROM PUBLIC,anon,authenticated;



-- SOURCE: database/functions/eshop_orders/get_orders.sql
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
        WHERE link = p_occasion_link
          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());
    ELSE
        SELECT occasion, id
        INTO v_occasion_id, v_form_id
        FROM public.forms
        WHERE link = p_form_link
          AND occasion IN (SELECT o.id FROM public.occasions o WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()));
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT get_is_editor_order_view_on_occasion(v_occasion_id)) <> TRUE THEN
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

    -- Fetch orders, conditionally filtering by form link
    IF v_form_id IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',public.get_waitlist_summary_internal(o.id)->'allowedActions',
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id AND o.form = v_form_id;
    ELSE
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',public.get_waitlist_summary_internal(o.id)->'allowedActions',
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id;
    END IF;

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
        'id', pi.id, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
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


-- SOURCE: database/functions/eshop_forms/get_form_for_edit.sql
-- Fix get_form_for_edit: Remove bigint = uuid comparison and add can_delete
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
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
    WHERE f.link = form_link;

    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    PERFORM check_is_editor_order_view_via_form_link(form_link);

    -- Calculate can_delete
    -- FIXED: Compare form (bigint) with v_form_id (bigint) directly
    SELECT NOT EXISTS (
        SELECT 1 FROM eshop.orders WHERE form = v_form_id
    ) INTO canDelete;

    SELECT jsonb_build_object(
        'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
        'key', f.key,
        'is_open', f.is_open,
        'created_at', f.created_at,
        'data', f.data,
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
            'title', pt.title,
            'description', pt.description,
            'type', pt.type,
            'data', pt.data,
            'occasion', pt.occasion
        ) ORDER BY pt.title
    ), '[]'::jsonb)
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

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
      WHEN EXISTS (SELECT 1 FROM used_products u WHERE u.product = p.id::text) THEN 'orders'
      WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
      WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
      WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
    END AS reason) usage
    WHERE p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id);

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
    CROSS JOIN LATERAL (SELECT CASE WHEN EXISTS (
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

    -- FIX: Exclude CASH accounts and ensure deterministic sorting by Priority
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ba.id,
            'account_number', ba.account_number,
            'account_number_human_readable', ba.account_number_human_readable,
            'title', ba.title,
            'supported_currencies', ba.supported_currencies,
            'type', ba.type,
            'bank_sync_warning', public.bank_sync_warning(ba.id),
            'bank_sync', (SELECT jsonb_build_object('state',c.state,'mode',c.mode) FROM eshop.bank_sync_connections c
              WHERE c.bank_account_id=ba.id OR c.id IN (SELECT a.connection_id FROM eshop.bank_sync_account_aliases a WHERE a.bank_account_id=ba.id))
        ) ORDER BY uba.priority ASC, ba.id ASC
    ), '[]'::jsonb)
    INTO availableBankAccountsData
    FROM eshop.unit_bank_accounts uba
    JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
    WHERE uba.unit = v_unit_id
      AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

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


-- SOURCE: database/functions/eshop_bank_accounts/get_bank_accounts_for_unit_management.sql
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

CREATE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    creditor_name text,
    type text,
    is_admin boolean,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    last_fio_fetch_time timestamptz,
    bank_sync jsonb,
    bank_sync_warning jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM public.demo_occasions d JOIN public.occasions o ON o.id=d.occasion
      WHERE o.unit=p_unit_id AND public.can_read_demo_occasion(d.occasion)) THEN
      PERFORM public.check_is_manager_on_unit(p_unit_id);
    END IF;
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.title,
        ba.creditor_name,
        ba.type,
        EXISTS (
            SELECT 1
            FROM eshop.bank_account_users bau
            WHERE bau.bank_account = ba.id
            AND bau."user" = auth.uid()
            AND bau.is_admin = true
        ) as is_admin,
        NULL::text as token_masked,
        NULL::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ba.last_fio_fetch_time,
        CASE WHEN EXISTS (
            SELECT 1 FROM eshop.bank_account_users bank_admin
            WHERE bank_admin.bank_account = ba.id
              AND bank_admin."user" = auth.uid()
              AND bank_admin.is_admin
        ) THEN public.get_bank_sync_connection(ba.id)
          ELSE (
            SELECT jsonb_build_object('state',connection.state,'mode',connection.mode)
            FROM eshop.bank_sync_connections connection
            WHERE connection.bank_account_id = ba.id
          ) END AS bank_sync,
        public.bank_sync_warning(ba.id) AS bank_sync_warning
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id
    AND ba.type != 'CASH'
    AND (NOT public.is_demo_unit(p_unit_id) OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=ba.id AND public.get_is_editor_order_view_on_occasion(demo_bank.occasion))); -- Exclude Cash Accounts from management list
END;
$$;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;



-- SOURCE: database/functions/emails/email_queue.sql (email_intent_valid)
CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id' AND h.warning_code IS NOT NULL
      AND c.state IN ('connected','degraded') AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
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
