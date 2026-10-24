-- Parents before ticket, shared by web and retained native/admin writers.
CREATE OR REPLACE FUNCTION public.scanner_lock_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE parents bigint[]; current_parents bigint[]; parent bigint;
BEGIN
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 PERFORM public.lock_order_capacity_scope_internal(parents);
 FOREACH parent IN ARRAY coalesce(parents,ARRAY[]::bigint[]) LOOP
  PERFORM 1 FROM eshop.orders WHERE id=parent FOR UPDATE;
 END LOOP;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO current_parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 IF parents IS DISTINCT FROM current_parents THEN RAISE serialization_failure USING MESSAGE='ticket_parent_changed'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.scanner_admit_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_ticket_is_mutable(p_ticket);
 IF NOT public.stripe_ticket_admission_allowed_internal(p_ticket) THEN RAISE EXCEPTION 'stripe_admission_hold'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=p_ticket AND state='used') THEN RAISE EXCEPTION 'already_used'; END IF;
 UPDATE eshop.tickets SET state='used',updated_at=clock_timestamp() WHERE id=p_ticket;
END $$;
CREATE OR REPLACE FUNCTION public.lookup_scanner_ticket(p_session uuid,p_token text,p_symbol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; tid bigint; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 SELECT t.id INTO tid FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol=p_symbol LIMIT 1;
 IF tid IS NULL AND p_symbol ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN
  SELECT t.id INTO tid FROM public.occasion_users ou JOIN eshop.tickets t ON t.id=ou.ticket WHERE ou.occasion=s.occasion_id AND ou."user"=p_symbol::uuid AND t.occasion=s.occasion_id LIMIT 1;
 END IF;
 SELECT dto INTO result FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid) WHERE ticket_id=tid;
 IF result IS NOT NULL THEN result:=result||jsonb_build_object('can_reset_password',public.scanner_can_reset_password_internal(s.occasion_id,tid)); END IF;
 RETURN jsonb_build_object('code',CASE WHEN result IS NULL THEN 404 ELSE 200 END,'reason',CASE WHEN result IS NULL THEN 'not_found' ELSE 'found' END,
 'data',result,'settings_revision',cfg.revision,'server_time',now());
END $$;
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
 AND (strpos(lower(dto->>'holder_name'),lower(p_query))>0 OR strpos(lower(dto->>'batch_title'),lower(p_query))>0 OR strpos(lower(dto->>'symbol'),lower(p_query))>0) ORDER BY ticket_id LIMIT 30) found;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.sync_scanner_operations(p_session uuid,p_token text,p_operations jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; op jsonb; canonical jsonb; h text; prior public.scanner_operations;
 tid bigint; proj jsonb; receipt jsonb; outcome text; reason text; results jsonb:='[]'; existing boolean; snap public.scanner_snapshots;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF p_operations IS NULL OR jsonb_typeof(p_operations)<>'array' OR jsonb_array_length(p_operations) NOT BETWEEN 1 AND 50 OR octet_length(p_operations::text)>262144 THEN
  RETURN jsonb_build_object('code',400,'reason','invalid_batch','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now()); END IF;
 FOR op IN SELECT value FROM jsonb_array_elements(p_operations) LOOP
  IF op->>'action' IS DISTINCT FROM 'admit_ticket' OR op->>'origin_session_id' IS DISTINCT FROM p_session::text
   OR op->>'eligibility_fingerprint' IS NULL OR length(op->>'eligibility_fingerprint')<>64
   OR op->>'operation_id' IS NULL OR op->>'ticket_id' IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid_operation'; END IF;
  tid:=(op->>'ticket_id')::bigint;
  canonical:=jsonb_build_object('operation_id',(op->>'operation_id')::uuid,'origin_session_id',p_session,'occasion_id',s.occasion_id,
   'ticket_id',tid,'action','admit_ticket','snapshot_id',op->'snapshot_id','settings_revision',op->'settings_revision',
   'eligibility_fingerprint',op->'eligibility_fingerprint','confirm_unpaid',coalesce((op->>'confirm_unpaid')::boolean,false),'captured_at',op->'captured_at');
  h:=encode(digest(canonical::text,'sha256'),'hex');
  -- Serializes global identity before any domain mutation. No incomplete receipt survives a transaction.
  PERFORM pg_advisory_xact_lock(hashtextextended(op->>'operation_id',5317));
  SELECT * INTO prior FROM public.scanner_operations WHERE operation_id=(op->>'operation_id')::uuid;
  IF FOUND THEN
   IF prior.session_id<>p_session OR prior.payload_hash<>h THEN
    results:=results||jsonb_build_array(jsonb_build_object('operation_id',op->>'operation_id','outcome','rejected','reason','operation_payload_mismatch'));
   ELSE results:=results||jsonb_build_array(prior.receipt||jsonb_build_object('replayed',true)); END IF;
   CONTINUE;
  END IF;
  IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN
   RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now());
  END IF;
  outcome:='rejected'; reason:='not_found'; proj:=NULL;
  IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=tid AND occasion=s.occasion_id) THEN
   PERFORM public.scanner_lock_ticket_internal(tid);
   PERFORM public.check_occasion_writable(s.occasion_id);
   SELECT dto INTO proj FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid);
   IF op->>'snapshot_id' IS NOT NULL AND coalesce((proj->>'online_required')::boolean,false) THEN reason:='online_required';
   ELSIF proj->>'state'='used' THEN outcome:='conflict'; reason:='already_used';
   ELSIF proj->>'state' IN ('storno','waitlisted') OR NOT coalesce((proj->>'admission_allowed')::boolean,false) THEN reason:='admission_not_allowed';
   ELSIF proj->>'eligibility_fingerprint' IS DISTINCT FROM op->>'eligibility_fingerprint' THEN outcome:='conflict'; reason:='eligibility_changed';
   ELSIF (proj->>'requires_unpaid_confirmation')::boolean AND (NOT coalesce((op->>'confirm_unpaid')::boolean,false) OR op->>'snapshot_id' IS NOT NULL) THEN reason:='unpaid_confirmation_required';
   ELSE
    reason:='admitted'; outcome:='accepted';
    IF op->>'snapshot_id' IS NOT NULL THEN
     SELECT * INTO snap FROM public.scanner_snapshots WHERE id=(op->>'snapshot_id')::uuid AND session_id=p_session;
     IF snap.id IS NULL OR snap.expires_at<=now() OR s.offline_until<=now() OR NOT EXISTS(
      SELECT 1 FROM public.scanner_snapshot_pages pg CROSS JOIN LATERAL jsonb_array_elements(pg.payload_text::jsonb) item
      WHERE pg.snapshot_id=snap.id AND item->>'ticket_id'=tid::text AND item->>'eligibility_fingerprint'=op->>'eligibility_fingerprint') THEN
      outcome:='conflict'; reason:='offline_grant_invalid'; END IF;
    END IF;
    IF outcome='accepted' THEN
     PERFORM public.scanner_admit_ticket_internal(tid);
    END IF;
   END IF;
  END IF;
  receipt:=jsonb_build_object('operation_id',op->>'operation_id','ticket_id',tid,'outcome',outcome,'reason',reason,
   'committed_at',clock_timestamp(),'eligibility_fingerprint',op->>'eligibility_fingerprint');
  INSERT INTO public.scanner_operations(operation_id,session_id,occasion_id,ticket_id,payload_hash,payload,receipt)
   VALUES((op->>'operation_id')::uuid,p_session,s.occasion_id,tid,h,canonical,receipt);
  results:=results||jsonb_build_array(receipt);
 END LOOP;
 RETURN jsonb_build_object('code',200,'data',results,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_receipts(p_session uuid,p_token text,p_operation_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token,true);
 IF coalesce(array_length(p_operation_ids,1),0)>50 THEN RAISE invalid_parameter_value; END IF;
 -- Expired/revoked devices can reconcile their immutable history, never perform a new write.
 SELECT coalesce(jsonb_agg(receipt),'[]'::jsonb) INTO result FROM public.scanner_operations WHERE session_id=p_session AND operation_id=ANY(p_operation_ids);
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_summary(p_session uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 WITH eligible AS MATERIALIZED (
 SELECT t.id,t.state FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol IS NOT NULL
 AND t.state IN ('used','paid','sent','ordered') AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=t.id)
 AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" WHERE z.ticket=t.id AND (o.state IN ('stock','storno','waitlisted','preparing_payment') OR o.occasion<>s.occasion_id)))
 SELECT jsonb_build_object('used_current',count(*) FILTER(WHERE state='used'),'unused_eligible',count(*) FILTER(WHERE state IN ('paid','sent')),
 'eligible_total',count(*) FILTER(WHERE state IN ('used','paid','sent')),'unpaid_conditional',count(*) FILTER(WHERE state='ordered'),
 'definition_version',1,'definition','used + paid/sent; excludes conditional unpaid, cancelled and waitlisted',
 'server_time',now(),'settings_revision',(SELECT revision FROM public.scanner_settings WHERE occasion_id=s.occasion_id)) INTO result FROM eligible;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.resolve_scanner_conflict(p_operation uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE op public.scanner_operations;
BEGIN
 SELECT * INTO STRICT op FROM public.scanner_operations WHERE operation_id=p_operation;
 PERFORM public.check_is_editor_order_on_occasion(op.occasion_id);
 IF auth.uid() IS NULL OR op.receipt->>'outcome'<>'conflict' THEN RAISE insufficient_privilege; END IF;
 INSERT INTO public.scanner_conflict_resolutions(operation_id,actor_user_id,reason) VALUES(p_operation,auth.uid(),p_reason) ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('code',200,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_summary(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_summary(uuid,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.resolve_scanner_conflict(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_scanner_conflict(uuid,text) TO authenticated,service_role;
