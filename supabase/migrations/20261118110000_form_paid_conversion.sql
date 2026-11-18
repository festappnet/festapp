-- Historical purchase facts remain readable only in the private ledger. The
-- new kind records settlement; there is no conversion backfill.
ALTER TABLE analytics.conversion_facts DROP CONSTRAINT conversion_facts_kind_check;
ALTER TABLE analytics.conversion_facts ADD CONSTRAINT conversion_facts_kind_check
 CHECK (kind IN ('purchase','waitlist','free_registration','order_fully_paid'));

-- SOURCE: eshop_forms/form_datalayer.sql
CREATE OR REPLACE FUNCTION public.form_conversion_policy_allows_internal(p_status jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_status @> '{"requested_enabled":true,"organization_allowed":true,"organization_enabled":true,"unit_enabled":true}'::jsonb
  AND NOT (p_status->'blocked_reasons' @> '["no_privacy_policy"]'::jsonb),false);
$$;
REVOKE ALL ON FUNCTION public.form_conversion_policy_allows_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Read only after the existing command's receipt authorization. Live policy is
-- deliberately separate from immutable conversion facts and durable receipts.
CREATE OR REPLACE FUNCTION public.form_conversion_datalayer_internal(p_order bigint,p_kind text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT c.payload FROM analytics.conversion_facts c
 JOIN eshop.orders o ON o.id=c."order"
 CROSS JOIN LATERAL (SELECT public.form_measurement_status_internal(o.form) s) policy
 WHERE p_kind IN ('waitlist','free_registration')
   AND c."order"=p_order AND c.kind=p_kind AND public.form_conversion_policy_allows_internal(s);
$$;
REVOKE ALL ON FUNCTION public.form_conversion_datalayer_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

DROP FUNCTION IF EXISTS public.form_purchase_datalayer_internal(bigint);

-- Called exactly at canonical finalization/registration, never on replay.
CREATE OR REPLACE FUNCTION public.record_form_conversion_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE o eshop.orders; s jsonb; lead_kind text; identity uuid:=gen_random_uuid();
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 lead_kind:=CASE WHEN o.state='waitlisted' THEN 'waitlist' WHEN o.price=0 THEN 'free_registration' END;
 IF lead_kind IS NULL THEN RETURN; END IF;
 s:=public.form_measurement_status_internal(o.form);
 IF NOT public.form_conversion_policy_allows_internal(s) THEN RETURN; END IF;
 INSERT INTO analytics.conversion_facts("order",kind,event_id,payload)
 VALUES (p_order,lead_kind,identity,jsonb_build_object('event','generate_lead','event_id',identity,
   'currency',coalesce(nullif(trim(o.currency_code),''),'CZK'),'value',0,'lead_source',lead_kind))
 ON CONFLICT("order",kind) DO NOTHING;
-- Measurement failure cannot change checkout.
EXCEPTION WHEN OTHERS THEN RETURN;
END $$;
REVOKE ALL ON FUNCTION public.record_form_conversion_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/form_paid_conversion.sql
CREATE OR REPLACE FUNCTION public.form_paid_conversion_eligible_internal(p_order bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE
 o eshop.orders;
 payment eshop.payment_info;
 totals record;
 eligible_bank_received numeric;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.form IS NULL OR (o.state IN ('paid','sent')) IS NOT TRUE OR coalesce(o.price,0)<=0
  OR coalesce(trim(o.currency_code),'') !~ '^[A-Z]{3}$'
  OR NOT public.form_conversion_policy_allows_internal(public.form_measurement_status_internal(o.form))
 THEN RETURN false; END IF;

 SELECT * INTO payment FROM eshop.payment_info WHERE id=o.payment_info;
 IF payment.amount IS DISTINCT FROM o.price OR payment.currency_code IS DISTINCT FROM o.currency_code
  OR payment.payment_method IS NULL THEN RETURN false; END IF;

 SELECT * INTO totals FROM public.payment_financial_totals_internal(payment.id);
 IF totals.invalid_identity IS DISTINCT FROM false OR coalesce(totals.available,0)<o.price THEN RETURN false; END IF;

 IF payment.payment_method='bank' THEN
  -- Cash and administrative settlements cannot complete a qualifying purchase.
  SELECT coalesce(sum(m.amount),0) INTO eligible_bank_received
  FROM public.payment_transaction_movements_internal(payment.id) m
  JOIN eshop.transactions t ON t.id=m.transaction_id
  JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
  WHERE NOT m.is_refund AND NOT m.voided AND upper(b.type)<>'CASH'
    AND t.transaction_type IS DISTINCT FROM 'manual' AND t.ingest_source IS DISTINCT FROM 'manual';
  IF eligible_bank_received-totals.refunded<o.price THEN RETURN false; END IF;
 ELSIF NOT public.payment_method_is_online_internal(payment.payment_method) THEN
  RETURN false;
 END IF;

 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.form_paid_conversion_eligible_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Payment owners hold the order and payment locks. Preserve the settlement fact
-- in the same transaction so provider or manual pairing retries cannot lose it.
CREATE OR REPLACE FUNCTION public.record_form_paid_conversion_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT FROM analytics.conversion_facts c WHERE c."order"=p_order AND c.kind='order_fully_paid')
    OR NOT public.form_paid_conversion_eligible_internal(p_order) THEN RETURN; END IF;
 INSERT INTO analytics.conversion_facts("order",kind,payload)
 SELECT id,'order_fully_paid',jsonb_build_object('value',price,'currency',trim(currency_code))
 FROM eshop.orders WHERE id=p_order
 ON CONFLICT("order",kind) DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.record_form_paid_conversion_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/meta_purchase_schema.sql
-- Provision one approved connector per organizer. The token itself lives in Vault.
CREATE TABLE analytics.meta_purchase_connectors (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 dataset text NOT NULL CHECK(dataset ~ '^[0-9]{5,30}$'),
 vault_secret uuid NOT NULL UNIQUE,
 website_origin text NOT NULL CHECK(website_origin ~ '^https://[a-z0-9.-]+$'),
 revision uuid NOT NULL DEFAULT gen_random_uuid(),
 enabled boolean NOT NULL DEFAULT false,
 test_event_code text CHECK(test_event_code ~ '^[A-Za-z0-9_-]{1,60}$'),
 paused_at timestamptz
);
CREATE TABLE analytics.meta_purchase_forms (
 form bigint PRIMARY KEY REFERENCES public.forms(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES analytics.meta_purchase_connectors(unit) ON DELETE CASCADE
);
CREATE TABLE analytics.meta_purchase_deliveries (
 order_id bigint PRIMARY KEY REFERENCES eshop.orders(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES analytics.meta_purchase_connectors(unit) ON DELETE CASCADE,
 connector_revision uuid NOT NULL,
 consent_revision text NOT NULL,
 consent_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 email_hash text,
 client_agent text,
 source_url text,
 revoked_at timestamptz,
 next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 attempts integer NOT NULL DEFAULT 0,
 lease uuid,
 lease_until timestamptz,
 prepared boolean NOT NULL DEFAULT false,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sent','revoked','expired','invalid','failed')),
 done_at timestamptz,
 error_code text
);
CREATE INDEX meta_purchase_delivery_due ON analytics.meta_purchase_deliveries(next_attempt_at,order_id)
 WHERE status='pending';
ALTER TABLE analytics.meta_purchase_connectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.meta_purchase_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.meta_purchase_forms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.meta_purchase_connectors,analytics.meta_purchase_forms,analytics.meta_purchase_deliveries FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/meta_purchase_consent.sql
-- Policy gates and destination/notice binding are shared by checkout and delivery.
CREATE OR REPLACE FUNCTION public.meta_purchase_consent_revision_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT md5(jsonb_build_array(c.revision,c.dataset,c.website_origin,c.test_event_code,
         public.unit_measurement_consent_scope_internal(c.unit)->>'consentRevision')::text)
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN analytics.meta_purchase_forms pilot ON pilot.form=f.id AND pilot.unit=o.unit
 JOIN analytics.meta_purchase_connectors c ON c.unit=pilot.unit
 WHERE f.id=p_form AND c.enabled AND NOT public.is_demo_occasion(o.id)
  AND public.form_conversion_policy_allows_internal(public.form_measurement_status_internal(f.id));
$$;
REVOKE ALL ON FUNCTION public.meta_purchase_consent_revision_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_meta_purchase_consent(p_form_link text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'origin',c.website_origin,
     'privacyUrl',u.data->>'measurement_privacy_url')
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN public.units u ON u.id=o.unit JOIN analytics.meta_purchase_connectors c ON c.unit=u.id
 CROSS JOIN LATERAL (SELECT public.meta_purchase_consent_revision_internal(f.id) revision) v
 WHERE f.id=public.resolve_form_link_internal(p_form_link) AND public.can_read_public_form_measurement(f.id) AND v.revision IS NOT NULL
  AND public.form_measurement_visitor_role_internal(f.id)<>'staff';
$$;
REVOKE ALL ON FUNCTION public.get_meta_purchase_consent(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_meta_purchase_consent(text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.capture_meta_purchase_consent_internal(p_order bigint,p_consent jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE
 details record;
 agent text:=p_consent->>'userAgent';
 email text;
BEGIN
 IF jsonb_typeof(p_consent) IS DISTINCT FROM 'object'
    OR coalesce(length(agent),0) NOT BETWEEN 1 AND 512 OR agent ~ '[[:cntrl:]]'
    OR coalesce(p_consent->>'revision','') !~ '^[a-f0-9]{32}$'
 THEN RETURN; END IF;
 SELECT o.form,o.price,o.data,oc.unit,f.link,c.website_origin,c.revision
 INTO details
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN public.forms f ON f.id=o.form
 JOIN analytics.meta_purchase_connectors c ON c.unit=oc.unit
 WHERE o.id=p_order;
 IF NOT FOUND OR coalesce(details.price,0)<=0
    OR public.form_measurement_visitor_role_internal(details.form)='staff'
    OR coalesce(details.link,'') !~ '^[a-zA-Z0-9_-]+$'
    OR public.meta_purchase_consent_revision_internal(details.form) IS DISTINCT FROM p_consent->>'revision'
 THEN RETURN; END IF;
 email:=lower(btrim(details.data->>'email'));
 IF coalesce(length(email),0) NOT BETWEEN 3 AND 254 OR email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RETURN; END IF;
 INSERT INTO analytics.meta_purchase_deliveries(order_id,unit,connector_revision,consent_revision,email_hash,client_agent,source_url)
 VALUES (p_order,details.unit,details.revision,p_consent->>'revision',
   encode(extensions.digest(email,'sha256'),'hex'),agent,details.website_origin||'/form/'||details.link)
 ON CONFLICT(order_id) DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.capture_meta_purchase_consent_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Use the same buyer capability and order scope as the confirmation email.
CREATE OR REPLACE FUNCTION public.revoke_meta_purchase_consent(p_token text,p_order_id bigint)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE overview jsonb;
BEGIN
 overview:=public.get_customer_order_overview_internal(p_token,p_order_id);
 IF overview->>'code' IS DISTINCT FROM '200' THEN RETURN false; END IF;
 UPDATE analytics.meta_purchase_deliveries SET revoked_at=clock_timestamp(),status=CASE WHEN status='pending' THEN 'revoked' ELSE status END,
  done_at=clock_timestamp(),lease=NULL,lease_until=NULL,email_hash=NULL,client_agent=NULL,source_url=NULL
 WHERE order_id IN(SELECT (value->>'id')::bigint FROM jsonb_array_elements(overview->'orders'))
   AND revoked_at IS NULL;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.revoke_meta_purchase_consent(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_meta_purchase_consent(text,bigint) TO anon,authenticated;

-- SOURCE: eshop_forms/meta_purchase_worker.sql
CREATE OR REPLACE FUNCTION public.claim_meta_purchase_deliveries(p_limit integer)
RETURNS TABLE(order_id bigint, lease uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 -- Only a small bounded set is scrubbed per run. Keep delivery receipts 90 days.
 WITH expired AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  WHERE d.status='pending' AND d.consent_at<clock_timestamp()-interval '30 days'
  ORDER BY d.consent_at LIMIT 100 FOR UPDATE SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET status='expired',done_at=clock_timestamp(),
  lease=NULL,lease_until=NULL,email_hash=NULL,client_agent=NULL,source_url=NULL
 FROM expired WHERE d.order_id=expired.order_id;
 DELETE FROM analytics.meta_purchase_deliveries d WHERE d.order_id IN(
  SELECT x.order_id FROM analytics.meta_purchase_deliveries x
  WHERE x.done_at<clock_timestamp()-interval '90 days' LIMIT 100 FOR UPDATE SKIP LOCKED);
 RETURN QUERY
 WITH due AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind='order_fully_paid'
  WHERE d.status='pending' AND c.enabled AND c.paused_at IS NULL
    AND d.next_attempt_at<=clock_timestamp() AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
  ORDER BY d.next_attempt_at,d.order_id LIMIT least(greatest(coalesce(p_limit,1),1),20)
  FOR UPDATE OF d SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET lease=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',prepared=false
 FROM due WHERE d.order_id=due.order_id RETURNING d.order_id,d.lease;
END $$;

-- Revalidate as close to sending as possible. Claiming does not disclose any
-- matching data or confer permission after withdrawal or destination changes.
CREATE OR REPLACE FUNCTION public.prepare_meta_purchase_delivery(p_order_id bigint,p_lease uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 delivery analytics.meta_purchase_deliveries;
 connector analytics.meta_purchase_connectors;
 fact analytics.conversion_facts;
 o eshop.orders;
 token text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND status='pending' AND lease=p_lease AND lease_until>clock_timestamp() AND NOT prepared
 FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO connector FROM analytics.meta_purchase_connectors WHERE unit=delivery.unit;
 IF connector.enabled IS DISTINCT FROM true OR connector.paused_at IS NOT NULL THEN RETURN NULL; END IF;
 SELECT * INTO fact FROM analytics.conversion_facts WHERE "order"=p_order_id AND kind='order_fully_paid';
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 IF delivery.connector_revision IS DISTINCT FROM connector.revision
    OR delivery.consent_revision IS DISTINCT FROM public.meta_purchase_consent_revision_internal(o.form)
    OR delivery.consent_at>fact.created_at
    OR delivery.consent_at<clock_timestamp()-interval '30 days'
    OR fact.created_at<clock_timestamp()-interval '7 days'
    OR delivery.attempts>=6
    OR fact.payload IS DISTINCT FROM jsonb_build_object('value',o.price,'currency',trim(o.currency_code))
    OR NOT public.form_paid_conversion_eligible_internal(p_order_id) THEN
  UPDATE analytics.meta_purchase_deliveries SET status='invalid',done_at=clock_timestamp(),
   lease=NULL,lease_until=NULL,email_hash=NULL,client_agent=NULL,source_url=NULL
  WHERE order_id=p_order_id;
  RETURN NULL;
 END IF;
 SELECT decrypted_secret INTO token FROM vault.decrypted_secrets WHERE id=connector.vault_secret;
 IF coalesce(length(token),0) NOT BETWEEN 16 AND 4096 THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=connector.unit AND revision=connector.revision;
  RETURN NULL;
 END IF;
 UPDATE analytics.meta_purchase_deliveries SET attempts=attempts+1,prepared=true WHERE order_id=p_order_id;
 RETURN jsonb_build_object('dataset',connector.dataset,'accessToken',token,'testEventCode',connector.test_event_code,
  'eventId',fact.event_id,'eventTime',floor(extract(epoch FROM fact.created_at)),
  'value',fact.payload->'value','currency',fact.payload->>'currency',
  'emailHash',delivery.email_hash,'clientAgent',delivery.client_agent,'sourceUrl',delivery.source_url);
END $$;

CREATE OR REPLACE FUNCTION public.finish_meta_purchase_delivery(p_order_id bigint,p_lease uuid,p_result text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE delivery analytics.meta_purchase_deliveries; final_status text;
BEGIN
 PERFORM public.require_service_role();
 IF p_result IS NULL OR p_result NOT IN ('sent','retry','credentials','rejected') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid delivery result'; END IF;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND lease=p_lease AND status='pending' AND prepared FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_result='credentials' THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=delivery.unit AND revision=delivery.connector_revision;
 END IF;
 final_status:=CASE WHEN p_result='sent' THEN 'sent'
  WHEN p_result='rejected' OR delivery.attempts>=6 THEN 'failed' ELSE 'pending' END;
 UPDATE analytics.meta_purchase_deliveries SET status=final_status,error_code=nullif(p_result,'sent'),
  next_attempt_at=clock_timestamp()+interval '2 minutes'*power(2,greatest(delivery.attempts-1,0)),
  lease=NULL,lease_until=NULL,done_at=CASE WHEN final_status<>'pending' THEN clock_timestamp() END,
  email_hash=CASE WHEN final_status='pending' THEN email_hash END,
  client_agent=CASE WHEN final_status='pending' THEN client_agent END,
  source_url=CASE WHEN final_status='pending' THEN source_url END
 WHERE order_id=p_order_id;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.claim_meta_purchase_deliveries(integer),
 public.prepare_meta_purchase_delivery(bigint,uuid),public.finish_meta_purchase_delivery(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_meta_purchase_deliveries(integer),
 public.prepare_meta_purchase_delivery(bigint,uuid),public.finish_meta_purchase_delivery(bigint,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.wake_meta_purchase_worker()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE endpoint text;
BEGIN
 IF NOT EXISTS(
  SELECT FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit AND c.enabled AND c.paused_at IS NULL
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind='order_fully_paid'
  WHERE d.status='pending' AND d.next_attempt_at<=clock_timestamp()
   AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
 ) AND NOT EXISTS(
  SELECT FROM analytics.meta_purchase_deliveries WHERE status='pending' AND consent_at<clock_timestamp()-interval '30 days'
     OR done_at<clock_timestamp()-interval '90 days'
 ) THEN RETURN; END IF;
 SELECT regexp_replace(worker_url,'/process-email-queue$','/process-meta-purchases') INTO endpoint
 FROM public.email_capacity
 WHERE worker_url LIKE '%/process-email-queue';
 IF endpoint IS NULL THEN RETURN; END IF;
 PERFORM net.http_post(url:=endpoint,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),
   timeout_milliseconds:=90000);
END $$;
REVOKE ALL ON FUNCTION public.wake_meta_purchase_worker() FROM PUBLIC,anon,authenticated,service_role;

-- An operator activates the schedule only after configuring a test dataset and
-- releasing the worker with the canonical gateway.
DO $$ DECLARE job bigint; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  SELECT jobid INTO job FROM cron.job WHERE jobname='festapp_meta_purchase_delivery';
  IF job IS NULL THEN
   job:=cron.schedule('festapp_meta_purchase_delivery','* * * * *','SELECT public.wake_meta_purchase_worker()');
   PERFORM cron.alter_job(job,active:=false);
  END IF;
 END IF;
END $$;

-- SOURCE: eshop_waitlist/order_overview.sql
-- Private pure projection. No matcher, paid transition or payment side effect.
CREATE OR REPLACE FUNCTION public.customer_order_payment_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH facts AS (
 SELECT o.*,public.payment_collection_action_internal(o.id) collection_action,p.payment_method,p.amount,coalesce(p.paid,0) received,coalesce(p.returned,0) returned,
 coalesce(p.paid,0)-coalesce(p.returned,0) net,
 (SELECT coalesce(sum(r.amount),0) FROM eshop.refund_requests r WHERE r.payment_info=p.id AND r.status IN ('pending','processing','unknown')) pending,
 p.data->'payment_policy' payment_policy,p.deposit_amount,p.deposit_deadline,p.deadline,p.variable_symbol,p.creditor_reference,
 b.account_number,b.account_number_human_readable,
 coalesce(nullif(trim(b.creditor_name),''),(SELECT left(trim(regexp_replace(org.title,'[[:space:][:cntrl:]]+',' ','g')),70) FROM public.occasions occ JOIN public.organizations org ON org.id=occ.organization WHERE occ.id=o.occasion)) creditor_name,
 CASE WHEN o.state='preparing_payment' THEN 'preparing'
 WHEN o.state='storno' THEN 'cancelled'
 WHEN o.state='expired' THEN 'expired'
 WHEN o.state='waitlisted' AND p.id IS NULL THEN 'not_required_yet'
 WHEN o.price=0 THEN 'free'
 WHEN p.id IS NULL OR p.currency_code IS DISTINCT FROM o.currency_code OR p.amount IS NULL OR p.amount<0 OR coalesce(p.paid,0)<0 OR coalesce(p.paid_externally,0)<>0
  OR (o.state IN ('paid','sent') AND o.price>0 AND coalesce(p.paid,0)=0) THEN 'unknown'
 WHEN coalesce(p.paid,0)-coalesce(p.returned,0)>=p.amount THEN 'fully_paid'
 WHEN coalesce(p.paid,0)-coalesce(p.returned,0)<=0 THEN 'unpaid'
 WHEN p.deposit_amount>0 AND coalesce(p.paid,0)-coalesce(p.returned,0)>=p.deposit_amount THEN 'deposit_paid'
 ELSE 'partially_paid' END status
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order),
 due AS (SELECT *,greatest(amount-net,0) outstanding,
 CASE WHEN deposit_amount>net THEN greatest(deposit_amount-net,0) ELSE greatest(amount-net,0) END due_now,
 CASE WHEN deposit_amount>net THEN deposit_deadline ELSE deadline END due_at FROM facts)
 SELECT CASE WHEN public.payment_method_is_online_internal(payment_method) THEN public.provider_order_payment_projection_internal(p_order)||jsonb_build_object('allowedActions',CASE WHEN collection_action->'allowed'='true'::jsonb THEN public.provider_order_payment_projection_internal(p_order)->'allowedActions' ELSE '["refresh"]'::jsonb END,'net',net,'pending',pending,'totalOutstanding',outstanding,'overpaid',greatest(net-amount,0)) ELSE jsonb_build_object('method',payment_method,'deadlinePolicy',payment_policy->>'mode','instructions',jsonb_build_object('cashInstructions',payment_policy->>'cashInstructions'),'currency',trim(currency_code),'paid',received,'remaining',outstanding,'status',status,'amount',amount,'received',received,'returned',returned,'net',net,'pending',pending,
 'totalOutstanding',outstanding,'overpaid',greatest(net-amount,0),'depositAmount',deposit_amount,
 'depositDeadline',deposit_deadline,'finalDeadline',deadline,
 'dueNow',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN due_now ELSE 0 END,
 'dueAt',due_at,'overdue',coalesce(due_at<statement_timestamp() AND due_now>0,false),
 'instructionsAvailable',collection_action->'allowed'='true'::jsonb AND status IN ('unpaid','partially_paid','deposit_paid') AND (payment_method='cash' OR account_number IS NOT NULL)
  AND (payment_method='cash' OR CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END),
 'reference',CASE WHEN collection_action->'allowed'='true'::jsonb AND status IN ('unpaid','partially_paid','deposit_paid') THEN
  CASE WHEN currency_code='EUR' THEN creditor_reference ELSE variable_symbol::text END END,
 'qrPayment',CASE WHEN collection_action->'allowed'='true'::jsonb AND payment_method='bank' AND status IN ('unpaid','partially_paid','deposit_paid') AND due_now>0 AND account_number IS NOT NULL
  AND CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END
 THEN jsonb_build_object('amount',due_now,'currency_code',trim(currency_code),'account_number',account_number,
  'account_number_human_readable',account_number_human_readable,'creditor_name',creditor_name,
  'variable_symbol',variable_symbol,'creditor_reference',creditor_reference) END,
 'referenceKind',CASE WHEN currency_code='EUR' THEN 'RF' ELSE 'VS' END,
 'transactions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
  'date',t.date::date,'recordedAt',t.created_at,'amount',t.amount,'currency',trim(t.currency),
  'kind',CASE WHEN m.voided THEN 'payment_adjustment_voided' WHEN m.is_refund THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END)
  ORDER BY t.created_at NULLS LAST,t.id),'[]') FROM eshop.transactions t JOIN LATERAL public.payment_transaction_movements_internal(due.payment_info) m ON m.transaction_id=t.id WHERE t.payment_info=due.payment_info),
 'publicAccount',CASE WHEN collection_action->'allowed'='true'::jsonb AND payment_method='bank' AND status IN ('unpaid','partially_paid','deposit_paid') THEN coalesce(account_number_human_readable,account_number) END)
 END FROM due;
$$;
REVOKE ALL ON FUNCTION public.customer_order_payment_internal(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.customer_ticket_label_internal(p_ticket bigint,p_form bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT nullif(string_agg(a.value#>>'{}',' ' ORDER BY CASE f.type WHEN 'name' THEN 0 ELSE 1 END,f.id),'')
 FROM eshop.tickets t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t.data->'fields','[]')) field
 CROSS JOIN LATERAL jsonb_each(field) a JOIN public.form_fields f ON f.id::text=a.key
 WHERE t.id=p_ticket AND f.form=p_form AND f.is_ticket_field AND NOT f.is_hidden AND f.type IN ('name','surname');
$$;
REVOKE ALL ON FUNCTION public.customer_ticket_label_internal(bigint,bigint) FROM PUBLIC,anon,authenticated;

-- Customer-visible answers only; field definitions own scope and visibility.
CREATE OR REPLACE FUNCTION public.customer_order_answers_internal(p_form bigint,p_data jsonb,p_ticket boolean)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('title',f.title,'type',f.type,'value',CASE WHEN f.type='id_document' AND jsonb_typeof(answer.value)='object'
  THEN jsonb_strip_nulls(jsonb_build_object('id_document_number',answer.value->'id_document_number',
   'id_document_expiry_date',answer.value->'id_document_expiry_date')) ELSE answer.value END) ORDER BY f."order",f.id),'[]')
 FROM public.form_fields f CROSS JOIN LATERAL (
  SELECT coalesce(a->(f.id::text),a->f.type) value
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'fields')='array' THEN p_data->'fields' ELSE '[]' END) a
  WHERE a ? f.id::text OR (a->>'_subFieldId'=f.id::text AND a ? f.type)
   OR (NOT a ? '_subFieldId' AND a ? f.type
    AND NOT EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k ~ '^[0-9]+$')
    AND 1=(SELECT count(*) FROM public.form_fields other WHERE other.form=p_form AND other.type=f.type AND other.is_ticket_field=p_ticket AND NOT other.is_hidden))
  LIMIT 1
 ) answer
 WHERE f.form=p_form AND f.is_ticket_field=p_ticket AND NOT f.is_hidden
 AND f.type IN ('name','surname','email','phone','city','sex','birth_year','birth_date','address','nationality','id_document','text','note','select_one','select_many')
 AND ((f.type='id_document' AND jsonb_typeof(answer.value)='object'
  AND jsonb_typeof(answer.value->'id_document_number')='string'
  AND (answer.value->'id_document_expiry_date' IS NULL OR jsonb_typeof(answer.value->'id_document_expiry_date') IN ('string','null')))
  OR jsonb_typeof(answer.value) IN ('string','number','boolean') OR (jsonb_typeof(answer.value)='array'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(answer.value)='array' THEN answer.value ELSE '[]' END) v WHERE jsonb_typeof(v) NOT IN ('string','number','boolean'))));
$$;
REVOKE ALL ON FUNCTION public.customer_order_answers_internal(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_customer_order_overview_internal(p_token text,p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE root eshop.orders; cap eshop.waitlist_capabilities; occ public.occasions; f public.forms;
 ids bigint[]; result jsonb;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO root FROM eshop.orders WHERE id=p_order_id AND source_waitlist_order_id IS NULL;
 SELECT * INTO occ FROM public.occasions WHERE id=root.occasion;
 SELECT * INTO f FROM public.forms WHERE id=root.form AND occasion=occ.id;
 SELECT * INTO cap FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND kind='order_view' AND order_id=root.id AND form_id=f.id AND organization_id=occ.organization
 AND revoked_at IS NULL AND expires_at>statement_timestamp();
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' OR cap.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT array_agg(id) INTO ids FROM eshop.orders WHERE id=root.id OR (source_waitlist_order_id=root.id AND NOT (
  NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=eshop.orders.id)
  AND EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=eshop.orders.id AND source_order_id=root.id AND state='aborted')));
 -- Reject malformed provenance rather than expanding an apparently related scope.
 IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(ids) AND (o.form IS DISTINCT FROM f.id OR o.occasion IS DISTINCT FROM occ.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=ANY(ids)
  AND (t.occasion<>occ.id OR EXISTS(SELECT 1 FROM eshop.order_product_ticket y WHERE y.ticket=t.id AND y."order" IS DISTINCT FROM x."order")))
 OR EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(ids) AND o.source_waitlist_order_id=root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  JOIN eshop.order_product_ticket x ON x.ticket=s.ticket_id AND x."order"=o.id
  WHERE w.order_id=root.id AND w.form_id=f.id AND s.form_id=f.id AND s.outcome='accepted' AND s.resulting_order_id=o.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=ANY(ids) AND x."order"<>root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.ticket_id=x.ticket AND s.resulting_order_id=x."order" AND s.outcome='accepted' AND w.order_id=root.id AND w.form_id=f.id))
 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT jsonb_build_object('code',200,'root',jsonb_build_object('id',root.id,'symbol',root.order_symbol,'createdAt',root.created_at,'state',root.state,'title',occ.title,'formLink',f.link,'communicationTone',public.effective_form_metadata_internal(f.data,(SELECT data FROM public.units WHERE id=occ.unit))->>'communication_tone','hasTickets',public.uses_ticket_terminology_internal(occ.features)),
 'timeline',(SELECT coalesce(jsonb_agg(event ORDER BY happened,sort_key),'[]') FROM (
  SELECT root.created_at happened,'0' sort_key,jsonb_build_object('kind',CASE WHEN root.state='waitlisted' THEN 'waitlist_entered' ELSE 'order_ordered' END,'at',root.created_at,'symbol',root.order_symbol) event
  WHERE root.state='waitlisted' OR NOT EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=root.id AND state='ordered')
  UNION ALL
  SELECT w.created_at,'1'||w.id::text,jsonb_build_object('kind','places_offered','at',w.created_at)
  FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id
  UNION ALL
  SELECT s.updated_at,'2'||s.id::text,jsonb_build_object('kind','offer_'||s.outcome,'at',s.updated_at)
  FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE w.order_id=root.id AND w.form_id=f.id AND s.form_id=f.id AND s.outcome IN ('accepted','declined','cancelled','expired')
  UNION ALL
  SELECT t.created_at,'4'||t.id::text,jsonb_build_object('kind',CASE WHEN m.voided THEN 'payment_adjustment_voided' WHEN m.is_refund THEN 'refund' WHEN t.amount>0 THEN 'payment_received' ELSE 'payment_adjustment' END,
   'at',t.created_at,'timeKind','recorded','amount',t.amount,'currency',trim(t.currency),'symbol',o.order_symbol,
   'paymentMethod',CASE WHEN b.type='CASH' THEN 'cash' WHEN nullif(trim(b.account_number),'') IS NOT NULL THEN 'bank' END,
   'recipientAccount',CASE WHEN b.type<>'CASH' THEN coalesce(nullif(trim(b.account_number_human_readable),''),nullif(trim(b.account_number),'')) END)
  FROM eshop.orders o JOIN eshop.transactions t ON t.payment_info=o.payment_info JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id LEFT JOIN eshop.bank_accounts b ON b.id=t.bank_account_id WHERE o.id=ANY(ids) AND t.created_at IS NOT NULL
  UNION ALL
  SELECT h.created_at,'3'||h.id::text,jsonb_build_object(
   'kind',CASE WHEN h.state IS DISTINCT FROM h.previous_state THEN 'order_'||h.state ELSE 'order_changed' END,
   'at',h.created_at,'symbol',h.order_symbol,'previousState',h.previous_state,'state',h.state,
   'previousTotal',CASE WHEN h.price IS DISTINCT FROM h.previous_price AND h.previous_state IS NOT NULL THEN h.previous_price END,
   'total',h.price,'currency',h.currency_code,
   'itemsChanged',h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items,
   'itemsBefore',CASE WHEN h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items THEN h.previous_items END,
   'itemsAfter',CASE WHEN h.previous_state IS NOT NULL AND h.items IS DISTINCT FROM h.previous_items THEN h.items END,
   'detailsChanged',h.previous_state IS NOT NULL AND h.details IS DISTINCT FROM h.previous_details)
  FROM (SELECT snapshots.*,lag(state) OVER w previous_state,lag(price) OVER w previous_price,
   lag(items) OVER w previous_items,lag(details) OVER w previous_details FROM (
    SELECT h.id,h.created_at,h."order",h.state,h.price,coalesce(h.currency_code,o.currency_code) currency_code,o.order_symbol,
     (SELECT coalesce(jsonb_agg(jsonb_build_object('id',p->'id','ticketId',t->'id','ticketSymbol',t->>'ticket_symbol','title',p->>'title','price',p->'price') ORDER BY t->>'id',p->>'id'),'[]')
      FROM jsonb_array_elements(coalesce(h.data->'tickets','[]')) t
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p) items,
     jsonb_build_object('fields',coalesce(h.data->'fields',h.data#>'{input_data,fields}'),'tickets',
      (SELECT jsonb_agg(jsonb_build_object('id',t->'id','fields',t->'fields') ORDER BY t->>'id') FROM jsonb_array_elements(coalesce(h.data->'tickets','[]')) t)) details
    FROM eshop.orders_history h JOIN eshop.orders o ON o.id=h."order" WHERE h."order"=ANY(ids)
      AND h.state IN ('ordered','paid','sent','storno') AND (h.price IS NOT NULL OR h.data ? 'tickets')
   ) snapshots WINDOW w AS (PARTITION BY "order" ORDER BY created_at,id)) h
  WHERE h.state IS DISTINCT FROM h.previous_state OR h.price IS DISTINCT FROM h.previous_price
   OR h.items IS DISTINCT FROM h.previous_items OR h.details IS DISTINCT FROM h.previous_details
 ) events),
 'organizationIdentity',CASE WHEN occ.organization=(SELECT organization FROM public.units WHERE id=occ.unit) THEN public.get_verified_unit_identity_internal(occ.unit) END,
 'allowedActions',public.customer_order_actions_internal(root.id),'changeRequests',public.customer_order_change_requests_internal(root.id),
 'serverTime',statement_timestamp(),'accessExpiresAt',cap.expires_at,'actions',jsonb_build_array('refresh'),
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'symbol',t.ticket_symbol,
  'answers',public.customer_order_answers_internal(f.id,t.data,true),'effectiveLifecycle',CASE WHEN (SELECT state FROM eshop.orders WHERE id=x."order")='preparing_payment' THEN 'preparing' ELSE public.get_effective_waitlist_ticket_lifecycle_internal(t.id) END,'currentOrderId',x."order") ORDER BY t.id),'[]')
  FROM (SELECT DISTINCT "order",ticket FROM eshop.order_product_ticket WHERE "order"=ANY(ids)) x JOIN eshop.tickets t ON t.id=x.ticket),
 'offers',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'expiresAt',w.expires_at,
  'pendingPlaces',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending' AND w.expires_at>statement_timestamp()),
  'effectiveStatus',CASE WHEN w.expires_at<=statement_timestamp() THEN 'expired'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending') THEN 'pending'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome IN ('declined','cancelled')) THEN 'cancelled' ELSE 'accepted' END)
  ORDER BY w.created_at,w.id),'[]') FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id),
 'orders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'symbol',o.order_symbol,'state',o.state,'total',o.price,'currency',o.currency_code,
  'discount',o.data->'discount',
  'payment',public.customer_order_payment_internal(o.id),
  'answers',public.customer_order_answers_internal(f.id,o.data,false),
  'ticketIds',(SELECT coalesce(jsonb_agg(t.id ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t),
  'items',CASE WHEN o.state='preparing_payment' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticketId',t->'id','id',p->'id','title',p->>'title','spotTitle',p->>'spot_title','spotGroupTitle',p->>'spot_group_title','isStanding',coalesce((p->>'is_standing')::boolean,false),'standingAreaTitle',p->>'standing_area_title','price',p->'price','basePrice',p->'base_price','discountAmount',p->'discount_amount','currency',p->>'currency_code') ORDER BY (t->>'id')::bigint,
    (SELECT min(coalesce(ff."order",0)) FROM public.form_fields ff WHERE ff.form=f.id AND ff.product_type=product.product_type) NULLS LAST,
    coalesce(product."order",0),product.id),'[]')
   FROM jsonb_array_elements(public.order_tickets_with_seating_internal(o.id,o.data->'tickets')) t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p
   JOIN eshop.products product ON product.id=(p->>'id')::bigint
   WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint)) END,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'rawState',t.state,
   'displayStatus',CASE t.state WHEN 'ordered' THEN 'awaiting_payment' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END,
   'usageStatus',CASE t.state WHEN 'ordered' THEN 'unused' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END) ORDER BY t.id),'[]')
   FROM public.get_order_tickets_internal(o.id) t)) ORDER BY o.id),'[]')
  FROM eshop.orders o WHERE o.id=ANY(ids) AND o.state IS DISTINCT FROM 'waitlisted')) INTO result;
 IF EXISTS(SELECT FROM analytics.meta_purchase_deliveries d
   WHERE d.order_id=ANY(ids) AND d.revoked_at IS NULL AND d.status IN ('pending','sent')) THEN
  result:=result||'{"metaPurchaseConsent":true}'::jsonb;
 END IF;
 RETURN result;
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.get_customer_order_overview_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_customer_order_overview(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; p record;
BEGIN
 result:=public.get_customer_order_overview_internal(input_data->>'token',(input_data->>'order_id')::bigint);
 IF result->>'code'='200' THEN
  FOR p IN SELECT pi.data->'payment_policy' policy,pi.payment_method method FROM eshop.orders o
   JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id IN(SELECT (x->>'id')::bigint FROM jsonb_array_elements(result->'orders') x) LOOP
   PERFORM public.check_payment_client_capabilities_internal(p.policy,p.method,input_data->'client_capabilities');
  END LOOP;
 END IF;
 RETURN result;
EXCEPTION WHEN raise_exception THEN
 IF left(SQLERRM,1)='{' THEN RETURN SQLERRM::jsonb; END IF; RAISE;
END $$;
CREATE OR REPLACE FUNCTION public.get_customer_order_overview(p_token text,p_order_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_customer_order_overview(jsonb_build_object('token',p_token,'order_id',p_order_id));
$$;
REVOKE ALL ON FUNCTION public.get_customer_order_overview(jsonb),public.get_customer_order_overview(text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_customer_order_overview(jsonb),public.get_customer_order_overview(text,bigint) TO anon,authenticated,service_role;

-- SOURCE: eshop_orders/create_ticket_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_command_internal(
  p_order jsonb,p_command_id uuid,p_client_id uuid,p_context jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_symbol text; v_before_users uuid[]; v_actor_kind text; v_origin jsonb; v_form bigint;
BEGIN
  IF p_order IS NULL OR jsonb_typeof(p_order)<>'object'
    OR octet_length(p_order::text)>4194304 OR p_command_id IS NULL
    OR (v_actor IS NULL AND p_client_id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order command'; END IF;
  SELECT f.occasion INTO v_occasion FROM public.forms f
    WHERE f.key=NULLIF(p_order->>'form','')::uuid;
  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket order form not found'; END IF;
  v_hash:=encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion',v_occasion,'order',public.strip_payment_sources_internal(p_order))
      ||CASE WHEN p_context IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('administration',p_context) END)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,p_client_id,v_hash);
    v_actor_kind:='unknown';
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,v_actor,v_hash);
    v_actor_kind:='user';
  END IF;
  IF v_begin->>'disposition'='replay' THEN
    v_result := v_begin->'response';
    IF v_result#>'{data,order}' IS NOT NULL AND v_result#>>'{data,order,order_symbol}' IS NULL THEN
      v_symbol := public.read_order_identity((v_result#>>'{data,order,id}')::bigint,
        v_occasion, (SELECT organization FROM public.occasions WHERE id=v_occasion));
      IF v_symbol IS NOT NULL THEN
        v_result := jsonb_set(v_result, '{data,order,order_symbol}', to_jsonb(v_symbol));
      END IF;
    END IF;
    IF v_actor IS NULL AND p_context IS NULL THEN
      v_result:=jsonb_set(v_result,'{data,analytics}',coalesce(public.form_conversion_datalayer_internal((v_result#>>'{data,order,id}')::bigint,'free_registration'),'null'::jsonb));
    END IF;
    RETURN public.project_local_payment_reference_order_internal(v_result);
  END IF;
  IF p_order ? 'checkoutOrigin' THEN
    SELECT id INTO v_form FROM public.forms WHERE key=(p_order->>'form')::uuid;
    v_origin:=public.read_checkout_origin_internal(p_order->>'checkoutOrigin',v_form);
    IF v_origin IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',400,
        jsonb_build_object('code',400,'errorCode','CHECKOUT_CONTEXT_EXPIRED'));
    END IF;
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.create_ticket_order_internal_v1((public.strip_payment_sources_internal(p_order)-ARRAY['checkoutOrigin','discount_command_id','metaPurchaseConsent'])||CASE WHEN p_order ? 'discount' THEN jsonb_build_object('discount_command_id',p_command_id) ELSE '{}'::jsonb END);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  IF p_context IS NULL AND p_order ? 'metaPurchaseConsent' THEN
    PERFORM public.capture_meta_purchase_consent_internal((v_result#>>'{order,id}')::bigint,p_order->'metaPurchaseConsent');
  END IF;
  PERFORM public.attach_checkout_origin_internal((v_result#>>'{order,id}')::bigint,v_origin);
  PERFORM public.attach_provider_order_source_internal((v_result#>>'{order,id}')::bigint,p_command_id,p_order);
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  IF p_context IS NOT NULL THEN v_result:=v_result||jsonb_build_object('adminQuote',p_context->'quote','paymentPreparationPolicy','leased_keep_pending'); END IF;
  v_result:=public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
  -- The receipt remains frozen; first response and authorized replay project the
  -- same immutable facts, filtered through current stored form policy.
  IF v_actor IS NULL AND p_context IS NULL THEN
    PERFORM public.record_form_conversion_internal((v_result#>>'{data,order,id}')::bigint);
    v_result:=jsonb_set(v_result,'{data,analytics}',coalesce(
      public.form_conversion_datalayer_internal((v_result#>>'{data,order,id}')::bigint,'free_registration'),'null'::jsonb));
  END IF;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_command_internal(jsonb,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Released RPC signature and ordinary checkout hashes remain unchanged.
CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(p_order jsonb,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.create_ticket_order_command_internal(p_order,p_command_id,p_client_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) TO anon,authenticated;

-- SOURCE: eshop_waitlist/commands.sql
-- Edge is the trusted preparation boundary for random capabilities and sealed email.
-- It verifies the bearer user; SQL still checks the explicit actor's occasion rights.
CREATE OR REPLACE FUNCTION public.sanitize_waitlist_history_internal(p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(key,public.sanitize_waitlist_history_internal(value)),'{}') INTO result
  FROM jsonb_each(p_value) WHERE lower(key) NOT IN
   ('token','secret','password','offertoken','managetoken','capability','waitlistenvelope','sealed','tokenhash') AND lower(key) NOT IN(SELECT lower(source_field) FROM eshop.payment_providers WHERE source_field IS NOT NULL);
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(value) ORDER BY ordinal),'[]') INTO result
  FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,ordinal);
  RETURN result;
 END IF;
 RETURN p_value;
END $$;
CREATE OR REPLACE FUNCTION public.snapshot_waitlist_tickets_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(to_jsonb(p)||jsonb_build_object('answers',p.data,'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(p.id))) ORDER BY created_at,id),'[]')
 FROM public.get_order_tickets_internal(p_order) p;
$$;
REVOKE ALL ON FUNCTION public.sanitize_waitlist_history_internal(jsonb),public.snapshot_waitlist_tickets_internal(bigint)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.execute_waitlist_command_client_sync_v1(
 p_operation text,p_payload jsonb,p_command_id uuid,p_client_id uuid,p_actor uuid DEFAULT NULL,p_deliveries jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; occ bigint; oid bigint; offer uuid; mode text; c jsonb; result jsonb; claim jsonb;
 hash text; selected bigint[]; expected integer; changed integer; recipients jsonb; r jsonb; delivery jsonb;
 person jsonb; created_ticket bigint; slot_ids uuid[]; expiry timestamptz; f public.forms; people jsonb; n integer; before_users uuid[];
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
 PERFORM public.check_occasion_writable(occ);
 IF occ IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Match checkout and cancellation: scope precedes the form/order parents.
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 IF p_operation IN ('send','cancel') AND NOT public.can_write_orders_as_actor_internal(p_actor,occ) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 previous_sub:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
 hash:=encode(extensions.digest(jsonb_build_object('operation',p_operation,'payload',CASE WHEN p_payload ? 'orderDetails' THEN jsonb_set(p_payload,'{orderDetails}',public.strip_payment_sources_internal(p_payload->'orderDetails')) ELSE p_payload END,'actor',p_actor)::text,'sha256'),'hex');
 BEGIN
  IF p_actor IS NULL THEN claim:=public.begin_anonymous_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_client_id,hash); actor_kind:='unknown';
  ELSE claim:=public.begin_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_actor,hash); actor_kind:='user'; END IF;
 EXCEPTION WHEN invalid_parameter_value THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN jsonb_build_object('code',409,'errorCode','COMMAND_PAYLOAD_CONFLICT');
 END;
 IF claim->>'disposition'='replay' THEN
  result:=claim->'response';
  IF p_actor IS NULL AND p_operation IN ('register','accept') THEN
   result:=jsonb_set(result,'{data,analytics}',coalesce(public.form_conversion_datalayer_internal((result#>>'{data,order,id}')::bigint,CASE WHEN p_operation='register' THEN 'waitlist' ELSE 'free_registration' END),'null'::jsonb));
  END IF;
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN public.project_local_payment_reference_order_internal(result); END IF;
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
   people:=public.normalize_form_ticket_answers_internal(fid,p_payload->'tickets');
   PERFORM public.validate_waitlist_answers_internal(fid,p_payload,people,true);
   IF nullif(p_payload->>'email','') IS NULL THEN RAISE EXCEPTION 'Email required'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(people) p CROSS JOIN LATERAL jsonb_array_elements(coalesce(p->'fields','[]')) a WHERE a ? 'product_type') THEN
    RAISE EXCEPTION 'Waitlist does not accept products'; END IF;
   oid:=public.allocate_ticket_order_identity_internal(fid);
   UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=p_payload-'tickets'-'token' WHERE id=oid;
   FOR person IN SELECT * FROM jsonb_array_elements(people) LOOP
    INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data,waitlist_queue_at)
     VALUES(occ,'waitlisted',NULL,public.extract_ticket_answers_internal(fid,person),clock_timestamp()) RETURNING id INTO created_ticket;
    INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,created_ticket,NULL); END LOOP;
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
    SELECT array_agg(id) INTO selected FROM (SELECT p.id FROM eshop.tickets p WHERE p.state='waitlisted'
     AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=p.id AND x."order"=oid)
     AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE ticket_id=p.id AND outcome='pending')
     ORDER BY waitlist_queue_at,created_at,id LIMIT n FOR UPDATE) tickets;
    IF coalesce(cardinality(selected),0)<>n THEN RAISE EXCEPTION 'OFFER_CHANGED'; END IF;
    INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision) VALUES(oid,fid,p_actor,expiry,f.capacity_revision) RETURNING id INTO offer;
    INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id) SELECT offer,id,fid FROM unnest(selected) id;
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
   SELECT array_agg(x::bigint) INTO selected FROM jsonb_array_elements_text(p_payload->'ticketIds') x; n:=coalesce(cardinality(selected),0);
   IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(selected) x) THEN RAISE EXCEPTION 'Invalid persons'; END IF;
   IF n<>(SELECT count(*) FROM public.get_order_tickets_internal(oid) WHERE id=ANY(selected) AND state='waitlisted') THEN
    RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   IF p_operation IN ('decline','cancel') AND n<>(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND outcome='pending' AND ticket_id=ANY(selected)) THEN
    RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   UPDATE eshop.waitlist_offer_slots SET outcome=CASE WHEN p_operation='decline' THEN 'declined' ELSE 'cancelled' END,updated_at=clock_timestamp()
    WHERE ticket_id=ANY(selected) AND outcome='pending' AND (p_operation='withdraw' OR offer_id=offer);
   UPDATE eshop.tickets SET state=CASE WHEN p_operation='withdraw' THEN 'storno' ELSE state END,
    waitlist_queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=ANY(selected);
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
     'ticketIds',CASE WHEN p_operation='register' THEN
       (SELECT jsonb_agg(id ORDER BY created_at,id) FROM public.get_order_tickets_internal(oid))
       ELSE to_jsonb(selected) END,
     'tickets',public.snapshot_waitlist_tickets_internal(oid)));
   END IF;
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist order','changedFields',jsonb_build_array('waitlistSummary','tickets')));
  END IF;
  IF p_operation='register' THEN
   PERFORM public.notification_center_order_internal(oid,'waitlist_registered','created',p_actor);
  ELSIF p_operation='accept' THEN
   PERFORM public.notification_center_order_internal((result#>>'{order,id}')::bigint,'offer_accepted',offer::text||':'||p_command_id,p_actor,
    jsonb_build_object('offerId',offer,'count',jsonb_array_length(p_payload->'ticketIds')));
  ELSIF p_operation='withdraw' THEN
   PERFORM public.notification_center_order_internal(oid,'order_cancelled','withdraw:'||p_command_id,p_actor,jsonb_build_object('count',n));
  ELSIF p_operation='decline' THEN
   PERFORM public.notification_center_order_internal(oid,'offer_declined',offer::text||':'||p_command_id,p_actor,jsonb_build_object('offerId',offer,'count',n));
  END IF;
  PERFORM public.notification_center_form_capacity_internal(fid,p_actor);
  result:=result||jsonb_build_object('capacity',public.get_form_capacity_snapshot_internal(fid));
 EXCEPTION WHEN OTHERS THEN
  result:=CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',409,'errorCode',SQLERRM,'message',SQLERRM) END;
  result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
   CASE WHEN (result->>'code')::integer BETWEEN 200 AND 599 THEN (result->>'code')::integer ELSE 409 END,result);
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN result;
 END;
 entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','form','entityId',fid,'operation','update','safeLabel','Form capacity','changedFields',jsonb_build_array('capacity','registrationMode')));
 IF p_operation='accept' AND p_payload ? 'administrativeApproval' THEN
  result:=result||jsonb_build_object('adminQuote',p_payload#>'{administrativeApproval,quote}',
   'adminScope',p_payload#>'{administrativeApproval,scope}','paymentPreparationPolicy','leased_keep_pending'); END IF;
 result:=public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.waitlist.'||p_operation,entity_changes,before_users,result,actor_kind);
 IF p_actor IS NULL AND p_operation IN ('register','accept') THEN
  PERFORM public.record_form_conversion_internal((result#>>'{data,order,id}')::bigint);
  result:=jsonb_set(result,'{data,analytics}',coalesce(public.form_conversion_datalayer_internal((result#>>'{data,order,id}')::bigint,CASE WHEN p_operation='register' THEN 'waitlist' ELSE 'free_registration' END),'null'::jsonb));
 END IF;
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) TO service_role;

-- SOURCE: eshop_transactions/apply_transaction_pairing.sql
CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
  v_order_ids bigint[];
  v_order_bindings jsonb;
  v_locked_order_bindings jsonb;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id));
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;

  -- The transaction row stabilizes the old target (also held by ingest/matcher).
  -- Acquire every stored old/new form and order before either payment row,
  -- matching product edit and cancellation. Never trust a caller's scope list.
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]),
    coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_order_ids,v_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  PERFORM public.lock_order_capacity_scope_internal(v_order_ids);
  SELECT coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_locked_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  IF v_order_bindings IS DISTINCT FROM v_locked_order_bindings THEN
    RAISE EXCEPTION 'PAIRING_ORDER_SCOPE_CHANGED' USING ERRCODE='40001';
  END IF;
  PERFORM 1 FROM eshop.payment_info WHERE id IN (v_old_payment_info_id,p_payment_info_id)
  ORDER BY id FOR UPDATE;

  -- A settled movement is immutable through the generic attach/unlink API.
  -- Cash voids and evidenced bank reclassification have their explicit owner.
  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id)
     AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION';
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0
     AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b WHERE b.id=v_transaction.bank_account_id
       AND upper(b.type)='CASH' AND v_transaction.transaction_type='manual'
       AND v_transaction.ingest_source='manual') THEN
    RAISE EXCEPTION 'OUTGOING_REQUIRES_REFUND_CLASSIFICATION';
  END IF;
  IF v_old_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.assert_payment_refund_reservations_internal(v_old_payment_info_id,greatest(v_transaction.amount,0));
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0 THEN
    PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-v_transaction.amount);
  END IF;

  IF p_actor_kind='user' THEN
    FOR v_order_id IN SELECT id FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      PERFORM public.check_order_is_mutable(v_order_id);
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF public.payment_method_is_online_internal(v_target.payment_method) THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_target.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b
      WHERE b.id=v_transaction.bank_account_id AND b.type='CASH' AND v_transaction.transaction_type='manual') THEN
      RAISE EXCEPTION 'CASH_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_transaction.transaction_type='manual' THEN
      IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
        JOIN eshop.orders o ON o.occasion=oc.id JOIN eshop.bank_accounts b ON b.id=link.bank_account
        WHERE o.payment_info=v_target.id AND b.id=v_transaction.bank_account_id ) THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
    END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(v_old_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(p_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN
      PERFORM public.recalculate_order_payment_status(v_order_id);
      IF v_transaction.amount>0 AND v_transaction.transaction_type IS DISTINCT FROM 'manual'
        AND v_transaction.ingest_source IS DISTINCT FROM 'manual' THEN
        PERFORM public.record_form_paid_conversion_internal(v_order_id);
      END IF;
    END IF;
  END IF;


  IF v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.notification_center_events e
     JOIN eshop.orders o ON o.occasion=e.occasion AND o.id=(e.data->>'orderId')::bigint
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id AND o.payment_info=v_old_payment_info_id;
    UPDATE public.notification_center_events e SET status='resolved' FROM eshop.orders o
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id
      AND o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion AND o.payment_info=v_old_payment_info_id;
    IF p_payment_info_id IS NOT NULL AND v_transaction.amount>0 THEN
      FOR v_order_id IN SELECT id FROM eshop.orders WHERE payment_info=p_payment_info_id LOOP
       PERFORM public.notification_center_payment_fact_internal(v_order_id,'transaction',p_transaction_id::text,
        v_transaction.amount,v_transaction.currency::text,coalesce(v_transaction.date,now()),
        EXISTS(SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_id=p_transaction_id AND new_payment_info_id IS NOT NULL));
      END LOOP;
    END IF;
  END IF;
  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE: payment_providers/effects.sql
-- Shared admission effect. Callers own authorization and financial interpretation.
-- This owner never manufactures a provider observation or changes original prices.
-- Lock hierarchy: payment policy fence -> capacity/forms -> order -> payment ->
-- provider attempt -> tickets. Callers that hold later locks must own the parents.
CREATE OR REPLACE FUNCTION public.cancel_online_order_admission_internal(p_order bigint,p_state text)
RETURNS bigint[] LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; cancelled bigint[];
BEGIN
 IF p_state IS NULL OR p_state NOT IN ('storno','expired') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid admission cancellation state'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info
  AND public.payment_method_is_online_internal(pi.payment_method)) THEN
  RAISE EXCEPTION 'ONLINE_ADMISSION_SOURCE_REQUIRED'; END IF;
 IF o.state=p_state THEN RETURN '{}'::bigint[]; END IF;
 SELECT array_agg(t.id ORDER BY t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t
 WHERE coalesce(t.state,'') NOT IN ('used','storno');
 PERFORM public.internal_storno_tickets_221(cancelled);
 UPDATE eshop.orders SET state=p_state,email_payment_version=email_payment_version+1,
  updated_at=clock_timestamp() WHERE id=o.id;
 PERFORM public.cancel_order_email_intents(o.id);
 RETURN coalesce(cancelled,'{}');
END $$;
REVOKE ALL ON FUNCTION public.cancel_online_order_admission_internal(bigint,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- Lock order: capacity/form scope -> order -> payment -> provider attempt -> tickets.
-- All facts are read back from connector storage. No caller-supplied markPaid/amount.
CREATE OR REPLACE FUNCTION public.apply_provider_payment_effects_internal(
 p_provider text,p_attempt uuid,p_revision text,p_before jsonb,p_expired boolean DEFAULT false,
 p_unresolved boolean DEFAULT false,p_action text DEFAULT 'observe',p_tickets bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE context jsonb; prior jsonb; o eshop.orders; pi eshop.payment_info; totals record; projection jsonb; transition jsonb;
 received numeric; refunded numeric; payment_time timestamptz; deadline timestamptz; cancelled bigint[];
 conflict boolean; action_required boolean; changed boolean:=false; args jsonb:=jsonb_build_object('attemptId',p_attempt); decision jsonb; fact jsonb;
BEGIN
 IF p_provider IS NULL OR p_provider='bank' OR p_attempt IS NULL OR nullif(p_revision,'') IS NULL
  OR p_action IS NULL OR p_action NOT IN ('observe','keep','cancel_selected') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_INPUT_INVALID'; END IF;
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS NULL OR jsonb_typeof(context)<>'object' OR NOT context ?& ARRAY['attemptId','orderId','paymentId','connectionId','organizationId','unitId','accountId','livemode','amountMinor','currency','reservationExpiresAt','state','incomplete','receivedMinor','refundedMinor','paymentTime','decisions']
  OR context->>'attemptId' IS DISTINCT FROM p_attempt::text OR nullif(context->>'accountId','') IS NULL
  OR nullif(context->>'connectionId','') IS NULL OR (context->>'connectionId')::uuid IS NULL
  OR context->>'state' IS NULL OR context->>'state' NOT IN ('preparing','open','uncertain','paid','expired','action_required')
  OR jsonb_typeof(context->'livemode') IS DISTINCT FROM 'boolean' OR jsonb_typeof(context->'incomplete') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(context->'decisions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(context->'amountMinor') IS DISTINCT FROM 'number' OR jsonb_typeof(context->'receivedMinor') IS DISTINCT FROM 'number'
  OR jsonb_typeof(context->'refundedMinor') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'PAYMENT_EFFECT_CONTEXT_INVALID'; END IF;
 prior:=context;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[(context->>'orderId')::bigint]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(context->>'orderId')::bigint FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 PERFORM public.payment_provider_call_internal(p_provider,'effect_lock',args);
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS DISTINCT FROM prior OR pi.id IS DISTINCT FROM (context->>'paymentId')::bigint
  OR pi.payment_method IS DISTINCT FROM p_provider OR pi.amount*100 IS DISTINCT FROM (context->>'amountMinor')::numeric
  OR pi.currency_code::text IS DISTINCT FROM context->>'currency'
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=(context->>'organizationId')::bigint AND unit=(context->>'unitId')::bigint)
  OR (p_before IS NOT NULL AND p_before->>'method' IS DISTINCT FROM p_provider) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_SCOPE_INVALID'; END IF;
 IF (context->>'amountMinor')::numeric<=0 OR (context->>'amountMinor')::numeric<>trunc((context->>'amountMinor')::numeric) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 received:=(context->>'receivedMinor')::numeric/100;refunded:=(context->>'refundedMinor')::numeric/100;
 deadline:=(context->>'reservationExpiresAt')::timestamptz;payment_time:=(context->>'paymentTime')::timestamptz;
 IF received<0 OR refunded<0 OR received>pi.amount OR refunded>received OR deadline IS NULL
  OR received*100<>trunc(received*100) OR refunded*100<>trunc(refunded*100)
  OR (received>0 AND payment_time IS NULL) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 action_required:=context->>'state'='action_required';
 IF p_action<>'observe' THEN
  IF auth.uid() IS NULL OR NOT public.can_write_orders(o.occasion) OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=(context->>'organizationId')::bigint)
   THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF refunded<=0 OR refunded>=pi.amount OR context->>'state'<>'paid' OR o.state NOT IN ('paid','sent') OR totals.invalid_identity
   OR context->'incomplete'='true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_REQUIRED'; END IF;
  IF (p_action='keep' AND cardinality(p_tickets)<>0) OR (p_action='cancel_selected' AND cardinality(p_tickets) NOT BETWEEN 1 AND 1000)
   OR EXISTS(SELECT 1 FROM unnest(p_tickets) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'PAYMENT_REFUND_TICKET_UNAVAILABLE'; END IF;
  PERFORM 1 FROM eshop.tickets WHERE id=ANY(p_tickets) ORDER BY id FOR UPDATE;
  IF p_action='cancel_selected' THEN
   PERFORM public.internal_storno_tickets_221(p_tickets);
   UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  END IF;
  decision:=public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason',CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,'revision',p_revision,'tickets',to_jsonb(p_tickets)));
  PERFORM public.enqueue_order_wallet_internal(o.id);
  RETURN jsonb_build_object('changed',true,'decisionId',decision,'payment',public.provider_order_payment_projection_internal(o.id));
 END IF;
 IF conflict AND NOT context->'decisions' ? 'financial_conflict' THEN
  action_required:=true;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','financial_conflict','revision',p_revision));
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 IF received>=pi.amount AND refunded<pi.amount AND NOT conflict AND context->'incomplete'='false'::jsonb THEN
  IF o.state IN ('ordered','created') AND payment_time<=deadline THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'PAYMENT_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   action_required:=true;
   PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
   IF NOT context->'decisions' ? 'late_payment' THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','late_payment','revision',p_revision)); END IF;
  END IF;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||jsonb_build_object('state',CASE WHEN action_required THEN 'action_required' ELSE 'paid' END));
  IF NOT action_required THEN
   PERFORM public.record_form_paid_conversion_internal(o.id);
  END IF;
 END IF;
 IF refunded>=pi.amount AND received>0 THEN
  IF NOT context->'decisions' ? 'full_refund' THEN
   cancelled:=public.cancel_online_order_admission_internal(o.id,'storno');
   PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','full_refund','revision',p_revision,'tickets',to_jsonb(coalesce(cancelled,'{}'))));
   changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND (p_expired OR (p_unresolved AND deadline<=clock_timestamp())) AND o.state='ordered' THEN
  cancelled:=public.cancel_online_order_admission_internal(o.id,'expired');
  -- Releasing inventory does not prove financial absence. Keep uncertain recovery alive.
  IF NOT p_unresolved THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"expired"}'); END IF;
  changed:=true;
 END IF;
 projection:=public.provider_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM p_before->>'admissionState' AND
  (projection->>'status'='disputed' OR p_before->>'status'='disputed' OR projection->'reconciliationPending'='true'::jsonb OR p_before->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('revision',p_revision,'reason',
   CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN p_before->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END));
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;

 FOR fact IN SELECT value FROM jsonb_array_elements(public.payment_provider_call_internal(p_provider,'notification_facts',args)) LOOP
  PERFORM public.notification_center_payment_fact_internal(o.id,p_provider,fact->>'identity',(fact->>'amount')::numeric,fact->>'currency',(fact->>'occurredAt')::timestamptz);
 END LOOP;
 PERFORM public.notification_center_payment_problem_internal(o.id,action_required OR conflict,
  CASE WHEN conflict THEN 'financial_conflict' ELSE 'action_required' END);
 PERFORM public.enqueue_order_wallet_internal(o.id);
 RETURN jsonb_build_object('changed',changed,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
