-- Machine-only recovery remains available with new sales disabled or the
-- connection retired. Claiming each job uses the same lease as webhooks/pay.
CREATE OR REPLACE FUNCTION public.get_recoverable_stripe_attempts_internal(p_livemode boolean,p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_livemode IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('attemptId',x.id,'accountId',x.account_id) ORDER BY x.next_reconcile_at,x.id),'[]'::jsonb)
 INTO result FROM (
  SELECT a.id,c.account_id,a.next_reconcile_at FROM eshop.stripe_checkout_attempts a
   JOIN eshop.stripe_connections c ON c.id=a.connection_id
   WHERE a.livemode=p_livemode AND a.next_reconcile_at<=statement_timestamp()
    AND coalesce(a.lease_expires_at<=statement_timestamp(),true)
   ORDER BY a.next_reconcile_at,a.id LIMIT p_limit
 ) x;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_recoverable_stripe_attempts_internal(boolean,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_stripe_attempts_internal(boolean,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_reconciliation_internal(p_attempt uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 -- A stale worker cannot clear another worker's lease or reset its cursor.
 UPDATE eshop.stripe_checkout_attempts SET reconcile_failures=least(reconcile_failures+1,1000),
  next_reconcile_at=clock_timestamp()+make_interval(secs=>least(3600,30*power(2,least(reconcile_failures,7)))::integer),
  lease_token=NULL,lease_expires_at=NULL WHERE id=p_attempt AND lease_token=p_lease AND p_lease IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_reconciliation_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_reconciliation_internal(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.checkpoint_stripe_session_lookup_internal(p_attempt uuid,p_lease uuid,p_cursor text,p_found text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT order_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt));
 PERFORM 1 FROM eshop.orders WHERE id=(SELECT order_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt) FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=(SELECT payment_info_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt) FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR p_lease IS DISTINCT FROM a.lease_token OR a.lease_expires_at<=clock_timestamp()
  OR a.session_id IS NOT NULL OR p_cursor IS NULL OR p_cursor !~ '^cs_[A-Za-z0-9_]+$' OR p_cursor=a.session_lookup_cursor
  OR (p_found IS NOT NULL AND p_found !~ '^cs_[A-Za-z0-9_]+$')
  OR (a.session_lookup_found IS NOT NULL AND a.session_lookup_found IS DISTINCT FROM p_found) THEN RAISE EXCEPTION 'STRIPE_SESSION_LOOKUP_INVALID'; END IF;
 IF a.reservation_expires_at<=clock_timestamp() THEN
  PERFORM public.defer_stripe_recovery_internal(p_attempt,p_lease,10);
 END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_lookup_cursor=p_cursor,session_lookup_found=p_found,
  lease_token=NULL,lease_expires_at=NULL,reconcile_failures=0,next_reconcile_at=clock_timestamp()+interval '10 seconds' WHERE id=a.id;
END $$;
REVOKE ALL ON FUNCTION public.checkpoint_stripe_session_lookup_internal(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.checkpoint_stripe_session_lookup_internal(uuid,uuid,text,text) TO service_role;

-- Retain economic facts and capability hashes; erase only expired bearer sources.
-- Historical account-scoped reads deliberately do not depend on these secrets.
CREATE OR REPLACE FUNCTION public.purge_expired_stripe_sources_internal(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE removed integer;
BEGIN
 PERFORM public.require_service_role();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 WITH expired AS (
  SELECT token_hash FROM eshop.stripe_payment_link_sources WHERE expires_at<=clock_timestamp()
   ORDER BY expires_at,token_hash LIMIT p_limit FOR UPDATE SKIP LOCKED
 ) DELETE FROM eshop.stripe_payment_link_sources s USING expired e WHERE s.token_hash=e.token_hash;
 GET DIAGNOSTICS removed=ROW_COUNT;
 RETURN removed;
END $$;
REVOKE ALL ON FUNCTION public.purge_expired_stripe_sources_internal(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_stripe_sources_internal(integer) TO service_role;

-- Uncertainty releases only elapsed inventory through the common domain owner.
-- No payment fact, absent checkout or successful remote expiry is manufactured.
CREATE OR REPLACE FUNCTION public.defer_stripe_recovery_internal(p_attempt uuid,p_lease uuid,p_retry_seconds integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; o eshop.orders; before_users uuid[]; before_projection jsonb; result jsonb;
 command uuid:=extensions.gen_random_uuid(); claim jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_retry_seconds IS NULL OR p_retry_seconds NOT BETWEEN 1 AND 3600 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;
 claim:=public.begin_anonymous_client_mutation_v1(command,'inventory.order.stripe_sync',o.occasion,command,
  encode(extensions.digest(p_attempt::text||p_lease::text,'sha256'),'hex'));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at IS NULL OR a.lease_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'STRIPE_SYNC_LEASE_INVALID'; END IF;

 SELECT coalesce(array_agg("user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users WHERE occasion=o.occasion;
 before_projection:=public.stripe_order_payment_projection_internal(o.id);
 result:=public.apply_provider_payment_effects_internal('stripe',a.id,'unresolved:'||p_lease::text,before_projection,false,true);
 UPDATE eshop.stripe_checkout_attempts SET lease_token=NULL,lease_expires_at=NULL,
  reconcile_failures=least(reconcile_failures+1,1000),next_reconcile_at=clock_timestamp()+make_interval(secs=>greatest(p_retry_seconds,least(3600,30*power(2,least(reconcile_failures,7)))::integer)) WHERE id=a.id;
 PERFORM public.complete_profile_inventory_membership_mutation_v1(command,o.occasion,'inventory.order.stripe_sync',
  CASE WHEN result->'changed'='true'::jsonb THEN jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','safeLabel','Payment recovery','changedFields',jsonb_build_array('payment','state','tickets','admission','allocations'))) ELSE '[]'::jsonb END,
  before_users,jsonb_build_object('committed',true,'payment',result->'payment'),'service');
 PERFORM public.notification_center_order_state_internal(o.id);
 PERFORM public.notification_center_order_capacity_internal(o.id);
END $$;
REVOKE ALL ON FUNCTION public.defer_stripe_recovery_internal(uuid,uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.defer_stripe_recovery_internal(uuid,uuid,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.request_payment_reconciliation(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF p_project_url IS NULL OR p_project_url !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$' THEN RAISE EXCEPTION 'PAYMENT_RECOVERY_ORIGIN_INVALID'; END IF;
 PERFORM net.http_post(url:=p_project_url||'/functions/v1/payment-reconcile',
  body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=90000);
END $$;
REVOKE ALL ON FUNCTION public.request_payment_reconciliation(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.request_payment_reconciliation(text) TO service_role;
-- Retained installed SQL callers use the same scheduler work, never a second job.
CREATE OR REPLACE FUNCTION public.request_stripe_reconciliation(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.request_payment_reconciliation(p_project_url);
END $$;

REVOKE ALL ON FUNCTION public.request_stripe_reconciliation(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.request_stripe_reconciliation(text) TO service_role;
