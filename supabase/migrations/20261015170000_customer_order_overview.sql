-- Customer order overview: read-only capability and durable encrypted sources.

-- Source: database/functions/eshop_waitlist/order_overview_schema.sql
-- Forward-only follow-up. The published capacity migration remains immutable.
ALTER TABLE eshop.waitlist_capabilities DROP CONSTRAINT IF EXISTS waitlist_capabilities_kind_check;
ALTER TABLE eshop.waitlist_capabilities DROP CONSTRAINT IF EXISTS waitlist_capabilities_check;
ALTER TABLE eshop.waitlist_capabilities ADD CONSTRAINT waitlist_capabilities_kind_check CHECK(kind IN ('manage','offer','order_view'));
ALTER TABLE eshop.waitlist_capabilities ADD CONSTRAINT waitlist_capabilities_check CHECK(
 (kind='offer' AND offer_id IS NOT NULL AND expires_at IS NOT NULL) OR
 (kind='manage' AND offer_id IS NULL) OR
 (kind='order_view' AND offer_id IS NULL AND expires_at IS NOT NULL));
CREATE TABLE eshop.order_overview_sources (
 token_hash text PRIMARY KEY REFERENCES eshop.waitlist_capabilities(token_hash) ON DELETE CASCADE,
 sealed jsonb NOT NULL, content_hash text NOT NULL CHECK(content_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 command_id uuid NOT NULL UNIQUE);
ALTER TABLE eshop.order_overview_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.order_overview_sources FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop_waitlist/order_overview.sql
-- Private pure projection. No matcher, paid transition or payment side effect.
CREATE OR REPLACE FUNCTION public.customer_order_payment_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH facts AS (
 SELECT o.*,p.amount,coalesce(p.paid,0) received,coalesce(p.returned,0) returned,
 p.deposit_amount,p.deposit_deadline,p.deadline,p.variable_symbol,p.creditor_reference,
 b.account_number,b.account_number_human_readable,
 CASE WHEN o.state='preparing_payment' THEN 'preparing'
 WHEN o.state='storno' THEN 'cancelled'
 WHEN o.state='waitlisted' AND p.id IS NULL THEN 'not_required_yet'
 WHEN o.price=0 THEN 'free'
 WHEN p.id IS NULL OR p.currency_code IS DISTINCT FROM o.currency_code OR p.amount IS NULL OR p.amount<0 OR coalesce(p.paid,0)<0 OR coalesce(p.paid_externally,0)<>0
  OR (o.state IN ('paid','sent') AND o.price>0 AND coalesce(p.paid,0)=0) THEN 'unknown'
 WHEN coalesce(p.paid,0)>=p.amount THEN 'fully_paid'
 WHEN coalesce(p.paid,0)=0 THEN 'unpaid'
 WHEN p.deposit_amount>0 AND p.paid>=p.deposit_amount THEN 'deposit_paid'
 ELSE 'partially_paid' END status
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order),
 due AS (SELECT *,greatest(amount-received,0) outstanding,
 CASE WHEN deposit_amount>received THEN greatest(deposit_amount-received,0) ELSE greatest(amount-received,0) END due_now,
 CASE WHEN deposit_amount>received THEN deposit_deadline ELSE deadline END due_at FROM facts)
 SELECT jsonb_build_object('status',status,'amount',amount,'received',received,'returned',returned,
 'totalOutstanding',outstanding,'overpaid',greatest(received-amount,0),'depositAmount',deposit_amount,
 'depositDeadline',deposit_deadline,'finalDeadline',deadline,
 'dueNow',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN due_now ELSE 0 END,
 'dueAt',due_at,'overdue',coalesce(due_at<statement_timestamp() AND due_now>0,false),
 'instructionsAvailable',status IN ('unpaid','partially_paid','deposit_paid') AND account_number IS NOT NULL
  AND CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END,
 'reference',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN
  CASE WHEN currency_code='EUR' THEN creditor_reference ELSE variable_symbol::text END END,
 'referenceKind',CASE WHEN currency_code='EUR' THEN 'RF' ELSE 'VS' END,
 'publicAccount',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN coalesce(account_number_human_readable,account_number) END)
 FROM due;
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

CREATE OR REPLACE FUNCTION public.get_customer_order_overview(p_token text,p_order_id bigint)
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
 SELECT jsonb_build_object('code',200,'root',jsonb_build_object('id',root.id,'symbol',root.order_symbol,'title',occ.title,'formLink',f.link,'hasTickets',EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(occ.features,'[]')) feature WHERE feature->>'code'='ticket' AND feature->>'is_enabled'='true')),
 'serverTime',statement_timestamp(),'accessExpiresAt',cap.expires_at,'actions',jsonb_build_array('refresh'),
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),
  'effectiveLifecycle',CASE WHEN (SELECT state FROM eshop.orders WHERE id=x."order")='preparing_payment' THEN 'preparing' ELSE public.get_effective_waitlist_ticket_lifecycle_internal(t.id) END,'currentOrderId',x."order") ORDER BY t.id),'[]')
  FROM (SELECT DISTINCT "order",ticket FROM eshop.order_product_ticket WHERE "order"=ANY(ids)) x JOIN eshop.tickets t ON t.id=x.ticket),
 'offers',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'expiresAt',w.expires_at,
  'pendingPlaces',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending' AND w.expires_at>statement_timestamp()),
  'effectiveStatus',CASE WHEN w.expires_at<=statement_timestamp() THEN 'expired'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending') THEN 'pending'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome IN ('declined','cancelled')) THEN 'cancelled' ELSE 'accepted' END)
  ORDER BY w.created_at,w.id),'[]') FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id),
 'orders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'symbol',o.order_symbol,'state',o.state,'total',o.price,'currency',o.currency_code,
  'payment',public.customer_order_payment_internal(o.id),
  'ticketIds',(SELECT coalesce(jsonb_agg(t.id ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t),
  'items',CASE WHEN o.state='preparing_payment' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticketId',t->'id','title',p->>'title','price',p->'price','currency',p->>'currency_code')),'[]')
   FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p
   WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint)) END,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'rawState',t.state,
   'displayStatus',CASE t.state WHEN 'ordered' THEN 'awaiting_payment' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END,
   'usageStatus',CASE t.state WHEN 'ordered' THEN 'unused' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END) ORDER BY t.id),'[]')
   FROM public.get_order_tickets_internal(o.id) t)) ORDER BY o.id),'[]')
  FROM eshop.orders o WHERE o.id=ANY(ids) AND o.state IS DISTINCT FROM 'waitlisted')) INTO result;
 RETURN result;
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.get_customer_order_overview(text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_customer_order_overview(text,bigint) TO anon,authenticated,service_role;


-- Source: database/functions/eshop_waitlist/order_overview_access.sql
CREATE OR REPLACE FUNCTION public.issue_order_overview_internal(p_order bigint,p_delivery jsonb,p_command uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; expiry timestamptz;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order AND source_waitlist_order_id IS NULL FOR UPDATE;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 IF occ.end_time IS NULL THEN RAISE EXCEPTION 'OVERVIEW_EVENT_END_REQUIRED'; END IF;
 expiry:=greatest(occ.end_time+interval '90 days',statement_timestamp()+interval '30 days');
 IF p_command IS NULL OR p_delivery->>'tokenHash' IS NULL OR p_delivery->>'tokenHash' !~ '^[0-9a-f]{64}$'
 OR p_delivery->>'contentHash' IS NULL OR p_delivery->>'contentHash' !~ '^[0-9a-f]{64}$'
 OR jsonb_typeof(p_delivery->'sealed') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'INVALID_OVERVIEW_SOURCE'; END IF;
 INSERT INTO eshop.waitlist_capabilities(token_hash,organization_id,form_id,order_id,kind,expires_at)
 VALUES(p_delivery->>'tokenHash',occ.organization,o.form,o.id,'order_view',expiry);
 INSERT INTO eshop.order_overview_sources(token_hash,sealed,content_hash,expires_at,command_id)
 VALUES(p_delivery->>'tokenHash',p_delivery->'sealed',p_delivery->>'contentHash',expiry,p_command);
END $$;
REVOKE ALL ON FUNCTION public.issue_order_overview_internal(bigint,jsonb,uuid) FROM PUBLIC,anon,authenticated;

-- Called only by trusted Edge after authentication. A view capability can never resolve write scope.
CREATE OR REPLACE FUNCTION public.resolve_customer_order_access_v1(p_token text,p_order_id bigint,p_offer_id uuid,
 p_command_id uuid,p_delivery jsonb DEFAULT NULL,p_actor uuid DEFAULT NULL,p_reissue boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; f public.forms; occ public.occasions; c eshop.waitlist_capabilities; s eshop.order_overview_sources;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_offer_id IS NOT NULL THEN
  IF p_order_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=p_offer_id AND order_id=p_order_id) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT order_id INTO p_order_id FROM eshop.waitlist_offers WHERE id=p_offer_id;
 END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id AND source_waitlist_order_id IS NULL FOR UPDATE;
 SELECT * INTO STRICT f FROM public.forms WHERE id=o.form AND occasion=o.occasion;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 IF p_reissue THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=o.id AND kind='manage' AND form_id=f.id AND organization_id=occ.organization) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occ.id AND "user"=p_actor AND is_editor_order) THEN
   RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 ELSE
  IF o.state<>'waitlisted' OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted') THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO c FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
   AND order_id=o.id AND form_id=f.id AND organization_id=occ.organization AND revoked_at IS NULL
   AND (expires_at IS NULL OR expires_at>statement_timestamp())
   AND ((p_offer_id IS NULL AND kind='manage') OR (kind='offer' AND offer_id=p_offer_id));
  IF p_token IS NULL OR length(p_token)<>64 OR c.token_hash IS NULL OR (p_offer_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots x ON x.offer_id=w.id
   WHERE w.id=p_offer_id AND w.order_id=o.id AND w.form_id=f.id AND w.expires_at>statement_timestamp() AND x.outcome='pending')) THEN
   RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 END IF;
 -- Command replay precedes rotation. It never resurrects a revoked/expired generation.
 SELECT src.* INTO s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities cap USING(token_hash)
 WHERE cap.order_id=o.id AND cap.kind='order_view' AND cap.revoked_at IS NULL
 AND cap.expires_at>statement_timestamp() AND src.expires_at=cap.expires_at
 AND (NOT p_reissue OR src.command_id=p_command_id) ORDER BY src.created_at DESC LIMIT 1;
 IF s.token_hash IS NULL AND p_delivery IS NOT NULL THEN
  IF p_reissue AND EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=o.id
   AND data->>'action'='order_overview_reissued' AND data->>'commandId'=p_command_id::text) THEN
   RAISE EXCEPTION 'OVERVIEW_REISSUE_REQUIRED'; END IF;
  IF NOT p_reissue AND EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=o.id AND kind='order_view') THEN
   RAISE EXCEPTION 'OVERVIEW_REISSUE_REQUIRED'; END IF;
  IF p_reissue THEN UPDATE eshop.waitlist_capabilities SET revoked_at=statement_timestamp() WHERE order_id=o.id AND kind='order_view' AND revoked_at IS NULL; END IF;
  PERFORM public.issue_order_overview_internal(o.id,p_delivery,p_command_id);
  IF p_reissue THEN INSERT INTO eshop.orders_history("order",state,data) VALUES(o.id,o.state,
   jsonb_build_object('action','order_overview_reissued','commandId',p_command_id,'actor',p_actor)); END IF;
  SELECT * INTO s FROM eshop.order_overview_sources WHERE command_id=p_command_id;
 END IF;
 RETURN jsonb_build_object('code',200,'orderId',o.id,'formLink',f.link,'organization',occ.organization,'occasion',occ.id,'unit',occ.unit,
  'orderSymbol',o.order_symbol,
  'email',(SELECT jsonb_build_object('message_id',message_id,'workflow_state',workflow_state) FROM public.email_messages WHERE dedupe_key='order-overview:'||p_command_id::text AND order_id=o.id),
  'recipient',o.data->>'email','occasionTitle',occ.title,'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(o.id)),
  'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=occ.organization),
  'source',CASE WHEN s.token_hash IS NOT NULL THEN jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,'expiresAt',s.expires_at) END);
END $$;
REVOKE ALL ON FUNCTION public.resolve_customer_order_access_v1(text,bigint,uuid,uuid,jsonb,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_customer_order_access_v1(text,bigint,uuid,uuid,jsonb,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.cleanup_order_overview_sources_internal(p_limit integer DEFAULT 200)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 DELETE FROM eshop.order_overview_sources WHERE token_hash IN
 (SELECT token_hash FROM eshop.order_overview_sources WHERE expires_at<statement_timestamp() ORDER BY expires_at LIMIT least(greatest(p_limit,0),1000));
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.cleanup_order_overview_sources_internal(integer) FROM PUBLIC,anon,authenticated;

-- Registration replay reads its original encrypted generation, never the freshly
-- prepared retry candidate. Raw URLs are added by Edge after the durable receipt.
CREATE OR REPLACE FUNCTION public.get_registered_order_overview_source_v1(p_order_id bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; f public.forms; s eshop.order_overview_sources;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO STRICT f FROM public.forms WHERE id=o.form AND occasion=o.occasion;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 SELECT src.* INTO STRICT s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities c USING(token_hash)
 WHERE src.command_id=p_command_id AND c.order_id=o.id AND c.form_id=f.id AND c.organization_id=occ.organization
 AND c.kind='order_view' AND c.revoked_at IS NULL AND c.expires_at>statement_timestamp() AND src.expires_at=c.expires_at;
 RETURN jsonb_build_object('orderId',o.id,'organization',occ.organization,'occasion',occ.id,'unit',occ.unit,'formLink',f.link,
 'recipient',o.data->>'email','webLink',(SELECT data->>'DEFAULT_URL' FROM organizations WHERE id=occ.organization),
 'source',jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash));
END $$;
REVOKE ALL ON FUNCTION public.get_registered_order_overview_source_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_registered_order_overview_source_v1(bigint,uuid) TO service_role;


-- Source: database/functions/eshop_waitlist/order_overview_email.sql
-- Explicit editor redelivery uses the existing encrypted prepared-email path.
-- It shares the global send gate, rate limits, pause and provider worker.
INSERT INTO public.email_templates(code,subject,html)
SELECT 'ORDER_OVERVIEW','Přehled objednávky - {{occasion_title}}',
 '<h2>{{occasion_title}}</h2><p>Přehled přihlášky {{order_symbol}}, objednávek, evidovaných úhrad a vstupenek:</p><p>{{order_overview_button}}</p>'
WHERE NOT EXISTS(SELECT 1 FROM public.email_templates WHERE code='ORDER_OVERVIEW' AND organization IS NULL AND unit IS NULL AND occasion IS NULL);
CREATE OR REPLACE FUNCTION public.enqueue_order_overview_reissue_v1(p_order_id bigint,p_command_id uuid,p_actor uuid,p_prepared jsonb,p_content_hash text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; s eshop.order_overview_sources; result jsonb;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occ.id AND "user"=p_actor AND is_editor_order) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 SELECT src.* INTO STRICT s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities cap USING(token_hash)
 WHERE src.command_id=p_command_id AND cap.order_id=o.id AND cap.form_id=o.form AND cap.organization_id=occ.organization
 AND cap.kind='order_view' AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp() AND src.expires_at=cap.expires_at;
 IF jsonb_typeof(p_prepared) IS DISTINCT FROM 'object' OR p_content_hash IS NULL OR p_content_hash !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_OVERVIEW_SOURCE'; END IF;
 result:=public.enqueue_email('custom',jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit),
 o.data->>'email',jsonb_build_object('content_hash',p_content_hash,'order_overview_command',p_command_id),
 'order-overview:'||p_command_id::text,'ORDER_OVERVIEW',now(),s.expires_at,o.id,NULL);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),
 prepared_at=coalesce(prepared_at,now()),tracking_policy='disabled'
 WHERE message_id=(result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_order_overview_reissue_v1(bigint,uuid,uuid,jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_order_overview_reissue_v1(bigint,uuid,uuid,jsonb,text) TO service_role;


-- Source: database/functions/eshop_waitlist/offers.sql
DROP FUNCTION IF EXISTS public.expire_waitlist_form_internal(bigint,timestamptz);
CREATE OR REPLACE FUNCTION public.expire_waitlist_form_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp(),p_limit integer DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 IF public.is_demo_occasion((SELECT occasion FROM public.forms WHERE id=p_form)) THEN RETURN 0; END IF;
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 WITH expired AS (UPDATE eshop.waitlist_offer_slots s SET outcome='expired',updated_at=p_at
 FROM eshop.waitlist_offers w WHERE w.id=s.offer_id AND w.form_id=p_form AND w.expires_at<=p_at AND s.outcome='pending'
 AND s.id IN(SELECT x.id FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers y ON y.id=x.offer_id WHERE y.form_id=p_form AND y.expires_at<=p_at AND x.outcome='pending' ORDER BY x.id LIMIT p_limit)
 RETURNING s.ticket_id)
 UPDATE eshop.tickets SET waitlist_queue_at=p_at,updated_at=p_at WHERE id IN(SELECT ticket_id FROM expired) AND state='waitlisted';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n>0 THEN
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=p_form;
  UPDATE eshop.waitlist_capabilities SET revoked_at=p_at WHERE form_id=p_form AND kind='offer' AND expires_at<=p_at AND revoked_at IS NULL;
 END IF;
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_proposal(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; proposals jsonb; available integer;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 PERFORM 1 FROM public.forms WHERE id=f.id FOR UPDATE;
 PERFORM public.expire_waitlist_form_internal(f.id);
 c:=public.get_form_capacity_snapshot_internal(f.id); available:=(c->>'offerablePlaces')::integer;
 -- count is the suggested allocation; waitingCount is the authoritative recipient limit.
 -- Keep unallocated eligible recipients so editors can adjust the allocation safely.
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',order_id,'count',offered,'waitingCount',total) ORDER BY first_queue,order_id),'[]') INTO proposals
 FROM (SELECT order_id,min(waitlist_queue_at) first_queue,count(*) total,
  count(*) FILTER(WHERE position<=available) offered FROM
  (SELECT p.*,o.id order_id,row_number() OVER(ORDER BY p.waitlist_queue_at,p.created_at,p.id) position FROM eshop.tickets p
   JOIN LATERAL(SELECT DISTINCT x."order" FROM eshop.order_product_ticket x WHERE x.ticket=p.id) x ON true
   JOIN eshop.orders o ON o.id=x."order" WHERE o.form=f.id AND o.state='waitlisted' AND public.get_effective_waitlist_ticket_lifecycle_internal(p.id)='waiting' ) ranked GROUP BY order_id) grouped;
 RETURN jsonb_build_object('code',200,'formId',f.id,'revision',c->'revision','capacity',c,'recipients',proposals,
 'offerDurationSeconds',f.waitlist_offer_duration_seconds,'serverTime',clock_timestamp());
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_waitlist_email_internal(p_order bigint,p_offer uuid,p_command uuid,p_delivery jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; result jsonb; expiry timestamptz; code text; kind text;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order; SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 code:=CASE WHEN p_offer IS NULL THEN 'waitlist_confirmation' ELSE 'waitlist_offer' END;
 kind:=code;
 IF p_delivery->>'recipient' IS DISTINCT FROM o.data->>'email' OR p_delivery->>'templateCode' IS DISTINCT FROM code
 OR p_delivery->'sealed' IS NULL OR p_delivery->>'tokenHash' !~ '^[0-9a-f]{64}$'
 OR p_delivery->>'contentHash' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid waitlist delivery binding'; END IF;
 SELECT expires_at INTO expiry FROM eshop.waitlist_offers WHERE id=p_offer AND order_id=p_order;
 INSERT INTO eshop.waitlist_capabilities(token_hash,organization_id,form_id,order_id,offer_id,kind,expires_at)
 VALUES(p_delivery->>'tokenHash',occ.organization,o.form,o.id,p_offer,CASE WHEN p_offer IS NULL THEN 'manage' ELSE 'offer' END,expiry);
 IF p_offer IS NULL AND p_delivery ? 'overview' THEN
  PERFORM public.issue_order_overview_internal(o.id,p_delivery->'overview',p_command);
 END IF;
 result:=public.enqueue_email(kind,jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit),o.data->>'email',
 jsonb_build_object('order_id',o.id,'offer_id',p_offer,'command_id',p_command,'content_hash',p_delivery->>'contentHash','waitlistEnvelope',p_delivery->'sealed'),
 p_command::text||':'||o.id::text,code,now(),expiry,o.id,NULL);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.expire_waitlist_form_internal(bigint,timestamptz,integer),public.enqueue_waitlist_email_internal(bigint,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_proposal(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_proposal(bigint) TO authenticated;


-- Source: database/functions/eshop_waitlist/email_render_context.sql
-- Shared presentation metadata; no lifecycle or capability decisions.
CREATE OR REPLACE FUNCTION public.get_waitlist_form_timezone_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(occasion_zone.name,unit_zone.name,organization_zone.name,'Europe/Prague')
 FROM public.forms f JOIN public.occasions occ ON occ.id=f.occasion
 LEFT JOIN public.units u ON u.id=occ.unit
 LEFT JOIN public.organizations org ON org.id=occ.organization
 LEFT JOIN pg_timezone_names occasion_zone ON occasion_zone.name=nullif(occ.data->>'timezone','')
 LEFT JOIN pg_timezone_names unit_zone ON unit_zone.name=nullif(u.data->>'timezone','')
 LEFT JOIN pg_timezone_names organization_zone ON organization_zone.name=nullif(org.data->>'timezone','')
 WHERE f.id=p_form;
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_form_timezone_internal(bigint) FROM PUBLIC,anon,authenticated;

-- One presentation vocabulary for both gated delivery and authenticated preview.
-- The existing effective-form resolver owns tone inheritance.
CREATE OR REPLACE FUNCTION public.get_waitlist_email_tone_substitutions_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object(
  'waitlist_offer_button_single','Potvrdit přihlášení',
  'waitlist_offer_button_multiple','Potvrdit vybrané osoby',
  'waitlist_manage_button_label','Spravovat čekání',
  'waitlist_confirmation_heading',CASE WHEN informal THEN 'Jsi mezi náhradníky' ELSE 'Jste mezi náhradníky' END,
  'waitlist_confirmation_explanation',CASE WHEN informal THEN 'Zatím nic neplatíš. Jakmile se uvolní místo, pošleme ti nabídku. Čekání můžeš spravovat nebo ukončit přes tento odkaz:' ELSE 'Zatím nic neplatíte. Jakmile se uvolní místo, pošleme vám nabídku. Čekání můžete spravovat nebo ukončit přes tento odkaz:' END,
  'waitlist_offer_heading',CASE WHEN informal THEN 'Máme pro tebe nabídku' ELSE 'Máme pro vás nabídku' END,
  'waitlist_offer_instructions_single',CASE WHEN informal THEN 'Po otevření nabídky doplníš údaje a vybereš produkty podle aktuální dostupnosti. Přihlášení pak potvrdíš.' ELSE 'Po otevření nabídky doplníte údaje a vyberete produkty podle aktuální dostupnosti. Přihlášení pak potvrdíte.' END,
  'waitlist_offer_instructions',CASE WHEN informal THEN 'Po otevření nabídky vybereš, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíš.' ELSE 'Po otevření nabídky vyberete, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíte.' END)
 FROM (SELECT coalesce(public.get_effective_form_data(p_form)->>'communication_tone','formal')='informal' informal) tone;
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_tone_substitutions_internal(bigint) FROM PUBLIC,anon,authenticated;

-- Private queue renderer boundary. Personal capabilities remain encrypted in
-- existing queue sources; the renderer receives only their hashes and envelopes.
CREATE OR REPLACE FUNCTION public.get_waitlist_email_render_context_v1(
 p_order_id bigint,p_offer_id uuid DEFAULT NULL,p_recipient text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE o eshop.orders; f public.forms; occ public.occasions; org public.organizations;
 manage_message public.email_messages; manage_cap eshop.waitlist_capabilities;
 source_cap eshop.waitlist_capabilities; v_recipient text; v_timezone text;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO f FROM public.forms WHERE id=o.form;
 SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 SELECT * INTO org FROM public.organizations WHERE id=occ.organization;
 IF o.id IS NULL OR f.id IS NULL OR f.occasion<>occ.id OR o.state<>'waitlisted'
 OR (p_offer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers
  WHERE id=p_offer_id AND order_id=o.id AND form_id=f.id AND expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending'))) THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 v_timezone:=public.get_waitlist_form_timezone_internal(f.id);
 v_recipient:=coalesce(p_recipient,o.data->>'email');
 SELECT * INTO manage_message FROM public.email_messages m
 WHERE m.order_id=o.id AND m.message_kind='waitlist_confirmation'
 AND m.recipient=v_recipient
 AND m.data ? 'waitlistEnvelope' ORDER BY m.id LIMIT 1;
 SELECT * INTO manage_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id
 AND kind='manage' AND revoked_at IS NULL;
 SELECT * INTO source_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id AND revoked_at IS NULL
 AND CASE WHEN p_offer_id IS NULL THEN kind='manage'
  ELSE kind='offer' AND offer_id=p_offer_id AND expires_at>clock_timestamp() END;
 IF manage_message.id IS NULL OR manage_cap.token_hash IS NULL OR source_cap.token_hash IS NULL THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 RETURN jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,
  'organization',org.id,'occasion',occ.id,'unit',occ.unit,'formLink',f.link,
  'webLink',org.data->>'DEFAULT_URL','replyTo',public.get_reply_to_email_for_order(o.id),
  'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(o.id)),
  'offeredCount',(SELECT count(*) FROM eshop.waitlist_offer_slots
    WHERE offer_id=p_offer_id AND outcome='pending'),
  'timeZone',v_timezone,
  'communicationTone',public.get_effective_form_data(f.id)->>'communication_tone',
  'toneSubstitutions',public.get_waitlist_email_tone_substitutions_internal(f.id),
  'expiresAt',(SELECT expires_at FROM eshop.waitlist_offers WHERE id=p_offer_id),
  'tokenHash',source_cap.token_hash,'manageTokenHash',manage_cap.token_hash,
  'manageEnvelope',manage_message.data->'waitlistEnvelope',
  'overviewSource',(SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash) WHERE c.order_id=o.id AND c.kind='order_view' AND c.revoked_at IS NULL AND c.expires_at>statement_timestamp() ORDER BY s.created_at DESC LIMIT 1),
  'manageContentHash',manage_message.data->>'content_hash');
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 TO service_role;


-- Source: database/functions/eshop_waitlist/fakturoid_recovery.sql
CREATE OR REPLACE FUNCTION public.abort_waitlist_acceptance_internal(p_order bigint,p_command uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.waitlist_acceptance_attempts; s jsonb; p jsonb; expiry timestamptz;
 original_ticket eshop.tickets; restored_outcome text; original_id bigint;
BEGIN
 SELECT * INTO a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command AND target_order_id=p_order;
 IF a.command_id IS NULL THEN RETURN false; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.source_order_id,a.target_order_id]);
 SELECT * INTO STRICT a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command FOR UPDATE;
 IF a.state='aborted' THEN RETURN true; END IF;
 IF a.state<>'preparing' THEN RAISE EXCEPTION 'Acceptance attempt already completed'; END IF;
 SELECT expires_at INTO expiry FROM eshop.waitlist_offers WHERE id=a.offer_id FOR UPDATE;
 PERFORM public.cancel_order_email_intents(p_order);
 PERFORM public.internal_storno_tickets_221(a.ticket_ids);
 DELETE FROM eshop.order_product_ticket WHERE "order"=a.target_order_id AND ticket=ANY(a.ticket_ids);
 IF a.conversion='in_place' THEN
  UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=a.previous_order_data->'data',updated_at=clock_timestamp() WHERE id=a.target_order_id;
 ELSE
  UPDATE eshop.orders SET state='storno',price=0,payment_info=NULL,updated_at=clock_timestamp() WHERE id=a.target_order_id;
 END IF;
 -- Only the selected tickets are fenced by the preparing target. Never restore
 -- unselected/displaced answers or resurrect a concurrently withdrawn remainder.
 FOR p IN SELECT * FROM jsonb_array_elements(a.previous_tickets) LOOP
  IF NOT (p->>'id')::bigint=ANY(a.ticket_ids) THEN CONTINUE; END IF;
  UPDATE eshop.tickets SET state=p->>'state',ticket_symbol=p->>'ticket_symbol',data=p->'data',note=p->>'note',
   note_hidden=p->>'note_hidden',waitlist_queue_at=(p->>'waitlist_queue_at')::timestamptz,updated_at=clock_timestamp() WHERE id=(p->>'id')::bigint;
 END LOOP;
 INSERT INTO eshop.order_product_ticket SELECT * FROM jsonb_populate_recordset(NULL::eshop.order_product_ticket,a.previous_links);
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(a.slot_ids);
 FOR s IN SELECT * FROM jsonb_array_elements(a.previous_slots) LOOP
  original_id:=(s->>'ticket_id')::bigint;
  SELECT * INTO STRICT original_ticket FROM eshop.tickets WHERE id=original_id FOR UPDATE;
  restored_outcome:=CASE
   WHEN original_ticket.state<>'waitlisted' OR NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=original_id AND x."order"=a.source_order_id)
    OR EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots other WHERE other.ticket_id=original_id AND other.outcome='pending' AND NOT other.id=ANY(a.slot_ids)) THEN 'cancelled'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots other JOIN eshop.waitlist_offers ow ON ow.id=other.offer_id
     WHERE other.ticket_id=original_id AND other.outcome IN ('declined','cancelled')
     AND ow.created_at>(SELECT created_at FROM eshop.waitlist_offers WHERE id=a.offer_id)) THEN 'cancelled'
   WHEN expiry<=clock_timestamp() THEN 'expired' ELSE 'pending' END;
  UPDATE eshop.waitlist_offer_slots SET ticket_id=original_id,outcome=restored_outcome,resulting_order_id=NULL,updated_at=clock_timestamp() WHERE id=(s->>'id')::uuid;
  IF restored_outcome='expired' AND original_ticket.state='waitlisted' THEN
   UPDATE eshop.tickets SET waitlist_queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=original_id;
  END IF;
 END LOOP;
 UPDATE eshop.waitlist_acceptance_attempts SET state='aborted',updated_at=clock_timestamp() WHERE command_id=p_command;
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=(SELECT form FROM eshop.orders WHERE id=a.source_order_id);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(a.source_order_id,'waitlisted',jsonb_build_object('action','acceptance_aborted','commandId',p_command,'targetOrderId',a.target_order_id));
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.expire_waitlist_offers(p_batch_size integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; affected integer:=0; n integer; occ bigint; impacts jsonb;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 PERFORM public.cleanup_order_overview_sources_internal(p_batch_size);
 IF p_batch_size NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid expiry batch'; END IF;
 FOR f IN SELECT DISTINCT form_id FROM eshop.waitlist_offers w WHERE expires_at<=clock_timestamp() AND EXISTS
  (SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.offer_id=w.id AND outcome='pending') ORDER BY form_id LIMIT p_batch_size LOOP
  PERFORM 1 FROM public.forms WHERE id=f FOR UPDATE;
  PERFORM 1 FROM eshop.orders WHERE form=f ORDER BY id FOR UPDATE;
  n:=public.expire_waitlist_form_internal(f,clock_timestamp(),p_batch_size-affected); affected:=affected+n;
  IF n>0 THEN
   SELECT occasion INTO occ FROM public.forms WHERE id=f;
   SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,'userId',ou."user")),'[]') INTO impacts
    FROM public.occasion_users ou CROSS JOIN unnest(ARRAY['private_profile','private_inventory']) component WHERE ou.occasion=occ;
   PERFORM public.record_client_sync_commit_v1(occ,'inventory.waitlist.expire','inventory',
    jsonb_build_array(jsonb_build_object('entityType','form','entityId',f,'operation','update','safeLabel','Offer expiry',
    'changedFields',jsonb_build_array('capacity','waitlistSummary'))),'{}',impacts,'[]','service',NULL);
  END IF;
  EXIT WHEN affected>=p_batch_size;
 END LOOP;
 RETURN jsonb_build_object('expiredSlots',affected);
END $$;
REVOKE ALL ON FUNCTION public.abort_waitlist_acceptance_internal(bigint,uuid),public.expire_waitlist_offers(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.expire_waitlist_offers(integer) TO service_role;


-- Source: database/functions/emails/email_queue.sql (email_intent_valid only)
CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id' AND h.warning_code IS NOT NULL
      AND c.state IN ('connected','degraded') AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND coalesce(v_pi.paid,0)<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;
