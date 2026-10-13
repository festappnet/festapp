-- Edge is the trusted preparation boundary for random capabilities and sealed email.
-- It verifies the bearer user; SQL still checks the explicit actor's occasion rights.
CREATE OR REPLACE FUNCTION public.sanitize_waitlist_history_internal(p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(key,public.sanitize_waitlist_history_internal(value)),'{}') INTO result
  FROM jsonb_each(p_value) WHERE lower(key) NOT IN
   ('token','secret','password','offertoken','managetoken','capability','waitlistenvelope','sealed','tokenhash');
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(value) ORDER BY ordinal),'[]') INTO result
  FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,ordinal);
  RETURN result;
 END IF;
 RETURN p_value;
END $$;
CREATE OR REPLACE FUNCTION public.snapshot_waitlist_participants_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(to_jsonb(p)) ORDER BY registered_at,id),'[]')
 FROM eshop.order_participants p WHERE current_order_id=p_order;
$$;
REVOKE ALL ON FUNCTION public.sanitize_waitlist_history_internal(jsonb),public.snapshot_waitlist_participants_internal(bigint)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.execute_waitlist_command_client_sync_v1(
 p_operation text,p_payload jsonb,p_command_id uuid,p_client_id uuid,p_actor uuid DEFAULT NULL,p_deliveries jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; occ bigint; oid bigint; offer uuid; mode text; c jsonb; result jsonb; claim jsonb;
 hash text; selected uuid[]; expected integer; changed integer; recipients jsonb; r jsonb; delivery jsonb;
 person jsonb; slot_ids uuid[]; expiry timestamptz; f public.forms; people jsonb; n integer; before_users uuid[];
 previous_sub text; actor_kind text; o eshop.orders; entity_changes jsonb:='[]';
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_operation NOT IN ('register','send','accept','decline','cancel','withdraw') OR p_command_id IS NULL OR p_client_id IS NULL
 OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4194304 THEN RAISE EXCEPTION 'Invalid waitlist command'; END IF;
 IF p_operation='register' THEN SELECT id INTO fid FROM public.forms WHERE key=(p_payload->>'form')::uuid;
 ELSIF p_operation='send' THEN fid:=(p_payload->>'formId')::bigint;
 ELSIF p_operation='withdraw' THEN oid:=(p_payload->>'orderId')::bigint; SELECT form INTO fid FROM eshop.orders WHERE id=oid;
 ELSE offer:=(p_payload->>'offerId')::uuid; SELECT order_id,form_id INTO oid,fid FROM eshop.waitlist_offers WHERE id=offer; END IF;
 SELECT * INTO f FROM public.forms WHERE id=fid; occ:=f.occasion;
 IF occ IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_operation IN ('send','cancel') AND NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occ AND "user"=p_actor AND is_editor_order) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 previous_sub:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
 hash:=encode(extensions.digest(jsonb_build_object('operation',p_operation,'payload',p_payload,'actor',p_actor)::text,'sha256'),'hex');
 BEGIN
  IF p_actor IS NULL THEN claim:=public.begin_anonymous_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_client_id,hash); actor_kind:='unknown';
  ELSE claim:=public.begin_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_actor,hash); actor_kind:='user'; END IF;
 EXCEPTION WHEN invalid_parameter_value THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN jsonb_build_object('code',409,'errorCode','COMMAND_PAYLOAD_CONFLICT');
 END;
 IF claim->>'disposition'='replay' THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN claim->'response'; END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO before_users FROM public.occasion_users WHERE occasion=occ;
 BEGIN
  PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 IF p_operation IN ('accept','decline','cancel','withdraw') THEN
  PERFORM public.check_waitlist_scope_internal(oid,offer,p_payload->>'token',p_actor,p_operation); END IF;

  PERFORM public.expire_waitlist_form_internal(fid);
  c:=public.get_form_capacity_snapshot_internal(fid);
  IF p_operation='register' THEN
   mode:=public.get_form_registration_mode_internal(fid);
   IF mode<>'waitlist' THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   people:=public.normalize_form_participant_answers_internal(fid,p_payload->'people');
   PERFORM public.validate_waitlist_answers_internal(fid,p_payload,people,true);
   IF nullif(p_payload->>'email','') IS NULL THEN RAISE EXCEPTION 'Email required'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(people) p CROSS JOIN LATERAL jsonb_array_elements(coalesce(p->'fields','[]')) a WHERE a ? 'product_type') THEN
    RAISE EXCEPTION 'Waitlist does not accept products'; END IF;
   oid:=public.allocate_ticket_order_identity_internal(fid);
   UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=p_payload-'people'-'token' WHERE id=oid;
   FOR person IN SELECT * FROM jsonb_array_elements(people) LOOP
    INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,answers,lifecycle)
     VALUES(oid,oid,fid,public.extract_participant_answers_internal(fid,person),'waiting'); END LOOP;
   result:=jsonb_build_object('code',200,'order',jsonb_build_object('id',oid,'order_symbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),'state','waitlisted','payment_info',NULL,'price',NULL),
    'waitlistSummary',public.get_waitlist_summary_internal(oid),'email',public.enqueue_waitlist_email_internal(oid,NULL,p_command_id,p_deliveries->0));
  ELSIF p_operation='send' THEN
   SELECT * INTO f FROM public.forms WHERE id=fid;
   IF NOT f.waitlist_enabled THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   IF f.capacity_revision<>(p_payload->>'revision')::bigint THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','OFFER_CHANGED','capacity',c)::text; END IF;
   expiry:=(p_payload->>'expiresAt')::timestamptz;
   IF expiry IS NULL OR expiry<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
   recipients:=p_payload->'recipients';
   IF jsonb_typeof(recipients)<>'array' OR jsonb_array_length(recipients)<1 OR
    jsonb_array_length(recipients)<>(SELECT count(DISTINCT x->>'orderId') FROM jsonb_array_elements(recipients) x) THEN RAISE EXCEPTION 'Invalid recipients'; END IF;
   SELECT sum((x->>'count')::integer) INTO n FROM jsonb_array_elements(recipients) x;
   IF n>(c->>'offerablePlaces')::integer THEN RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
   PERFORM 1 FROM eshop.orders WHERE id IN(SELECT (x->>'orderId')::bigint FROM jsonb_array_elements(recipients) x) ORDER BY id FOR UPDATE;
   result:=jsonb_build_object('code',200,'offers','[]'::jsonb);
   FOR r IN SELECT * FROM jsonb_array_elements(recipients) ORDER BY (value->>'orderId')::bigint LOOP
    oid:=(r->>'orderId')::bigint; n:=(r->>'count')::integer;
    IF n<1 OR NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND form=fid AND state='waitlisted') THEN RAISE EXCEPTION 'Invalid recipient scope'; END IF;
    SELECT array_agg(id) INTO selected FROM (SELECT p.id FROM eshop.order_participants p WHERE current_order_id=oid
     AND lifecycle IN ('waiting','offer_expired','offer_declined','offer_cancelled') AND NOT EXISTS
     (SELECT 1 FROM eshop.waitlist_offer_slots s WHERE participant_id=p.id AND outcome='pending')
     ORDER BY queue_at,registered_at,id LIMIT n FOR UPDATE) persons;
    IF coalesce(cardinality(selected),0)<>n THEN RAISE EXCEPTION 'OFFER_CHANGED'; END IF;
    INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision) VALUES(oid,fid,p_actor,expiry,f.capacity_revision) RETURNING id INTO offer;
    INSERT INTO eshop.waitlist_offer_slots(offer_id,participant_id,form_id) SELECT offer,id,fid FROM unnest(selected) id;
    UPDATE eshop.order_participants SET lifecycle='offered',updated_at=clock_timestamp() WHERE id=ANY(selected);
    SELECT x INTO delivery FROM jsonb_array_elements(p_deliveries) x WHERE (x->>'orderId')::bigint=oid;
    result:=jsonb_set(result,'{offers}',result->'offers'||jsonb_build_array(jsonb_build_object('orderId',oid,'offerId',offer,'count',n,'expiresAt',expiry,
     'email',public.enqueue_waitlist_email_internal(oid,offer,p_command_id,delivery))));
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,'waitlisted',jsonb_build_object('action','offer_sent','offerId',offer,'count',n,'expiresAt',expiry));
    entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist offer','changedFields',jsonb_build_array('waitlistSummary')));
   END LOOP;
  ELSIF p_operation='accept' THEN
   result:=public.accept_waitlist_offer_internal(p_payload,p_command_id,p_actor);
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',result#>>'{order,id}','operation','update','safeLabel','Accepted order','changedFields',jsonb_build_array('state','tickets','products','allocations')));
  ELSE
   PERFORM public.lock_order_capacity_scope_internal(ARRAY[oid]);
   IF (SELECT state FROM eshop.orders WHERE id=oid)<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   SELECT array_agg(x::uuid) INTO selected FROM jsonb_array_elements_text(p_payload->'personIds') x; n:=coalesce(cardinality(selected),0);
   IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(selected) x) THEN RAISE EXCEPTION 'Invalid persons'; END IF;
   IF n<>(SELECT count(*) FROM eshop.order_participants WHERE id=ANY(selected) AND current_order_id=oid AND lifecycle IN ('waiting','offered','offer_expired','offer_declined','offer_cancelled')) THEN
    RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   IF p_operation IN ('decline','cancel') AND n<>(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND outcome='pending' AND participant_id=ANY(selected)) THEN
    RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   UPDATE eshop.waitlist_offer_slots SET outcome=CASE WHEN p_operation='decline' THEN 'declined' ELSE 'cancelled' END,updated_at=clock_timestamp()
    WHERE participant_id=ANY(selected) AND outcome='pending' AND (p_operation='withdraw' OR offer_id=offer);
   UPDATE eshop.order_participants SET lifecycle=CASE p_operation WHEN 'decline' THEN 'offer_declined' WHEN 'cancel' THEN 'offer_cancelled' ELSE 'withdrawn' END,
    queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=ANY(selected);
   UPDATE eshop.waitlist_capabilities cap SET revoked_at=clock_timestamp() WHERE cap.order_id=oid AND kind='offer' AND NOT EXISTS
    (SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=cap.offer_id AND outcome='pending');
   result:=jsonb_build_object('code',200,'orderId',oid,'waitlistSummary',public.get_waitlist_summary_internal(oid));
  END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=fid;
  IF p_operation<>'send' THEN
   -- Acceptance owns its richer before/after snapshot at the same transaction
   -- boundary; avoid a second action-only row hiding that record in the detail.
   IF p_operation<>'accept' THEN
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,(SELECT state FROM eshop.orders WHERE id=oid),
     jsonb_build_object('action','waitlist_'||p_operation,'commandId',p_command_id,
     'personIds',CASE WHEN p_operation='register' THEN
       (SELECT jsonb_agg(id ORDER BY registered_at,id) FROM eshop.order_participants WHERE current_order_id=oid)
       ELSE to_jsonb(selected) END,
     'participants',public.snapshot_waitlist_participants_internal(oid)));
   END IF;
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist order','changedFields',jsonb_build_array('waitlistSummary','participants')));
  END IF;
  result:=result||jsonb_build_object('capacity',public.get_form_capacity_snapshot_internal(fid));
 EXCEPTION WHEN OTHERS THEN
  result:=CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',409,'errorCode',SQLERRM,'message',SQLERRM) END;
  result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
   CASE WHEN (result->>'code')::integer BETWEEN 200 AND 599 THEN (result->>'code')::integer ELSE 409 END,result);
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN result;
 END;
 entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','form','entityId',fid,'operation','update','safeLabel','Form capacity','changedFields',jsonb_build_array('capacity','registrationMode')));
 result:=public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.waitlist.'||p_operation,entity_changes,before_users,result,actor_kind);
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) TO service_role;
