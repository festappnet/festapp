-- Restore scoped owners overwritten by older assembled migrations.

-- Source: database/functions/users/reception_qr_login.sql
CREATE OR REPLACE FUNCTION public.create_reception_user_v1(p_occasion bigint,p_command_id uuid,p_profile jsonb,p_group_id bigint DEFAULT NULL,p_accommodation_code text DEFAULT NULL,p_confirm_same_name boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_org bigint; v_user uuid; v_hash text; v_existing public.reception_registrations%rowtype;
  v_name text:=btrim(p_profile->>'name'); v_surname text:=btrim(p_profile->>'surname'); v_email text:=lower(btrim(p_profile->>'email'));
  v_sex text:=p_profile->>'sex'; v_matches jsonb; v_services jsonb:='{}'::jsonb; v_catalog jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('create') THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_profile) k WHERE k NOT IN('name','surname','email','sex','phone','birthDate'))
  THEN RETURN jsonb_build_object('code',400,'message','invalid_profile_fields'); END IF;
  IF COALESCE(v_name,'')='' OR COALESCE(v_surname,'')='' OR COALESCE(v_email,'')='' OR position('@' IN v_email)<=1 OR v_sex NOT IN('male','female','unspecified')
  THEN RETURN jsonb_build_object('code',400,'message','required_profile_fields'); END IF;
  v_hash:=encode(digest(jsonb_build_object('profile',p_profile,'group',p_group_id,'accommodation',p_accommodation_code)::text,'sha256'),'hex');
  SELECT * INTO v_existing FROM public.reception_registrations WHERE occasion=p_occasion AND created_by=v_actor AND command_id=p_command_id;
  IF FOUND THEN
    IF v_existing.request_hash<>v_hash THEN RETURN jsonb_build_object('code',409,'message','command_conflict'); END IF;
    SELECT ui.email_readonly INTO v_email FROM public.user_info ui WHERE ui.id=v_existing."user";
    RETURN jsonb_build_object('code',200,'userId',v_existing."user",'email',v_email,'replayed',true);
  END IF;
  SELECT o.organization,COALESCE(o.services,'{}'::jsonb) INTO v_org,v_catalog FROM public.occasions o WHERE o.id=p_occasion FOR SHARE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reception-email:'||v_org::text||':'||v_email,0));
  SELECT ui.id INTO v_user
  FROM public.user_info ui
  WHERE ui.organization=v_org AND lower(btrim(ui.email_readonly))=v_email;
  IF v_user IS NOT NULL THEN
    IF (public.get_is_admin_on_occasion(p_occasion)
        OR public.get_is_manager_on_occasion(p_occasion))
      AND EXISTS(SELECT 1 FROM public.occasion_users ou
        WHERE ou.occasion=p_occasion AND ou."user"=v_user) THEN
      RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,
        'existing',true,'replayed',false);
    END IF;
    RETURN jsonb_build_object('code',409,'message','email_already_exists');
  END IF;
  SELECT COALESCE(jsonb_agg(candidate),'[]'::jsonb) INTO v_matches FROM (
    SELECT jsonb_build_object('name',ui.name,'surname',ui.surname,'sex',ui.sex,
      'birthYear',CASE WHEN ui.birth_date IS NULL THEN NULL ELSE extract(year FROM ui.birth_date)::int END,
      'email',CASE WHEN position('@' IN ui.email_readonly)>2 THEN left(ui.email_readonly,1)||'***@'||split_part(ui.email_readonly,'@',2) ELSE '***' END,
      'onOccasion',EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=ui.id)) candidate
    FROM public.user_info ui WHERE ui.organization=v_org AND public.f_unaccent(btrim(ui.name))=public.f_unaccent(v_name)
      AND public.f_unaccent(btrim(ui.surname))=public.f_unaccent(v_surname) ORDER BY ui.created_at NULLS LAST LIMIT 10) q;
  IF jsonb_array_length(v_matches)>0 AND NOT p_confirm_same_name THEN RETURN jsonb_build_object('code',409,'message','same_name_confirmation_required','candidates',v_matches); END IF;
  IF p_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.user_group_info g WHERE g.id=p_group_id AND g.occasion=p_occasion AND g.type IS NULL FOR SHARE)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_group'); END IF;
  IF p_accommodation_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_catalog->'accommodation')='array' THEN v_catalog->'accommodation' ELSE '[]'::jsonb END) x WHERE x->>'code'=p_accommodation_code)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_accommodation'); END IF;
  v_user:=public.create_user_in_organization_with_data_pure(v_org,v_email,v_email,encode(gen_random_bytes(32),'hex'),p_profile-'email');
  IF p_accommodation_code IS NOT NULL THEN v_services:=jsonb_build_object('accommodation',jsonb_build_object(p_accommodation_code,'paid')); END IF;
  INSERT INTO public.occasion_users(occasion,"user",data,services) VALUES(p_occasion,v_user,p_profile,v_services);
  IF p_group_id IS NOT NULL THEN INSERT INTO public.user_groups("user","group",is_admin) VALUES(v_user,p_group_id,false); END IF;
  INSERT INTO public.reception_registrations(occasion,"user",created_by,command_id,request_hash) VALUES(p_occasion,v_user,v_actor,p_command_id,v_hash);
  RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,'replayed',false);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('code',409,'message','email_or_command_conflict');
END $$;

-- Source: database/functions/users/reception_qr_login.sql
CREATE OR REPLACE FUNCTION public.cancel_reception_registration_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_r public.reception_registrations%rowtype; v_actor uuid:=auth.uid(); v_impacts jsonb;
BEGIN
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  SELECT * INTO v_r FROM public.reception_registrations WHERE occasion=p_occasion AND "user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','registration_unavailable'); END IF;
  IF NOT public.get_can_use_reception(p_occasion) OR NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR (v_r.created_by=v_actor AND (v_r.status='cancelled' OR v_r.created_at>now()-interval '30 minutes'))) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  IF v_r.status='cancelled' THEN RETURN jsonb_build_object('code',200,'status',CASE WHEN v_r.auth_revoked_at IS NULL THEN 'domain_blocked_auth_revocation_pending' ELSE 'cancelled' END,'targetUser',p_user); END IF;
  IF NOT public.reception_rate_limit_v1('cancel') THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  UPDATE public.reception_registrations SET status='cancelled',cancelled_by=v_actor,cancelled_at=now() WHERE occasion=p_occasion AND "user"=p_user;
  v_impacts:=public.remove_occasion_user_domain_internal_v1(p_occasion,p_user);
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT x->>'component',p_occasion,(x->>'userId')::uuid,1 FROM jsonb_array_elements(v_impacts) x ORDER BY x->>'component',x->>'userId'
  ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();
  RETURN jsonb_build_object('code',200,'status','domain_blocked_auth_revocation_pending','targetUser',p_user);
END $$;

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
  PERFORM public.admit_order_mutation_v1(v_occasion,(SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=p_order));
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

-- Source: database/functions/emails/email_queue.sql
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
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
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
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
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
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.email_intent_valid(public.email_messages) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.email_intent_valid(public.email_messages) TO service_role;
