-- Scoped admin deletion of waiting orders and safe active waitlist labels.

-- Source: database/functions/eshop_orders/delete_order.sql
CREATE OR REPLACE FUNCTION public.delete_order_internal_v1(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payment_info_id BIGINT;
  order_product_ticket_ids BIGINT[];
  ticket_ids BIGINT[];
  order_oc BIGINT;
  unit_id BIGINT;
  ou_record RECORD;
  form_id BIGINT;
  related_orders BIGINT[];
  offer_ids UUID[];
  v_activity_impacts jsonb := '[]'::jsonb;
BEGIN
  -- Retrieve the order's occasion and payment_info.
  SELECT occasion, payment_info, form
    INTO order_oc, payment_info_id, form_id
    FROM eshop.orders
   WHERE id = delete_order_internal_v1.order_id;

  IF order_oc IS NULL THEN
    RAISE EXCEPTION 'Order not found.';
  END IF;

  -- Deletion belongs to scoped unit managers/editors and organization admins.
  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = order_oc;

  IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(unit_id)
      OR public.get_is_editor_on_unit(unit_id) OR public.get_is_admin_on_occasion(order_oc)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;
  -- The queue send gate locks global capacity before an order. Deletion must
  -- acquire that outer lock before the form/order helper to avoid inversion.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  -- Form serialization fences offer issuance, acceptance, expiry and recovery.
  -- Lock every directly related order in ID order before changing any links.
  PERFORM 1 FROM public.forms WHERE id=form_id FOR UPDATE;
  SELECT array_agg(DISTINCT id ORDER BY id) INTO related_orders FROM (
    SELECT o.id FROM eshop.orders o WHERE o.id=delete_order_internal_v1.order_id OR o.source_waitlist_order_id=delete_order_internal_v1.order_id
      OR o.id=(SELECT source_waitlist_order_id FROM eshop.orders WHERE id=delete_order_internal_v1.order_id)
    UNION SELECT a.source_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
    UNION SELECT a.target_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
  ) related;
  IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(related_orders)
      AND (o.occasion<>order_oc OR o.form IS DISTINCT FROM form_id)) THEN
    RAISE EXCEPTION 'ORDER_WAITLIST_SCOPE_MISMATCH'; END IF;
  PERFORM public.lock_order_capacity_scope_internal(related_orders);
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=delete_order_internal_v1.order_id AND state='preparing_payment')
    OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts a
      WHERE (a.target_order_id=delete_order_internal_v1.order_id OR a.source_order_id=delete_order_internal_v1.order_id) AND a.state='preparing') THEN
    RAISE EXCEPTION 'WAITLIST_ACCEPTANCE_IN_PROGRESS'; END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(SELECT form FROM eshop.orders WHERE id=delete_order_internal_v1.order_id);
  PERFORM public.lock_activity_aggregate_internal_v1(order_oc);
  IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(unit_id)
      OR public.get_is_editor_on_unit(unit_id) OR public.get_is_admin_on_occasion(order_oc)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;

  -- After authorization, match the worker lock order (capacity, order,
  -- attempts, message). Recheck the order after locking against concurrent edits.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  SELECT o.payment_info INTO payment_info_id
    FROM eshop.orders o
   WHERE o.id = delete_order_internal_v1.order_id AND o.occasion = order_oc
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found or occasion changed.';
  END IF;

  -- Remove every queued/reminder/provider record for this order. log_emails
  -- and address suppressions are independent audit/safety records and remain.
  DELETE FROM public.email_delivery_events e
   WHERE e.message_id IN (SELECT m.message_id FROM public.email_messages m
                           WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.attempt_id IN (SELECT a.attempt_id FROM public.email_attempts a
                          JOIN public.email_messages m USING (message_id)
                         WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.provider_message_id IN (
           SELECT m.provider_message_id FROM public.email_messages m
            WHERE m.order_id = delete_order_internal_v1.order_id
           UNION
           SELECT a.provider_message_id FROM public.email_attempts a
           JOIN public.email_messages m USING (message_id)
            WHERE m.order_id = delete_order_internal_v1.order_id);

  DELETE FROM public.email_confirmation_receipts r
   WHERE r.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_attempts a
   WHERE a.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_messages m
   WHERE m.order_id = delete_order_internal_v1.order_id;

  -- Collect all order_product_ticket IDs for the order.
  SELECT ARRAY(SELECT id FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id)
    INTO order_product_ticket_ids;

  -- Collect all ticket IDs from the order_product_ticket rows.
  SELECT ARRAY(SELECT ticket
                 FROM eshop.order_product_ticket
                WHERE "order" = delete_order_internal_v1.order_id
                  AND ticket IS NOT NULL)
    INTO ticket_ids;

  IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=ANY(ticket_ids) AND x."order"<>delete_order_internal_v1.order_id) THEN
    RAISE EXCEPTION 'TICKET_LINKED_TO_ANOTHER_ORDER'; END IF;

  -- Remove only this order's capability/offer evidence. Accepted children are
  -- independent orders: detach their source FK, never their tickets or finance.
  SELECT coalesce(array_agg(w.id),'{}') INTO offer_ids FROM eshop.waitlist_offers w WHERE w.order_id=delete_order_internal_v1.order_id;
  PERFORM 1 FROM eshop.waitlist_acceptance_attempts a
    WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id ORDER BY a.command_id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids) ORDER BY w.id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offer_slots x
    WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids) OR x.resulting_order_id=delete_order_internal_v1.order_id ORDER BY x.id FOR UPDATE;
  DELETE FROM eshop.waitlist_capabilities c WHERE c.order_id=delete_order_internal_v1.order_id OR c.offer_id=ANY(offer_ids);
  DELETE FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id;
  UPDATE eshop.waitlist_offer_slots x SET resulting_order_id=NULL,updated_at=clock_timestamp() WHERE x.resulting_order_id=delete_order_internal_v1.order_id;
  DELETE FROM eshop.waitlist_offer_slots x WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids);
  DELETE FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids);
  UPDATE eshop.orders o SET source_waitlist_order_id=NULL,updated_at=clock_timestamp() WHERE o.source_waitlist_order_id=delete_order_internal_v1.order_id;

  -- Free any spots that reference these order_product_ticket rows:
  -- set order_product_ticket, secret, and secret_expiration_time to NULL.
  UPDATE eshop.spots
     SET order_product_ticket      = NULL,
         secret                  = NULL,
         secret_expiration_time  = NULL,
         updated_at              = NOW()
   WHERE order_product_ticket = ANY(order_product_ticket_ids);

  -- Delete the related order_product_ticket entries.
  DELETE FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id;

  -- Ticket-bound membership teardown has one domain owner, independent of
  -- the retired public RPC. Authorization remains the order's manager boundary.
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE ticket=ANY(ticket_ids) AND occasion<>order_oc) THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket membership belongs to another occasion';
  END IF;
  FOR ou_record IN SELECT "user",occasion FROM public.occasion_users
    WHERE ticket=ANY(ticket_ids) AND occasion=order_oc ORDER BY "user"
  LOOP
    v_activity_impacts:=v_activity_impacts || public.remove_occasion_user_domain_internal_v1(order_oc,ou_record."user");
  END LOOP;
  -- The canonical order facade already invalidates profiles for remaining members.
  -- Teardown must also invalidate affected activity projections in sorted order.
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT DISTINCT x->>'component',order_oc,(x->>'userId')::uuid,1
  FROM jsonb_array_elements(v_activity_impacts) x
  JOIN public.occasion_users ou ON ou.occasion=order_oc AND ou."user"=(x->>'userId')::uuid
  WHERE x->>'component'='private_activity' ORDER BY 1,3
  ON CONFLICT(component,occasion,user_id) DO UPDATE
    SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();

  -- Delete the related tickets.
  -- This is now safe, as any occasion_users foreign key constraints
  -- should be resolved by the loop above.
  DELETE FROM eshop.tickets WHERE id = ANY(ticket_ids);

  -- Delete order history rows.
  DELETE FROM eshop.orders_history WHERE "order" = delete_order_internal_v1.order_id;

  -- Order-specific bank requests must not keep the order alive through their FK.
  DELETE FROM eshop.bank_account_requests WHERE "order" = delete_order_internal_v1.order_id;

  -- If a payment_info row exists, first free it from the order reference, then delete it.
  IF payment_info_id IS NOT NULL THEN
    UPDATE eshop.orders
       SET payment_info = NULL
     WHERE id = delete_order_internal_v1.order_id;

    -- Retain imported/manual bank transactions while removing their payment link.
    UPDATE eshop.transactions
       SET payment_info = NULL
     WHERE payment_info = payment_info_id;

    DELETE FROM eshop.payment_info WHERE id = payment_info_id;
  END IF;

  -- Finally, delete the order record.
  DELETE FROM eshop.orders WHERE id = delete_order_internal_v1.order_id;

END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_internal_v1(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_removed_users uuid[]; v_remaining_users uuid[];
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  SELECT o.occasion,oc.unit INTO v_occasion,v_unit FROM eshop.orders o
    JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
  -- Successful deletion removes the order. Exact retries retain their verified
  -- scope in the existing receipt, and still require current scoped rights.
  IF v_occasion IS NULL THEN
    SELECT r.occasion,oc.unit INTO v_occasion,v_unit FROM public.client_mutation_receipts r
    JOIN public.occasions oc ON oc.id=r.occasion
    WHERE r.command_id=p_command_id AND r.command_name='inventory.order.delete'
      AND r.actor_id=v_actor AND r.request_sha256=v_hash AND r.status IN ('completed','expired');
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT (public.get_is_manager_on_unit(v_unit) OR public.get_is_editor_on_unit(v_unit)
      OR public.get_is_admin_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required'; END IF;
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  -- Match the email worker's outer send fence before form/order locks.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  PERFORM 1 FROM public.forms WHERE id=(SELECT form FROM eshop.orders WHERE id=p_order) FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_removed_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt."order"=p_order;
  PERFORM public.delete_order_internal_v1(p_order);
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=v_occasion
    AND s.user_id=ANY(v_removed_users);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed_users) id));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_remaining_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  IF cardinality(v_removed_users)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=v_occasion;
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,v_occasion,
    'inventory.order.delete',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order,'operation','delete',
      'safeLabel','Order','changedFields',jsonb_build_array(
        'tickets','membership','allocations'))),v_remaining_users,v_public,v_dirty,
    jsonb_build_object('orderId',p_order,'removedUsers',cardinality(v_removed_users)));
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_221(order_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.delete_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_221(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_221(bigint) TO authenticated;


-- Source: database/functions/eshop_orders/delete_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.delete_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_removed_users uuid[]; v_remaining_users uuid[];
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  SELECT o.occasion,oc.unit INTO v_occasion,v_unit FROM eshop.orders o
    JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
  -- Successful deletion removes the order. Exact retries retain their verified
  -- scope in the existing receipt, and still require current scoped rights.
  IF v_occasion IS NULL THEN
    SELECT r.occasion,oc.unit INTO v_occasion,v_unit FROM public.client_mutation_receipts r
    JOIN public.occasions oc ON oc.id=r.occasion
    WHERE r.command_id=p_command_id AND r.command_name='inventory.order.delete'
      AND r.actor_id=v_actor AND r.request_sha256=v_hash AND r.status IN ('completed','expired');
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT (public.get_is_manager_on_unit(v_unit) OR public.get_is_editor_on_unit(v_unit)
      OR public.get_is_admin_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required'; END IF;
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  -- Match the email worker's outer send fence before form/order locks.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  PERFORM 1 FROM public.forms WHERE id=(SELECT form FROM eshop.orders WHERE id=p_order) FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_removed_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt."order"=p_order;
  PERFORM public.delete_order_internal_v1(p_order);
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=v_occasion
    AND s.user_id=ANY(v_removed_users);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed_users) id));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_remaining_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  IF cardinality(v_removed_users)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=v_occasion;
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,v_occasion,
    'inventory.order.delete',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order,'operation','delete',
      'safeLabel','Order','changedFields',jsonb_build_array(
        'tickets','membership','allocations'))),v_remaining_users,v_public,v_dirty,
    jsonb_build_object('orderId',p_order,'removedUsers',cardinality(v_removed_users)));
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  TO authenticated;


-- Source: database/functions/eshop_forms/get_form_by_link.sql
CREATE OR REPLACE FUNCTION public.get_form_bundle_internal(p_form_id bigint,p_allow_closed boolean DEFAULT false)
RETURNS JSON LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
    allData JSON;
    generated_secret UUID := gen_random_uuid();
    form_exists BOOLEAN;
    is_editor_view BOOLEAN := false;
    occ_id BIGINT;
BEGIN
    -- Check if the form exists
    SELECT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id
    ) INTO form_exists;

    IF NOT form_exists THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form does not exist.'
        );
    END IF;

    SELECT occasion INTO occ_id FROM public.forms WHERE id = p_form_id;
    is_editor_view := public.get_is_editor_order_view_on_occasion(occ_id);


    IF NOT p_allow_closed AND NOT is_editor_view AND NOT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id AND is_open = true
    ) THEN
        -- If the form is closed, retrieve only the 'header_off' message
        SELECT jsonb_build_object(
            'code', 400,
            'data', jsonb_build_object(
                'header_off', f.header_off,
                'is_open', f.is_open
            )
        )
        INTO allData
        FROM public.forms f
        WHERE f.id = p_form_id;

        RETURN allData;
    END IF;

    -- If the form is open, retrieve the full form data including dynamic product availability
    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'capacity', public.get_form_capacity_snapshot_internal(f.id),
            'registrationMode',public.get_form_registration_mode_internal(f.id),
            'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'id', f.id,
            'link', f.link,
            'key', f.key,
            'created_at', f.created_at,
            'data', public.get_effective_form_data(f.id),
            'type', f.type,
            'title', f.title,
            'is_open', f.is_open,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', jsonb_build_object(
                'id', o.id,
                'title', o.title,
                'features', o.features,
                'start_time', o.start_time
            ),
            'blueprint', f.blueprint,
            'deadline_duration_seconds', f.deadline_duration_seconds,
            'account_number', ba.account_number,
            'secret', generated_secret,
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'data', p.data,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum,
                                                    'is_dynamically_available', is_product_dynamically_available(p.id)
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                              AND NOT p.is_hidden
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id AND ff.is_hidden = false
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    LEFT JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    RETURN allData;
END;
$$;

REVOKE ALL ON FUNCTION public.get_form_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_form_by_link(form_link text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT public.get_form_bundle_internal((SELECT id FROM public.forms WHERE link=form_link),false);
$$;


-- Source: database/functions/eshop_waitlist/capabilities.sql
-- Only visible name/surname definitions in this form can label a ticket.
CREATE OR REPLACE FUNCTION public.get_waitlist_ticket_display_name_internal(p_form bigint,p_answers jsonb,p_contact jsonb DEFAULT '{}')
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(nullif((SELECT string_agg(btrim(answer.value#>>'{}'),' ' ORDER BY CASE definition.type WHEN 'name' THEN 0 ELSE 1 END,definition."order" NULLS LAST,definition.id)
 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_answers->'fields')='array' THEN p_answers->'fields' ELSE '[]' END) field
 CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(field)='object' THEN field ELSE '{}' END) answer
 JOIN public.form_fields definition ON definition.id::text=answer.key
 WHERE definition.form=p_form AND definition.is_ticket_field AND NOT definition.is_hidden
 AND definition.type IN ('name','surname') AND jsonb_typeof(answer.value)='string' AND btrim(answer.value#>>'{}')<>''),''),
 nullif(btrim(concat_ws(' ',nullif(btrim(p_contact->>'name'),''),nullif(btrim(p_contact->>'surname'),''))),''));
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_ticket_display_name_internal(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_effective_waitlist_ticket_lifecycle_internal(p_ticket bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN t.state='storno' THEN CASE WHEN t.ticket_symbol IS NULL THEN 'withdrawn' ELSE 'cancelled' END
 WHEN t.state IS DISTINCT FROM 'waitlisted' THEN 'admitted'
 WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id WHERE s.ticket_id=t.id AND s.outcome='pending' AND w.expires_at>clock_timestamp()) THEN 'offered'
 ELSE coalesce((SELECT CASE s.outcome WHEN 'expired' THEN 'offer_expired' WHEN 'declined' THEN 'offer_declined' WHEN 'cancelled' THEN 'offer_cancelled' WHEN 'pending' THEN 'offer_expired' ELSE 'waiting' END
 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id WHERE s.ticket_id=t.id ORDER BY w.created_at DESC,s.updated_at DESC,s.id DESC LIMIT 1),'waiting') END
 FROM eshop.tickets t WHERE t.id=p_ticket;
$$;
REVOKE ALL ON FUNCTION public.get_effective_waitlist_ticket_lifecycle_internal(bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.check_waitlist_scope_internal(p_order bigint,p_offer uuid,p_token text,p_actor uuid,p_operation text)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; c eshop.waitlist_capabilities; occ public.occasions;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order; SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 IF o.id IS NULL OR o.form IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_actor IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=o.occasion AND "user"=p_actor AND is_editor_order) THEN
  IF p_offer IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=p_offer AND order_id=p_order AND form_id=o.form) THEN
   RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF; RETURN o.form;
 END IF;
 IF p_operation IN ('send','cancel','proposal') OR p_token IS NULL OR length(p_token)<>64 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO c FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND organization_id=occ.organization AND form_id=o.form AND order_id=o.id AND (revoked_at IS NULL OR p_operation='read')
 AND ((p_operation='withdraw' AND kind='manage' AND o.state='waitlisted') OR
 (p_operation IN ('read','accept','decline') AND kind='offer' AND offer_id=p_offer));
 IF c.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Expired offer links may read their own terminal state; writers recheck time under locks.
 IF p_operation<>'read' AND c.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 RETURN o.form;
END $$;
CREATE OR REPLACE FUNCTION public.get_waitlist_summary_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH effective AS (SELECT public.get_effective_waitlist_ticket_lifecycle_internal(person.id) lifecycle
 FROM public.get_order_tickets_internal(p_order) person), p AS (SELECT lifecycle,count(*) n FROM effective GROUP BY lifecycle),
 s AS (SELECT count(*) n,min(w.expires_at) expiry FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers w ON w.id=x.offer_id
 JOIN public.get_order_tickets_internal(p_order) person ON person.id=x.ticket_id WHERE true AND x.outcome='pending' AND w.expires_at>clock_timestamp())
 SELECT jsonb_build_object('counts',coalesce((SELECT jsonb_object_agg(lifecycle,n) FROM p),'{}'),
 'pendingPlaces',s.n,'earliestExpiry',s.expiry,'isActive',CASE WHEN o.state='waitlisted' THEN
  coalesce((SELECT n>0 FROM p WHERE lifecycle='waiting'),false) OR s.n>0 ELSE o.state IS DISTINCT FROM 'storno' END,
 'allowedActions',CASE WHEN o.state='waitlisted' THEN jsonb_build_array('view','note','offer','withdraw')
 WHEN o.state IN ('storno','preparing_payment') THEN jsonb_build_array('view')
 WHEN o.state='ordered' THEN jsonb_build_array('view','note','edit','cancel','paid')
 ELSE jsonb_build_array('view','note','edit','cancel','send') END)
 FROM eshop.orders o CROSS JOIN s WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_form(p_token text DEFAULT NULL,p_offer_id uuid DEFAULT NULL,p_order_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oid bigint; fid bigint; bundle jsonb; w eshop.waitlist_offers;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO w FROM eshop.waitlist_offers WHERE id=p_offer_id;
 oid:=coalesce(w.order_id,p_order_id);
 fid:=public.check_waitlist_scope_internal(oid,p_offer_id,p_token,auth.uid(),CASE WHEN p_offer_id IS NULL THEN 'withdraw' ELSE 'read' END);
 -- Terminal links explain their own outcome without exposing form answers,
 -- contact data, products, or payment details after capability revocation.
 IF p_offer_id IS NOT NULL AND (w.expires_at<=clock_timestamp() OR NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending')) THEN
  RETURN jsonb_build_object('code',200,'registrationMode','offer','form',NULL,
   'offerId',w.id,'pendingCount',0,'expiresAt',w.expires_at,'serverTime',clock_timestamp(),
   'offerStatus',CASE WHEN w.expires_at<=clock_timestamp() THEN 'expired'
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome IN ('declined','cancelled')) THEN 'cancelled'
    ELSE 'accepted' END,'tickets','[]'::jsonb,'slots','[]'::jsonb);
 END IF;
 bundle:=public.get_form_bundle_internal(fid,true)::jsonb;
 bundle:=jsonb_set(bundle,'{data,registrationMode}',to_jsonb(CASE WHEN p_offer_id IS NOT NULL THEN 'offer'::text ELSE 'waitlist' END),true);
 RETURN jsonb_build_object('code',200,'form',bundle->'data','registrationMode',CASE WHEN p_offer_id IS NOT NULL THEN 'offer' ELSE 'waitlist' END,
  'orderSymbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),
  'occasionTitle',(SELECT occ.title FROM public.occasions occ JOIN eshop.orders source ON source.occasion=occ.id WHERE source.id=oid),
  'orderData',(SELECT data FROM eshop.orders WHERE id=oid),'pendingCount',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending' AND w.expires_at>clock_timestamp()),
  'orderId',oid,'offerId',p_offer_id,'serverTime',clock_timestamp(),'expiresAt',w.expires_at,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'displayName',public.get_waitlist_ticket_display_name_internal(fid,data,CASE WHEN (SELECT count(*) FROM public.get_order_tickets_internal(oid))=1 THEN (SELECT source.data FROM eshop.orders source WHERE source.id=oid) ELSE '{}'::jsonb END),'answers',public.extract_ticket_answers_internal(fid,data),'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(id)) ORDER BY created_at,id),'[]')
   FROM public.get_order_tickets_internal(oid)),
  'slots',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'ticketId',ticket_id,'outcome',CASE WHEN outcome='pending' AND w.expires_at<=clock_timestamp() THEN 'expired' ELSE outcome END)),'[]')
   FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id),'waitlistSummary',public.get_waitlist_summary_internal(oid));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.check_waitlist_scope_internal(bigint,uuid,text,uuid,text),public.get_waitlist_summary_internal(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_waitlist_order_detail(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
 IF NOT public.get_is_editor_order_view_on_occasion(o.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Order viewer required'; END IF;
 RETURN jsonb_build_object('orderId',o.id,'sourceOrderId',o.source_waitlist_order_id,
 'occasionTitle',(SELECT title FROM public.occasions WHERE id=o.occasion),'waitlistSummary',public.get_waitlist_summary_internal(o.id),
 'capacity',public.get_form_capacity_snapshot_internal(o.form),
 'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'displayName',public.get_waitlist_ticket_display_name_internal(o.form,p.data,CASE WHEN (SELECT count(*) FROM public.get_order_tickets_internal(o.id))=1 THEN o.data ELSE '{}'::jsonb END),'createdAt',p.created_at,'waitlistQueueAt',p.waitlist_queue_at,'answers',public.extract_ticket_answers_internal(o.form,p.data),
  'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(p.id)) ORDER BY created_at,id),'[]') FROM public.get_order_tickets_internal(o.id) p),
 'offers',(SELECT coalesce(jsonb_agg(to_jsonb(w)||jsonb_build_object('slots',(SELECT coalesce(jsonb_agg((to_jsonb(s)-'ticket_id')||jsonb_build_object('ticketId',s.ticket_id)),'[]') FROM eshop.waitlist_offer_slots s WHERE offer_id=w.id)) ORDER BY created_at),'[]')
 FROM eshop.waitlist_offers w WHERE order_id=o.id),
 'linkedOrders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'orderSymbol',order_symbol,'state',state)),'[]') FROM eshop.orders WHERE source_waitlist_order_id=o.id));
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_order_detail(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_order_detail(bigint) TO authenticated;
