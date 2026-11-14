-- Presentation-only ticket and application terminology from the occasion feature.

-- SOURCE: eshop/order_item_terminology.sql
-- Presentation only. Issuance, scanning and delivery keep their own policies.
CREATE OR REPLACE FUNCTION public.uses_ticket_terminology_internal(p_features jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER
SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(
  CASE WHEN jsonb_typeof(p_features)='array' THEN p_features ELSE '[]'::jsonb END
 ) feature WHERE feature->>'code'='ticket' AND feature->'is_enabled'='true'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.uses_ticket_terminology_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: sale_opening_notifications/settings.sql
-- Invoked only inside the existing form aggregate command, under its form lock.
CREATE OR REPLACE FUNCTION public.sync_sale_opening_settings_internal(p_form bigint,p_previous jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; d jsonb; c public.sale_opening_campaigns; a jsonb; enabled boolean;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 d:=public.normalize_form_metadata_internal(f.data);
 IF coalesce(public.normalize_form_metadata_internal(p_previous)#>>'{schedule,countdown_title}','') LIKE '%form-sale-opening-notification%'
  AND coalesce(d#>>'{schedule,countdown_title}','') NOT LIKE '%form-sale-opening-notification%'
  AND coalesce((d#>>'{sale_opening_notifications,enabled}')::boolean,false) THEN
  d:=jsonb_set(d,'{sale_opening_notifications,collection_paused}','true');
  UPDATE public.forms SET data=d WHERE id=p_form;
 END IF;
 enabled:=coalesce((d#>>'{sale_opening_notifications,enabled}')::boolean,false);
 SELECT * INTO c FROM public.sale_opening_campaigns WHERE form_id=p_form FOR UPDATE;
 a:=public.get_form_availability_snapshot_internal(p_form);
 IF enabled AND c.id IS NULL THEN
  IF NOT f.is_open OR (a->>'startAt')::timestamptz IS NULL OR (a->>'startAt')::timestamptz<=clock_timestamp()
   OR public.is_demo_occasion(f.occasion) THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_requires_future_public_form'; END IF;
  INSERT INTO public.sale_opening_campaigns(form_id) VALUES(p_form);
 ELSIF c.id IS NOT NULL AND c.phase<>'cancelled' THEN
  IF NOT enabled THEN
   UPDATE public.sale_opening_campaigns SET phase='cancelled',revision=revision+1,closed_at=clock_timestamp() WHERE id=c.id;
   UPDATE public.sale_opening_subscriptions SET state='closed',closed_at=clock_timestamp(),version=version+1
    WHERE campaign_id=c.id AND state='active';
   UPDATE public.sale_opening_capabilities SET revoked_at=clock_timestamp() WHERE subscription_id IN
    (SELECT id FROM public.sale_opening_subscriptions WHERE campaign_id=c.id) AND revoked_at IS NULL;
  ELSIF (a->>'startAt')::timestamptz IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='explicitly_end_sale_opening_notifications_before_removing_date';
  END IF;
 ELSIF enabled AND c.phase='cancelled' THEN
  RAISE invalid_parameter_value USING MESSAGE='sale_opening_campaign_already_ended';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.sync_sale_opening_settings_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.sale_opening_has_tickets_internal(p_form bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.uses_ticket_terminology_internal(o.features)
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form),false);
$$;
REVOKE ALL ON FUNCTION public.sale_opening_has_tickets_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_sale_opening_projection_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH input AS (SELECT f.*,public.get_effective_form_data(f.id) metadata,
  public.get_form_availability_snapshot_internal(f.id) availability,c.phase
  FROM public.forms f LEFT JOIN public.sale_opening_campaigns c ON c.form_id=f.id WHERE f.id=p_form),
 reason AS (SELECT *,CASE
  WHEN public.is_demo_occasion(occasion) OR phase IS NULL OR phase<>'armed' OR
   NOT coalesce((metadata#>>'{sale_opening_notifications,enabled}')::boolean,false) THEN 'disabled'
  WHEN coalesce((metadata#>>'{sale_opening_notifications,collection_paused}')::boolean,false) THEN 'paused'
  WHEN NOT is_open THEN 'manual_closed'
  WHEN availability->>'gate'<>'before_start' THEN 'not_before_start'
  ELSE NULL END unavailable FROM input)
 SELECT jsonb_build_object('canSubscribe',unavailable IS NULL,'hasTickets',public.sale_opening_has_tickets_internal(id),'reason',unavailable,
  'startAt',availability->'startAt','timeZone',public.get_waitlist_form_timezone_internal(id),'serverTime',statement_timestamp()) FROM reason;
$$;
REVOKE ALL ON FUNCTION public.get_sale_opening_projection_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

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
  'payment',public.customer_order_payment_internal(o.id),
  'answers',public.customer_order_answers_internal(f.id,o.data,false),
  'ticketIds',(SELECT coalesce(jsonb_agg(t.id ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t),
  'items',CASE WHEN o.state='preparing_payment' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticketId',t->'id','id',p->'id','title',p->>'title','spotTitle',p->>'spot_title','spotGroupTitle',p->>'spot_group_title','isStanding',coalesce((p->>'is_standing')::boolean,false),'standingAreaTitle',p->>'standing_area_title','price',p->'price','currency',p->>'currency_code') ORDER BY (t->>'id')::bigint,
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

-- SOURCE: occasion_setup/sale_status.sql
-- Read-only summary inside the already authorized unit catalogue. Checkout and
-- waitlist commands remain the owners of availability and reservations.
CREATE OR REPLACE FUNCTION public.get_occasion_sale_forms_internal(p_occasion bigint,p_at timestamptz DEFAULT statement_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 -- LATERAL aliases can be expanded once for every JSON field/CASE reference.
 -- Keep each form's configuration and capacity mode as one request-local value.
 WITH form_data AS MATERIALIZED (
  SELECT f.*,public.get_effective_form_data(f.id) AS effective_data
  FROM public.forms f WHERE f.occasion=p_occasion
 ), form_modes AS MATERIALIZED (
  SELECT f.*,public.get_form_registration_mode_internal(f.id,
   greatest(p_at,nullif(coalesce(f.effective_data#>>'{schedule,start_time}',
    f.effective_data->>'start_time'),'')::timestamptz)) AS registration_mode
  FROM form_data f
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',f.id,'is_open',f.is_open,
  'has_tickets',public.uses_ticket_terminology_internal((SELECT features FROM public.occasions WHERE id=p_occasion)),
  'is_preparation',coalesce((f.effective_data#>>'{schedule,sale_preparation}')::boolean,false),
  'start_time',nullif(coalesce(f.effective_data#>>'{schedule,start_time}',f.effective_data->>'start_time'),''),
  'end_time',nullif(coalesce(f.effective_data#>>'{schedule,end_time}',f.effective_data->>'end_time'),''),
  'enable_countdown',coalesce((coalesce(f.effective_data#>>'{schedule,enable_countdown}',f.effective_data->>'enable_countdown'))::boolean,false),
  'registration_mode',f.registration_mode,
  'has_availability',CASE
   WHEN f.registration_mode='blueprint' THEN EXISTS (
    -- Resolve the form's small offer before running expensive inventory checks.
    -- Without this boundary a hash join can evaluate every system product.
    WITH offered_products AS MATERIALIZED (
     SELECT p.id,offered.has_capacity
     FROM public.blueprint_form_products_internal(f.id) offered
     JOIN eshop.products p ON p.id=offered.product
     WHERE NOT p.is_hidden
    )
    SELECT 1 FROM offered_products p
    WHERE public.is_product_dynamically_available(p.id)
    AND (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0
    AND (p.has_capacity OR EXISTS (
     SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
     WHERE sb.blueprint=f.blueprint AND s.product=p.id AND NOT sb.blocked
      AND NOT EXISTS (
       SELECT 1 FROM unnest(public.blueprint_selection_unit_spots_internal(s.id)) member(id)
       JOIN eshop.spots occupied ON occupied.id=member.id
       WHERE occupied.order_product_ticket IS NOT NULL OR occupied.state='black'
        OR (occupied.secret IS NOT NULL AND occupied.secret_expiration_time>p_at))
    )))
   WHEN f.registration_mode='regular' THEN NOT EXISTS (
    WITH required_fields AS MATERIALIZED (
     SELECT ff.product_type FROM public.form_fields ff
     JOIN eshop.product_types pt ON pt.id=ff.product_type
     WHERE ff.form=f.id AND NOT coalesce(ff.is_hidden,false)
     AND (pt.type='spot' OR ff.is_required)
    )
    SELECT 1 FROM required_fields ff WHERE NOT EXISTS (
      WITH field_products AS MATERIALIZED (
       SELECT p.id FROM eshop.products p
       WHERE p.product_type=ff.product_type AND NOT p.is_hidden
      )
      SELECT 1 FROM field_products p WHERE public.is_product_dynamically_available(p.id)
      AND (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0))
   ELSE f.registration_mode='waitlist' END
 ) ORDER BY f.id),'[]'::jsonb)
 FROM form_modes f;
$$;
REVOKE ALL ON FUNCTION public.get_occasion_sale_forms_internal(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: scanning/sessions.sql
CREATE OR REPLACE FUNCTION public.scanner_session_internal(p_session uuid,p_token text,p_allow_expired boolean DEFAULT false)
RETURNS public.scanner_sessions LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; secret text;
BEGIN
 -- Shared policy then session locks also serialize revocation and settings changes.
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=(SELECT occasion_id FROM public.scanner_sessions WHERE id=p_session) FOR SHARE;
 SELECT * INTO s FROM public.scanner_sessions WHERE id=p_session FOR SHARE;
 IF s.id IS NULL OR p_token IS NULL OR s.token_hash<>encode(digest(p_token,'sha256'),'hex') THEN
  RAISE SQLSTATE 'PT401' USING MESSAGE='invalid_scanner_session'; END IF;
 IF s.actor_user_id IS NOT NULL AND (auth.uid() IS DISTINCT FROM s.actor_user_id OR NOT public.scanner_can_manage_settings_internal(s.occasion_id)) THEN
  RAISE SQLSTATE 'PT403' USING MESSAGE='scanner_actor_changed'; END IF;
 SELECT oh.secret INTO secret FROM public.occasions o JOIN public.occasions_hidden oh ON oh.id=o.occasion_hidden WHERE o.id=s.occasion_id;
 IF NOT p_allow_expired AND (s.revoked_at IS NOT NULL OR s.expires_at<=now() OR s.epoch<>cfg.epoch
 OR (s.access_origin='scan_link' AND (
   s.scan_secret_hash IS DISTINCT FROM encode(digest(secret,'sha256'),'hex')
   OR NOT EXISTS (SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(secret) proof WHERE proof.id=s.occasion_id)
 ))) THEN
  RAISE SQLSTATE 'PT401' USING MESSAGE='scanner_session_expired'; END IF;
 RETURN s;
END $$;
CREATE OR REPLACE FUNCTION public.open_scanner_session(p_scan_code text DEFAULT NULL,p_occasion bigint DEFAULT NULL,p_device_name text DEFAULT 'Hlavní vstup')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; s public.scanner_sessions; cfg public.scanner_settings; token text; origin text; sec text;
BEGIN
 IF NOT public.check_scan_attempt_budget_v1(p_occasion) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now()); END IF;
 IF p_scan_code IS NOT NULL THEN
  SELECT * INTO oc FROM public.get_scanner_occasion_for_scan_code_internal(p_scan_code) LIMIT 1;
  -- record assignment above must match the occasion row exactly
  origin:='scan_link'; sec:=p_scan_code;
 ELSE
  PERFORM public.scanner_require_settings_editor_internal(p_occasion);
  SELECT * INTO oc FROM public.occasions WHERE id=p_occasion; origin:='authenticated';
 END IF;
 IF oc.id IS NULL THEN PERFORM public.admit_scan_access_v1(NULL,false); RETURN jsonb_build_object('code',401,'reason','invalid_scan_code','server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(oc.id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 INSERT INTO public.scanner_settings(occasion_id,config) VALUES(oc.id,public.scanner_default_settings_internal(oc.id)) ON CONFLICT DO NOTHING;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=oc.id FOR SHARE;
 token:=encode(gen_random_bytes(32),'hex');
 INSERT INTO public.scanner_sessions(occasion_id,actor_user_id,access_origin,token_hash,scan_secret_hash,epoch,device_name,expires_at,offline_until)
 VALUES(oc.id,CASE WHEN origin='authenticated' THEN auth.uid() END,origin,encode(digest(token,'sha256'),'hex'),encode(digest(sec,'sha256'),'hex'),cfg.epoch,left(p_device_name,80),now()+interval '12 hours',
 now()+make_interval(hours=>CASE WHEN (cfg.config#>>'{offline,enabled}')::boolean THEN (cfg.config#>>'{offline,max_hours}')::integer ELSE 0 END)) RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'server_time',now(),'data',jsonb_build_object('session_id',s.id,'token',token,'occasion_id',oc.id,'organization_id',oc.organization,
 'title',oc.title,'hasTickets',public.uses_ticket_terminology_internal(oc.features),'occasion_link',oc.link,'epoch',s.epoch,'expires_at',s.expires_at,'offline_until',s.offline_until,'settings_revision',cfg.revision,'settings',cfg.config,'device_name',s.device_name,
 'capabilities',jsonb_build_object('search_tickets',(cfg.config#>>'{manual_search,tickets}')::boolean,'search_users',(cfg.config#>>'{manual_search,users}')::boolean,
 'settings',public.scanner_can_manage_settings_internal(oc.id),'event_history',auth.uid() IS NOT NULL AND public.can_write_orders(oc.id),'offline',(cfg.config#>>'{offline,enabled}')::boolean)));
END $$;
CREATE OR REPLACE FUNCTION public.revoke_scanner_session(p_session uuid,p_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions;
BEGIN
 SELECT * INTO s FROM public.scanner_sessions WHERE id=p_session;
 IF p_token IS NOT NULL THEN s:=public.scanner_session_internal(p_session,p_token,true);
 ELSE PERFORM public.check_is_editor_order_on_occasion(s.occasion_id); END IF;
 UPDATE public.scanner_sessions SET revoked_at=now() WHERE id=p_session;
 RETURN jsonb_build_object('code',200,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.scanner_session_internal(uuid,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.open_scanner_session(text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.open_scanner_session(text,bigint,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.revoke_scanner_session(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_scanner_session(uuid,text) TO anon,authenticated,service_role;
