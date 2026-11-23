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

CREATE OR REPLACE FUNCTION public.bank_sync_api_review_view_internal(p_inbox eshop.bank_sync_inbox)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('review_token',public.bank_sync_review_token_internal(p_inbox,candidate_ids),
  'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(candidate_ids))
 FROM (SELECT public.bank_sync_email_duplicate_candidates_internal(
   p_inbox.connection_id,p_inbox.payload->'data',true) AS candidate_ids) c;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_api_review_view_internal(eshop.bank_sync_inbox) FROM PUBLIC,anon,authenticated,service_role;

-- A null related transaction declares a distinct payment. Selecting an
-- existing verified receipt resolves this API row without issuing a credit.
CREATE OR REPLACE FUNCTION public.resolve_bank_sync_api_duplicate_v1(
 p_transaction_id bigint,p_payment_info_id bigint,p_review_token text,p_existing_transaction_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_tx eshop.transactions; v_inbox eshop.bank_sync_inbox; v_target record;
 v_ids bigint[]; v_review jsonb; v_result jsonb;
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
 IF v_inbox.resolution IS NOT NULL THEN
  IF (v_inbox.resolution->>'payment_info_id')::bigint=p_payment_info_id
    AND (v_inbox.resolution->>'existing_transaction_id')::bigint IS NOT DISTINCT FROM p_existing_transaction_id THEN
   RETURN jsonb_build_object('action',v_inbox.resolution->>'action');
  END IF;
  RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED';
 END IF;
 IF v_tx.payment_info IS NOT NULL THEN RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED'; END IF;

 v_ids:=public.bank_sync_email_duplicate_candidates_internal(v_inbox.connection_id,v_inbox.payload->'data',true);
 PERFORM 1 FROM eshop.transactions WHERE id=ANY(v_ids) ORDER BY id FOR UPDATE;
 IF p_review_token IS NULL OR p_review_token IS DISTINCT FROM public.bank_sync_review_token_internal(v_inbox,v_ids) THEN
  v_review:=public.bank_sync_api_review_view_internal(v_inbox);
  RETURN v_review||jsonb_build_object('action','review_changed');
 END IF;
 IF p_existing_transaction_id IS NOT NULL AND NOT EXISTS(
  SELECT FROM eshop.transactions t WHERE t.id=p_existing_transaction_id AND t.id=ANY(v_ids)
   AND public.can_read_bank_transactions(t.bank_account_id)
 ) THEN RAISE EXCEPTION 'BANK_SYNC_REVIEW_CANDIDATE_INVALID'; END IF;

 v_result:=jsonb_build_object(
   'action',CASE WHEN p_existing_transaction_id IS NULL THEN 'api_distinct' ELSE 'api_same_movement' END,
   'actor_id',auth.uid(),'resolved_at',now(),'payment_info_id',p_payment_info_id,
   'existing_transaction_id',p_existing_transaction_id,'reviewed_transaction_ids',to_jsonb(v_ids));
 UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
 WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
 IF p_existing_transaction_id IS NULL THEN
  PERFORM public.add_transaction_to_payment_info_ws(p_transaction_id,p_payment_info_id);
 END IF;
 RETURN jsonb_build_object('action',v_result->>'action');
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_bank_sync_api_duplicate_v1(bigint,bigint,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_bank_sync_api_duplicate_v1(bigint,bigint,text,bigint) TO authenticated;
