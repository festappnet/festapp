CREATE OR REPLACE FUNCTION public.claim_notification_center_bank_health(p_limit integer DEFAULT 20) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_require_service();
 INSERT INTO public.notification_center_bank_health(connection_id)
 SELECT DISTINCT c.id FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts uba ON uba.bank_account=c.bank_account_id OR uba.bank_account IN
 (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 JOIN public.units u ON u.id=uba.unit JOIN public.notification_center_activation a ON a.organization=u.organization AND a.enabled
 WHERE c.mode='api' AND c.state IN ('connected','degraded') ON CONFLICT DO NOTHING;
 -- A newly connected source starts against the activation boundary, not its first failed refresh.
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 SELECT DISTINCT a.organization,'bank:'||c.id,jsonb_build_object('problem',c.created_at<a.activated_at AND
  (c.last_error IS NOT NULL OR coalesce(c.bank_pull_at,c.created_at)<a.activated_at-interval '30 minutes'))
 FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts uba ON uba.bank_account=c.bank_account_id OR uba.bank_account IN
  (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 JOIN public.units u ON u.id=uba.unit JOIN public.notification_center_activation a ON a.organization=u.organization AND a.enabled
 WHERE c.mode='api' AND c.state IN ('connected','degraded') ON CONFLICT DO NOTHING;
 WITH selected AS (SELECT h.connection_id FROM public.notification_center_bank_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
 WHERE h.next_at<=clock_timestamp() AND (h.lease_until IS NULL OR h.lease_until<clock_timestamp()) AND c.mode='api' AND c.state IN ('connected','degraded')
 AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
 JOIN public.notification_center_activation a ON a.organization=u.organization AND a.enabled WHERE uba.bank_account=c.bank_account_id
 OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))
 ORDER BY h.next_at,h.connection_id LIMIT greatest(1,least(p_limit,20)) FOR UPDATE OF h SKIP LOCKED), claimed AS (
 UPDATE public.notification_center_bank_health h SET lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes'
 FROM selected s WHERE s.connection_id=h.connection_id RETURNING h.*)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',h.connection_id,'token',h.lease_token,'remoteId',c.remote_bank_account_id)),'[]') INTO result
 FROM claimed h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.complete_notification_center_bank_health(p_connection bigint,p_token uuid,p_success_at timestamptz,p_reason text,p_at timestamptz DEFAULT clock_timestamp())
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE h public.notification_center_bank_health; c eshop.bank_sync_connections; scope record; old public.notification_center_source_state;
 nc_reason text; key text:='bank:'||p_connection; ev uuid; ep bigint; affected bigint[];
BEGIN
 PERFORM public.notification_center_require_service();
 SELECT * INTO h FROM public.notification_center_bank_health WHERE connection_id=p_connection AND lease_token=p_token AND lease_until>clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'notification_health_lease_lost'; END IF;
 SELECT * INTO STRICT c FROM eshop.bank_sync_connections WHERE id=p_connection;
 IF p_reason NOT IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch','bank_sync_retry_required','transport_unavailable') AND p_reason IS NOT NULL THEN RAISE EXCEPTION 'notification_health_reason_invalid'; END IF;
 nc_reason:=p_reason;
 IF c.state='suspended' THEN nc_reason:=NULL;
 ELSIF nc_reason IS NULL AND coalesce(p_success_at,h.last_success,c.bank_pull_at,c.created_at)<p_at-interval '30 minutes' THEN nc_reason:='stale_health'; END IF;
 h.failures:=CASE WHEN nc_reason IS NULL THEN 0 ELSE h.failures+1 END;
 h.failure_since:=CASE WHEN nc_reason IS NULL THEN NULL ELSE coalesce(h.failure_since,p_at) END;
 UPDATE public.notification_center_bank_health SET failures=h.failures,failure_since=h.failure_since,reason=nc_reason,last_success=greatest(last_success,p_success_at),
 lease_token=NULL,lease_until=NULL,next_at=p_at+CASE WHEN p_reason='transport_unavailable' THEN interval '10 minutes' ELSE interval '5 minutes' END WHERE connection_id=p_connection;
 FOR scope IN SELECT DISTINCT u.organization FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
 JOIN public.notification_center_activation a ON a.organization=u.organization AND a.enabled
 WHERE uba.bank_account=c.bank_account_id OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id) LOOP
  PERFORM 1 FROM public.notification_center_activation WHERE organization=scope.organization FOR SHARE;
  SELECT array_agg(DISTINCT f.occasion) INTO affected FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion
  WHERE oc.organization=scope.organization AND (f.bank_account=c.bank_account_id OR f.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.form=f.id AND (pi.bank_account=c.bank_account_id OR pi.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id))));
  SELECT * INTO old FROM public.notification_center_source_state WHERE organization=scope.organization AND source_key=key FOR UPDATE;
  IF NOT FOUND THEN
   INSERT INTO public.notification_center_source_state(organization,source_key,state) VALUES(scope.organization,key,jsonb_build_object('problem',nc_reason IS NOT NULL,'reason',nc_reason));
   CONTINUE;
  END IF;
  ep:=old.episode;
  IF nc_reason IS NOT NULL AND (nc_reason='fio_token_invalid_or_inactive' OR (h.failures>=2 AND h.failure_since<=p_at-interval '15 minutes')) THEN
   IF NOT coalesce((old.state->>'problem')::boolean,false) THEN
    ep:=ep+1;
    ev:=public.notification_center_publish_internal(scope.organization,NULL,'bank_problem',key||':episode:'||ep,
     jsonb_build_object('reason',nc_reason,'bankConnectionId',c.id),NULL,p_at,coalesce(affected,'{}'));
    old.state:=jsonb_build_object('problem',true,'reason',nc_reason,'eventId',ev);
   ELSE
    -- New confirmed evidence refines the same episode. A transport timeout does
    -- not erase a previously confirmed token/account failure before recovery.
    IF old.state->>'reason' IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch')
     AND nc_reason IN ('transport_unavailable','bank_sync_retry_required','stale_health') THEN nc_reason:=old.state->>'reason'; END IF;
    UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',nc_reason) WHERE id=(old.state->>'eventId')::uuid;
    old.state:=old.state||jsonb_build_object('reason',nc_reason);
   END IF;
  ELSIF nc_reason IS NULL AND p_success_at IS NOT NULL AND (old.observed_at<p_success_at OR NOT coalesce((old.state->>'problem')::boolean,false)) THEN
   UPDATE public.notification_center_events SET status='recovered' WHERE id=(old.state->>'eventId')::uuid;
   old.state:=old.state||jsonb_build_object('problem',false,'reason',NULL);
  END IF;
  UPDATE public.notification_center_source_state SET state=old.state,episode=ep,observed_at=p_at WHERE organization=scope.organization AND source_key=key;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.claim_notification_center_bank_health(integer),public.complete_notification_center_bank_health(bigint,uuid,timestamptz,text,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_center_bank_health(integer),public.complete_notification_center_bank_health(bigint,uuid,timestamptz,text,timestamptz) TO service_role;
