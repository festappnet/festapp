-- A reviewed API movement retains its own ledger row and bank identity.
CREATE OR REPLACE FUNCTION public.bank_sync_api_review_row_internal(p_transaction bigint)
RETURNS eshop.bank_sync_inbox LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT i FROM eshop.bank_sync_inbox i
 WHERE i.diagnostics->>'reason'='stored_unpaired_possible_duplicate'
  AND (i.diagnostics->>'transaction_id')::bigint=p_transaction
 ORDER BY i.received_at,i.delivery_id LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_api_review_row_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_recovery_account_internal(p_account bigint,p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.can_manage_bank_account(p_account)
  AND EXISTS(SELECT FROM eshop.unit_bank_accounts l WHERE l.unit=p_unit AND l.bank_account=p_account)
  AND EXISTS(SELECT FROM eshop.bank_sync_connections c
   WHERE c.legacy_blocked_at IS NOT NULL AND public.can_manage_bank_account(c.bank_account_id)
    AND (c.bank_account_id=p_account OR EXISTS(SELECT FROM eshop.bank_sync_account_aliases a
     WHERE a.connection_id=c.id AND a.bank_account_id=p_account)));
$$;
REVOKE ALL ON FUNCTION public.bank_sync_recovery_account_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_recovery_receipt_internal(p_tx eshop.transactions)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT p_tx.ingest_source='banksync_email_confirmed' OR
  (p_tx.ingest_source='banksync_api' AND (public.bank_sync_api_review_row_internal(p_tx.id)).delivery_id IS NOT NULL);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_recovery_receipt_internal(eshop.transactions) FROM PUBLIC,anon,authenticated,service_role;

-- The same candidate set serves repair availability and the actual picker.
CREATE OR REPLACE FUNCTION public.bank_sync_pairing_candidates_internal(p_account bigint,p_recovery_only boolean)
RETURNS TABLE(movement eshop.transactions,review eshop.bank_sync_inbox)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT t,r FROM eshop.transactions t
 LEFT JOIN LATERAL public.bank_sync_api_review_row_internal(
   CASE WHEN t.ingest_source='banksync_api' THEN t.id END) r ON true
 WHERE t.bank_account_id IN (
  SELECT p_account
  UNION SELECT c.bank_account_id FROM eshop.bank_sync_connections c
  JOIN eshop.bank_sync_account_aliases a ON a.connection_id=c.id
  WHERE a.bank_account_id=p_account AND public.can_manage_bank_account(c.bank_account_id)
 )
 AND (t.bank_account_id=p_account OR public.bank_sync_accounts_match(t.id,p_account))
 AND (NOT p_recovery_only OR t.ingest_source='banksync_email_confirmed' OR r.delivery_id IS NOT NULL)
 AND t.payment_info IS NULL AND t.amount>0
 AND NOT EXISTS(SELECT FROM eshop.refund_settlements s WHERE s.transaction_id=t.id);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_pairing_candidates_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_api_review_candidates_internal(p_inbox eshop.bank_sync_inbox)
RETURNS bigint[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) FROM (
  SELECT unnest(public.bank_sync_email_duplicate_candidates_internal(
    p_inbox.connection_id,p_inbox.payload->'data',true)) AS id
  -- The current counterpart is unavailable to other API movements. It remains
  -- selectable when reconsidering this movement's decision.
  UNION SELECT (p_inbox.resolution->>'existing_transaction_id')::bigint
   WHERE p_inbox.resolution->>'action'='api_same_movement'
 ) candidates WHERE id IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_api_review_candidates_internal(eshop.bank_sync_inbox) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_api_review_view_internal(p_inbox eshop.bank_sync_inbox)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('review_token',public.bank_sync_review_token_internal(p_inbox,candidate_ids),
  'previous_action',p_inbox.resolution->>'action',
  'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(candidate_ids))
 FROM (SELECT public.bank_sync_api_review_candidates_internal(p_inbox) AS candidate_ids) c;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_api_review_view_internal(eshop.bank_sync_inbox) FROM PUBLIC,anon,authenticated,service_role;

-- Review an unpaired API movement. Keep the financial credit on its verified
-- counterpart for a same-movement decision and use the API row for a separate
-- payment. Corrections use the same command and append to the decision history.
CREATE OR REPLACE FUNCTION public.resolve_bank_sync_api_duplicate_v1(
 p_transaction_id bigint,p_payment_info_id bigint,p_review_token text,p_existing_transaction_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_tx eshop.transactions; v_inbox eshop.bank_sync_inbox; v_target record;
 v_ids bigint[]; v_review jsonb; v_result jsonb; v_counterpart eshop.transactions;
 v_paired_now boolean:=false; v_revision integer;
 v_request_hash text:=encode(extensions.digest(p_review_token,'sha256'),'hex');
BEGIN
 SELECT pi.bank_account,pi.currency_code,oc.id AS occasion_id,oc.organization,oc.unit INTO v_target
 FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
 JOIN public.occasions oc ON oc.id=o.occasion
 WHERE pi.id=p_payment_info_id AND pi.payment_method='bank';
 IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 PERFORM public.check_is_admin_for_bank_account(v_target.bank_account);
 PERFORM public.check_is_editor_order_on_occasion(v_target.occasion_id);
 IF NOT public.bank_sync_recovery_account_internal(v_target.bank_account,v_target.unit)
 THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 PERFORM public.payment_policy_fence_internal(v_target.organization);

 SELECT * INTO v_tx FROM eshop.transactions WHERE id=p_transaction_id;
 PERFORM public.check_is_admin_for_bank_account(v_tx.bank_account_id);
 v_inbox:=public.bank_sync_api_review_row_internal(v_tx.id);
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_REVIEW_NOT_FOUND'; END IF;
 -- Match ingest's connection-before-transaction lock order.
 PERFORM 1 FROM eshop.bank_sync_connections WHERE id=v_inbox.connection_id FOR UPDATE;
 SELECT * INTO v_tx FROM eshop.transactions WHERE id=p_transaction_id FOR UPDATE;
 PERFORM public.check_is_admin_for_bank_account(v_tx.bank_account_id);
 IF v_tx.ingest_source IS DISTINCT FROM 'banksync_api'
  OR upper(trim(v_tx.currency)) IS DISTINCT FROM upper(trim(v_target.currency_code))
  OR (v_tx.bank_account_id<>v_target.bank_account AND NOT public.bank_sync_accounts_match(v_tx.id,v_target.bank_account))
 THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 v_inbox:=public.bank_sync_api_review_row_internal(v_tx.id);
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_REVIEW_NOT_FOUND'; END IF;
 -- A transport retry reuses the recorded outcome. A deliberate correction
 -- supplies the current review token, which includes the last decision.
 IF v_inbox.resolution->>'review_request_sha256'=v_request_hash
  AND v_inbox.resolution->>'actor_id'=auth.uid()::text
  AND (v_inbox.resolution->>'payment_info_id')::bigint=p_payment_info_id
  AND (v_inbox.resolution->>'existing_transaction_id')::bigint IS NOT DISTINCT FROM p_existing_transaction_id THEN
  RETURN jsonb_build_object('action',v_inbox.resolution->>'action',
    'paired_now',coalesce((v_inbox.resolution->>'paired_now')::boolean,false));
 END IF;
 IF v_tx.payment_info IS NOT NULL THEN RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED'; END IF;

 v_ids:=public.bank_sync_api_review_candidates_internal(v_inbox);
 PERFORM 1 FROM eshop.transactions WHERE id=ANY(v_ids) ORDER BY id FOR UPDATE;
 IF p_review_token IS NULL OR p_review_token IS DISTINCT FROM public.bank_sync_review_token_internal(v_inbox,v_ids) THEN
  v_review:=public.bank_sync_api_review_view_internal(v_inbox);
  RETURN v_review||jsonb_build_object('action','review_changed');
 END IF;
 IF p_existing_transaction_id IS NOT NULL THEN
  SELECT * INTO v_counterpart FROM eshop.transactions t
  WHERE t.id=p_existing_transaction_id AND t.id=ANY(v_ids)
   AND t.ingest_source='banksync_email_confirmed' AND public.can_read_bank_transactions(t.bank_account_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_REVIEW_CANDIDATE_INVALID'; END IF;
  IF v_counterpart.payment_info IS NULL THEN
   PERFORM public.add_transaction_to_payment_info_ws(v_counterpart.id,p_payment_info_id);
   v_paired_now:=true;
  END IF;
 ELSE
  v_paired_now:=true;
 END IF;

 v_revision:=coalesce((v_inbox.resolution->>'revision')::integer,0)+1;
 v_result:=jsonb_build_object(
   'action',CASE WHEN p_existing_transaction_id IS NULL THEN 'api_distinct' ELSE 'api_same_movement' END,
   'actor_id',auth.uid(),'resolved_at',now(),'payment_info_id',p_payment_info_id,
   'existing_transaction_id',p_existing_transaction_id,'reviewed_transaction_ids',to_jsonb(v_ids),
   'revision',v_revision,'review_request_sha256',v_request_hash,'paired_now',v_paired_now);
 INSERT INTO eshop.bank_sync_api_review_events(instance_id,consumer_app_id,delivery_id,revision,decision)
 VALUES(v_inbox.instance_id,v_inbox.consumer_app_id,v_inbox.delivery_id,v_revision,v_result);
 UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
 WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
 IF p_existing_transaction_id IS NULL THEN
  PERFORM public.add_transaction_to_payment_info_ws(p_transaction_id,p_payment_info_id);
 END IF;
 RETURN jsonb_build_object('action',v_result->>'action','paired_now',v_paired_now);
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_bank_sync_api_duplicate_v1(bigint,bigint,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_bank_sync_api_duplicate_v1(bigint,bigint,text,bigint) TO authenticated;
