-- Additive Barion sandbox connector. No credentials, sales activation or jobs.

SET LOCAL ROLE postgres;

-- SOURCE: eshop_barion/schema.sql
-- Sandbox-only connector. Credentials live outside SQL. No sales activation.
CREATE TABLE eshop.barion_connections (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 unit_id bigint NOT NULL REFERENCES public.units(id),
 account_id text NOT NULL UNIQUE CHECK(account_id ~ '^[a-f0-9]{32}$'),
 enabled boolean NOT NULL DEFAULT false,
 sandbox_form_ids bigint[] NOT NULL DEFAULT '{}',
 business_name text NOT NULL,
 UNIQUE(id,organization_id,unit_id)
);
ALTER TABLE eshop.payment_info ADD COLUMN barion_connection_id uuid REFERENCES eshop.barion_connections(id);
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_barion_identity CHECK((payment_method='barion')=(barion_connection_id IS NOT NULL));
CREATE TABLE eshop.barion_attempts (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 order_id bigint NOT NULL UNIQUE REFERENCES eshop.orders(id),
 payment_info_id bigint NOT NULL UNIQUE REFERENCES eshop.payment_info(id),
 organization_id bigint NOT NULL, unit_id bigint NOT NULL, connection_id uuid NOT NULL,
 amount_minor bigint NOT NULL CHECK(amount_minor BETWEEN 1 AND 1000000000),
 currency text NOT NULL CHECK(currency IN ('CZK','EUR','USD')),
 state text NOT NULL DEFAULT 'preparing' CHECK(state IN ('preparing','open','uncertain','paid','expired','action_required')),
 created_at timestamptz NOT NULL DEFAULT date_trunc('second',clock_timestamp()),
 reservation_expires_at timestamptz NOT NULL,
 return_base_url text NOT NULL, locale text NOT NULL DEFAULT 'en',
 remote_id text UNIQUE CHECK(remote_id ~ '^[a-f0-9]{32}$'), checkout_url text,
 dispatched_at timestamptz, lease_token uuid, lease_expires_at timestamptz,
 next_reconcile_at timestamptz NOT NULL DEFAULT now(), last_synced_at timestamptz,
 reconcile_failures integer NOT NULL DEFAULT 0 CHECK(reconcile_failures>=0),
 financial_hold boolean NOT NULL DEFAULT false,
 decisions jsonb NOT NULL DEFAULT '[]',
 FOREIGN KEY(connection_id,organization_id,unit_id) REFERENCES eshop.barion_connections(id,organization_id,unit_id),
 UNIQUE(id,connection_id,currency), UNIQUE(id,order_id),
 CHECK(reservation_expires_at>created_at), CHECK((lease_token IS NULL)=(lease_expires_at IS NULL))
);
CREATE TABLE eshop.barion_movements (
 attempt_id uuid NOT NULL, connection_id uuid NOT NULL, provider_id text NOT NULL CHECK(provider_id ~ '^[a-f0-9]{32}$'),
 kind text NOT NULL CHECK(kind IN ('payment','refund')),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),currency text NOT NULL,occurred_at timestamptz NOT NULL,
 FOREIGN KEY(attempt_id,connection_id,currency) REFERENCES eshop.barion_attempts(id,connection_id,currency),
 PRIMARY KEY(connection_id,provider_id), UNIQUE(attempt_id,provider_id)
);
CREATE UNIQUE INDEX barion_one_original ON eshop.barion_movements(attempt_id) WHERE kind='payment';
CREATE TABLE eshop.barion_capabilities (
 token_hash text PRIMARY KEY CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 attempt_id uuid NOT NULL REFERENCES eshop.barion_attempts(id),
 scope text NOT NULL CHECK(scope IN ('order_pay','return_read','handoff')),
 expires_at timestamptz NOT NULL, consumed_at timestamptz
);
CREATE TABLE eshop.barion_sources (
 attempt_id uuid PRIMARY KEY REFERENCES eshop.barion_attempts(id),command_id uuid NOT NULL UNIQUE,
 token_hash text NOT NULL UNIQUE REFERENCES eshop.barion_capabilities(token_hash),
 sealed jsonb NOT NULL, content_hash text NOT NULL CHECK(content_hash ~ '^[a-f0-9]{64}$')
);
CREATE TABLE eshop.barion_observations (
 attempt_id uuid NOT NULL REFERENCES eshop.barion_attempts(id),
 digest text NOT NULL CHECK(digest ~ '^[a-f0-9]{64}$'),facts jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), PRIMARY KEY(attempt_id,digest)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['barion_connections','barion_attempts','barion_movements','barion_capabilities','barion_sources','barion_observations'] LOOP
  EXECUTE format('ALTER TABLE eshop.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON eshop.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
END $$;

-- SOURCE: eshop_barion/provider.sql
-- Protocol persistence and projections only. Order/ticket/email decisions are
-- exclusively owned by apply_provider_payment_effects_internal.
CREATE OR REPLACE FUNCTION public.barion_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.barion_attempts; c eshop.barion_connections; o eshop.orders; pi eshop.payment_info;
 result jsonb; input jsonb; binding uuid; amount numeric; stamp timestamptz:=date_trunc('second',clock_timestamp());
 received bigint; refunded bigint; status text; admission text; expiry timestamptz;
BEGIN
 IF p_operation IN ('unit_feature','unit_fields') THEN RETURN CASE WHEN p_operation='unit_feature' THEN 'false'::jsonb ELSE '{}'::jsonb END;
 ELSIF p_operation='setup_recipients' THEN RETURN '[]'::jsonb;
 ELSIF p_operation='form_editor_fields' THEN RETURN '{}'::jsonb;
 ELSIF p_operation IN ('form_availability','validate_form') THEN
  binding:=public.payment_provider_connection_internal((SELECT data->'payments' FROM public.forms WHERE id=(p_args->>'formId')::bigint),'barion');
  IF p_operation='validate_form' THEN
   IF binding IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.barion_connections b JOIN public.forms f ON f.id=(p_args->>'formId')::bigint JOIN public.occasions oc ON oc.id=f.occasion
    WHERE b.id=binding AND b.unit_id=oc.unit AND b.organization_id=oc.organization AND f.id=ANY(b.sandbox_form_ids)) THEN RAISE EXCEPTION 'BARION_SANDBOX_FORM_REQUIRED'; END IF;
   RETURN NULL;
  END IF;
  SELECT * INTO c FROM eshop.barion_connections WHERE id=binding;
  RETURN jsonb_build_object('providerId','barion','configured',binding IS NOT NULL,'available',false,
   'recipient',CASE WHEN c.id IS NOT NULL THEN jsonb_build_object('connectionId',c.id,'name',c.business_name,'livemode',false) ELSE NULL END,
   'supportedSurfaces','[]'::jsonb,'reason',jsonb_build_object('code','sandbox_only'));
 ELSIF p_operation='initialize_payment' THEN
  input:=p_args->'input';amount:=(p_args->>'amount')::numeric;
  binding:=public.payment_provider_connection_internal((SELECT data->'payments' FROM public.forms WHERE id=(p_args->>'formId')::bigint),'barion');
  SELECT b.* INTO c FROM eshop.barion_connections b JOIN public.forms f ON f.id=(p_args->>'formId')::bigint JOIN public.occasions oc ON oc.id=f.occasion
   WHERE b.id=binding AND b.enabled AND b.organization_id=oc.organization AND b.unit_id=oc.unit AND f.id=ANY(b.sandbox_form_ids);
  IF c.id IS NULL OR input->>'payment_connection_id' IS DISTINCT FROM binding::text THEN RAISE EXCEPTION 'BARION_SANDBOX_FORM_REQUIRED'; END IF;
  IF amount<=0 OR amount*100<>trunc(amount*100) OR amount*100>1000000000 OR p_args->>'currency' NOT IN ('CZK','EUR','USD')
   OR (input->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM amount*100 OR input->>'expected_payment_currency' IS DISTINCT FROM p_args->>'currency'
   OR coalesce(input->>'payment_type','full')<>'full' OR coalesce((p_args->>'deposit')::numeric,0)<>0 THEN RAISE EXCEPTION 'BARION_PRICE_INVALID'; END IF;
  INSERT INTO eshop.payment_info(amount,currency_code,payment_method,created_at,barion_connection_id) VALUES(amount,p_args->>'currency','barion',stamp,binding) RETURNING id INTO amount;
  RETURN jsonb_build_object('paymentInfoId',amount);
 END IF;
 IF p_args ? 'attemptId' THEN SELECT * INTO a FROM eshop.barion_attempts WHERE id=(p_args->>'attemptId')::uuid;
 ELSIF p_args ? 'orderId' THEN SELECT * INTO a FROM eshop.barion_attempts WHERE order_id=(p_args->>'orderId')::bigint;
 ELSE SELECT * INTO a FROM eshop.barion_attempts WHERE payment_info_id=(p_args->>'paymentId')::bigint; END IF;
 IF p_operation='create_attempt' THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint FOR UPDATE;
  SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
  binding:=pi.barion_connection_id;
  SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=binding AND enabled AND o.form=ANY(sandbox_form_ids);
  IF pi.payment_method<>'barion' OR pi.amount<>o.price OR pi.currency_code<>o.currency_code OR o.state<>'ordered'
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND unit=c.unit_id AND organization=c.organization_id) THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
  expiry:=stamp+make_interval(secs=>(public.payment_sale_policy_internal()->>'reservationSeconds')::integer);
  INSERT INTO eshop.barion_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,amount_minor,currency,reservation_expires_at,return_base_url,locale)
   SELECT o.id,pi.id,c.organization_id,c.unit_id,c.id,(pi.amount*100)::bigint,pi.currency_code,expiry,
    rtrim(data->>'DEFAULT_URL','/')||'/payments/barion/return',CASE WHEN data->>'DEFAULT_LANGUAGE' IN ('cs','en','de','pl','sk') THEN data->>'DEFAULT_LANGUAGE' ELSE 'en' END
   FROM public.organizations WHERE id=c.organization_id RETURNING * INTO a;
  UPDATE eshop.payment_info SET deadline=expiry WHERE id=pi.id;
  RETURN jsonb_build_object('expiresAt',expiry);
 END IF;
 IF a.id IS NULL THEN
  IF p_operation='projection' THEN RETURN NULL; END IF;
  IF p_operation='paid_guard' THEN RETURN jsonb_build_object('code',409,'message','BARION_VERIFIED_PAYMENT_REQUIRED'); END IF;
  RAISE EXCEPTION 'BARION_ATTEMPT_REQUIRED';
 END IF;
 SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=a.connection_id;
 SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0),coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0) INTO received,refunded FROM eshop.barion_movements WHERE attempt_id=a.id;
 IF p_operation='totals' THEN RETURN jsonb_build_object('received',received/100.0,'returned',refunded/100.0,'held',CASE WHEN a.financial_hold THEN a.amount_minor/100.0 ELSE 0 END,'invalid',false);
 ELSIF p_operation='movements' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at)),'[]') FROM eshop.barion_movements m WHERE attempt_id=a.id);
 ELSIF p_operation='effect_context' THEN
  RETURN jsonb_build_object('attemptId',a.id,'orderId',a.order_id,'paymentId',a.payment_info_id,'connectionId',c.id,'organizationId',a.organization_id,'unitId',a.unit_id,
   'accountId',c.account_id,'livemode',false,'amountMinor',a.amount_minor,'currency',a.currency,'reservationExpiresAt',a.reservation_expires_at,
   'state',a.state,'incomplete',a.financial_hold,'receivedMinor',received,'refundedMinor',refunded,
   'paymentTime',(SELECT min(occurred_at) FROM eshop.barion_movements WHERE attempt_id=a.id AND kind='payment'),'decisions',a.decisions);
 ELSIF p_operation='effect_lock' THEN PERFORM 1 FROM eshop.barion_attempts WHERE id=a.id FOR UPDATE;RETURN NULL;
 ELSIF p_operation='effect_state' THEN
  IF p_args->>'state' NOT IN ('paid','expired','action_required') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_STATE_INVALID'; END IF;
  UPDATE eshop.barion_attempts SET state=p_args->>'state' WHERE id=a.id;RETURN NULL;
 ELSIF p_operation='effect_decision' THEN
  UPDATE eshop.barion_attempts SET decisions=decisions||jsonb_build_array(p_args->>'reason') WHERE id=a.id;RETURN to_jsonb(extensions.gen_random_uuid());
 ELSIF p_operation IN ('projection','paid_guard') THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=a.payment_info_id;
  IF p_operation='paid_guard' THEN
   IF a.financial_hold OR received<>a.amount_minor OR refunded>=a.amount_minor OR o.state='expired' OR NOT EXISTS(
    SELECT 1 FROM eshop.barion_movements WHERE attempt_id=a.id AND kind='payment' AND occurred_at<=a.reservation_expires_at) THEN
    RETURN jsonb_build_object('code',409,'message','BARION_VERIFIED_PAYMENT_REQUIRED'); END IF; RETURN NULL;
  END IF;
  status:=CASE WHEN a.financial_hold THEN 'disputed' WHEN refunded>=a.amount_minor THEN 'refunded' WHEN a.state='action_required' THEN 'action_required'
   WHEN refunded>0 THEN 'partially_refunded' WHEN received>=a.amount_minor AND o.state IN ('paid','sent') THEN 'paid'
   WHEN a.state='uncertain' AND a.remote_id IS NULL THEN 'pending'
   WHEN a.state='expired' OR a.reservation_expires_at<=clock_timestamp() OR o.state IN ('expired','storno') THEN 'expired'
   WHEN a.state='preparing' THEN 'preparing' ELSE 'open' END;
  admission:=CASE WHEN status IN ('disputed','refunded','action_required') THEN 'hold' WHEN status IN ('paid','partially_refunded') AND o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END;
  RETURN jsonb_build_object('method','barion','status',status,'amount',pi.amount::text,'received',(received/100.0)::numeric(30,2)::text,'returned',(refunded/100.0)::numeric(30,2)::text,
   'currency',a.currency,'admissionState',admission,'orderState',o.state,'reservationExpiresAt',a.reservation_expires_at,'serverNow',clock_timestamp(),
   'reconciliationPending',a.financial_hold OR (a.state='uncertain' AND a.remote_id IS NULL),'reconciliationFailures',a.reconcile_failures,'lastSyncedAt',a.last_synced_at,
   'deliveryState',coalesce((SELECT CASE workflow_state WHEN 'accepted' THEN 'accepted' WHEN 'failed' THEN 'failed' ELSE 'pending' END FROM public.email_messages WHERE order_id=o.id AND message_kind='order_tickets' ORDER BY created_at DESC,id DESC LIMIT 1),'not_requested'),
   'allowedActions',CASE WHEN status IN ('preparing','open') THEN '["refresh","pay"]'::jsonb ELSE '["refresh"]'::jsonb END);
 ELSIF p_operation='attach_source' THEN
  input:=p_args->'source';
  IF input->>'tokenHash' IS NULL OR input->>'tokenHash' !~ '^[a-f0-9]{64}$' OR input->>'returnHash' IS NULL OR input->>'returnHash' !~ '^[a-f0-9]{64}$'
   OR input->>'tokenHash'=input->>'returnHash' OR input->>'contentHash' IS NULL OR input->>'contentHash' !~ '^[a-f0-9]{64}$'
   OR jsonb_typeof(input->'sealed') IS DISTINCT FROM 'object' OR input#>>'{sealed,v}' IS DISTINCT FROM '1'
   OR nullif(input#>>'{sealed,iv}','') IS NULL OR nullif(input#>>'{sealed,ciphertext}','') IS NULL THEN RAISE EXCEPTION 'BARION_SOURCE_INVALID'; END IF;
  INSERT INTO eshop.barion_capabilities(token_hash,attempt_id,scope,expires_at) VALUES(input->>'tokenHash',a.id,'order_pay',stamp+interval '30 days'),(input->>'returnHash',a.id,'return_read',a.reservation_expires_at+interval '1 day');
  INSERT INTO eshop.barion_sources VALUES(a.id,(p_args->>'commandId')::uuid,input->>'tokenHash',input->'sealed',input->>'contentHash');RETURN NULL;
 END IF;
 RAISE EXCEPTION 'BARION_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.barion_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field) VALUES('barion','public.barion_payment_provider_internal(text,jsonb)'::regprocedure,'barionPaymentSource') ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,source_field=excluded.source_field;

-- SOURCE: eshop_barion/runtime.sql
-- Single service boundary. Every operation checks service role; browser tokens
-- are independently scoped/hashed and never treated as account credentials.
CREATE OR REPLACE FUNCTION public.barion_runtime_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.barion_attempts; c eshop.barion_connections; cap eshop.barion_capabilities;
 lease uuid; facts jsonb; tx jsonb; existing eshop.barion_movements; before_projection jsonb; source jsonb;
 result jsonb; digest text; seconds integer; total bigint; refunded bigint; held boolean:=false; stamp timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.require_service_role();
 IF p_operation='recoverable' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('attemptId',q.id,'accountId',q.account_id)),'[]') FROM (
   SELECT a.id,c.account_id FROM eshop.barion_attempts a JOIN eshop.barion_connections c ON c.id=a.connection_id
   WHERE a.next_reconcile_at<=stamp AND (a.lease_expires_at IS NULL OR a.lease_expires_at<=stamp)
   ORDER BY a.next_reconcile_at,a.id LIMIT 10) q);
 ELSIF p_operation='callback_schedule' THEN
  IF p_args->>'paymentId' IS NULL OR p_args->>'paymentId' !~ '^[a-f0-9]{32}$' THEN RAISE EXCEPTION 'BARION_CALLBACK_INVALID'; END IF;
  -- Coalesce bursts; callback cannot cause a remote create or overwrite facts.
  UPDATE eshop.barion_attempts SET next_reconcile_at=least(next_reconcile_at,greatest(stamp,coalesce(last_synced_at,'-infinity')+interval '6 seconds')) WHERE remote_id=p_args->>'paymentId';
  RETURN NULL;
 ELSIF p_operation='purge' THEN
  WITH selected AS (SELECT s.attempt_id FROM eshop.barion_sources s JOIN eshop.barion_capabilities c USING(token_hash) WHERE c.expires_at<=stamp ORDER BY c.expires_at LIMIT 100),
   removed AS (DELETE FROM eshop.barion_sources WHERE attempt_id IN(SELECT attempt_id FROM selected) RETURNING 1) SELECT count(*) INTO total FROM removed;
  RETURN to_jsonb(total);
 END IF;
 IF p_operation IN ('claim_checkout','read','handoff') THEN
  IF p_args->>'token' IS NULL OR p_args->>'token' !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO cap FROM eshop.barion_capabilities WHERE token_hash=encode(extensions.digest(p_args->>'token','sha256'),'hex')
   AND scope=CASE p_operation WHEN 'claim_checkout' THEN 'order_pay' WHEN 'handoff' THEN 'handoff' ELSE p_args->>'scope' END AND expires_at>stamp;
  IF cap.token_hash IS NULL OR (p_operation='read' AND p_args->>'scope' NOT IN ('order_pay','return_read')) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=cap.attempt_id;
 ELSIF p_operation IN ('source','attach_handoff') THEN SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE order_id=(p_args->>'orderId')::bigint;
 ELSE SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=(p_args->>'attemptId')::uuid; END IF;
 SELECT * INTO STRICT c FROM eshop.barion_connections WHERE id=a.connection_id;
 IF p_operation='read' THEN RETURN public.provider_order_payment_projection_internal(a.order_id);
 ELSIF p_operation='source' THEN
  SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,
   'payBaseUrl',regexp_replace(a.return_base_url,'/payments/barion/return$','/payments/barion/pay'),'payment',public.provider_order_payment_projection_internal(a.order_id)) INTO result
  FROM eshop.barion_sources s JOIN eshop.barion_capabilities pc USING(token_hash)
   WHERE s.attempt_id=a.id AND s.command_id=(p_args->>'commandId')::uuid AND pc.scope='order_pay' AND pc.expires_at>stamp;
  IF result IS NULL THEN RETURN jsonb_build_object('payment',public.provider_order_payment_projection_internal(a.order_id)); END IF;
  RETURN result;
 ELSIF p_operation='attach_handoff' THEN
  IF p_args->>'tokenHash' IS NULL OR p_args->>'tokenHash' !~ '^[a-f0-9]{64}$' OR NOT EXISTS(SELECT 1 FROM eshop.barion_sources WHERE attempt_id=a.id AND command_id=(p_args->>'commandId')::uuid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  INSERT INTO eshop.barion_capabilities(token_hash,attempt_id,scope,expires_at) VALUES(p_args->>'tokenHash',a.id,'handoff',least(a.reservation_expires_at,stamp+interval '30 minutes')) ON CONFLICT DO NOTHING;
  RETURN NULL;
 END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 PERFORM 1 FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.barion_attempts WHERE id=a.id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info JOIN public.occasions oc ON oc.id=o.occasion
  WHERE o.id=a.order_id AND pi.id=a.payment_info_id AND pi.payment_method='barion' AND pi.barion_connection_id=a.connection_id
   AND pi.amount*100=a.amount_minor AND pi.currency_code=a.currency AND oc.organization=a.organization_id AND oc.unit=a.unit_id) THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
 before_projection:=public.provider_order_payment_projection_internal(a.order_id);
 IF p_operation='handoff' THEN
  IF p_args->'consume'='true'::jsonb THEN
   UPDATE eshop.barion_capabilities SET consumed_at=stamp WHERE token_hash=cap.token_hash AND consumed_at IS NULL AND expires_at>stamp;
   IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.barion_sources WHERE attempt_id=a.id;
   RETURN jsonb_build_object('source',source);
  END IF;
  RETURN jsonb_build_object('payment',before_projection);
 ELSIF p_operation IN ('claim_checkout','claim_sync') THEN
  IF p_operation='claim_sync' AND p_args->>'accountId' IS DISTINCT FROM c.account_id THEN RAISE EXCEPTION 'BARION_SCOPE_INVALID'; END IF;
  IF a.lease_expires_at>stamp OR coalesce(a.last_synced_at,'-infinity')>stamp-interval '6 seconds' THEN
   RETURN jsonb_build_object('providerId','barion','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' AND (a.reservation_expires_at<=stamp OR before_projection->>'status' NOT IN ('open','preparing')) THEN
   RETURN jsonb_build_object('providerId','barion','disposition','read','payment',before_projection); END IF;
  SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.barion_sources WHERE attempt_id=a.id;
  IF p_operation='claim_checkout' AND a.remote_id IS NULL AND (a.dispatched_at IS NOT NULL OR source IS NULL OR NOT c.enabled) THEN
   RETURN jsonb_build_object('providerId','barion','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' THEN
   PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('barion.checkout',a.unit_id,a.organization_id),
    jsonb_build_object('actor',cap.token_hash,'unit',a.unit_id,'organization',a.organization_id));
  END IF;
  lease:=extensions.gen_random_uuid();
  UPDATE eshop.barion_attempts SET lease_token=lease,lease_expires_at=stamp+interval '120 seconds',
   dispatched_at=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN coalesce(dispatched_at,stamp) ELSE dispatched_at END,
   state=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN 'uncertain' ELSE state END WHERE id=a.id;
  RETURN jsonb_build_object('providerId','barion','disposition','dispatch','lease',lease,'checkoutId',a.remote_id,'connectorState','{}'::jsonb,'source',source,'returnBaseUrl',a.return_base_url,
   'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',false,'amountMinor',a.amount_minor,'currency',a.currency,
    'orderReference','Order '||(SELECT order_symbol FROM eshop.orders WHERE id=a.order_id),'createdAt',extract(epoch FROM a.created_at)::bigint,
    'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,'idempotencyKey',a.id,'locale',a.locale));
 END IF;
 IF p_args->>'lease' IS NULL OR a.lease_token IS NULL OR a.lease_token IS DISTINCT FROM (p_args->>'lease')::uuid OR a.lease_expires_at<=stamp THEN RAISE EXCEPTION 'BARION_LEASE_LOST'; END IF;
 IF p_operation='commit_checkout' THEN
  facts:=p_args->'checkout';
  IF facts->>'id' IS NULL OR facts->>'id' !~ '^[a-f0-9]{32}$' OR (a.remote_id IS NOT NULL AND a.remote_id<>facts->>'id')
   OR facts->>'url' IS DISTINCT FROM ('https://secure.test.barion.com/Pay?Id='||(facts->>'id'))
   OR (facts->>'expiresAt')::bigint IS DISTINCT FROM extract(epoch FROM a.reservation_expires_at)::bigint THEN RAISE EXCEPTION 'BARION_CHECKOUT_INVALID'; END IF;
  UPDATE eshop.barion_attempts SET remote_id=facts->>'id',checkout_url=facts->>'url',state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END,
   lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=stamp+interval '6 seconds' WHERE id=a.id;
 ELSIF p_operation IN ('fail','defer') THEN
  seconds:=CASE WHEN p_operation='fail' THEN 60 ELSE (p_args->>'seconds')::integer END;
  IF seconds IS NULL OR seconds NOT BETWEEN 1 AND 3600 THEN RAISE EXCEPTION 'BARION_RECOVERY_INVALID'; END IF;
  IF p_operation='defer' THEN
   PERFORM public.apply_provider_payment_effects_internal('barion',a.id,'unresolved:'||a.id,before_projection,false,true);
  END IF;
  UPDATE eshop.barion_attempts SET lease_token=NULL,lease_expires_at=NULL,reconcile_failures=reconcile_failures+1,next_reconcile_at=stamp+make_interval(secs=>seconds) WHERE id=a.id;
 ELSIF p_operation='ingest' THEN
  facts:=p_args->'facts';
  IF facts->>'checkoutId' IS NULL OR facts->>'checkoutId' !~ '^[a-f0-9]{32}$' OR facts->>'paymentId' IS DISTINCT FROM facts->>'checkoutId'
   OR (a.remote_id IS NOT NULL AND a.remote_id<>facts->>'checkoutId')
   OR facts->>'checkoutStatus' IS NULL OR facts->>'checkoutStatus' NOT IN ('open','complete','expired')
   OR jsonb_typeof(facts->'movements') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'movements')>100
   OR jsonb_typeof(facts->'disputes') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'disputes')>1
   OR facts ? 'noCheckoutVerified' THEN RAISE EXCEPTION 'BARION_FACTS_INVALID'; END IF;
  -- An incomplete or changed history never subtracts a previously proved fact.
  held:=a.financial_hold OR jsonb_array_length(facts->'disputes')>0 OR EXISTS(
   SELECT 1 FROM eshop.barion_movements m WHERE m.attempt_id=a.id AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'movements') x WHERE x->>'providerId'=m.provider_id));
  FOR tx IN SELECT * FROM jsonb_array_elements(facts->'movements') LOOP
   IF tx->>'providerId' IS NULL OR tx->>'providerId' !~ '^[a-f0-9]{32}$' OR tx->>'kind' IS NULL OR tx->>'kind' NOT IN ('payment','refund')
    OR jsonb_typeof(tx->'amountMinor') IS DISTINCT FROM 'number' OR (tx->>'amountMinor')::numeric<>trunc((tx->>'amountMinor')::numeric)
    OR (tx->>'amountMinor')::numeric NOT BETWEEN 1 AND a.amount_minor OR tx->>'currency' IS DISTINCT FROM a.currency
    OR jsonb_typeof(tx->'occurredAt') IS DISTINCT FROM 'number' OR (tx->>'occurredAt')::numeric<>trunc((tx->>'occurredAt')::numeric)
    OR (tx->>'occurredAt')::bigint<extract(epoch FROM a.created_at)::bigint OR (tx->>'occurredAt')::bigint>extract(epoch FROM stamp+interval '1 minute')::bigint
    THEN RAISE EXCEPTION 'BARION_MOVEMENT_INVALID'; END IF;
   SELECT * INTO existing FROM eshop.barion_movements WHERE connection_id=c.id AND provider_id=tx->>'providerId';
   IF FOUND THEN
    IF existing.attempt_id<>a.id OR existing.kind<>tx->>'kind' OR existing.amount_minor<>(tx->>'amountMinor')::bigint OR existing.currency<>tx->>'currency'
      OR existing.occurred_at<>to_timestamp((tx->>'occurredAt')::bigint) THEN RAISE EXCEPTION 'BARION_MOVEMENT_CONFLICT'; END IF;
   ELSE INSERT INTO eshop.barion_movements VALUES(a.id,c.id,tx->>'providerId',tx->>'kind',(tx->>'amountMinor')::bigint,a.currency,to_timestamp((tx->>'occurredAt')::bigint)); END IF;
  END LOOP;
  SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0),coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0) INTO total,refunded FROM eshop.barion_movements WHERE attempt_id=a.id;
  IF total NOT IN (0,a.amount_minor) OR refunded>total THEN RAISE EXCEPTION 'BARION_TOTALS_INVALID'; END IF;
  digest:=encode(extensions.digest(facts::text,'sha256'),'hex');
  INSERT INTO eshop.barion_observations(attempt_id,digest,facts) VALUES(a.id,digest,facts) ON CONFLICT DO NOTHING;
  UPDATE eshop.barion_attempts SET remote_id=facts->>'checkoutId',financial_hold=held,last_synced_at=stamp,reconcile_failures=0,
   state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END WHERE id=a.id;
  PERFORM public.apply_provider_payment_effects_internal('barion',a.id,digest,before_projection,facts->>'checkoutStatus'='expired',false);
  UPDATE eshop.barion_attempts SET lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=stamp+CASE WHEN total>0 THEN interval '15 minutes' ELSE interval '1 minute' END WHERE id=a.id;
 ELSE RAISE EXCEPTION 'BARION_RUNTIME_OPERATION_UNSUPPORTED';
 END IF;
 RETURN jsonb_build_object('committed',true,'payment',public.provider_order_payment_projection_internal(a.order_id));
END $$;
REVOKE ALL ON FUNCTION public.barion_runtime_internal(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.barion_runtime_internal(text,jsonb) TO service_role;

-- SOURCE: eshop_barion/connections.sql
-- Operator-managed sandbox installation only. This neither discovers keys nor
-- attests production merchant/marketplace/refund eligibility.
CREATE OR REPLACE FUNCTION public.configure_barion_sandbox_connection_internal(p_organization bigint,p_unit bigint,p_shop text,p_name text,p_forms bigint[],p_enabled boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE existing eshop.barion_connections; connection uuid;
BEGIN
 PERFORM public.require_service_role();
 IF p_shop IS NULL OR p_shop !~ '^[a-f0-9]{32}$' OR nullif(p_name,'') IS NULL OR p_forms IS NULL OR cardinality(p_forms)>20 OR p_enabled IS NULL
  OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization)
  OR EXISTS(SELECT 1 FROM unnest(p_forms) fid WHERE fid IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=fid AND oc.unit=p_unit AND oc.organization=p_organization))
  THEN RAISE EXCEPTION 'BARION_SANDBOX_SCOPE_INVALID'; END IF;
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 SELECT * INTO existing FROM eshop.barion_connections WHERE account_id=p_shop FOR UPDATE;
 IF existing.id IS NOT NULL AND (existing.unit_id<>p_unit OR existing.organization_id<>p_organization) THEN RAISE EXCEPTION 'BARION_SANDBOX_SCOPE_INVALID'; END IF;
 INSERT INTO eshop.barion_connections(organization_id,unit_id,account_id,business_name,sandbox_form_ids,enabled) VALUES(p_organization,p_unit,p_shop,p_name,p_forms,p_enabled)
 ON CONFLICT(account_id) DO UPDATE SET business_name=excluded.business_name,sandbox_form_ids=excluded.sandbox_form_ids,enabled=excluded.enabled RETURNING id INTO connection;
 RETURN connection;
END $$;
REVOKE ALL ON FUNCTION public.configure_barion_sandbox_connection_internal(bigint,bigint,text,text,bigint[],boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_barion_sandbox_connection_internal(bigint,bigint,text,text,bigint[],boolean) TO service_role;
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('barion.checkout.token.minute','barion.checkout','actor','rolling',60,60,5,10),
 ('barion.checkout.unit.minute','barion.checkout','unit','rolling',60,60,100,200),
 ('barion.checkout.organization.day','barion.checkout','organization','rolling',86400,3600,5000,10000);

-- SOURCE: abuse/policy.sql
-- One statement snapshot per domain admission. Scoped overrides cannot alter an actor rule.
CREATE OR REPLACE FUNCTION public.abuse_effective_rules_v1(p_budget text,p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'rules',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object(
 'base_limit',coalesce(u.base_limit,o.base_limit,r.base_limit)) ORDER BY r.rule_key),'[]'::jsonb))
 FROM public.abuse_policy_revision v CROSS JOIN public.abuse_policy_rules r
 LEFT JOIN public.abuse_policy_overrides o ON o.rule_key=r.rule_key AND o.target_kind='organization'
  AND o.target_id=p_org AND r.scope_kind IN ('unit','organization') AND o.expires_at>statement_timestamp()
 LEFT JOIN public.abuse_policy_overrides u ON u.rule_key=r.rule_key AND u.target_kind='unit'
  AND u.target_id=p_unit AND r.scope_kind='unit' AND u.expires_at>statement_timestamp()
 WHERE r.budget_key=p_budget GROUP BY v.revision
 HAVING count(*)=CASE p_budget WHEN 'occasion.creation' THEN 8 WHEN 'occasion.copy' THEN 2 WHEN 'occasion.draft' THEN 7
  WHEN 'unit.creation' THEN 3 WHEN 'email.ordinary' THEN 4 WHEN 'email.auth' THEN 4
  WHEN 'email.backlog' THEN 4 WHEN 'email.auth.backlog' THEN 1 WHEN 'email.payload' THEN 1
  WHEN 'email.prepare' THEN 2 WHEN 'email.actor' THEN 1 WHEN 'email.dispatch' THEN 1 WHEN 'ticket.document' THEN 4 WHEN 'ticket.preview' THEN 4 WHEN 'bank.operation' THEN 3 WHEN 'stripe.connect' THEN 3 WHEN 'stripe.checkout' THEN 3 WHEN 'barion.checkout' THEN 3 WHEN 'order.creation' THEN 4 WHEN 'qr.global' THEN 1 WHEN 'qr.proof' THEN 1 WHEN 'qr.payload' THEN 1 WHEN 'spot.hold' THEN 3 WHEN 'image.upload' THEN 5 WHEN 'image.fetch' THEN 5 WHEN 'sync.snapshot' THEN 2 WHEN 'sync.work' THEN 1 WHEN 'hold.duration' THEN 1 WHEN 'auth.reset.source' THEN 2 WHEN 'organization.creation' THEN 1 WHEN 'auth.reset.account' THEN 1
  WHEN 'auth.google.source' THEN 1 WHEN 'auth.google.client' THEN 1 WHEN 'auth.google.global' THEN 1 WHEN 'auth.google.attempt' THEN 1 WHEN 'auth.google.proof' THEN 1
  WHEN 'scan.operation' THEN 2 WHEN 'scan.invalid.global' THEN 1 WHEN 'scan.invalid.source' THEN 1 WHEN 'scan.password' THEN 2 WHEN 'scan.export' THEN 2
  WHEN 'reception.create' THEN 1 WHEN 'reception.issue' THEN 1 WHEN 'reception.revoke' THEN 1 WHEN 'reception.cancel' THEN 1
  WHEN 'order.mutation' THEN 4 WHEN 'batch-create' THEN 1 WHEN 'batch-document' THEN 2
  WHEN 'push.delivery' THEN 10
  WHEN 'cleaning.report' THEN 3
  WHEN 'push.dispatch' THEN 2
  WHEN 'image.records' THEN 9 WHEN 'auth.password' THEN 2 WHEN 'document.output' THEN 4 WHEN 'image.storage' THEN 3 WHEN 'monitor.thresholds' THEN 6 WHEN 'auth.password.change' THEN 3
  WHEN 'email.send.ordinary' THEN 2 WHEN 'email.send.auth' THEN 2 WHEN 'email.send.commitment' THEN 2
  ELSE -1 END;
$$;

-- All families in one admission phase share a PostgreSQL STABLE statement
-- snapshot, including overrides and revision; no config lock or HTTP hop.
CREATE OR REPLACE FUNCTION public.abuse_policy_bundle_v1(p_budgets text[],p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_object_agg(b,public.abuse_effective_rules_v1(b,p_unit,p_org)) FROM unnest(p_budgets) b;
$$;
REVOKE ALL ON FUNCTION public.abuse_policy_bundle_v1(text[],bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Only numeric limits may be changed here. Algorithm/window/identity changes need a migration.
-- A batch is one audited optimistic revision; no writes to usage.
CREATE OR REPLACE FUNCTION public.set_abuse_policy_v1(p_expected_revision bigint,p_reason text,p_changes jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_revision bigint; c jsonb; r public.abuse_policy_rules; v_old jsonb; v_author text;
BEGIN
 PERFORM public.require_service_role();
 IF length(btrim(p_reason)) NOT BETWEEN 8 AND 1000 OR p_reason IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy batch'; END IF;
 SELECT revision INTO v_revision FROM public.abuse_policy_revision FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM v_revision THEN RAISE serialization_failure USING MESSAGE='abuse policy revision conflict'; END IF;
 v_author:=coalesce(auth.uid()::text,session_user::text);
 SELECT jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
 'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x)) INTO v_old;
 FOR c IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('rule_key','base_limit','target_kind','target_id','expires_at')) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported abuse policy parameter'; END IF;
  SELECT * INTO r FROM public.abuse_policy_rules WHERE rule_key=c->>'rule_key';
  IF NOT FOUND OR (c->>'base_limit')::bigint IS NULL OR (c->>'base_limit')::bigint NOT BETWEEN 1 AND r.hard_cap THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy limit'; END IF;
  IF c ? 'target_kind' THEN
   IF (c->>'target_kind'='unit' AND r.scope_kind<>'unit') OR
    (c->>'target_kind'='organization' AND r.scope_kind NOT IN ('unit','organization')) OR
    c->>'target_kind' NOT IN ('unit','organization') OR (c->>'target_id')::bigint IS NULL OR
    (c->>'expires_at')::timestamptz IS NULL OR (c->>'expires_at')::timestamptz<=statement_timestamp() OR
    (c->>'expires_at')::timestamptz>statement_timestamp()+interval '90 days' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid abuse override scope or expiry'; END IF;
   IF NOT (CASE WHEN c->>'target_kind'='unit' THEN EXISTS(SELECT 1 FROM public.units WHERE id=(c->>'target_id')::bigint)
    ELSE EXISTS(SELECT 1 FROM public.organizations WHERE id=(c->>'target_id')::bigint) END) THEN
    RAISE invalid_parameter_value USING MESSAGE='unknown abuse override target'; END IF;
   INSERT INTO public.abuse_policy_overrides VALUES(r.rule_key,c->>'target_kind',(c->>'target_id')::bigint,
    (c->>'base_limit')::bigint,(c->>'expires_at')::timestamptz,p_reason,v_author)
   ON CONFLICT(rule_key,target_kind,target_id) DO UPDATE SET base_limit=excluded.base_limit,expires_at=excluded.expires_at,reason=excluded.reason,author=excluded.author;
  ELSE
   IF c ? 'target_id' OR c ? 'expires_at' THEN RAISE invalid_parameter_value USING MESSAGE='override target required'; END IF;
   UPDATE public.abuse_policy_rules SET base_limit=(c->>'base_limit')::bigint WHERE rule_key=r.rule_key;
  END IF;
 END LOOP;
 UPDATE public.abuse_policy_revision SET revision=revision+1 RETURNING revision INTO v_revision;
 INSERT INTO public.abuse_policy_audit SELECT v_revision,clock_timestamp(),v_author,p_reason,v_old,
  jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
   'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x));
 RETURN v_revision;
END $$;
REVOKE ALL ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.abuse_effective_rules_v1(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_abuse_policy_v1(p_unit bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_read_unit_abuse_policy(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 SELECT organization INTO v_org FROM public.units WHERE id=p_unit;
 RETURN jsonb_build_object('creation',public.abuse_effective_rules_v1('occasion.creation',p_unit,v_org),
 'draft',public.abuse_effective_rules_v1('occasion.draft',p_unit,v_org),
 'usage',coalesce((SELECT jsonb_agg(jsonb_build_object('rule',u.rule_key,'amount',u.amount,'bucketAt',u.bucket_at,'expiresAt',u.expires_at))
 FROM public.abuse_budget_usage u JOIN public.abuse_policy_rules r USING(rule_key)
 WHERE u.expires_at>statement_timestamp() AND ((r.scope_kind='unit' AND u.scope_id=p_unit::text)
 OR (r.scope_kind='actor' AND u.scope_id=auth.uid()::text))),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_unit_abuse_policy_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_abuse_policy_v1(bigint) TO authenticated;

RESET ROLE;
