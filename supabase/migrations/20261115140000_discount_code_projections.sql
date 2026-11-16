-- Discount sale snapshots in customer overviews, after shared customer-policy projection owners.

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

-- SOURCE: others/get_ticket_layout_write_contract_v1.sql
-- Generated by automation/generate_ticket_layout_write_contract.py.
-- A readiness probe, not a write dispatcher or a grant to any new executor.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_write_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ready boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 SELECT coalesce(bool_and(p.oid IS NOT NULL AND md5(btrim(p.prosrc,E' \n\r\t'))=expected.body_md5
  AND p.prosecdef=expected.definer AND (EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
   WHERE regexp_replace(setting,'[[:space:]]','','g')='search_path=public,extensions')=expected.needs_path)),false)
 INTO ready FROM (VALUES
  ('public.active_membership(boolean,boolean)','2dd31a8b531c745b2ed16af90e0260ea',false,false),
  ('public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)','7a9559975e19ae53e8b15a23a4b8b68a',false,false),
  ('public.blueprint_write_rule(boolean,boolean)','0c68680b6879b48966f2bf3bc0210d37',false,false),
  ('public.can_create_occasion(bigint)','f13b39c68d18a53dbb79125c23d7dc23',true,true),
  ('public.can_delete_orders(bigint)','8db8081db5e65a6948f4cefe1b109f93',true,true),
  ('public.can_edit_occasion(bigint,bigint)','af8850fc3a3bed9a06274880669c340d',true,true),
  ('public.can_edit_ticket_layout(bigint)','bb45fdb1e72cd16860e9719c8f9ab84f',true,true),
  ('public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint)','f6ee7e318387522f6146e13b3c4854f7',true,true),
  ('public.can_manage_occasion_participants(bigint)','8cb3dd4327ae5c9302da134994dd5d07',true,true),
  ('public.can_manage_unit_users(bigint)','700c32f30396d2bc5bb21553c2f42ca8',true,true),
  ('public.can_preview_ticket_readonly(bigint)','48efb47c1529b5106cbab4edf641fd0a',true,true),
  ('public.can_read_information_editor_bundle(bigint)','ba203be730cbf9acca46c0b3e63363ad',true,true),
  ('public.can_read_map_editor_bundle(bigint)','02c9fbcfcd61c8598e88407a9f3070fa',true,true),
  ('public.can_read_orders(bigint)','795b29c048acb37bc949683bfc586f43',true,true),
  ('public.can_read_ticket_layout(bigint)','50105a20a0ff5d89389f80e5dd9f891c',true,true),
  ('public.can_read_unit_users(bigint)','76b08038f169406ba1ba56652e44608e',true,true),
  ('public.can_write_orders(bigint)','680cbd3862cc0f6abc89d7d2497c7fb1',true,true),
  ('public.can_write_orders_as_actor_internal(uuid,bigint)','064d9d9fe95cfbb62ccbe39efa120a62',false,false),
  ('public.cleaning_crew_navigation_rule(boolean)','30e845096d248f7112e1d570bb489e6a',false,false),
  ('public.client_activity_read_rule(boolean,boolean,boolean)','002ce7bce477126bcdab9e94db022734',false,false),
  ('public.client_commit_read_rule(boolean,boolean,boolean)','229306cbca2f8a160f4d66b2598fc127',false,false),
  ('public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean)','9f7f53c36711c06eb5a130dc339b325b',false,false),
  ('public.companion_assignment_rule(boolean,boolean)','7d53e2d7e2196b118c29f85cc90d0ab2',false,false),
  ('public.context_private_access_rule(boolean,boolean,boolean)','a187283398f1802a1b79b46963ff98b6',false,false),
  ('public.demo_own_work_rule(boolean,boolean,boolean,boolean)','3dd99e356714a2005743f678f09f7ae9',false,false),
  ('public.email_template_read_rule(boolean,boolean)','6501d868e3a245da411c8685a6c39406',false,false),
  ('public.email_template_write_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.event_attendance_read_rule(boolean,boolean)','e85f194d54fb7db63b079e5d689de085',false,false),
  ('public.form_authoring_rule(boolean,boolean)','378d42348079d8d5df8ed0d914f5d007',false,false),
  ('public.form_catalog_read_rule(boolean,boolean,boolean)','7a7263f988a28c0272c14f0234b12563',false,false),
  ('public.form_copy_source_rule(boolean,boolean)','0fff049746a86488382290a67c8c9838',false,false),
  ('public.group_assignments_write_rule(boolean,boolean,boolean,boolean)','0221c1b7823f38a4d5afa4abe5e0912f',false,false),
  ('public.group_data_read_rule(boolean,boolean)','a5a4e0f5924790a0c9e68e79bc606a1e',false,false),
  ('public.group_editor_read_rule(boolean,boolean,boolean)','c1fd67eb4de0001ed5aaffb65d36b437',false,false),
  ('public.group_members_read_rule(boolean,boolean,boolean)','c8e7fdf47b08fac95a18ed026d4d07bc',false,false),
  ('public.group_members_write_rule(boolean,boolean)','46f6cef5344290b2caf0182185c3ce4e',false,false),
  ('public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','937805bab351b685970512e7f5e6f285',false,false),
  ('public.group_write_rule(boolean,boolean,boolean)','3dd26a325ee3dd2e391136570cbc5f60',false,false),
  ('public.inventory_copy_target_rule(boolean,boolean)','604bd24712dc418a35616de6d38e0578',false,false),
  ('public.map_editor_read_rule(boolean,boolean)','3f4dc9022d50562b6a48d6e46b0c5928',false,false),
  ('public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb)','337628341725ae78a7c14a130a0fe7a4',false,true),
  ('public.merge_ticket_layout_features(jsonb,jsonb,jsonb,boolean)','d8c6d2e6a64880af2fa1e5553dbf85f5',false,true),
  ('public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','f68f00938a5a8efee47af7edc0062f94',false,false),
  ('public.occasion_commit_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.occasion_context_read_rule(boolean,boolean,boolean)','b54f8cf02bc1580acba23e2497d1cc9f',false,false),
  ('public.occasion_create_rule(boolean,boolean)','faa2f799767b4c9edb52c58944b4a66b',false,false),
  ('public.occasion_directory_read_rule(boolean,boolean)','d4937332739a00292987baae5b876b2b',false,false),
  ('public.occasion_edit_rule(boolean,boolean)','1d4987935db34cc6011f633ef3f6f291',false,false),
  ('public.occasion_editor_read_rule(boolean,boolean,boolean)','1702aa0f9d1003c29f02ef70a017dee6',false,false),
  ('public.occasion_list_read_rule(boolean,boolean)','7ecb040f0c43bb540a15e2ab868ac31e',false,false),
  ('public.occasion_media_upload_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean)','6c7cfeabfb173e0283543f575272d4d8',false,false),
  ('public.occasion_users_write_rule(boolean,boolean,boolean)','2a1ee1bc8a910030a6010ff778df7bc4',false,false),
  ('public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean)','939699b1b32832f4e2ad0c3af5f22210',false,false),
  ('public.order_delete_rule(boolean,boolean,boolean)','6fdbd70c92f774e10d2be6e0e30eb219',false,false),
  ('public.order_editor_membership_as_actor_internal(uuid,bigint)','aa05414eef3f73d8792cdaaa22023c39',false,false),
  ('public.order_read_rule(boolean,boolean,boolean)','d8acd43d69e2797bbd63063512eb4e69',false,false),
  ('public.order_write_rule(boolean,boolean)','4dd2fa01cd16e5c36983aa7aeb280d3f',false,false),
  ('public.participant_contacts_read_rule(boolean,boolean,boolean)','c371f5c035213b1fd9c8a5f15ba3c6e3',false,false),
  ('public.participant_manage_rule(boolean,boolean)','2ddebfa1df2bdd7becf910d5b619a3c0',false,false),
  ('public.place_move_rule(boolean,boolean,boolean,boolean)','73f870eaea9c56088435b4d80cbf5315',false,false),
  ('public.public_publication_actor_rule(boolean,boolean,boolean)','47ad63e39013d34b5a4105a18f04457d',false,false),
  ('public.readable_membership(boolean,boolean,boolean)','057c3a891e1c41c9b77dc8af67983e20',false,false),
  ('public.reception_enabled(jsonb)','0844ea35e4e7bfad821b8f09f81e8fbb',false,false),
  ('public.reception_use_rule(boolean,boolean,boolean,boolean)','99350a72fb204f5160cb72714b85882c',false,false),
  ('public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean)','53eb537fe636ad48274e61bafb683e4a',false,false),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)','56bf52d069b80a2ffa254509afdaa5a1',true,true),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','4a2bacea00089021e673b0ef3fd67237',true,true),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)','eda19f32835616334b3adc0f4d2cd2f6',true,true),
  ('public.scanner_settings_rule(boolean,boolean,boolean)','2b1717b65933cede78c39b44f5d6230d',false,false),
  ('public.schedule_entry_navigation_rule(boolean)','f0258b7a3cc8e3a024dee1a96d34d407',false,false),
  ('public.schedule_feedback_read_rule(boolean,boolean)','a546bbfc24dce06e231e832a11ddb4b4',false,false),
  ('public.schedule_participants_read_rule(boolean,boolean,boolean)','7f6977ddb21f0e2044e154b4428275d1',false,false),
  ('public.ticket_delivery_mode(jsonb)','c2590b2701840fc3cba0df9e8d0359cd',false,true),
  ('public.ticket_layout_rule(boolean,boolean)','8bc8e0cd6a5a45d10d57f79cec655768',false,false),
  ('public.ticket_layout_uses_product_type(bigint,bigint)','dddc7962230734dd5835601b455d8bb4',false,true),
  ('public.ticket_wallet_enabled(jsonb)','ccbb73fd52b030315763e2be50b8e7a7',false,true),
  ('public.ticket_wallet_fingerprint(bigint)','e5418eafc472dc4076cf366b2e82df82',true,true),
  ('public.ticket_wallet_ready(bigint)','25dc8cba98b32f00f8f0980b207fa197',true,true),
  ('public.unit_abuse_policy_read_rule(boolean,boolean)','42fc89183ec978eccce36173bc6c3a50',false,false),
  ('public.unit_discovery_rule(boolean,boolean,boolean)','d49526989a25babf6f7ca9ba34b3061c',false,false),
  ('public.unit_landing_read_rule(boolean,boolean,boolean,boolean)','14e7808464b1206a6842240b8db567ff',false,false),
  ('public.unit_legal_profile_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.unit_template_read_rule(boolean,boolean,boolean)','a22a3f456bfac47bcc58b72c2ec5f75f',false,false),
  ('public.unit_users_read_rule(boolean,boolean,boolean)','a7131760aa20a35fa57d63f718037a34',false,false),
  ('public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean)','5ba3417d0406073b8ce9421770304558',false,false),
  ('public.update_occasion(jsonb)','0425e6f46c20d2c30a2ffd054619b2b0',true,true),
  ('public.update_occasion_182(jsonb)','bdcda71506ac0abb50a466bb18eb1cc7',true,true),
  ('public.update_occasion_203(jsonb)','916b23b47758d87e478b3b7d84a50ee2',true,true),
  ('public.update_occasion_internal_v1(jsonb)','e57ee2a1c8cb4110d1a78b99f9894a96',true,true),
  ('public.validate_ticket_layout(jsonb)','53d7703a06dbde87349a0ac04e50cd54',false,true),
  ('public.validate_ticket_layout_references(bigint,jsonb)','aad01d93c9f0a7035efa243caa3d5a20',false,true),
  ('public.validate_ticket_wallet_appearance(jsonb)','bdcc55cb2a986056fbae005acee1990c',false,true)
 ) expected(signature,body_md5,definer,needs_path)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);
 ready:=ready AND NOT EXISTS(
  SELECT 1 FROM (VALUES('authenticated'),('anon')) actor(role_name)
  WHERE has_table_privilege(actor.role_name,'public.occasions','INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_any_column_privilege(actor.role_name,'public.occasions','INSERT,UPDATE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion_internal_v1(jsonb)'),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)')
 ) private(signature) WHERE has_function_privilege('authenticated',to_regprocedure(private.signature),'EXECUTE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion(jsonb)'),('public.update_occasion_203(jsonb)'),('public.update_occasion_182(jsonb)'),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)')
 ) boundary(signature) WHERE NOT has_function_privilege('authenticated',to_regprocedure(boundary.signature),'EXECUTE')
 OR has_function_privilege('anon',to_regprocedure(boundary.signature),'EXECUTE'));
 RETURN jsonb_build_object('family','ticket_layouts','contractVersion',1,'ready',coalesce(ready,false));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_write_contract_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_write_contract_v1() TO authenticated;
