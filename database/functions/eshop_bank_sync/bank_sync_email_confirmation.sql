CREATE OR REPLACE FUNCTION public.bank_sync_counter_account_internal(p_account text,p_code text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN nullif(a,'') IS NULL THEN NULL
  WHEN a LIKE '%/%' OR a ~ '^[A-Z]{2}' OR nullif(c,'') IS NULL THEN a ELSE a||'/'||c END
 FROM (SELECT upper(regexp_replace(coalesce(p_account,''),'[[:space:]]','','g')) a,
   regexp_replace(coalesce(p_code,''),'[[:space:]]','','g') c) x;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_counter_account_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;

-- A match is a review hint. These fields can be identical for separate
-- transfers, and email can omit references or counter-account details.
CREATE OR REPLACE FUNCTION public.bank_sync_email_possible_duplicate_internal(p_tx eshop.transactions,p_data jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH stored_signals AS MATERIALIZED (
   SELECT * FROM public.bank_transaction_signals_internal(p_tx.vs,p_tx.payer_reference,
     p_tx.message_for_recipient,p_tx.user_identification,p_tx.comment)
 ), incoming_signals AS MATERIALIZED (
   SELECT * FROM public.bank_transaction_signals_internal(p_data->>'raw_vs',p_data->>'payer_reference',
     p_data->>'message',p_data->>'user_identification',p_data->>'comment')
 ), accounts AS (
   SELECT public.bank_sync_counter_account_internal(p_tx.counter_account,p_tx.bank_code) AS stored,
     public.bank_sync_counter_account_internal(p_data->>'counter_account',p_data->>'bank_code') AS incoming
 )
 SELECT p_tx.amount IS NOT DISTINCT FROM (p_data->>'amount_cents')::numeric/100
  AND upper(trim(p_tx.currency)) IS NOT DISTINCT FROM upper(trim(p_data->>'currency'))
  AND public.bank_sync_fact_dates_match_internal(p_tx,p_data,1)
  AND (EXISTS(SELECT FROM stored_signals JOIN incoming_signals USING(kind,value))
    OR ((NOT EXISTS(SELECT FROM stored_signals) OR NOT EXISTS(SELECT FROM incoming_signals))
      AND (stored=incoming OR stored IS NULL OR incoming IS NULL)))
 FROM accounts;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_possible_duplicate_internal(eshop.transactions,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- The connection lock held by the caller serializes both sides of ingestion.
CREATE OR REPLACE FUNCTION public.bank_sync_email_duplicate_candidates_internal(p_connection bigint,p_data jsonb,p_confirmed_only boolean)
RETURNS bigint[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH accounts AS (
  SELECT bank_account_id FROM eshop.bank_sync_connections WHERE id=p_connection
  UNION SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection
 ), prefiltered AS MATERIALIZED (
  SELECT t AS fact FROM accounts a JOIN eshop.transactions t ON t.bank_account_id=a.bank_account_id
  WHERE t.amount=(p_data->>'amount_cents')::numeric/100
   AND t.date BETWEEN ((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')-interval '2 days'
                  AND ((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')+interval '2 days'
   AND upper(trim(t.currency))=upper(trim(p_data->>'currency'))
   AND CASE WHEN p_confirmed_only THEN t.ingest_source='banksync_email_confirmed'
      AND NOT EXISTS(SELECT FROM eshop.bank_sync_inbox r
       WHERE r.resolution->>'action'='api_same_movement'
         AND (r.resolution->>'existing_transaction_id')::bigint=t.id)
     ELSE t.ingest_source IN ('banksync_email_confirmed','banksync_api','fio_api','legacy_api','legacy') END
 )
 SELECT coalesce(array_agg((fact).id::bigint ORDER BY (fact).id),'{}'::bigint[]) FROM prefiltered
 WHERE public.bank_sync_email_possible_duplicate_internal(fact,p_data);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_duplicate_candidates_internal(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Compare across aliases internally. Project only the details the actor can
-- read on each ledger account. A single redacted hint keeps the review visible.
CREATE OR REPLACE FUNCTION public.bank_sync_email_possible_duplicates_view_internal(p_ids bigint[])
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH candidates AS MATERIALIZED (
   SELECT t.*,public.can_read_bank_transactions(t.bank_account_id) AS can_read
   FROM eshop.transactions t WHERE t.id=ANY(p_ids)
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('transaction_id',t.id,'ingest_source',t.ingest_source,
  'transaction_paired',t.payment_info IS NOT NULL,
  'order_symbol',CASE WHEN o.occasion IS NOT NULL AND public.can_read_orders(o.occasion) THEN o.order_symbol END,
  'order_number',CASE WHEN o.occasion IS NOT NULL AND public.can_read_orders(o.occasion) THEN o.order_sequence END,
  'facts',jsonb_build_object('amount_cents',round(t.amount*100)::bigint,'currency',trim(t.currency),
    'date',t.date AT TIME ZONE 'UTC','raw_vs',nullif(trim(t.vs),''),'counter_account',t.counter_account,
    'bank_code',t.bank_code,'payer_reference',t.payer_reference)) ORDER BY t.id),'[]'::jsonb)
  || CASE WHEN EXISTS(SELECT FROM candidates WHERE NOT can_read)
    THEN '[{"restricted":true}]'::jsonb ELSE '[]'::jsonb END
 FROM candidates t LEFT JOIN eshop.orders o ON o.payment_info=t.payment_info WHERE t.can_read;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_possible_duplicates_view_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Bind decisions to the current candidates without exposing restricted IDs.
CREATE OR REPLACE FUNCTION public.bank_sync_review_token_internal(p_inbox eshop.bank_sync_inbox,p_ids bigint[])
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT encode(extensions.hmac(convert_to(jsonb_build_array(auth.uid(),p_inbox.connection_id,
   p_inbox.delivery_id,p_inbox.body_sha256,p_ids,
   (SELECT jsonb_agg(jsonb_build_array(t.id,t.payment_info) ORDER BY t.id)
    FROM eshop.transactions t WHERE t.id=ANY(p_ids)))::text,'UTF8'),secret,'sha256'),'hex')
 FROM eshop.bank_sync_review_signing_key WHERE singleton;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_review_token_internal(eshop.bank_sync_inbox,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- A BankSync observation can have more than one transport delivery.
CREATE OR REPLACE FUNCTION public.bank_sync_email_source_row_internal(p_connection bigint,p_remote_id text)
RETURNS eshop.bank_sync_inbox LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT i FROM eshop.bank_sync_inbox i
 WHERE i.connection_id=p_connection AND i.remote_transaction_id=p_remote_id
  AND i.payload->'data'->>'source' ~ '(^|_)email$'
  AND i.outcome IN ('quarantined_identity','quarantined_conflict')
  AND (i.payload->'data'->>'amount_cents')::numeric>0
 ORDER BY (i.resolution IS NULL),i.received_at,i.delivery_id LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_source_row_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- Account authorization is completed before callers read any inbox facts,
-- digests or resolutions. In particular an alias alone grants no source access.
CREATE OR REPLACE FUNCTION public.bank_sync_email_authorized_connection_internal(p_bank_account bigint)
RETURNS eshop.bank_sync_connections LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections;
BEGIN
 PERFORM public.check_is_admin_for_bank_account(p_bank_account);
 SELECT bc.* INTO v_connection FROM eshop.bank_sync_connections bc WHERE bc.bank_account_id=p_bank_account
  OR EXISTS(SELECT FROM eshop.bank_sync_account_aliases a WHERE a.bank_account_id=p_bank_account AND a.connection_id=bc.id);
 IF v_connection.id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_NOT_FOUND'; END IF;
 PERFORM public.check_is_admin_for_bank_account(v_connection.bank_account_id);
 RETURN v_connection;
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_authorized_connection_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One payable/editable target set for suggestions, manual lookup and mutation.
-- Paid/sent deposit orders remain eligible while a balance is outstanding.
CREATE OR REPLACE FUNCTION public.bank_sync_email_payable_targets_for_ids_internal(p_account bigint,p_currency text,p_ids bigint[])
RETURNS TABLE(payment_info_id bigint,order_id bigint,occasion_id bigint,candidate jsonb)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH eligible AS MATERIALIZED (
  SELECT pi.id,pi.amount,pi.currency_code,o.id AS order_id,o.occasion,o.order_symbol,o.order_sequence,o.state,o.data
  FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id JOIN public.occasions oc ON oc.id=o.occasion
  WHERE pi.id=ANY(p_ids) AND pi.bank_account=p_account AND pi.payment_method='bank'
   AND upper(trim(pi.currency_code))=upper(trim(p_currency)) AND pi.amount>0
   AND (o.state IN ('created','ordered','expired')
     OR (o.state IN ('paid','sent') AND pi.deposit_amount>0))
   AND NOT public.is_demo_occasion(o.occasion) AND NOT public.is_demo_bank_account(p_account)
   AND public.can_write_orders(o.occasion)
   AND EXISTS(SELECT FROM eshop.unit_bank_accounts a WHERE a.unit=oc.unit AND a.bank_account=p_account)
 ), totals AS MATERIALIZED (
  SELECT * FROM public.payment_financial_totals_bulk_internal((SELECT coalesce(array_agg(id::bigint),'{}'::bigint[]) FROM eligible))
 )
 SELECT e.id::bigint,e.order_id::bigint,e.occasion::bigint,jsonb_build_object(
  'payment_info_id',e.id,'order_id',e.order_id,'order_symbol',e.order_symbol,'order_number',e.order_sequence,
  'state',e.state,'customer_name',concat_ws(' ',coalesce(e.data->>'name',e.data->>'first_name'),coalesce(e.data->>'surname',e.data->>'last_name')),
  'customer_email',e.data->>'email','remaining_due',greatest(e.amount-t.available,0),'currency',upper(trim(e.currency_code)))
 FROM eligible e JOIN totals t ON t.payment_id=e.id WHERE e.amount>t.available;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_payable_targets_for_ids_internal(bigint,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_lookup_signals_internal(p_query text)
RETURNS TABLE(kind text,value text) LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT 'vs',substring(trim(p_query) FROM '(?i)^(?:(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*)?([0-9]{1,10})$')::bigint::text
 WHERE trim(coalesce(p_query,'')) ~ '(?i)^(?:(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*)?[0-9]{1,10}$'
 UNION SELECT 'rf',public.normalize_creditor_reference(p_query)
 WHERE p_query IS NOT NULL AND public.is_valid_creditor_reference(p_query);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_lookup_signals_internal(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_email_candidates_internal(p_account bigint,p_facts jsonb,p_query text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH signals AS MATERIALIZED (
  SELECT * FROM public.bank_transaction_signals_internal(p_facts->>'raw_vs',p_facts->>'payer_reference',
    p_facts->>'message',p_facts->>'user_identification',p_facts->>'comment') WHERE p_query IS NULL
  UNION SELECT * FROM public.bank_sync_email_lookup_signals_internal(p_query) WHERE p_query IS NOT NULL
 ), matched AS MATERIALIZED (
  SELECT pi.id FROM signals s JOIN eshop.payment_info pi ON pi.variable_symbol=CASE WHEN s.kind='vs' THEN s.value::bigint END
   WHERE s.kind='vs' AND pi.bank_account=p_account AND pi.payment_method='bank'
    AND upper(trim(pi.currency_code))=upper(trim(p_facts->>'currency'))
  UNION SELECT pi.id FROM signals s JOIN eshop.payment_info pi ON pi.creditor_reference=s.value
   WHERE s.kind='rf' AND pi.bank_account=p_account AND pi.payment_method='bank'
    AND upper(trim(pi.currency_code))=upper(trim(p_facts->>'currency'))
  UNION SELECT pi.id FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
   WHERE p_query IS NOT NULL
    AND (o.order_symbol=trim(p_query) OR o.order_symbol=upper(trim(p_query))
      OR (trim(p_query) ~ '^[0-9]{1,18}$' AND o.order_sequence=trim(p_query)::bigint))
    AND pi.bank_account=p_account AND pi.payment_method='bank'
    AND upper(trim(pi.currency_code))=upper(trim(p_facts->>'currency'))
 )
 SELECT coalesce(jsonb_agg(target.candidate||jsonb_build_object('amount_matches',
  (target.candidate->>'remaining_due')::numeric=(p_facts->>'amount_cents')::numeric/100) ORDER BY target.order_id),'[]')
 FROM public.bank_sync_email_payable_targets_for_ids_internal(p_account,p_facts->>'currency',
   (SELECT coalesce(array_agg(id::bigint),'{}'::bigint[]) FROM matched)) target;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_email_candidates_internal(bigint,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.find_bank_sync_email_targets_v1(p_bank_account_id bigint,p_facts jsonb,p_query text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 IF p_query IS NULL OR length(trim(p_query)) NOT BETWEEN 1 AND 100 OR octet_length(p_facts::text)>65536 THEN
  RAISE EXCEPTION 'BANK_SYNC_LOOKUP_INVALID'; END IF;
 RETURN public.bank_sync_email_candidates_internal(p_bank_account_id,p_facts,p_query);
END;
$$;
REVOKE ALL ON FUNCTION public.find_bank_sync_email_targets_v1(bigint,jsonb,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.find_bank_sync_email_targets_v1(bigint,jsonb,text) TO authenticated;

-- Keyset paging is stable when earlier rows are resolved by another admin.
CREATE OR REPLACE FUNCTION public.get_bank_sync_email_queue_page_v1(p_bank_account_id bigint,p_limit integer DEFAULT 50,p_cursor jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_result jsonb; v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
BEGIN
 v_connection:=public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 SELECT coalesce(jsonb_agg(item ORDER BY received_at,delivery_id),'[]') INTO v_result FROM (
  SELECT i.received_at,i.delivery_id,jsonb_build_object('delivery_id',i.delivery_id,'body_sha256',i.body_sha256,
   'facts',i.payload->'data','received_at',i.received_at,'confirmable',true,
   'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(d.ids),
   'duplicate_review_token',CASE WHEN cardinality(d.ids)>0 THEN public.bank_sync_review_token_internal(i,d.ids) END,
   'candidates',public.bank_sync_email_candidates_internal(p_bank_account_id,i.payload->'data')) AS item
  FROM eshop.bank_sync_inbox i
  CROSS JOIN LATERAL (SELECT public.bank_sync_email_duplicate_candidates_internal(
    v_connection.id,i.payload->'data',false) AS ids) d
  WHERE i.connection_id=v_connection.id
   AND (i.payload->'data'->>'source' ~ '(^|_)email$')
   AND i.outcome IN ('quarantined_identity','quarantined_conflict') AND i.resolution IS NULL
   AND (i.payload->'data'->>'amount_cents')::numeric>0
   AND i.delivery_id=(public.bank_sync_email_source_row_internal(i.connection_id,i.remote_transaction_id)).delivery_id
   AND (p_cursor IS NULL OR (i.received_at,i.delivery_id)>
     ((p_cursor->>'received_at')::timestamptz,p_cursor->>'delivery_id'))
  ORDER BY i.received_at,i.delivery_id LIMIT v_limit+1
 ) q;
 RETURN jsonb_build_object('items',(SELECT coalesce(jsonb_agg(value ORDER BY ordinality),'[]')
   FROM jsonb_array_elements(v_result) WITH ORDINALITY WHERE ordinality<=v_limit),
  'next_cursor',CASE WHEN jsonb_array_length(v_result)>v_limit THEN jsonb_build_object(
    'received_at',v_result->(v_limit-1)->'received_at','delivery_id',v_result->(v_limit-1)->'delivery_id') END);
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_email_queue_page_v1(bigint,integer,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_email_queue_page_v1(bigint,integer,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_bank_sync_email_observation(
 p_bank_account_id bigint,p_delivery_id text,p_payment_info_id bigint,
 p_expected_body_sha256 text,p_checked_internet_banking boolean,p_not_duplicate boolean DEFAULT false,
 p_duplicate_review_token text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 v_connection eshop.bank_sync_connections; v_inbox eshop.bank_sync_inbox; v_payment eshop.payment_info;
 v_source eshop.bank_sync_inbox; v_review_token text;
 v_data jsonb; v_transaction_id bigint; v_result jsonb; v_organization bigint; v_unit bigint; v_occasion bigint; v_order bigint; v_ids bigint[];
BEGIN
 v_connection:=public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 -- Order authorization also precedes inbox access, digest tests and replay.
 SELECT oc.organization,oc.unit,oc.id,o.id INTO v_organization,v_unit,v_occasion,v_order FROM eshop.orders o
 JOIN public.occasions oc ON oc.id=o.occasion WHERE o.payment_info=p_payment_info_id;
 IF v_occasion IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 PERFORM public.check_is_editor_order_on_occasion(v_occasion);
 IF NOT EXISTS(SELECT FROM eshop.payment_info WHERE id=p_payment_info_id AND bank_account=p_bank_account_id) THEN
  RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH';
 END IF;
 IF p_checked_internet_banking IS DISTINCT FROM true THEN RAISE EXCEPTION 'BANK_SYNC_ATTESTATION_REQUIRED'; END IF;
 -- Recovery of an existing bank receipt is independent of new-sales policy.
 PERFORM public.payment_policy_fence_internal(v_organization);
 PERFORM pg_advisory_xact_lock(hashtextextended(v_connection.instance_id||':'||v_connection.consumer_app_id||':'||p_delivery_id,0));
 SELECT * INTO v_connection FROM eshop.bank_sync_connections WHERE id=v_connection.id FOR UPDATE;
 PERFORM public.check_is_admin_for_bank_account(v_connection.bank_account_id);
 SELECT * INTO v_inbox FROM eshop.bank_sync_inbox WHERE instance_id=v_connection.instance_id
  AND consumer_app_id=v_connection.consumer_app_id AND delivery_id=p_delivery_id AND connection_id=v_connection.id FOR UPDATE;
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_NOT_FOUND'; END IF;
 IF v_inbox.body_sha256 IS DISTINCT FROM p_expected_body_sha256 THEN RAISE EXCEPTION 'BANK_SYNC_DELIVERY_CONFLICT'; END IF;
 IF (v_inbox.payload->'data'->>'source' ~ '(^|_)email$') IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 v_source:=public.bank_sync_email_source_row_internal(v_inbox.connection_id,v_inbox.remote_transaction_id);
 IF v_source.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 IF v_source.payload->'data' IS DISTINCT FROM v_inbox.payload->'data' THEN
  RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_CONFLICT';
 END IF;
 v_inbox:=v_source;
 IF v_inbox.resolution IS NOT NULL THEN
  IF v_inbox.resolution->>'action'='confirmed' AND (v_inbox.resolution->>'payment_info_id')::bigint=p_payment_info_id THEN
   RETURN (v_inbox.resolution-'possible_duplicate_transaction_ids')||jsonb_build_object('transaction_paired',coalesce((SELECT t.payment_info IS NOT NULL
     FROM eshop.transactions t WHERE t.id=(v_inbox.resolution->>'transaction_id')::bigint),false));
  END IF;
  RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED';
 END IF;
 v_data:=v_inbox.payload->'data';
 IF v_inbox.outcome IS NULL OR v_inbox.outcome NOT IN ('quarantined_identity','quarantined_conflict')
  OR (v_data->>'source' ~ '(^|_)email$') IS DISTINCT FROM true
  OR ((v_data->>'amount_cents')::numeric>0) IS DISTINCT FROM true OR v_connection.legacy_blocked_at IS NULL THEN
  RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 SELECT * INTO v_payment FROM eshop.payment_info WHERE id=p_payment_info_id;
 IF v_payment.bank_account IS DISTINCT FROM p_bank_account_id OR v_payment.payment_method IS DISTINCT FROM 'bank'
   OR upper(trim(v_payment.currency_code)) IS DISTINCT FROM upper(trim(v_data->>'currency')) THEN
  RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 v_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,false);
 IF cardinality(v_ids)>0 OR p_not_duplicate IS TRUE THEN
  PERFORM 1 FROM eshop.transactions WHERE id=ANY(v_ids) ORDER BY id FOR UPDATE;
  v_review_token:=public.bank_sync_review_token_internal(v_inbox,v_ids);
  IF p_not_duplicate IS DISTINCT FROM true OR p_duplicate_review_token IS DISTINCT FROM v_review_token THEN
   RETURN jsonb_build_object('action','possible_duplicate','transaction_paired',false,
     'duplicate_review_token',v_review_token,
     'possible_duplicates',public.bank_sync_email_possible_duplicates_view_internal(v_ids));
  END IF;
 END IF;
 IF NOT EXISTS(SELECT FROM public.bank_sync_email_payable_targets_for_ids_internal(p_bank_account_id,v_data->>'currency',ARRAY[p_payment_info_id])
   WHERE payment_info_id=p_payment_info_id AND occasion_id=v_occasion) THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,ks,ss,payer_reference,
  message_for_recipient,counter_account,counter_account_name,bank_code,bank_name,user_identification,comment,ingest_source)
 VALUES(v_connection.bank_account_id,(v_data->>'amount_cents')::numeric/100,upper(trim(v_data->>'currency')),
  (v_data->>'date')::timestamptz AT TIME ZONE 'UTC',nullif(v_data->>'raw_vs',''),v_data->>'ks',v_data->>'ss',
  v_data->>'payer_reference',v_data->>'message',v_data->>'counter_account',v_data->>'sender_name',v_data->>'bank_code',v_data->>'bank_name',v_data->>'user_identification',v_data->>'comment',
  'banksync_email_confirmed') RETURNING id INTO v_transaction_id;
 -- Acquire the same order/payment locks as pairing, then validate eligibility
 -- again. A concurrent confirmation cannot turn a paid order into an overpayment.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[v_order]);
 PERFORM 1 FROM eshop.payment_info WHERE id=p_payment_info_id FOR UPDATE;
 IF NOT EXISTS(SELECT FROM public.bank_sync_email_payable_targets_for_ids_internal(p_bank_account_id,v_data->>'currency',ARRAY[p_payment_info_id])
   WHERE payment_info_id=p_payment_info_id AND occasion_id=v_occasion) THEN RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 v_result:=jsonb_build_object('action','confirmed','actor_id',auth.uid(),'confirmed_at',now(),
  'payment_info_id',p_payment_info_id,'transaction_id',v_transaction_id,'facts',v_data,'checked_internet_banking',true,
  'not_duplicate',p_not_duplicate IS TRUE,'possible_duplicate_transaction_ids',coalesce(to_jsonb(v_ids),'[]'),
  'transaction_paired',true);
 UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
 WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
 PERFORM public.apply_transaction_pairing(v_transaction_id,p_payment_info_id,'email_admin_confirmation','user',
  jsonb_build_object('delivery_id',p_delivery_id,'checked_internet_banking',true,'not_duplicate',p_not_duplicate IS TRUE));
 -- Pairing locked the stored order and payment. Recheck scope and permissions;
 -- payable state was intentionally consumed by the successful paid transition.
 PERFORM public.check_is_editor_order_on_occasion(v_occasion);
 IF NOT EXISTS(SELECT FROM eshop.payment_info target_payment JOIN eshop.orders o ON o.payment_info=target_payment.id
   JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.unit_bank_accounts a ON a.unit=oc.unit AND a.bank_account=target_payment.bank_account
   WHERE target_payment.id=p_payment_info_id AND target_payment.bank_account=p_bank_account_id AND target_payment.payment_method='bank'
    AND upper(trim(target_payment.currency_code))=upper(trim(v_data->>'currency')) AND oc.id=v_occasion AND oc.unit=v_unit AND oc.organization=v_organization) THEN
  RAISE EXCEPTION 'BANK_SYNC_TARGET_MISMATCH'; END IF;
 RETURN v_result-'possible_duplicate_transaction_ids';
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_bank_sync_email_observation(bigint,text,bigint,text,boolean,boolean,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_bank_sync_email_observation(bigint,text,bigint,text,boolean,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.dismiss_bank_sync_email_observation(p_bank_account_id bigint,p_delivery_id text,p_expected_body_sha256 text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_inbox eshop.bank_sync_inbox; v_source eshop.bank_sync_inbox; v_result jsonb;
BEGIN
 v_connection:=public.bank_sync_email_authorized_connection_internal(p_bank_account_id);
 IF length(trim(p_reason)) NOT BETWEEN 1 AND 240 OR p_reason IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_DISMISS_REASON_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(v_connection.instance_id||':'||v_connection.consumer_app_id||':'||p_delivery_id,0));
 SELECT * INTO v_connection FROM eshop.bank_sync_connections WHERE id=v_connection.id FOR UPDATE;
 PERFORM public.check_is_admin_for_bank_account(v_connection.bank_account_id);
 SELECT * INTO v_inbox FROM eshop.bank_sync_inbox WHERE instance_id=v_connection.instance_id AND consumer_app_id=v_connection.consumer_app_id
  AND connection_id=v_connection.id AND delivery_id=p_delivery_id FOR UPDATE;
 IF v_inbox.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_NOT_FOUND'; END IF;
 IF v_inbox.body_sha256 IS DISTINCT FROM p_expected_body_sha256 THEN RAISE EXCEPTION 'BANK_SYNC_DELIVERY_CONFLICT'; END IF;
 IF (v_inbox.payload->'data'->>'source' ~ '(^|_)email$') IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 -- Dismiss the same source observation for all of its transport deliveries.
 v_source:=public.bank_sync_email_source_row_internal(v_inbox.connection_id,v_inbox.remote_transaction_id);
 IF v_source.delivery_id IS NULL THEN RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 IF v_source.payload->'data' IS DISTINCT FROM v_inbox.payload->'data' THEN
  RAISE EXCEPTION 'BANK_SYNC_OBSERVATION_CONFLICT';
 END IF;
 v_inbox:=v_source;
 IF v_inbox.resolution IS NOT NULL THEN
  IF v_inbox.resolution->>'action'='dismissed' AND v_inbox.resolution->>'reason'=trim(p_reason) THEN RETURN v_inbox.resolution; END IF;
  RAISE EXCEPTION 'BANK_SYNC_ALREADY_RESOLVED';
 END IF;
 IF (v_inbox.payload->'data'->>'source' ~ '(^|_)email$') IS DISTINCT FROM true OR v_inbox.outcome IS NULL OR v_inbox.outcome NOT IN ('quarantined_identity','quarantined_conflict') THEN RAISE EXCEPTION 'BANK_SYNC_NOT_CONFIRMABLE'; END IF;
 v_result:=jsonb_build_object('action','dismissed','actor_id',auth.uid(),'resolved_at',now(),'reason',trim(p_reason),'facts',v_inbox.payload->'data');
 UPDATE eshop.bank_sync_inbox SET resolution=v_result,resolved_at=now()
  WHERE instance_id=v_inbox.instance_id AND consumer_app_id=v_inbox.consumer_app_id AND delivery_id=v_inbox.delivery_id;
 RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.dismiss_bank_sync_email_observation(bigint,text,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.dismiss_bank_sync_email_observation(bigint,text,text,text) TO authenticated;
