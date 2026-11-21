-- Preserve admission identity in product edits and expose confirmed admission operations.

-- SOURCE: eshop/product_selection_contract.sql
-- Physical seats contribute their server-owned product before this check.
CREATE OR REPLACE FUNCTION public.assert_single_ticket_admission_internal(p_products bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF (SELECT count(*) FROM unnest(p_products) selected(id)
   JOIN eshop.products p ON p.id=selected.id
   JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.type='spot')>1 THEN
  RAISE EXCEPTION 'ADMISSION_MULTIPLE_PRODUCTS';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_single_ticket_admission_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Shared admission/required-product validation for checkout and term moves.
CREATE OR REPLACE FUNCTION public.assert_ticket_required_products_internal(p_form bigint,p_products bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE missing_field bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE p.id=ANY(p_products) AND pt.type='spot') AND NOT coalesce((SELECT bool_and(is_hidden IS TRUE)
   FROM public.form_fields WHERE form=p_form AND type='ticket'),false) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',1015,'message','Spot product is missing in ticket fields')::text;
 END IF;
 SELECT ff.id INTO missing_field FROM public.form_fields ff WHERE ff.form=p_form AND ff.type='product_type'
  AND ff.is_ticket_field AND ff.is_required AND NOT ff.is_hidden AND NOT EXISTS(
   SELECT 1 FROM eshop.products p WHERE p.id=ANY(p_products) AND p.product_type=ff.product_type)
 ORDER BY ff.id LIMIT 1;
 IF FOUND THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',missing_field,'message','Required product selection missing')::text;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_ticket_required_products_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_orders/ticket_admission_integrity.sql
-- Catalog type and persisted links own admission identity. Snapshot type is
-- also checked so a stale or damaged snapshot cannot silently lose an entry.
CREATE OR REPLACE FUNCTION public.ticket_admission_integrity_internal(
  p_order bigint, p_ticket bigint
)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH scope AS (
   SELECT o.id, o.occasion, o.data, t.occasion AS ticket_occasion
   FROM eshop.orders o CROSS JOIN eshop.tickets t WHERE o.id=p_order AND t.id=p_ticket
 ), links AS (
   SELECT x.id, x.product, x."order", p.occasion, pt.type, pt.occasion AS type_occasion
   FROM eshop.order_product_ticket x
   LEFT JOIN eshop.products p ON p.id=x.product
   LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE x.ticket=p_ticket
 ), linked AS (
   SELECT coalesce(array_agg(product ORDER BY product) FILTER (WHERE type='spot'),'{}') AS ids,
     coalesce(bool_or(l."order"<>s.id OR (l.type='spot' AND
       (l.occasion IS DISTINCT FROM s.occasion OR l.type_occasion IS DISTINCT FROM s.occasion))
       OR (l.type IS DISTINCT FROM 'spot' AND EXISTS (
         SELECT 1 FROM eshop.spots sp WHERE sp.order_product_ticket=l.id AND sp.blueprint IS NOT NULL))),false) AS invalid
   FROM links l CROSS JOIN scope s
 ), ticket_snapshot AS (
   SELECT t FROM scope s CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(s.data->'tickets')='array' THEN s.data->'tickets' ELSE '[]' END) t
   WHERE t->>'id'=p_ticket::text
 ), snapshot AS (
   SELECT coalesce(array_agg(p.id ORDER BY p.id),'{}') AS ids,
     coalesce(bool_or(pt.type IS DISTINCT FROM 'spot' OR
       (j ? 'order_product_ticket_id' AND NOT EXISTS (
         SELECT 1 FROM links l WHERE l.product=p.id AND l.id::text=j->>'order_product_ticket_id'))),false) AS invalid
   FROM ticket_snapshot ts CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(ts.t->'products')='array' THEN ts.t->'products' ELSE '[]' END) j
   LEFT JOIN eshop.products p ON p.id::text=j->>'id'
   LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE pt.type='spot' OR j->>'type'='spot'
 )
 SELECT jsonb_build_object('productIds',linked.ids,
   'spotCount',greatest(cardinality(linked.ids),cardinality(snapshot.ids)),
   'reason',CASE WHEN s.occasion IS DISTINCT FROM s.ticket_occasion
     OR linked.invalid OR snapshot.invalid OR (SELECT count(*) FROM ticket_snapshot)<>1
     OR cardinality(linked.ids)>1 OR linked.ids IS DISTINCT FROM snapshot.ids
     OR EXISTS(SELECT 1 FROM links l JOIN eshop.spots sp ON sp.order_product_ticket=l.id
       WHERE l.type='spot' AND sp.blueprint IS NOT NULL GROUP BY l.id
       HAVING count(*)>1 OR bool_or(sp.product IS DISTINCT FROM l.product OR sp.occasion IS DISTINCT FROM s.occasion))
     THEN 'ADMISSION_DATA_AMBIGUOUS' END)
 FROM scope s CROSS JOIN linked CROSS JOIN snapshot
$$;
REVOKE ALL ON FUNCTION public.ticket_admission_integrity_internal(bigint,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

-- Visibility and execution use the same order/ticket eligibility rules.
CREATE OR REPLACE FUNCTION public.order_admission_blocker_internal(p_order bigint,p_ticket bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE
   WHEN f.id IS NULL OR o.state NOT IN ('created','ordered','paid','sent') OR pi.id IS NULL
     OR o.price IS NULL OR pi.amount IS DISTINCT FROM o.price OR pi.currency_code IS DISTINCT FROM o.currency_code
     OR pi.payment_method IS DISTINCT FROM 'bank' AND
       (p_ticket IS NULL OR NOT public.payment_method_is_online_internal(pi.payment_method))
     THEN 'ORDER_ADMISSION_UNAVAILABLE'
   WHEN EXISTS(SELECT 1 FROM eshop.order_discounts d WHERE d.order_id=o.id)
     THEN 'DISCOUNTED_ORDER_PRICE_IMMUTABLE'
   WHEN EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) other
     WHERE other.state NOT IN ('storno','waitlisted')
       AND public.ticket_admission_integrity_internal(o.id,other.id)->>'reason' IS NOT NULL)
     THEN 'ADMISSION_DATA_AMBIGUOUS'
   WHEN p_ticket IS NULL THEN NULL
   WHEN t.id IS NULL OR t.state NOT IN ('ordered','paid','sent','used') THEN 'ORDER_ADMISSION_UNAVAILABLE'
   WHEN t.state='used' THEN 'USED_TICKET_PROTECTED'
   WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items bi WHERE bi.ticket_id=p_ticket) THEN 'BATCH_TICKET_PRINT_IMMUTABLE'
   WHEN v.integrity->>'reason' IS NOT NULL THEN v.integrity->>'reason'
   WHEN v.integrity->>'spotCount' IS DISTINCT FROM '1' THEN 'ORDER_ADMISSION_UNAVAILABLE'
   WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.spots s ON s.order_product_ticket=x.id
       WHERE x.ticket=p_ticket AND x."order"=o.id AND s.blueprint IS NOT NULL
       AND (s.blueprint IS DISTINCT FROM f.blueprint OR EXISTS(
         SELECT 1
         FROM eshop.spots member LEFT JOIN eshop.order_product_ticket admission ON admission.id=member.order_product_ticket
         LEFT JOIN eshop.tickets holder ON holder.id=admission.ticket
         WHERE member.id=ANY(public.blueprint_selection_unit_spots_internal(s.id))
           AND member.id<>s.id AND (
             admission."order" IS DISTINCT FROM o.id OR holder.state NOT IN ('ordered','paid','sent')
             OR public.ticket_admission_integrity_internal(o.id,holder.id)->>'reason' IS NOT NULL
             OR EXISTS(SELECT 1 FROM eshop.ticket_batch_items bi WHERE bi.ticket_id=holder.id)
           )
       )))
     THEN 'BLUEPRINT_INCOMPLETE_SELECTION_UNIT'
 END
 FROM eshop.orders o
 LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
 LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
 LEFT JOIN eshop.tickets t ON t.id=p_ticket AND t.occasion=o.occasion
   AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=t.id)
 CROSS JOIN LATERAL (SELECT CASE WHEN t.id IS NOT NULL THEN public.ticket_admission_integrity_internal(o.id,t.id) END AS integrity) v
 WHERE o.id=p_order
$$;
REVOKE ALL ON FUNCTION public.order_admission_blocker_internal(bigint,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

-- Fill missing historical type metadata from the scoped catalog for both editors.
CREATE OR REPLACE FUNCTION public.order_ticket_admission_snapshot_internal(p_ticket jsonb,p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_ticket IS NULL THEN NULL ELSE p_ticket || jsonb_build_object('products',
   coalesce((SELECT jsonb_agg(CASE WHEN pt.id IS NULL THEN item ELSE item||jsonb_build_object('type',pt.type) END ORDER BY n)
   FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_ticket->'products')='array' THEN p_ticket->'products' ELSE '[]' END) WITH ORDINALITY x(item,n)
   LEFT JOIN eshop.products p ON p.id::text=item->>'id' AND p.occasion=p_occasion
   LEFT JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.occasion=p_occasion),'[]')) END
$$;
REVOKE ALL ON FUNCTION public.order_ticket_admission_snapshot_internal(jsonb,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_waitlist/accept_offer.sql
CREATE OR REPLACE FUNCTION public.validate_waitlist_answers_internal(p_form bigint,p_input jsonb,p_people jsonb,p_waitlist boolean)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.form_fields; person jsonb; values jsonb; k text; max_people integer; email text;
BEGIN
 IF nullif(p_input->>'email','') IS NOT NULL AND NOT public.email_address_is_valid(p_input->>'email') THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL')::text; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND type='email' AND NOT is_hidden
 AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  FOR email IN
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE NOT f.is_ticket_field AND answer ? k
   UNION ALL
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_people,'[]')) participant(value),
    LATERAL jsonb_array_elements(coalesce(participant.value->'fields','[]')) answer WHERE f.is_ticket_field AND answer ? k
  LOOP
   IF nullif(email,'') IS NOT NULL AND NOT public.email_address_is_valid(email) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL','fieldId',f.id)::text; END IF;
  END LOOP;
 END LOOP;
 IF jsonb_typeof(p_people)<>'array' OR jsonb_array_length(p_people)<1 OR jsonb_array_length(p_people)>public.ticket_order_limit() THEN
  RAISE EXCEPTION 'Invalid participant count'; END IF;
 SELECT min((data->>'max_tickets')::integer) INTO max_people FROM public.form_fields WHERE form=p_form AND type='ticket';
 IF jsonb_array_length(p_people)>coalesce(max_people,public.ticket_order_limit()) THEN RAISE EXCEPTION 'Maximum participants exceeded'; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND is_required AND NOT is_hidden
 AND type NOT IN ('ticket','html','product_type') AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  IF f.is_ticket_field THEN
   FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
    -- Selected seats use the ticket's top-level spot transport. The finalizer
    -- checks occasion ownership, availability and reservation secret afterward.
    IF f.type='spot' AND (p_waitlist OR nullif(person->>'spot','') IS NOT NULL OR EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(person->'fields','[]')) a
     JOIN public.forms form ON form.id=p_form
     JOIN eshop.blueprint_area_bindings area ON area.blueprint=form.blueprint AND area.product::text=a->>'product_type'
     JOIN eshop.product_inventory_contexts pic ON pic.product=area.product AND pic.inventory_context=area.inventory_context
     WHERE pic.quantity>0
    )) THEN
     CONTINUE;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(person->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
     RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
   END LOOP;
  ELSE
   IF nullif(p_input->>f.type,'') IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
  END IF;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.accept_waitlist_offer_internal(p_payload jsonb,p_command uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE w eshop.waitlist_offers; o eshop.orders; fid bigint; target bigint; ids bigint[]; selected_slots uuid[];
 n integer; remaining integer; result jsonb; input jsonb; old_tickets jsonb; old_slots jsonb; old_links jsonb; conversion text;
 original_group jsonb; remaining_group jsonb; accepted_group jsonb; history_snapshot jsonb;
BEGIN
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=(p_payload->>'offerId')::uuid;
 fid:=public.check_waitlist_scope_internal(w.order_id,w.id,p_payload->>'token',p_actor,'accept');
 PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=w.order_id)]);
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[w.order_id]);
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=w.id FOR UPDATE;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=w.order_id;
 PERFORM public.expire_waitlist_form_internal(fid);
 IF w.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 IF o.state<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 SELECT array_agg(x::bigint) INTO ids FROM jsonb_array_elements_text(p_payload->'ticketIds') x;
 n:=coalesce(cardinality(ids),0);
 IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(ids) x) THEN RAISE EXCEPTION 'Invalid selected persons'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id) ORDER BY id FOR UPDATE;
 original_group:=public.snapshot_waitlist_tickets_internal(o.id);
 IF n<>(SELECT count(*) FROM public.get_order_tickets_internal(o.id) p WHERE p.id=ANY(ids) AND state='waitlisted'
 AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.ticket_id=p.id AND s.outcome='pending' AND s.offer_id<>w.id)) THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Preserve slots already attached to selected people, then exchange only the necessary unused bindings.
 SELECT array_agg(id ORDER BY CASE WHEN ticket_id=ANY(ids) THEN 0 ELSE 1 END,id) INTO selected_slots
 FROM (SELECT * FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending'
 ORDER BY CASE WHEN ticket_id=ANY(ids) THEN 0 ELSE 1 END,id LIMIT n FOR UPDATE) s;
 IF coalesce(cardinality(selected_slots),0)<>n THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 -- Journal the exact pre-swap bindings, including displaced offered people.
 SELECT jsonb_agg(to_jsonb(p)) INTO old_tickets FROM eshop.tickets p
 WHERE id=ANY(ids) OR id IN(SELECT ticket_id FROM eshop.waitlist_offer_slots WHERE id=ANY(selected_slots));
 SELECT jsonb_agg(to_jsonb(s)) INTO old_slots FROM eshop.waitlist_offer_slots s WHERE id=ANY(selected_slots);
 SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO old_links FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=ANY(ids);
 -- Release temporary bindings using a terminal outcome so the pending uniqueness invariant never needs deferral.
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(selected_slots);
 WITH persons AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(ids) id), slots AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(selected_slots) id)
 UPDATE eshop.waitlist_offer_slots s SET ticket_id=p.id FROM persons p JOIN slots x USING(n) WHERE s.id=x.id;
 SELECT count(*) INTO remaining FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted';
 conversion:=CASE WHEN remaining=n THEN 'in_place' ELSE 'split' END;
 target:=CASE WHEN conversion='in_place' THEN o.id ELSE public.allocate_ticket_order_identity_internal(fid) END;
 IF conversion='split' THEN UPDATE eshop.orders SET source_waitlist_order_id=o.id WHERE id=target; END IF;
 input:=p_payload->'orderDetails';
 input:=jsonb_set(input,'{ticket}',public.normalize_form_ticket_answers_internal(fid,input->'ticket'));
 IF (input->>'form')::uuid IS DISTINCT FROM (SELECT key FROM public.forms WHERE id=fid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF jsonb_array_length(input->'ticket')<>n THEN RAISE EXCEPTION 'Selected people and tickets differ'; END IF;
 -- Each selected person must explicitly bind their stable ID to their submitted ticket.
 IF n<>(SELECT count(DISTINCT (t->>'ticketId')::bigint) FROM jsonb_array_elements(input->'ticket') t WHERE (t->>'ticketId')::bigint=ANY(ids)) THEN
  RAISE EXCEPTION 'Invalid participant ticket binding'; END IF;
 PERFORM public.validate_waitlist_answers_internal(fid,input,input->'ticket',false);
 UPDATE eshop.order_product_ticket SET "order"=target WHERE "order"=o.id AND ticket=ANY(ids);
 result:=public.finalize_ticket_order_internal_v1(target,(public.strip_payment_sources_internal(input)-'discount_command_id')||jsonb_build_object('discount_command_id',p_command),true);
 IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted',resulting_order_id=target,updated_at=clock_timestamp() WHERE id=ANY(selected_slots);
 PERFORM public.attach_provider_order_source_internal(target,p_command,input);
 PERFORM public.enqueue_ticket_order_confirmation_v1(p_command,o.occasion,result,input->>'lang');
 IF (SELECT state='preparing_payment' FROM eshop.orders WHERE id=target) THEN
  INSERT INTO eshop.waitlist_acceptance_attempts(command_id,source_order_id,target_order_id,offer_id,conversion,ticket_ids,slot_ids,previous_order_data,previous_tickets,previous_links,previous_slots)
  VALUES(p_command,o.id,target,w.id,conversion,ids,selected_slots,to_jsonb(o),old_tickets,old_links,old_slots);
 ELSE
  UPDATE eshop.waitlist_capabilities SET revoked_at=clock_timestamp() WHERE offer_id=w.id
   AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending');
 END IF;
 remaining_group:=CASE WHEN conversion='split' THEN public.snapshot_waitlist_tickets_internal(o.id) ELSE '[]'::jsonb END;
 accepted_group:=public.snapshot_waitlist_tickets_internal(target);
 history_snapshot:=jsonb_build_object('action','waitlist_accept','commandId',p_command,'sourceOrderId',o.id,
  'targetOrderId',target,'ticketIds',ids,'conversion',conversion,'ticketsBefore',original_group,
  'ticketsAfter',remaining_group,'acceptedTickets',accepted_group);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(o.id,(SELECT state FROM eshop.orders WHERE id=o.id),history_snapshot);
 IF conversion='split' THEN
  INSERT INTO eshop.orders_history("order",state,data) VALUES(target,(SELECT state FROM eshop.orders WHERE id=target),history_snapshot);
 END IF;
 RETURN result||jsonb_build_object('sourceOrderId',o.id,'conversion',conversion,'waitlistSummary',public.get_waitlist_summary_internal(o.id));
END $$;
REVOKE ALL ON FUNCTION public.validate_waitlist_answers_internal(bigint,jsonb,jsonb,boolean),public.accept_waitlist_offer_internal(jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_ticket_batches/policy.sql
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('batch-document.actor.burst','batch-document','actor','rolling',600,60,300,1000),
 ('batch-document.unit.burst','batch-document','unit','rolling',600,60,1000,5000)
 ON CONFLICT(rule_key) DO NOTHING;
CREATE OR REPLACE FUNCTION public.admit_ticket_batch_document_internal(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o public.occasions;
BEGIN
 SELECT * INTO STRICT o FROM public.occasions WHERE id=p_occasion;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('batch-document',o.unit,o.organization),
  jsonb_build_object('actor',auth.uid(),'unit',o.unit,'organization',o.organization));
END $$;
REVOKE ALL ON FUNCTION public.admit_ticket_batch_document_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,base_limit,hard_cap)
 VALUES('batch-create.items','batch-create','unit','items',200,200) ON CONFLICT(rule_key) DO NOTHING;
CREATE OR REPLACE FUNCTION public.check_ticket_batch_cash_unit_internal(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_occasion_writable(p_occasion);
 IF EXISTS(SELECT 1 FROM eshop.external_services s JOIN public.occasions o ON o.unit=s.unit WHERE o.id=p_occasion AND s.type='FAKTUROID') THEN
  RAISE EXCEPTION 'CASH_SALE_INVOICE_WORKFLOW_REQUIRED'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_ticket_batch_cash_unit_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.check_ticket_batch_eligible_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; o public.occasions; feature jsonb; template jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=f.occasion;
 PERFORM public.check_ticket_batch_cash_unit_internal(o.id);
 -- Personal registration products and automatic participant imports are outside v1.
 IF EXISTS(SELECT 1 FROM public.form_fields WHERE form=f.id AND is_ticket_field AND is_required
   AND NOT is_hidden AND type NOT IN ('product_type','spot','ticket','html')) THEN
  RAISE EXCEPTION 'BATCH_PERSONAL_REGISTRATION_UNSUPPORTED'; END IF;
 SELECT value INTO feature FROM jsonb_array_elements(o.features) WHERE value->>'code'='ticket';
 IF feature IS NULL OR coalesce((feature->>'is_enabled')::boolean,false) IS NOT TRUE THEN
  RAISE EXCEPTION 'BATCH_TICKET_FEATURE_REQUIRED'; END IF;
 PERFORM public.validate_ticket_layout(feature->'layout');
 PERFORM public.validate_ticket_layout_references(o.id,feature->'layout');
 -- Explicit saved templates make anonymity and the frozen render contract reviewable.
 template:=feature#>ARRAY['layout','templates',CASE WHEN feature->>'ticket_type'='named' THEN 'named' ELSE 'wide' END];
 IF template IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements(template->'elements') e
 WHERE e->>'binding'='orderName' AND (e->>'visible')::boolean) THEN
  RAISE EXCEPTION 'BATCH_ANONYMOUS_TEMPLATE_REQUIRED'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.normalize_ticket_batch_selection_internal(p_form bigint,p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_selection) IS DISTINCT FROM 'array' OR jsonb_array_length(p_selection) NOT BETWEEN 1 AND 200
 OR octet_length(p_selection::text)>1048576 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_selection) t
 WHERE jsonb_typeof(t)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(t) k WHERE k NOT IN ('spot','fields'))) THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_SELECTION_INVALID'; END IF;
 result:=public.normalize_form_ticket_answers_internal(p_form,p_selection);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result) t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'fields','[]')) f
  WHERE NOT f ? 'product_type' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f) k
    WHERE k NOT IN ('product_type','_subFieldId','currency_code') AND k !~ '^[0-9]+$')) THEN
  RAISE invalid_parameter_value USING MESSAGE='BATCH_SELECTION_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result) t JOIN eshop.spots s ON s.id=(t->>'spot')::bigint
  JOIN public.forms f ON f.id=p_form WHERE s.blueprint IS DISTINCT FROM f.blueprint OR s.occasion IS DISTINCT FROM f.occasion) THEN
  RAISE EXCEPTION 'BATCH_SPOT_SCOPE_MISMATCH'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.check_ticket_batch_eligible_internal(bigint),
 public.normalize_ticket_batch_selection_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
-- Read preview and write command share the same normalized, server-priced selection.
CREATE OR REPLACE FUNCTION public.ticket_batch_selection_summary_internal(p_form bigint,p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE fid bigint; oc bigint; invalid boolean; currency text; total numeric; item record; capacity jsonb;
BEGIN
 SELECT occasion INTO STRICT oc FROM public.forms WHERE id=p_form;
 IF (SELECT count(*) FROM jsonb_array_elements(p_selection) t WHERE t->>'spot' IS NOT NULL)<>
  (SELECT count(DISTINCT t->>'spot') FROM jsonb_array_elements(p_selection) t WHERE t->>'spot' IS NOT NULL) THEN
  RAISE EXCEPTION 'BATCH_DUPLICATE_SPOT'; END IF;
 PERFORM public.assert_single_ticket_admission_internal(ARRAY(
   SELECT (field->>'product_type')::bigint FROM jsonb_array_elements(t->'fields') field
   UNION ALL SELECT s.product FROM eshop.spots s WHERE s.id=(t->>'spot')::bigint))
 FROM jsonb_array_elements(p_selection) t;
 FOR item IN
  WITH choices AS (
   SELECT n,(a->>'product_type')::bigint product,false seated FROM jsonb_array_elements(p_selection) WITH ORDINALITY t(v,n)
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(v->'fields','[]')) a
   UNION ALL SELECT n,s.product,true FROM jsonb_array_elements(p_selection) WITH ORDINALITY t(v,n)
    LEFT JOIN eshop.spots s ON s.id=(v->>'spot')::bigint WHERE v->>'spot' IS NOT NULL)
  SELECT c.*,p.price,p.currency_code,p.maximum,p.is_hidden,p.occasion,pt.type,pt.occasion type_occasion,p.product_type,
   EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=p_form AND ff.product_type=p.product_type AND NOT ff.is_hidden) offered,
   (SELECT count(*) FROM eshop.order_product_ticket x WHERE x.product=p.id) occupied,
   count(*) OVER(PARTITION BY c.product) selected
  FROM choices c LEFT JOIN eshop.products p ON p.id=c.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
 LOOP
  IF item.occasion IS DISTINCT FROM oc OR item.type_occasion IS DISTINCT FROM oc OR item.is_hidden
   OR item.price IS NULL OR item.price<0 OR (NOT item.seated AND NOT item.offered) THEN RAISE EXCEPTION 'BATCH_PRODUCT_UNAVAILABLE'; END IF;
  IF item.maximum>0 AND item.occupied+item.selected>item.maximum THEN RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  IF currency IS NULL THEN currency:=item.currency_code;
  ELSIF currency IS DISTINCT FROM item.currency_code THEN RAISE EXCEPTION 'BATCH_CURRENCY_MISMATCH'; END IF;
  total:=coalesce(total,0)+item.price;
 END LOOP;
 IF total IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_selection) t WHERE t->>'spot' IS NULL AND NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(t->'fields','[]')) a JOIN eshop.products p ON p.id=(a->>'product_type')::bigint
  JOIN eshop.product_types pt ON pt.id=p.product_type WHERE pt.type='spot')) THEN RAISE EXCEPTION 'BATCH_ADMISSION_PRODUCT_REQUIRED'; END IF;
 capacity:=public.get_form_capacity_snapshot_internal(p_form);
 IF (capacity->>'enabled')::boolean AND jsonb_array_length(p_selection)>(capacity->>'remainingPublic')::bigint THEN RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
 RETURN jsonb_build_object('count',jsonb_array_length(p_selection),'prices',jsonb_build_array(jsonb_build_object('currency_code',currency,'amount',total)),'capacity',capacity);
END $$;
REVOKE ALL ON FUNCTION public.ticket_batch_selection_summary_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_ticket_batches/create.sql
-- Private until immutable documents and the complete UI are available.
CREATE OR REPLACE FUNCTION public.create_ticket_batch_client_sync_v1(
 p_form bigint,p_title text,p_selection jsonb,p_secret uuid,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; o public.occasions; claimed jsonb; selection jsonb; oid bigint; tid bigint; symbol text;
 item jsonb; products jsonb; tickets jsonb:='[]'; currency text; result jsonb; bid uuid; ordinal integer:=0; snap jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 IF auth.uid() IS NULL OR public.can_write_orders(f.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 IF length(trim(p_title)) NOT BETWEEN 1 AND 200 OR p_title IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='BATCH_TITLE_INVALID'; END IF;
 selection:=public.normalize_ticket_batch_selection_internal(f.id,p_selection);
 claimed:=public.begin_client_mutation_v1(p_command_id,'inventory.ticket_batch.create',f.occasion,auth.uid(),
  encode(extensions.digest(jsonb_build_object('form',f.id,'title',p_title,'selection',selection,'secret',p_secret)::text,'sha256'),'hex'));
 IF claimed->>'disposition'='replay' THEN RETURN claimed->'response'; END IF;
 BEGIN
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
 PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(selection) t WHERE t->>'spot' IS NOT NULL));
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=f.occasion;
 PERFORM public.check_ticket_batch_eligible_internal(f.id);
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('batch-create',o.unit,o.organization),
 jsonb_build_object('actor',auth.uid(),'unit',o.unit,'organization',o.organization),jsonb_build_object('batch-create.items',jsonb_array_length(selection)));
 IF f.participant_capacity IS NOT NULL AND jsonb_array_length(selection)>(public.get_form_capacity_snapshot_internal(f.id)->>'remainingPublic')::bigint THEN
  RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
 oid:=public.allocate_ticket_order_identity_internal(f.id);
 PERFORM public.lock_ticket_order_products_internal(oid,jsonb_build_object('ticket',selection));
 PERFORM public.ticket_batch_selection_summary_internal(f.id,selection);
 PERFORM public.hold_ticket_batch_spots_internal(f.id,ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(selection) t WHERE t->>'spot' IS NOT NULL ORDER BY (t->>'spot')::bigint),p_secret);
 FOR item IN SELECT value FROM jsonb_array_elements(selection) LOOP
  IF item->>'spot' IS NOT NULL THEN
   PERFORM 1 FROM eshop.spots WHERE id=(item->>'spot')::bigint AND blueprint=f.blueprint AND occasion=f.occasion
    AND secret=p_secret AND secret_expiration_time>clock_timestamp() AND order_product_ticket IS NULL FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_SPOT_HOLD_REQUIRED'; END IF;
  END IF;
  symbol:=public.generate_ticket_symbol(o.organization,o.id);
  INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(o.id,'ordered',symbol) RETURNING id INTO tid;
  products:=public.materialize_ticket_products_internal_v1(oid,f.id,tid,item,p_secret);
  IF currency IS NULL THEN currency:=products->>'currency_code';
  ELSIF currency IS DISTINCT FROM products->>'currency_code' THEN RAISE EXCEPTION 'BATCH_CURRENCY_MISMATCH'; END IF;
  tickets:=tickets||jsonb_build_object('id',tid,'ticket_symbol',symbol,'products',products->'products');
 END LOOP;
 PERFORM public.apply_allocations(oid);
 tickets:=public.order_tickets_with_seating_internal(oid,tickets);
 UPDATE eshop.orders SET state='stock',price=NULL,payment_info=NULL,currency_code=currency,data=jsonb_build_object('tickets',tickets),updated_at=clock_timestamp() WHERE id=oid;
 SELECT jsonb_build_object('occasion',to_jsonb(o),'catalog',public.get_products_and_types(o.id)::jsonb,
 'tickets',tickets,'documentData',(SELECT jsonb_agg(jsonb_set(d,'{ticket,price_decimal_digits}',to_jsonb(CASE WHEN (d#>>'{ticket,price}')::numeric=trunc((d#>>'{ticket,price}')::numeric) THEN 0 ELSE 2 END),true) ORDER BY (x->>'id')::bigint)
 FROM jsonb_array_elements(tickets) x CROSS JOIN LATERAL (SELECT public.get_ticket_details_for_generating((x->>'id')::bigint) d) frozen),'renderContractVersion',1) INTO snap;
 INSERT INTO eshop.ticket_batches(occasion,form,stock_order_id,title,created_by,currency_code,snapshot)
 VALUES(o.id,f.id,oid,trim(p_title),auth.uid(),currency,snap) RETURNING id INTO bid;
 INSERT INTO eshop.ticket_batch_items(batch_id,ticket_id,ordinal)
 SELECT bid,(value->>'id')::bigint,n FROM jsonb_array_elements(tickets) WITH ORDINALITY x(value,n);
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=f.id;
 INSERT INTO eshop.orders_history("order",state,data,currency_code) VALUES(oid,'stock',jsonb_build_object('batchId',bid),currency);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.id,'inventory.ticket_batch.create',
 jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','insert','safeLabel','Ticket batch',
 'changedFields',jsonb_build_array('tickets','allocations'))),ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=o.id AND is_editor_order_view),
 jsonb_build_object('batchId',bid,'stockOrderId',oid,'count',jsonb_array_length(selection)));
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM=ANY(ARRAY['ADMISSION_MULTIPLE_PRODUCTS','FORM_CAPACITY_EXCEEDED','PRODUCT_CAPACITY_EXCEEDED','BATCH_SPOT_UNAVAILABLE','BATCH_SPOT_HOLD_REQUIRED','BATCH_CURRENCY_MISMATCH','BATCH_PRODUCT_UNAVAILABLE','BATCH_ADMISSION_PRODUCT_REQUIRED','CASH_SALE_INVOICE_WORKFLOW_REQUIRED','BATCH_ANONYMOUS_TEMPLATE_REQUIRED','BATCH_PERSONAL_REGISTRATION_UNSUPPORTED']) THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('errorCode',SQLERRM));
  END IF;
  RAISE;
 END;
END $$;
REVOKE ALL ON FUNCTION public.create_ticket_batch_client_sync_v1(bigint,text,jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_ticket_batch_client_sync_v1(bigint,text,jsonb,uuid,uuid) TO authenticated;

-- SOURCE: eshop_orders/order_admission_options.sql
-- Forms publish the only eligible sources. A seat selection represents its
-- entire selection unit; an admission change cannot displace another holder.
CREATE OR REPLACE FUNCTION public.order_admission_targets_internal(p_form bigint)
RETURNS TABLE(product_id bigint,spot_id bigint,spots bigint[],title text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH source AS (
   SELECT f.id,f.occasion,CASE WHEN jsonb_path_exists(o.features,
     '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN f.blueprint END AS blueprint
   FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form
 ), products AS (
   SELECT p.* FROM source f JOIN eshop.products p ON p.occasion=f.occasion AND NOT p.is_hidden
   JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.occasion=f.occasion AND pt.type='spot'
 )
 SELECT p.id,s.id,members.ids,concat_ws(' · ',p.title,group_title.title)
 FROM source f JOIN eshop.blueprint_seat_bindings sb ON sb.blueprint=f.blueprint
 JOIN eshop.spots s ON s.id=sb.spot AND s.blueprint=f.blueprint AND s.occasion=f.occasion
 JOIN products p ON p.id=s.product
 CROSS JOIN LATERAL (SELECT public.blueprint_selection_unit_spots_internal(s.id) AS ids) members
 CROSS JOIN LATERAL (SELECT string_agg(x.title,', ' ORDER BY x.id) AS title FROM eshop.spots x WHERE x.id=ANY(members.ids)) group_title
 WHERE s.id=members.ids[1]
 UNION ALL
 SELECT p.id,NULL::bigint,'{}'::bigint[],p.title
 FROM products p CROSS JOIN source f
 WHERE (f.blueprint IS NULL AND EXISTS(SELECT 1 FROM public.form_fields ff
   WHERE ff.form=f.id AND ff.product_type=p.product_type AND NOT ff.is_hidden)
   AND NOT EXISTS(SELECT 1 FROM eshop.spots seat JOIN eshop.blueprint_seat_bindings sb ON sb.spot=seat.id
     JOIN public.forms owner ON owner.blueprint=sb.blueprint
     WHERE seat.product=p.id AND owner.occasion=f.occasion))
 OR (f.blueprint IS NOT NULL AND EXISTS(
   SELECT 1 FROM eshop.blueprint_area_bindings ab JOIN eshop.product_inventory_contexts pic
     ON pic.product=ab.product AND pic.inventory_context=ab.inventory_context AND pic.quantity>0
   WHERE ab.blueprint=f.blueprint AND ab.product=p.id
 ) AND NOT EXISTS(SELECT 1 FROM eshop.spots seat JOIN eshop.blueprint_seat_bindings sb ON sb.spot=seat.id
   WHERE seat.product=p.id AND sb.blueprint=f.blueprint))
$$;
REVOKE ALL ON FUNCTION public.order_admission_targets_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_order_admission_options_v1(p_order_id bigint,p_ticket_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; blocker text; options jsonb; fields jsonb; source_spot bigint; source_product bigint; source_quantity integer:=1;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 IF o.id IS NULL OR auth.uid() IS NULL OR public.can_write_orders(o.occasion) IS NOT TRUE OR public.can_read_orders(o.occasion) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='order editor required';
 END IF;
 blocker:=public.order_admission_blocker_internal(o.id,p_ticket_id);
 IF blocker IS NOT NULL THEN RETURN jsonb_build_object('code',409,'data',jsonb_build_object('reason',blocker)); END IF;
 SELECT x.product,s.id INTO source_product,source_spot FROM eshop.order_product_ticket x
 JOIN eshop.products p ON p.id=x.product JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.type='spot'
 LEFT JOIN eshop.spots s ON s.order_product_ticket=x.id AND s.blueprint IS NOT NULL
 WHERE x."order"=o.id AND x.ticket=p_ticket_id;
 IF source_spot IS NOT NULL THEN
   source_quantity:=cardinality(public.blueprint_selection_unit_spots_internal(source_spot));
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'spotId',spot_id,'title',target.title,
    'quantity',greatest(1,cardinality(spots)),'price',p.price,'currency_code',p.currency_code)
    ORDER BY target.title,product_id,spot_id),'[]') INTO options
 FROM public.order_admission_targets_internal(o.form) target JOIN eshop.products p ON p.id=target.product_id
 WHERE p.currency_code=o.currency_code AND (source_product IS DISTINCT FROM product_id OR source_spot IS DISTINCT FROM spot_id)
   AND (p_ticket_id IS NULL OR greatest(1,cardinality(spots))=source_quantity)
   AND (spot_id IS NOT NULL OR (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0)
   AND NOT EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
     WHERE s.id=ANY(spots) AND (s.order_product_ticket IS NOT NULL OR sb.blocked OR
       s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()));
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'type',f.type,'title',coalesce(f.title,pt.title),'required',f.is_required,
   'data',f.data,'options',CASE WHEN f.type='product_type' THEN (
     SELECT coalesce(jsonb_agg(jsonb_build_object('productId',p.id,'title',p.title,
       'price',p.price,'currency_code',p.currency_code) ORDER BY p.title,p.id),'[]')
     FROM eshop.products p WHERE p.product_type=f.product_type AND p.occasion=o.occasion AND NOT p.is_hidden)
   ELSE coalesce(f.data->'options','[]') END) ORDER BY f."order",f.id),'[]') INTO fields
 FROM public.form_fields f LEFT JOIN eshop.product_types pt ON pt.id=f.product_type
 WHERE p_ticket_id IS NULL AND f.form=o.form AND f.is_ticket_field AND NOT f.is_hidden
   AND f.type NOT IN ('spot','ticket','html') AND pt.type IS DISTINCT FROM 'spot';
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('options',options,'fields',fields));
END $$;
REVOKE ALL ON FUNCTION public.get_order_admission_options_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_order_admission_options_v1(bigint,bigint) TO authenticated;

-- SOURCE: eshop_orders/order_admission_change.sql
-- Preview and confirmation prepare the same selection. Domain locks keep the
-- confirmation's selection, amounts and fingerprint stable through commit.
CREATE OR REPLACE FUNCTION public.prepare_order_admission_change_internal(
 p_order bigint,p_ticket bigint,p_target jsonb,p_answers jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; f public.forms; pi eshop.payment_info; src eshop.order_product_ticket;
 src_product jsonb; src_spot bigint; source_spots bigint[]:='{}'; source_tickets bigint[]:='{}';
 source_title text; all_same_product boolean; any_same_product boolean; target record; dst bigint; dst_spot bigint; quantity integer;
 ids bigint[]; selections jsonb:='[]'; people jsonb; person jsonb; fields jsonb; spot bigint;
 n integer:=0; delta numeric:=0; subtotal numeric; deposit numeric; currency_ok boolean; count_before integer;
 quote jsonb; facts jsonb; mapping jsonb; assignment jsonb; swap jsonb; capacity jsonb; blocker text;
BEGIN
 IF jsonb_typeof(p_target) IS DISTINCT FROM 'object' OR p_target-ARRAY['spotId','productId']<>'{}'
    OR coalesce(p_target->>'productId','')!~'^[1-9][0-9]{0,17}$'
    OR (p_target->>'spotId' IS NOT NULL AND p_target->>'spotId'!~'^[1-9][0-9]{0,17}$')
    OR jsonb_typeof(p_answers) IS DISTINCT FROM 'array' OR octet_length(p_answers::text)>131072 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid admission selection';
 END IF;
 dst:=(p_target->>'productId')::bigint;
 dst_spot:=(p_target->>'spotId')::bigint;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[o.occasion]);
 PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=o.occasion;
 -- Only lock in-scope target rows. Target availability is rechecked below.
 SELECT * INTO f FROM public.forms WHERE id=o.form AND occasion=o.occasion;
 SELECT * INTO target FROM public.order_admission_targets_internal(f.id)
   WHERE product_id=dst AND spot_id IS NOT DISTINCT FROM dst_spot;
 IF NOT FOUND THEN RAISE EXCEPTION 'ADMISSION_TARGET_UNAVAILABLE'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(target.spots) AND order_product_ticket IS NOT NULL) THEN
   RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE';
 END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[o.id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT f FROM public.forms WHERE id=o.form AND occasion=o.occasion;
 blocker:=public.order_admission_blocker_internal(o.id,p_ticket);
 IF blocker IS NOT NULL THEN RAISE EXCEPTION '%',blocker; END IF;
 PERFORM public.check_order_is_mutable(o.id);
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;

 IF p_ticket IS NOT NULL THEN
   SELECT x.* INTO STRICT src FROM eshop.order_product_ticket x
   JOIN eshop.products p ON p.id=x.product JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.type='spot'
   WHERE x.ticket=p_ticket AND x."order"=o.id;
   SELECT item INTO STRICT src_product FROM jsonb_array_elements(o.data->'tickets') t
   CROSS JOIN LATERAL jsonb_array_elements(t->'products') item
   WHERE t->>'id'=p_ticket::text AND item->>'id'=src.product::text;
   SELECT id INTO src_spot FROM eshop.spots WHERE order_product_ticket=src.id AND blueprint IS NOT NULL;
   IF src_spot IS NOT NULL THEN
     source_spots:=public.blueprint_selection_unit_spots_internal(src_spot);
   END IF;
   IF greatest(1,cardinality(target.spots))<>greatest(1,cardinality(source_spots)) OR p_answers<>'[]'::jsonb THEN
     RAISE EXCEPTION 'BLUEPRINT_INCOMPLETE_SELECTION_UNIT';
   END IF;
   IF (src.product=dst AND src_spot IS NOT DISTINCT FROM dst_spot) OR target.spots && source_spots THEN
     RAISE EXCEPTION 'ADMISSION_TARGET_UNAVAILABLE';
   END IF;
 END IF;

 quantity:=greatest(1,cardinality(target.spots));
 SELECT count(*) INTO count_before FROM public.get_order_tickets_internal(o.id) t WHERE t.state NOT IN ('storno','waitlisted');
 IF p_ticket IS NULL THEN
   IF count_before+quantity>least(public.ticket_order_limit(),coalesce((SELECT min((data->>'max_tickets')::integer)
       FROM public.form_fields WHERE form=f.id AND type='ticket'),public.ticket_order_limit()))
      OR (f.participant_capacity IS NOT NULL AND quantity>(public.get_form_capacity_snapshot_internal(f.id)->>'remainingPublic')::bigint) THEN
     RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED';
   END IF;
   people:=CASE WHEN quantity=1 THEN jsonb_build_array(p_answers) ELSE p_answers END;
   IF jsonb_array_length(people)<>quantity OR EXISTS(SELECT 1 FROM jsonb_array_elements(people) AS entry(value)
        WHERE jsonb_typeof(entry.value)<>'array') THEN RAISE EXCEPTION 'BLUEPRINT_INCOMPLETE_SELECTION_UNIT'; END IF;
   FOR person IN SELECT value FROM jsonb_array_elements(people) LOOP
     n:=n+1;
     spot:=target.spots[n];
     fields:=person;
     -- The target selector already owns the admission choice. Supply its exact
     -- form field when configured, so required products use the checkout owner.
     IF EXISTS(SELECT 1 FROM jsonb_array_elements(fields) a WHERE jsonb_typeof(a)<>'object'
       OR coalesce(a->>'_subFieldId','')!~'^[1-9][0-9]{0,17}$') THEN
       RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH';
     END IF;
     IF spot IS NULL THEN
       fields:=fields||jsonb_build_array(jsonb_build_object('product_type',dst));
     END IF;
     selections:=selections||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('spot',spot,'fields',fields)));
   END LOOP;
   selections:=public.normalize_form_ticket_answers_internal(f.id,selections);
   PERFORM public.validate_waitlist_answers_internal(f.id,o.data,selections,false);
 ELSE
   selections:=jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('spot',dst_spot,
     'fields',jsonb_build_array(jsonb_build_object('product_type',dst)))));
 END IF;

 -- Includes all existing order products, seat group members and inventory
 -- parents; a late hold or purchase is observed again under the same locks.
 SELECT ARRAY(SELECT DISTINCT (x->>'product_type')::bigint FROM jsonb_array_elements(selections) t
   CROSS JOIN LATERAL jsonb_array_elements(t->'fields') x WHERE x ? 'product_type'
   UNION SELECT s.product FROM eshop.spots s WHERE s.id=ANY(target.spots)) INTO ids;
 PERFORM public.lock_spot_assignment_scope_internal(
   ARRAY(SELECT s.id FROM eshop.spots s WHERE s.id=ANY(target.spots||source_spots) OR s.order_product_ticket=src.id ORDER BY s.id),
   '{}',true,ids,false,ARRAY[o.id],ARRAY[src.id]);
 IF public.order_admission_blocker_internal(o.id,p_ticket) IS NOT NULL THEN
   RAISE EXCEPTION '%',public.order_admission_blocker_internal(o.id,p_ticket);
 END IF;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 PERFORM public.check_blueprint_selection_units_internal(target.spots);
 IF EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
   WHERE s.id=ANY(target.spots) AND (s.order_product_ticket IS NOT NULL OR sb.blocked OR s.product IS NULL
      OR s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp())) THEN
   RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE';
 END IF;
 IF src_spot IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
   WHERE s.id=ANY(source_spots) AND (sb.spot IS NULL OR sb.blocked OR s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp())) THEN
   RAISE EXCEPTION 'BLUEPRINT_SEAT_PROTECTED';
 END IF;

 IF p_ticket IS NOT NULL AND quantity>1 THEN
   SELECT array_agg(x.ticket ORDER BY a.n),string_agg(s.title,', ' ORDER BY a.n),
     bool_and(x.product=move_to.product),bool_or(x.product=move_to.product),
     jsonb_agg(jsonb_build_object('ticketId',x.ticket,'admissionItemId',x.id,
       'expectedSpotId',s.id,'targetSpotId',move_to.id) ORDER BY a.n)
   INTO source_tickets,source_title,all_same_product,any_same_product,mapping
   FROM unnest(source_spots) WITH ORDINALITY a(spot,n)
   JOIN eshop.spots s ON s.id=a.spot JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
   JOIN eshop.spots move_to ON move_to.id=target.spots[a.n];
   IF all_same_product THEN
     assignment:=public.preview_ticket_seat_assignment(f.blueprint,mapping)->'data';
     IF jsonb_array_length(assignment->'blockers')>0 THEN
       RAISE EXCEPTION '%',assignment#>>'{blockers,0,reason}';
     END IF;
   ELSE
     -- A mixed group could reprice a member whose product did not change.
     -- The seat swap owner supports complete units with entirely new pricing.
     IF any_same_product OR EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.product_inventory_contexts pic ON pic.product=s.product
       WHERE s.id=ANY(source_spots||target.spots)) THEN RAISE EXCEPTION 'BLUEPRINT_INCOMPLETE_SELECTION_UNIT'; END IF;
     mapping:=NULL;
     SELECT public.preview_blueprint_seat_swap(o.occasion,oc.organization,oc.unit,f.blueprint,src_spot,dst_spot,true)
       INTO swap FROM public.occasions oc WHERE oc.id=o.occasion;
     IF swap->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION '%',swap->>'reason'; END IF;
     delta:=(swap#>>'{orders,0,delta}')::numeric;
     IF EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.products p ON p.id=s.product
       WHERE s.id=ANY(target.spots) AND coalesce((p.data#>>'{deposit,amount}')::numeric,0)<>0) THEN
       RAISE EXCEPTION 'ORDER_ADMISSION_DEPOSIT_UNSUPPORTED';
     END IF;
   END IF;
 ELSE
   source_tickets:=CASE WHEN p_ticket IS NULL THEN '{}' ELSE ARRAY[p_ticket] END;
   source_title:=concat_ws(' · ',src_product->>'title',(SELECT s.title FROM eshop.spots s WHERE s.id=src_spot));
   FOR person IN SELECT value FROM jsonb_array_elements(selections) LOOP
     spot:=(person->>'spot')::bigint;
     IF p_ticket IS NULL THEN
       SELECT ARRAY(SELECT (x->>'product_type')::bigint FROM jsonb_array_elements(person->'fields') x WHERE x ? 'product_type'
         UNION ALL SELECT s.product FROM eshop.spots s WHERE s.id=spot) INTO ids;
       PERFORM public.assert_single_ticket_admission_internal(ids);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(person->'fields') a
         WHERE a ? 'product_type' AND NOT a ? '_subFieldId' AND (spot IS NOT NULL OR a->>'product_type'<>dst::text)) THEN
         RAISE EXCEPTION 'PRODUCT_SCOPE_MISMATCH';
       END IF;
     ELSE
       SELECT array_agg(product) INTO ids FROM (
         SELECT x.product FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=p_ticket AND x.id<>src.id
         UNION ALL SELECT dst
       ) items;
     END IF;
     PERFORM public.assert_ticket_required_products_internal(f.id,ids);
     IF p_ticket IS NOT NULL THEN ids:=ARRAY[dst]; END IF;
     IF cardinality(ids)<>(SELECT count(DISTINCT i) FROM unnest(ids) i) OR EXISTS(
       SELECT 1 FROM unnest(ids) i LEFT JOIN eshop.products p ON p.id=i AND p.occasion=o.occasion
       LEFT JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.occasion=o.occasion
       WHERE p.id IS NULL OR pt.id IS NULL OR p.is_hidden OR p.price IS NULL OR p.price<0
     ) THEN RAISE EXCEPTION 'PRODUCT_SCOPE_MISMATCH'; END IF;
     PERFORM public.assert_admission_seating_internal(f.id,i,spot) FROM unnest(ids) i;
     SELECT coalesce(sum(p.price),0),coalesce(sum((p.data#>>'{deposit,amount}')::numeric),0),
       bool_and(p.currency_code=o.currency_code) INTO STRICT subtotal,deposit,currency_ok
     FROM eshop.products p WHERE p.id=ANY(ids);
     IF currency_ok IS NOT TRUE THEN RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;
     IF deposit<>0 AND (p_ticket IS NULL OR src.product<>dst) THEN RAISE EXCEPTION 'ORDER_ADMISSION_DEPOSIT_UNSUPPORTED'; END IF;
     -- Sum the same catalog prices that the materializer saves.
     delta:=delta+subtotal;
   END LOOP;
   IF p_ticket IS NOT NULL THEN
     IF src_product->>'price' IS NULL THEN RAISE EXCEPTION 'ADMISSION_DATA_AMBIGUOUS'; END IF;
     delta:=CASE WHEN src.product=dst THEN 0 ELSE delta-(src_product->>'price')::numeric END;
   END IF;
   IF p_ticket IS NOT NULL AND src.product=dst AND dst_spot IS NOT NULL THEN
     mapping:=jsonb_build_array(jsonb_build_object('ticketId',p_ticket,'admissionItemId',src.id,
       'expectedSpotId',src_spot,'targetSpotId',dst_spot));
     assignment:=public.preview_ticket_seat_assignment(f.blueprint,mapping)->'data';
     IF jsonb_array_length(assignment->'blockers')>0 THEN RAISE EXCEPTION '%',assignment#>>'{blockers,0,reason}'; END IF;
   ELSIF src_spot IS NOT NULL AND dst_spot IS NOT NULL AND NOT EXISTS(
     SELECT 1 FROM eshop.product_inventory_contexts WHERE product IN(src.product,dst)
   ) THEN
     SELECT public.preview_blueprint_seat_swap(o.occasion,oc.organization,oc.unit,f.blueprint,src_spot,dst_spot,true)
     INTO swap FROM public.occasions oc WHERE oc.id=o.occasion;
     IF swap->>'code'<>'200' THEN RAISE EXCEPTION '%',swap->>'reason'; END IF;
   END IF;

 END IF; -- individual move or additions

 IF delta<>0 AND coalesce(pi.deposit_amount,0)<>0 THEN RAISE EXCEPTION 'ORDER_ADMISSION_DEPOSIT_UNSUPPORTED'; END IF;
 IF delta<>0 AND public.payment_method_is_online_internal(pi.payment_method) THEN
   RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE';
 END IF;

 -- New addressed admissions use the same hold/capacity preflight as checkout.
 -- Assignment of the existing product does not consume another admission.
 IF dst_spot IS NOT NULL AND (p_ticket IS NULL OR mapping IS NULL) THEN
   capacity:=public.blueprint_hold_admission_internal(f.id,target.spots,NULL);
   IF capacity->>'code'<>'200' THEN RAISE EXCEPTION '%',capacity->>'reason'; END IF;
 END IF;

 -- Count product demand across a whole selection unit before showing the quote.
 IF p_ticket IS NULL THEN
   SELECT ARRAY(SELECT (x->>'product_type')::bigint FROM jsonb_array_elements(selections) t
     CROSS JOIN LATERAL jsonb_array_elements(t->'fields') x WHERE x ? 'product_type'
     UNION ALL SELECT s.product FROM eshop.spots s WHERE s.id=ANY(target.spots)) INTO ids;
 ELSIF quantity=1 THEN ids:=CASE WHEN src.product=dst THEN '{}' ELSE ARRAY[dst] END;
 ELSE SELECT ARRAY(SELECT s.product FROM eshop.spots s WHERE s.id=ANY(target.spots) AND mapping IS NULL) INTO ids;
 END IF;
 IF EXISTS(SELECT 1 FROM unnest(ids) product JOIN eshop.products p ON p.id=product
   GROUP BY p.id,p.maximum HAVING coalesce(p.maximum,0)>0 AND count(*)+
     (SELECT count(*) FROM eshop.order_product_ticket x WHERE x.product=p.id)>p.maximum) THEN
   RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED';
 END IF;
 -- For unaddressed products, the canonical availability owner includes
 -- standing holds. Allocation rechecks exact resources at confirmation.
 IF EXISTS(
   SELECT 1 FROM unnest(ids) AS chosen(id)
   WHERE NOT EXISTS(SELECT 1 FROM eshop.spots s WHERE s.id=ANY(target.spots) AND s.product=chosen.id)
   GROUP BY chosen.id
   HAVING count(*)>(public.blueprint_product_availability_internal(chosen.id)->>'available')::bigint
 ) THEN RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;

 quote:=jsonb_build_object('sourceTitle',source_title,'targetTitle',target.title,
   'quantity',quantity,'ticketCount',count_before+CASE WHEN p_ticket IS NULL THEN quantity ELSE 0 END,
   'priceDelta',delta,'total',o.price+delta,'balance',o.price+delta-coalesce(pi.paid,0)+coalesce(pi.returned,0),
   'currencyCode',o.currency_code);
 facts:=jsonb_build_object('revision',public.operator_order_revision_internal_v1(o.id),'payment',to_jsonb(pi),
   'form',to_jsonb(f),'selections',selections,'quote',quote,'sourceSpot',src_spot,'target',p_target,
   'layoutRevision',(SELECT layout_revision FROM eshop.blueprints WHERE id=f.blueprint),
   'assignment',assignment->'fingerprint','swap',swap->'confirmationHash');
 RETURN jsonb_build_object('quote',quote||jsonb_build_object('fingerprint',encode(extensions.digest(facts::text,'sha256'),'hex')),
   'formId',f.id,'selection',selections,'sourceItemId',src.id,'sourceSpotId',src_spot,'sourceTicketIds',source_tickets,'mapping',mapping,
   'assignmentFingerprint',assignment->'fingerprint','swap',swap,'blueprintId',f.blueprint);
END $$;
REVOKE ALL ON FUNCTION public.prepare_order_admission_change_internal(bigint,bigint,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.order_admission_rejection_internal(p_message text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE error_data jsonb:='{}'; reason text;
BEGIN
 IF left(p_message,1)='{' THEN error_data:=p_message::jsonb; END IF;
 reason:=coalesce(error_data->>'errorCode',p_message);
 IF reason<>ALL(ARRAY['ADMISSION_DATA_AMBIGUOUS','ADMISSION_MULTIPLE_PRODUCTS','ADMISSION_TARGET_UNAVAILABLE',
   'ORDER_ADMISSION_UNAVAILABLE','ORDER_ADMISSION_DEPOSIT_UNSUPPORTED','ORDER_CHANGED_RELOAD_REQUIRED',
   'ADMISSION_SOURCE_REQUIRES_SEATING','PRODUCT_SCOPE_MISMATCH','PRODUCT_NOT_IN_FORM','PRODUCT_HIDDEN','PRODUCT_CAPACITY_EXCEEDED','FORM_CAPACITY_EXCEEDED',
   'USED_TICKET_PROTECTED','BATCH_TICKET_PRINT_IMMUTABLE','STRIPE_ORDER_PRICE_IMMUTABLE','DISCOUNTED_ORDER_PRICE_IMMUTABLE',
   'REQUIRED_FIELD_MISSING','INVALID_EMAIL','FORM_FIELD_AMBIGUOUS','FORM_FIELD_SCOPE_MISMATCH',
   'FORM_FIELD_TYPE_MISMATCH','FORM_FIELD_VALUE_CONFLICT','BLUEPRINT_CURRENCY_MISMATCH','INVENTORY_CONFLICT',
   'BLUEPRINT_INCOMPLETE_SELECTION_UNIT','BLUEPRINT_SEAT_UNAVAILABLE','BLUEPRINT_SEAT_PROTECTED',
   'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED','ATOMIC_UNIT_INCOMPLETE','PRODUCT_MISMATCH','MODE_CHANGED',
   'PLACEMENT_MODE_AMBIGUOUS','ADMISSION_ASSIGNED_ELSEWHERE','CONTEXT_CHANGED','BLUEPRINT_SWAP_REJECTED',
   'BLUEPRINT_SWAP_MONEY_UNAVAILABLE','BLUEPRINT_UNIT_SIZE_MISMATCH','SEAT_UNAVAILABLE','HOLD_ACTIVE','PAYMENT_METHOD_POLICY_DISABLED',
   'PAYMENT_ACCOUNT_NOT_CONFIGURED']) THEN
   RAISE EXCEPTION '%',p_message;
 END IF;
 RETURN jsonb_strip_nulls(jsonb_build_object('reason',reason,'fieldId',error_data->'fieldId'));
END $$;
REVOKE ALL ON FUNCTION public.order_admission_rejection_internal(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_order_admission_change_v1(
 p_order_id bigint,p_ticket_id bigint,p_target jsonb,p_answers jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ bigint; prepared jsonb;
BEGIN
 SELECT occasion INTO occ FROM eshop.orders WHERE id=p_order_id;
 IF occ IS NULL OR auth.uid() IS NULL OR public.can_write_orders(occ) IS NOT TRUE OR public.can_read_orders(occ) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='order editor required';
 END IF;
 prepared:=public.prepare_order_admission_change_internal(p_order_id,p_ticket_id,p_target,p_answers);
 RETURN jsonb_build_object('code',200,'data',prepared->'quote');
EXCEPTION WHEN raise_exception OR check_violation THEN
 RETURN jsonb_build_object('code',409,'data',public.order_admission_rejection_internal(SQLERRM));
END $$;
REVOKE ALL ON FUNCTION public.preview_order_admission_change_v1(bigint,bigint,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.preview_order_admission_change_v1(bigint,bigint,jsonb,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_order_admission_change_v1(
 p_order_id bigint,p_ticket_id bigint,p_target jsonb,p_answers jsonb,p_fingerprint text,p_command_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; command_name text; started jsonb; prepared jsonb; quote jsonb;
 delta numeric; result jsonb; person jsonb; ticket_rows jsonb:='[]'; tid bigint; symbol text; note text;
 ids bigint[]:='{}'; item bigint; source bigint; target bigint; product bigint; plan bigint; swap jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 IF o.id IS NULL OR auth.uid() IS NULL OR public.can_write_orders(o.occasion) IS NOT TRUE OR public.can_read_orders(o.occasion) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='order editor required';
 END IF;
 IF p_fingerprint IS NULL OR p_fingerprint!~'^[a-f0-9]{64}$' OR p_command_id IS NULL
    OR octet_length(p_answers::text)>131072 OR octet_length(p_target::text)>512 THEN
   RAISE invalid_parameter_value USING MESSAGE='confirmed admission preview required';
 END IF;
 command_name:=CASE WHEN p_ticket_id IS NULL THEN 'orders.admission.add' ELSE 'orders.admission.move' END;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[o.occasion]);
 started:=public.begin_client_mutation_v1(p_command_id,command_name,o.occasion,auth.uid(),
   encode(extensions.digest(jsonb_build_array(o.id,p_ticket_id,p_target,p_answers,p_fingerprint)::text,'sha256'),'hex'));
 IF public.can_write_orders(o.occasion) IS NOT TRUE OR public.can_read_orders(o.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;

 BEGIN
   prepared:=public.prepare_order_admission_change_internal(o.id,p_ticket_id,p_target,p_answers);
   quote:=prepared->'quote';
   IF quote->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN
     RAISE EXCEPTION 'ORDER_CHANGED_RELOAD_REQUIRED';
   END IF;
   PERFORM public.admit_order_mutation_v1(o.occasion,(quote->>'quantity')::bigint);
   SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
   SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
   delta:=(quote->>'priceDelta')::numeric;
   IF p_ticket_id IS NULL THEN
     FOR person IN SELECT value FROM jsonb_array_elements(prepared->'selection') LOOP
       SELECT value->>'note' INTO note FROM jsonb_array_elements(person->'fields') WHERE value ? 'note' LIMIT 1;
       symbol:=public.generate_ticket_symbol(oc.organization,o.occasion);
       INSERT INTO eshop.tickets(occasion,state,ticket_symbol,note,data)
       VALUES(o.occasion,'ordered',symbol,note,public.extract_ticket_answers_internal(o.form,person)) RETURNING id INTO tid;
       result:=public.materialize_ticket_products_internal_v1(o.id,o.form,tid,person,NULL);
       ticket_rows:=ticket_rows||jsonb_build_array(jsonb_build_object('id',tid,'ticket_symbol',symbol,
         'note',note,'products',result->'products'));
       ids:=array_append(ids,tid);
     END LOOP;
     UPDATE eshop.orders SET data=jsonb_set(data,'{tickets}',coalesce(data->'tickets','[]')||ticket_rows),
       price=price+delta,updated_at=clock_timestamp() WHERE id=o.id;
     UPDATE eshop.payment_info SET amount=amount+delta WHERE id=o.payment_info AND delta<>0;
   ELSE
     ids:=ARRAY(SELECT jsonb_array_elements_text(prepared->'sourceTicketIds')::bigint);
     item:=(prepared->>'sourceItemId')::bigint;
     source:=(prepared->>'sourceSpotId')::bigint;
     target:=(p_target->>'spotId')::bigint;
     product:=(p_target->>'productId')::bigint;
     plan:=(prepared->>'blueprintId')::bigint;
     IF prepared->>'mapping' IS NOT NULL THEN
       result:=public.set_ticket_seat_assignments(plan,prepared->'mapping',prepared->>'assignmentFingerprint',
         md5(p_command_id::text||':seating')::uuid);
       IF result->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'ORDER_CHANGED_RELOAD_REQUIRED'; END IF;
     ELSIF prepared->>'swap' IS NOT NULL THEN
       swap:=prepared->'swap';
       result:=public.swap_blueprint_seats(o.occasion,oc.organization,oc.unit,plan,source,target,
         ARRAY(SELECT jsonb_array_elements_text(swap->'sourceSpotIds')::bigint),
         ARRAY(SELECT jsonb_array_elements_text(swap->'targetSpotIds')::bigint),
         (swap->>'layoutRevision')::bigint,swap->>'confirmationHash',md5(p_command_id::text||':swap')::uuid,true);
       IF result->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'ORDER_CHANGED_RELOAD_REQUIRED'; END IF;
     ELSE
       -- Keep the admission item and ticket identities. Reserve the new seat
       -- or standing capacity before releasing the old addressed seat.
       PERFORM public._swap_spots_update_ticket(item,product,target);
       IF target IS NOT NULL THEN
         UPDATE eshop.spots SET order_product_ticket=item,state='ordered',secret=NULL,
           secret_expiration_time=NULL,updated_at=clock_timestamp() WHERE id=target;
         -- The addressed seat replaces any anonymous allocation for that item.
         UPDATE eshop.spots SET order_product_ticket=NULL,state=NULL,resource=NULL,updated_at=clock_timestamp()
           WHERE order_product_ticket=item AND blueprint IS NULL;
       ELSE
         PERFORM public.apply_allocations(o.id);
       END IF;
       UPDATE eshop.spots SET order_product_ticket=NULL,state=NULL,updated_at=clock_timestamp() WHERE id=source;
     END IF;
     UPDATE eshop.tickets SET updated_at=clock_timestamp() WHERE id=ANY(ids);
   END IF;

   IF (SELECT price FROM eshop.orders WHERE id=o.id) IS DISTINCT FROM (quote->>'total')::numeric THEN
     RAISE EXCEPTION 'ORDER_CHANGED_RELOAD_REQUIRED';
   END IF;
   IF prepared->>'swap' IS NULL THEN
     PERFORM public.apply_allocations(o.id);
     UPDATE eshop.orders SET data=jsonb_set(data,'{tickets}',public.order_tickets_with_seating_internal(id,data->'tickets')),
       updated_at=clock_timestamp() WHERE id=o.id;
     IF p_ticket_id IS NULL AND o.state IN ('paid','sent') THEN
       -- Reconciliation can move the whole order back to ordered if it now
       -- has a balance. Already paid orders give the new tickets paid status.
       UPDATE eshop.tickets SET state='paid' WHERE id=ANY(ids);
     END IF;
     PERFORM public.reconcile_order_payment_internal_v1(o.id,'product_edit');
     PERFORM public.refresh_order_payment_deadline_internal(o.id);
     IF p_ticket_id IS NULL AND o.state='sent' THEN
       PERFORM public.enqueue_eligible_order_tickets_internal(o.id,true);
     END IF;
     INSERT INTO eshop.orders_history("order",data,state,price,currency_code)
     SELECT id,data,state,price,currency_code FROM eshop.orders WHERE id=o.id;
   END IF;
   IF prepared->>'mapping' IS NULL THEN
     UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=o.form;
   END IF;
 EXCEPTION WHEN raise_exception OR check_violation THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
     public.order_admission_rejection_internal(SQLERRM));
 END;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,command_name,
   jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
     'safeLabel','Order admission','changedFields',jsonb_build_array('tickets','allocations'))),
   ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=o.occasion),
   quote||jsonb_build_object('orderId',o.id,'ticketIds',to_jsonb(ids)));
END $$;
REVOKE ALL ON FUNCTION public.confirm_order_admission_change_v1(bigint,bigint,jsonb,jsonb,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_order_admission_change_v1(bigint,bigint,jsonb,jsonb,text,uuid) TO authenticated;

-- SOURCE: eshop_orders/update_ticket_products_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_price            numeric;
  v_reconciliation   jsonb;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_current_products_for_compare jsonb;
  v_admission jsonb;
  v_requested_admission jsonb;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT occasion FROM eshop.tickets WHERE id=p_ticket_id));
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=p_ticket_id));
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1 FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT public.can_write_orders(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);
  IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=p_ticket_id AND state='used') THEN
    RAISE EXCEPTION 'USED_TICKET_PROTECTED';
  END IF;
  PERFORM public.assert_order_discount_unchanged_internal(v_order_id);
  PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[p_ticket_id]);
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_payment_info_id AND public.payment_method_is_online_internal(payment_method)) THEN
    RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;

  IF jsonb_typeof(p_products) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'PRODUCT_SCOPE_MISMATCH';
  END IF;
  PERFORM public.lock_ticket_order_products_internal(v_order_id,
    jsonb_build_object('ticket',jsonb_build_array(jsonb_build_object('fields',(
      SELECT coalesce(jsonb_agg(jsonb_build_object('product_type',p.id)),'[]')
      FROM jsonb_array_elements(p_products) x
      JOIN eshop.products p ON p.id=(x->>'id')::bigint AND p.occasion=v_occasion_id
    )))));

  v_admission := public.ticket_admission_integrity_internal(v_order_id,p_ticket_id);
  IF v_admission->>'reason' IS NOT NULL THEN
    RAISE EXCEPTION 'ADMISSION_DATA_AMBIGUOUS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_products) x
    LEFT JOIN eshop.products p ON p.id=(x->>'id')::bigint AND p.occasion=v_occasion_id
    LEFT JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.occasion=v_occasion_id
    WHERE p.id IS NULL OR pt.id IS NULL OR x->>'price' IS NULL
  ) THEN
    RAISE EXCEPTION 'PRODUCT_SCOPE_MISMATCH';
  END IF;
  SELECT coalesce(jsonb_agg(p.id ORDER BY p.id),'[]') INTO v_requested_admission
  FROM jsonb_array_elements(p_products) x
  JOIN eshop.products p ON p.id=(x->>'id')::bigint AND p.occasion=v_occasion_id
  JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.occasion=v_occasion_id
  WHERE pt.type='spot';
  IF v_requested_admission IS DISTINCT FROM v_admission->'productIds' THEN
    RAISE EXCEPTION 'ADMISSION_CHANGE_REQUIRES_COMMAND';
  END IF;

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_products) x JOIN eshop.products p ON p.id=(x->>'id')::bigint
    WHERE p.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id)+
      CASE WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket_id AND product=p.id) THEN 0 ELSE 1 END>p.maximum) THEN
    RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  /* get old products for the ticket */
  SELECT t->'products' INTO v_old_products FROM jsonb_array_elements(v_old_data->'tickets') t
  WHERE t->>'id'=p_ticket_id::text;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) the shared owner decides eligibility and owns one invalidation. */
  v_reconciliation := public.reconcile_order_payment_internal_v1(v_order_id,'product_edit');
  SELECT price INTO v_price FROM eshop.orders WHERE id=v_order_id;

  PERFORM public.refresh_order_payment_deadline_internal(v_order_id);

  PERFORM public.apply_allocations(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_reconciliation->>'final_state',
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket_id]);
  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;

-- The receipted Client Sync command must use the same payment and email
-- transition as the legacy RPC, rather than its pre-email-cutover copy.
CREATE OR REPLACE FUNCTION public.update_ticket_products_internal_v1(
  p_ticket_id bigint, p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_ticket_products_wsv2(p_ticket_id, p_products);
END;
$$;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC, anon, authenticated;

-- SOURCE: eshop_orders/update_ticket_products_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_client_sync_v1(p_ticket bigint, p_products jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[]; v_result jsonb;
BEGIN
  SELECT t.occasion INTO v_occasion FROM eshop.tickets t WHERE t.id=p_ticket;
  IF v_actor IS NULL OR v_occasion IS NULL OR p_products IS NULL
    OR jsonb_typeof(p_products)<>'array' OR jsonb_array_length(p_products)>1000
    OR octet_length(p_products::text)>1048576
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'ticket',p_ticket,'products',p_products)::text,'UTF8'),'sha256'),'hex');
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.ticket.products',v_occasion,v_actor,v_hash);
  IF public.can_write_orders(v_occasion) IS NOT TRUE THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required';
  END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_users
    FROM public.occasion_users ou
    WHERE ou.occasion=v_occasion AND ou.ticket=p_ticket;
  BEGIN
    v_result:=public.update_ticket_products_internal_v1(p_ticket,p_products);
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT IN ('ADMISSION_CHANGE_REQUIRES_COMMAND','ADMISSION_DATA_AMBIGUOUS') THEN RAISE; END IF;
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason',SQLERRM));
  END;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.ticket.products',jsonb_build_array(jsonb_build_object(
      'entityType','ticket_products','entityId',p_ticket,'operation','update',
      'safeLabel','Ticket products','changedFields',jsonb_build_array(
        'products','allocations'))),v_users,v_result);
END; $function$
;
REVOKE ALL ON FUNCTION public.update_ticket_products_client_sync_v1(bigint,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_ticket_products_client_sync_v1(bigint,jsonb,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_ticket_products_client_sync_v1(bigint,jsonb,uuid) TO authenticated;

-- SOURCE: eshop_orders/operator_orders.sql
-- Thin delegated adapters over the existing order, payment, report and mail owners.
-- Scope is locked in the same transaction as every read, write and receipt replay.
CREATE OR REPLACE FUNCTION public.check_operator_order_scope_internal_v1(
  p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
  PERFORM 1 FROM public.occasions o JOIN public.user_info ui ON ui.organization=o.organization AND ui.id=auth.uid()
    WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit) FOR SHARE OF o;
  IF NOT FOUND OR public.can_read_orders(p_occasion) IS DISTINCT FROM TRUE OR (p_write AND public.can_write_orders(p_occasion) IS DISTINCT FROM TRUE) THEN
    RAISE insufficient_privilege USING MESSAGE='order context unavailable'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.operator_order_revision_internal_v1(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('order',to_jsonb(o),
   'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE p.id=o.payment_info),
   'items',(SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i WHERE i."order"=o.id),
   'tickets',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id)))::text,'UTF8'),'sha256'),'hex')
 FROM eshop.orders o WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_facts_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('id',o.id,'occasionId',o.occasion,'symbol',o.order_symbol,'state',o.state,
   'ticketCount',(SELECT count(DISTINCT i.ticket) FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket WHERE i."order"=o.id AND o.state IS DISTINCT FROM 'storno' AND o.state IS DISTINCT FROM 'waitlisted' AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'),
   'price',o.price::text,'currency',o.currency_code,'allowedActions',public.get_order_allowed_actions_internal_v1(o.id),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'net',(coalesce(p.paid,0)-coalesce(p.returned,0))::text,'pending',(SELECT coalesce(sum(r.amount),0)::text FROM eshop.refund_requests r WHERE r.payment_info=p.id AND r.status IN ('pending','processing','unknown'))) END)
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_snapshot_internal_v1(p_order bigint,p_detail boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.operator_order_facts_internal_v1(o.id) || jsonb_build_object(
   'createdAt',o.created_at,'updatedAt',o.updated_at,'revision',public.operator_order_revision_internal_v1(o.id),
   'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('method',p.payment_method,'amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'net',(coalesce(p.paid,0)-coalesce(p.returned,0))::text,'pending',(SELECT coalesce(sum(r.amount),0)::text FROM eshop.refund_requests r WHERE r.payment_info=p.id AND r.status IN ('pending','processing','unknown')),'policy',p.data->'payment_policy','variableSymbol',p.variable_symbol::text,'deadline',p.deadline) END)
   || CASE WHEN p_detail THEN jsonb_build_object('note',o.note_hidden,'responses',coalesce(o.data->'fields','[]'),
     'formFields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'type',f.type) ORDER BY f.id),'[]') FROM public.form_fields f WHERE f.form=o.form),
     'tickets',public.order_tickets_with_seating_internal(o.id,(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'state',t.state,
        'products',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',pr.id,'title',pr.title,'price',jsonb_path_query_first(o.data,'$.tickets[*] ? (@.id == $ticket).products[*] ? (@.id == $product).price',jsonb_build_object('ticket',t.id,'product',pr.id))#>>'{}','currentPrice',pr.price::text) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i JOIN eshop.products pr ON pr.id=i.product WHERE i."order"=o.id AND i.ticket=t.id)) ORDER BY t.id),'[]')
       FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id)))) ELSE '{}'::jsonb END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_summary_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_set(facts,'{allowedActions}',
   CASE WHEN facts->'allowedActions' ? 'view' THEN '["view"]'::jsonb ELSE '[]'::jsonb END)
 FROM (SELECT public.operator_order_facts_internal_v1(p_order) facts) safe;
$$;

CREATE OR REPLACE FUNCTION public.get_operator_order_summaries_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_symbol text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR (p_symbol IS NOT NULL AND p_symbol !~ '^[A-Z0-9]{10}$')
   OR (p_state IS NOT NULL AND length(p_state)>40)
   OR (p_order IS NOT NULL AND (p_before IS NOT NULL OR p_state IS NOT NULL OR p_symbol IS NOT NULL OR p_limit<>25)) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order summary page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_summary_internal_v1(p_order)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (p_symbol IS NULL OR order_symbol=p_symbol)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_summary_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN p_symbol IS NULL AND (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

REVOKE ALL ON FUNCTION public.operator_order_facts_internal_v1(bigint),public.operator_order_summary_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_operator_order_report_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb; v_link text;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 SELECT link INTO v_link FROM public.occasions WHERE id=p_occasion;
 r:=public.get_report_ws(v_link);
 IF (r->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order report unavailable'; END IF;
 RETURN jsonb_build_object('occasionId',p_occasion,'report',r->'report',
   'waitingTickets',(SELECT count(*) FROM eshop.tickets WHERE occasion=p_occasion AND state='waitlisted'));
END $$;

CREATE OR REPLACE FUNCTION public.get_operator_orders_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_search text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR coalesce(length(p_search),0)>200 THEN RAISE invalid_parameter_value USING MESSAGE='invalid order page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_snapshot_internal_v1(p_order,true)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (nullif(p_search,'') IS NULL OR position(lower(p_search) IN lower(concat_ws(' ',order_symbol,data->>'name',data->>'surname',data->>'email')))>0)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_snapshot_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

CREATE OR REPLACE FUNCTION public.manage_operator_order_v1(p_occasion bigint,p_organization bigint,p_unit bigint,
  p_order bigint,p_command_id uuid,p_expected_revision text,p_action text,p_changes jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_unit bigint; v_begin jsonb; v_hash text; v_child uuid;
 v_result jsonb; v_actions jsonb; v_item jsonb; v_products jsonb; v_message jsonb; v_users uuid[]; v_data jsonb;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,true);
 IF p_action IS NULL OR p_expected_revision IS NULL OR p_action NOT IN('update','cancel','mark_paid','record_payment','send_tickets') OR p_expected_revision !~ '^[a-f0-9]{64}$'
   OR p_changes IS NULL OR jsonb_typeof(p_changes)<>'object' OR octet_length(p_changes::text)>65536 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order command'; END IF;
 IF p_action NOT IN('update','record_payment') AND p_changes<>'{}'::jsonb THEN RAISE invalid_parameter_value USING MESSAGE='unexpected order changes'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('order',p_order,'occasion',p_occasion,'organization',p_organization,'unit',p_unit,'revision',p_expected_revision,'action',p_action,'changes',p_changes)::text,'UTF8'),'sha256'),'hex');
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 v_begin:=public.begin_client_mutation_v1(p_command_id,'orders.operator.'||p_action,p_occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN jsonb_set(v_begin->'response','{mutation,replayed}','true'); END IF;
 -- Preserve the domain lock order, including form -> order and blueprint scope.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_order AND occasion=p_occasion FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion;
 IF public.operator_order_revision_internal_v1(p_order) IS DISTINCT FROM p_expected_revision THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('orderId',p_order,'reason','ORDER_CHANGED_RELOAD_REQUIRED')); END IF;
 v_actions:=public.get_order_allowed_actions_internal_v1(p_order);
 IF NOT (v_actions ? CASE p_action WHEN 'update' THEN CASE WHEN p_changes ? 'note' AND p_changes - 'note'='{}'::jsonb THEN 'note' ELSE 'edit' END WHEN 'cancel' THEN 'cancel' WHEN 'mark_paid' THEN 'paid' WHEN 'record_payment' THEN 'edit' ELSE 'send' END) THEN
   RAISE insufficient_privilege USING MESSAGE='order action unavailable'; END IF;
 v_child:=md5(p_command_id::text||':domain')::uuid;
 IF p_action='cancel' THEN
   v_result:=public.storno_order_client_sync_v1(p_order,v_child);
 ELSIF p_action='update' THEN
   IF p_changes - ARRAY['responses','note','tickets','paymentDeadline']::text[]<>'{}'::jsonb OR p_changes='{}' THEN RAISE invalid_parameter_value USING MESSAGE='invalid order changes'; END IF;
   IF p_changes ? 'paymentDeadline' THEN
     IF v_pi.id IS NULL OR public.payment_method_is_online_internal(v_pi.payment_method)
       OR jsonb_typeof(p_changes->'paymentDeadline') NOT IN ('null','string') THEN
       RAISE invalid_parameter_value USING MESSAGE='payment deadline unavailable'; END IF;
     PERFORM public.check_order_is_mutable(p_order);
     PERFORM public.set_payment_deadline(v_pi.id,(p_changes->>'paymentDeadline')::timestamptz);
     INSERT INTO eshop.orders_history("order",data,state,price,currency_code)
     VALUES(p_order,v_order.data||jsonb_build_object('payment',public.customer_order_payment_internal(p_order)),v_order.state,v_order.price,v_order.currency_code);
   END IF;
   IF p_changes ? 'responses' THEN PERFORM public.update_order_responses(p_order,p_changes->'responses'); END IF;
   IF p_changes ? 'note' THEN
     v_result:=public.update_order_note_hidden(p_order,p_changes->>'note');
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='order note rejected'; END IF;
   END IF;
   FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_changes->'tickets','[]')) LOOP
     IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=p_order AND ticket=(v_item->>'ticketId')::bigint) THEN RAISE insufficient_privilege USING MESSAGE='ticket unavailable'; END IF;
     SELECT coalesce(jsonb_agg(jsonb_build_object('id',x->'productId','price',x->'price')),'[]') INTO v_products FROM jsonb_array_elements(v_item->'products') x;
     v_result:=public.update_ticket_products_client_sync_v1((v_item->>'ticketId')::bigint,v_products,md5(p_command_id::text||':ticket:'||(v_item->>'ticketId'))::uuid);
     IF v_result#>>'{data,reason}' IN ('ADMISSION_CHANGE_REQUIRES_COMMAND','ADMISSION_DATA_AMBIGUOUS') THEN
       RAISE EXCEPTION '%',v_result#>>'{data,reason}';
     END IF;
     IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='ticket products rejected'; END IF;
   END LOOP;
 ELSIF p_action='mark_paid' THEN
   v_result:=public.update_order_and_tickets_to_paid_ws(p_order);
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='payment state rejected'; END IF;
   v_result:=NULL;
 ELSIF p_action='record_payment' THEN
   IF NOT (p_changes ?& ARRAY['amount','currency','receivedAt']) OR p_changes - ARRAY['amount','currency','receivedAt','note']::text[]<>'{}'::jsonb
     OR jsonb_typeof(p_changes->'amount') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'currency') IS DISTINCT FROM 'string' OR jsonb_typeof(p_changes->'receivedAt') IS DISTINCT FROM 'string'
     OR v_pi.id IS NULL OR public.payment_method_is_online_internal(v_pi.payment_method) OR (p_changes->>'currency') IS DISTINCT FROM trim(v_order.currency_code)
     OR (p_changes->>'amount') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR (p_changes->>'amount')::numeric<=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='manual payment unavailable'; END IF;
   PERFORM public.command_payment_operation(p_changes||jsonb_build_object('operation','record_payment',
     'orderId',p_order,'method','cash'),md5(p_command_id::text||':payment')::uuid);
 ELSIF p_action='send_tickets' THEN
   v_message:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',p_order,'requested_by',auth.uid()),p_organization,p_occasion,v_unit,now(),'operator:'||p_command_id);
 END IF;
 v_data:=jsonb_build_object('orderId',p_order,'occasionId',p_occasion,'revision',public.operator_order_revision_internal_v1(p_order))
   ||CASE WHEN v_message IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('delivery','queued','messageId',v_message->'message_id') END;
 IF v_result ? 'mutation' THEN
   IF (v_result->>'code')::int<>200 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='cancellation rejected'; END IF;
   v_result:=jsonb_set(v_result,'{data}',v_data);
   v_result:=jsonb_set(v_result,'{mutation,commandId}',to_jsonb(p_command_id));v_result:=jsonb_set(v_result,'{mutation,receiptId}',to_jsonb(p_command_id));
   RETURN public.finish_client_mutation_v1(p_command_id,v_result,(v_result#>>'{mutation,commitId}')::uuid);
 END IF;
 IF p_action='send_tickets' THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,v_data);
 END IF;
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=p_occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,'orders.operator.'||p_action,
   jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,'operation','update','safeLabel','Order management','changedFields',jsonb_build_array(p_action))),v_users,v_data);
END $$;

REVOKE ALL ON FUNCTION public.check_operator_order_scope_internal_v1(bigint,bigint,bigint,boolean),public.operator_order_revision_internal_v1(bigint),
 public.operator_order_snapshot_internal_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_report_v1(bigint,bigint,bigint),public.get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint),
 public.manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb) TO authenticated;

-- SOURCE: eshop_orders/get_products_for_ticket.sql
CREATE OR REPLACE FUNCTION public.get_products_for_ticket(
  ticket_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion_id bigint;
  v_order_json jsonb;
  v_payment_info_json jsonb;
  v_ticket jsonb;
  v_latest_sent_at timestamptz;
  v_is_newer_available boolean := FALSE;
  v_order_id bigint;
  v_changes jsonb;
  v_admission jsonb;
  v_ticket_state text;
  v_batch boolean;
  v_actions jsonb;
  reference_history_data jsonb;
BEGIN
  -- Find the order containing the ticket and LEFT JOIN its associated payment_info.
  SELECT
    o.id,
    o.occasion,
    to_jsonb(o),
    to_jsonb(pi)
  INTO
    v_order_id,
    v_occasion_id,
    v_order_json,
    v_payment_info_json
  FROM eshop.orders AS o
  LEFT JOIN eshop.payment_info AS pi ON o.payment_info = pi.id
  WHERE EXISTS (
    SELECT 1
    FROM   jsonb_array_elements(o.data->'tickets') AS t
    WHERE  (t->>'id')::bigint = ticket_id
  );

  -- Check if the order was found.
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'code',    404,
      'message', 'Ticket not found'
    );
  END IF;

  -- Permission check.
  IF public.can_read_orders(v_occasion_id) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'code',    403,
      'message', 'Not authorized to view this ticket'
    );
  END IF;

  -- Extract the full JSON object for the specified ticket from the order's data.
  SELECT t
  INTO   v_ticket
  FROM   jsonb_array_elements(v_order_json->'data'->'tickets') AS t
  WHERE  (t->>'id')::bigint = ticket_id;

  v_admission := public.ticket_admission_integrity_internal(v_order_id,ticket_id)-'productIds';
  v_admission := v_admission||jsonb_build_object('recordedPlaces',coalesce((
    SELECT jsonb_agg(DISTINCT concat_ws(' · ',place->>'groupTitle',place->>'title'))
    FROM jsonb_array_elements(public.order_admin_places_internal(v_order_id)) place
    WHERE place->>'ticketId'=ticket_id::text),'[]'));
  v_actions := CASE WHEN public.can_write_orders(v_occasion_id) IS TRUE
    THEN public.get_order_allowed_actions_internal_v1(v_order_id) ELSE '["view"]'::jsonb END;
  SELECT t.state, EXISTS(SELECT 1 FROM eshop.ticket_batch_items bi WHERE bi.ticket_id=t.id)
  INTO v_ticket_state,v_batch FROM eshop.tickets t WHERE t.id=ticket_id;
  v_ticket := public.order_ticket_admission_snapshot_internal(v_ticket,v_occasion_id)
    || jsonb_build_object('state',v_ticket_state,'batch',CASE WHEN v_batch THEN '{}'::jsonb END);
  v_order_json := v_order_json || jsonb_build_object('allowedActions',v_actions,'payment_method',v_payment_info_json->'payment_method');

  v_changes := public.get_order_change_summary_v1(v_order_id);
  reference_history_data := v_changes->'referenceOrder';
  v_latest_sent_at := (v_changes->>'latestSentAt')::timestamptz;
  v_is_newer_available := (v_changes->>'hasChanges')::boolean;

  -- Build the simplified and comprehensive JSONB response object.
  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object(
      'ticket', v_ticket,
      'admission', v_admission,
      'canEdit', public.can_write_orders(v_occasion_id) IS TRUE AND v_actions ? 'edit'
        AND v_ticket_state NOT IN ('used','storno','waitlisted') AND NOT v_batch
        AND v_admission->>'reason' IS NULL
        AND NOT public.payment_method_is_online_internal(v_payment_info_json->>'payment_method')
        AND NOT EXISTS(SELECT 1 FROM eshop.order_discounts d WHERE d.order_id=v_order_id),
      'order', v_order_json,
      'payment_info', v_payment_info_json,
      'order_history', jsonb_build_object(
          'latest_sent_at', v_latest_sent_at,
          'is_newer_version_available', v_is_newer_available
      ),
      'reference_order_data', reference_history_data,
      'order_changes', v_changes
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'code',    500,
    'message', SQLERRM
  );
END;
$$;

-- SOURCE: eshop_orders/get_products_for_ticket_all_available.sql
CREATE OR REPLACE FUNCTION public.get_products_for_ticket_all_available(
  ticket_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion_id bigint;
  v_available   jsonb;
BEGIN
  -- find the ticket’s occasion
  SELECT occasion
  INTO   v_occasion_id
  FROM   eshop.tickets
  WHERE  id = ticket_id;

  IF NOT FOUND OR v_occasion_id IS NULL THEN
    RETURN jsonb_build_object(
      'code',    404,
      'message', 'Ticket not found'
    );
  END IF;

  IF public.can_read_orders(v_occasion_id) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'code',    403,
      'message', 'Not authorized'
    );
  END IF;

  -- aggregate all products for that occasion
  SELECT jsonb_agg(
           jsonb_build_object(
             'id',            p.id,
             'title',         p.title,
             'price',         p.price,
             'currency_code', p.currency_code,
             'type_title',    pt.title,
             'type',          pt.type,
             'product_type',  pt.id
           )
         )
  INTO   v_available
  FROM   eshop.products p
  JOIN eshop.product_types pt
    ON pt.id = p.product_type
  WHERE p.occasion=v_occasion_id AND pt.occasion=v_occasion_id AND pt.type IS DISTINCT FROM 'spot';

  RETURN jsonb_build_object(
    'code', 200,
    'data', COALESCE(v_available, '[]'::jsonb)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'code',    500,
    'message', SQLERRM
  );
END;
$$;

-- SOURCE: eshop_orders/get_order_admin_detail.sql
-- Exact-order read projection. This fingerprint is a read consistency token,
-- never authorization or a command fence. No registry, trigger, locks or writes.
CREATE OR REPLACE FUNCTION public.order_admin_places_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH own AS (
  SELECT x.id item_id,x.ticket,x.product,o.occasion,o.form,o.state order_state,t.state ticket_state,
   count(*) FILTER (WHERE pt.type='spot') OVER(PARTITION BY x.ticket) primary_count,
   pt.type product_type
  FROM eshop.orders o JOIN eshop.order_product_ticket x ON x."order"=o.id
  JOIN eshop.tickets t ON t.id=x.ticket AND t.occasion=o.occasion
  JOIN eshop.products p ON p.id=x.product AND p.occasion=o.occasion
  JOIN eshop.product_types pt ON pt.id=p.product_type WHERE o.id=p_order
 ), admission_integrity AS MATERIALIZED (
   SELECT ticket,public.ticket_admission_integrity_internal(p_order,ticket)->>'reason' AS problem
   FROM (SELECT DISTINCT ticket FROM own) tickets
 ), places AS (
 SELECT x.*,integrity.problem AS admission_problem,s.id spot_id,coalesce(s.blueprint,ab.blueprint) blueprint_id,
 coalesce(sb.node_id,ab.node_id) node_id,sb.group_node,sb.selection_unit,
 s.title,coalesce(sb.blocked,false) blocked,ab.node_id IS NOT NULL standing,
 (SELECT count(*) FROM eshop.spots sp WHERE sp.order_product_ticket=x.item_id AND sp.blueprint IS NOT NULL) addressed_count,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket other WHERE other.ticket=x.ticket AND other."order"<>p_order) foreign_order,
 b.layout,
 EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) has_node,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=sb.group_node::text) group_title,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) node_title
 FROM own x JOIN admission_integrity integrity ON integrity.ticket=x.ticket JOIN eshop.spots s ON s.order_product_ticket=x.item_id AND s.occasion=x.occasion
 LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=s.blueprint
 LEFT JOIN public.forms f ON f.id=x.form AND f.occasion=x.occasion
 LEFT JOIN eshop.blueprint_area_bindings ab ON s.blueprint IS NULL AND ab.inventory_context=s.inventory_context AND ab.product=x.product
   AND ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
     JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
       AND candidate.product=x.product AND target.occasion=x.occasion HAVING count(DISTINCT candidate.blueprint)=1))
 LEFT JOIN eshop.blueprints b ON b.id=coalesce(s.blueprint,ab.blueprint) AND b.occasion=x.occasion
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'spotId',spot_id,'ticketId',ticket,'admissionItemId',item_id,'productId',product,
  'blueprintId',blueprint_id,'nodeId',node_id,'groupNodeId',group_node,'selectionUnitId',selection_unit,
  'title',coalesce(node_title,title),'groupTitle',group_title,'standing',standing,
  'active',ticket_state NOT IN ('storno','waitlisted') AND order_state NOT IN ('storno','stock','waitlisted')
    AND admission_problem IS NULL AND primary_count=1 AND NOT foreign_order AND NOT blocked AND (standing OR addressed_count=1) AND has_node,
  'problem',CASE WHEN admission_problem IS NOT NULL OR primary_count<>1 OR foreign_order OR addressed_count>1 THEN 'ADMISSION_DATA_AMBIGUOUS'
    WHEN ticket_state='storno' OR order_state='storno' THEN 'HISTORICAL'
    WHEN NOT has_node THEN 'PLACE_NOT_IN_CURRENT_PLAN' WHEN blocked THEN 'BLOCKED' END
 ) ORDER BY item_id,spot_id,node_id),'[]') FROM places;
$$;
REVOKE ALL ON FUNCTION public.order_admin_places_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One canonical placement snapshot/fingerprint. The plan reader must not rebuild
-- payment, form, or email projections just to validate its read consistency token.
CREATE OR REPLACE FUNCTION public.order_admin_placement_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; places jsonb; tickets jsonb; plans jsonb; tr bigint;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL THEN RETURN NULL; END IF;
 places:=public.order_admin_places_internal(o.id);
 SELECT min(b.id) INTO tr FROM eshop.blueprints b CROSS JOIN LATERAL public.blueprint_seating_sources_internal(b.id) source WHERE b.occasion=o.occasion AND source.form_id=o.form HAVING count(*)=1;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,'state',t.state,
  'note',t.note,'note_hidden',t.note_hidden,'data',t.data,
  'snapshot',public.order_ticket_admission_snapshot_internal(coalesce((SELECT v FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) v WHERE v->>'id'=t.id::text),
    (SELECT v FROM eshop.orders_history h CROSS JOIN LATERAL jsonb_array_elements(coalesce(h.data->'tickets','[]')) v
     WHERE h."order"=o.id AND v->>'id'=t.id::text ORDER BY h.created_at DESC,h.id DESC LIMIT 1)),o.occasion),
  'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'productId',x.product) ORDER BY x.id),'[]') FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=t.id),
  'admission',coalesce((SELECT jsonb_strip_nulls(jsonb_build_object('category',a.category,'reason',a.reason))
    FROM public.seating_admissions_internal(tr) a WHERE a.order_id=o.id AND a.ticket_id=t.id),'{}')
    || jsonb_strip_nulls(public.ticket_admission_integrity_internal(o.id,t.id)-'productIds'),
  'canMoveAdmission',public.can_write_orders(o.occasion) IS TRUE AND public.order_admission_blocker_internal(o.id,t.id) IS NULL,
  'batch',(SELECT jsonb_build_object('id',i.batch_id,'title',b.title,'ordinal',i.ordinal) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id)
 ) ORDER BY t.id),'[]') INTO tickets FROM eshop.tickets t
 WHERE t.occasion=o.occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=o.id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,'layoutRevision',b.layout_revision) ORDER BY b.id),'[]') INTO plans
 FROM eshop.blueprints b WHERE b.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(places) v WHERE v->>'blueprintId'=b.id::text);
 RETURN jsonb_build_object('places',places,'tickets',tickets,'plans',plans,'placementFingerprint',md5(jsonb_build_object('order',o.id,'state',o.state,'form',o.form,'transition',tr,'places',places,'tickets',tickets)::text));
END $$;
REVOKE ALL ON FUNCTION public.order_admin_placement_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_order_admin_detail(p_order bigint,p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; places jsonb; tickets jsonb; plans jsonb; actions jsonb; placement jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL OR o.occasion IS DISTINCT FROM p_occasion OR public.can_read_orders(o.occasion) IS NOT TRUE THEN
  RETURN jsonb_build_object('code',404,'message','Order unavailable'); END IF;
 placement:=public.order_admin_placement_internal(o.id);
 places:=placement->'places';tickets:=placement->'tickets';plans:=placement->'plans';
 actions:=public.get_order_allowed_actions_internal_v1(o.id);
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
  'order',jsonb_build_object('id',o.id,'occasion',o.occasion,'form_id',o.form,'order_symbol',o.order_symbol,'order_sequence',o.order_sequence,
   'created_at',o.created_at,'updated_at',o.updated_at,'state',o.state,'price',o.price,'currency_code',o.currency_code,
   'data',o.data,'note_hidden',o.note_hidden,'allowedActions',actions,
   'canAddAdmission',public.can_write_orders(o.occasion) IS TRUE AND public.order_admission_blocker_internal(o.id,NULL) IS NULL
     AND EXISTS(SELECT 1 FROM public.order_admission_targets_internal(o.form)),
   'email_payment_version',o.email_payment_version,
   'email_payment_fingerprint',public.order_email_payment_fingerprint(o.id),
   'payment_method',(SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info)),
  'capabilities',jsonb_build_object('write',coalesce(public.can_write_orders(o.occasion),false),'allowedActions',actions),
  'payment',public.customer_order_payment_internal(o.id)-'transactions',
  'paymentOperations',public.payment_method_context_internal(o.id),
  'customerRequests',public.customer_order_change_requests_internal(o.id,public.can_write_orders(o.occasion)),
  -- Authorized admin metadata stays readable after payment. Never issue or
  -- regenerate instructions as a side effect of viewing an order.
  'bankPaymentDetails',(SELECT jsonb_build_object(
    'account',coalesce(b.account_number_human_readable,b.account_number),
    'iban',b.account_number,'creditorName',b.creditor_name,
    'referenceKind',CASE WHEN o.currency_code='EUR' THEN 'RF' ELSE 'VS' END,
    'reference',CASE WHEN o.currency_code='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END)
    FROM eshop.payment_info pi JOIN eshop.bank_accounts b ON b.id=pi.bank_account
    WHERE pi.id=o.payment_info AND pi.payment_method='bank'
      AND pi.currency_code=o.currency_code),
  'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL THEN public.get_waitlist_summary_internal(o.id) END,
  'tickets',tickets,'places',places,'placesComplete',true,'plans',plans,
  'placementFingerprint',placement->>'placementFingerprint',
  'form',(SELECT jsonb_build_object('id',f.id,'title',f.title,'blueprint',f.blueprint) FROM public.forms f WHERE f.id=o.form AND f.occasion=o.occasion),
  'fields',(SELECT coalesce(jsonb_agg(to_jsonb(ff)||jsonb_build_object('product_type_data',
    CASE WHEN pt.id IS NOT NULL THEN jsonb_build_object('id',pt.id,'title',pt.title,'description',pt.description,'type',pt.type) END)
    ORDER BY ff."order",ff.id),'[]') FROM public.form_fields ff
    LEFT JOIN eshop.product_types pt ON pt.id=ff.product_type AND pt.occasion=o.occasion WHERE ff.form=o.form),
  'productCategories',(SELECT coalesce(jsonb_object_agg(p.id::text,p.product_type),'{}') FROM eshop.products p
    WHERE p.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(tickets) t
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(t#>'{snapshot,products}','[]')) pr WHERE pr->>'id'=p.id::text)),
  'answers',coalesce(o.data->'fields','[]'),
  'emailSummary',public.get_order_email_summary(o.id)
 ));
END $$;
REVOKE ALL ON FUNCTION public.get_order_admin_detail(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_admin_detail(bigint,bigint) TO authenticated;

-- SOURCE: eshop/materialize_ticket_products_internal_v1.sql
-- Private product materializer. Callers normalize selection, lock capacity/products,
-- and determine ticket identity first. It never creates an order or a ticket.
CREATE OR REPLACE FUNCTION public.materialize_ticket_products_internal_v1(
 order_id bigint,form_id bigint,ticket_id bigint,ticket_data jsonb,spot_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE
 is_editor boolean; occasion_id bigint; spot_data record; spot_product record; spot_id bigint;
 spot_product_id bigint;
 missing_required_product_field bigint;
 ticket_note text; product_id bigint; ordered_count bigint; field_item jsonb;
 products_array bigint[] := '{}'; product_data record; ticket_products jsonb;
 order_product_ticket_id bigint; first_currency_code text; calculated_price numeric := 0;
 v_product_deposit numeric; v_total_deposit numeric := 0; now timestamptz := clock_timestamp();
BEGIN
 SELECT occasion INTO STRICT occasion_id FROM public.forms WHERE id=form_id;
 is_editor:=coalesce(public.can_write_orders(occasion_id),false);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=order_id AND form=form_id AND occasion=occasion_id)
 OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=ticket_id AND occasion=occasion_id AND state='ordered') THEN
  RAISE EXCEPTION 'TICKET_MATERIALIZATION_SCOPE_MISMATCH'; END IF;
            spot_data := NULL;
            spot_product_id := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT s.* INTO spot_data
                FROM eshop.spots s
                JOIN public.forms f ON f.id=form_id AND f.blueprint=s.blueprint AND f.occasion=s.occasion
                JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=f.blueprint
                WHERE s.id = (ticket_data->>'spot')::BIGINT
                  AND s.occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings b WHERE b.spot=spot_data.id AND b.blocked) OR spot_data.product IS NULL THEN
                    RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (spot_secret::text)::UUID;
                IF (NOT coalesce(is_editor,false) AND
                     (spot_secret IS NULL OR spot_data.secret IS NULL
                      OR spot_data.secret IS DISTINCT FROM spot_secret
                      OR spot_data.secret_expiration_time IS NULL
                      OR spot_data.secret_expiration_time <= clock_timestamp()))
                   OR (coalesce(is_editor,false) AND spot_data.secret IS NOT NULL
                       AND spot_data.secret_expiration_time > clock_timestamp()
                       AND spot_data.secret IS DISTINCT FROM spot_secret) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
                spot_product_id := spot_product.id;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                IF NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
                  WHERE p.id=spot_product_id AND p.occasion=occasion_id AND pt.occasion=occasion_id AND pt.type='spot') THEN
                    RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING';
                END IF;
                products_array := products_array || spot_product_id;
            END IF;

            BEGIN
                PERFORM public.assert_single_ticket_admission_internal(products_array);
            EXCEPTION WHEN raise_exception THEN
                IF SQLERRM<>'ADMISSION_MULTIPLE_PRODUCTS' THEN RAISE; END IF;
                RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode',SQLERRM)::text;
            END;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden)
                  AND NOT EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(form_id) offered
                    WHERE offered.product=product_data.id AND offered.has_capacity) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                PERFORM public.assert_admission_seating_internal(form_id,product_id,spot_id);

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product_id IS NULL THEN
                    spot_product := product_data;
                    spot_product_id := product_data.id;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                INSERT INTO eshop.order_product_ticket ("order", product, ticket,base_price,net_price)
                VALUES (order_id, product_id, ticket_id,product_data.price,product_data.price)
                RETURNING id INTO order_product_ticket_id;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product_id IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product_id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'order_product_ticket_id',order_product_ticket_id,
                        'base_price',product_data.price,'discount_amount',0,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product_id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, secret = NULL, secret_expiration_time = NULL, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- Active seat sales still require an actual admission entitlement.
            -- Hiding ticket issuance cannot turn an auxiliary fee into a
            -- seatless admission behind the published/legacy seating plan.
            IF spot_product_id IS NULL AND EXISTS(
                SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
                WHERE f.id=form_id AND f.blueprint IS NOT NULL
                  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
            ) THEN
                RAISE EXCEPTION '%',jsonb_build_object('code',409,
                  'errorCode','ADMISSION_SOURCE_REQUIRES_SEATING')::text;
            END IF;

            PERFORM public.assert_ticket_required_products_internal(form_id,products_array);

 RETURN jsonb_build_object('products',ticket_products,'price',calculated_price,
  'deposit',v_total_deposit,'currency_code',first_currency_code,'spot',spot_id,'note',ticket_note);
END $$;
REVOKE ALL ON FUNCTION public.materialize_ticket_products_internal_v1(bigint,bigint,bigint,jsonb,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/swap_spot_tickets.sql
CREATE OR REPLACE FUNCTION public._swap_spots_generate_product_json(
    p_product_id BIGINT,
    p_spot_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions
AS $$
DECLARE
    product_data RECORD;
BEGIN
    -- This query joins product, its type, and the spot (if provided)
    -- to get all data needed for the JSON object.
    SELECT
        p.id,
        p.price,
        p.title,
        p.description,
        p.data,
        p.currency_code,
        pt.title AS type_title,
        pt.type AS type,
        s.title AS spot_title
    INTO
        product_data
    FROM
        eshop.products AS p
    JOIN
        eshop.product_types AS pt ON p.product_type = pt.id
    LEFT JOIN
        eshop.spots AS s ON s.id = p_spot_id -- Use p_spot_id for spot_title
    WHERE
        p.id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product data not found for product_id %', p_product_id;
    END IF;

    -- Build the JSON object.
    -- jsonb_strip_nulls ensures that if 'spot_title' is NULL
    -- (because p_spot_id was NULL), the key is removed entirely.
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'id', product_data.id,
        'type', product_data.type,
        'price', product_data.price,
        'title', product_data.title,
        'spot_title', product_data.spot_title,
        'type_title', product_data.type_title,
        'description', product_data.description,
        'data', product_data.data,
        'currency_code', product_data.currency_code
    )) || coalesce(public.order_spot_metadata_internal(p_spot_id), '{}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public._swap_spots_update_ticket(
    p_opt_id BIGINT,
    p_new_product_id BIGINT,
    p_new_spot_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    opt RECORD;
    ord RECORD;
    original_product_id BIGINT;
    original_product_json JSONB;
    original_price NUMERIC;

    new_product_json JSONB;
    new_price NUMERIC;
    new_data JSONB;
    new_order_price NUMERIC;

    price_delta NUMERIC;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[opt.ticket]);
    SELECT * INTO ord FROM eshop.orders WHERE id = opt."order" FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', opt."order"; END IF;

    PERFORM public.assert_order_discount_unchanged_internal(ord.id);
    IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=opt.ticket AND state='used') THEN
        RAISE EXCEPTION 'USED_TICKET_PROTECTED';
    END IF;
    IF public.ticket_admission_integrity_internal(ord.id,opt.ticket)->>'reason' IS NOT NULL
       OR NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
         WHERE p.id=p_new_product_id AND p.occasion=ord.occasion AND pt.occasion=ord.occasion AND pt.type='spot')
       OR NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
         WHERE p.id=opt.product AND pt.type='spot') THEN
        RAISE EXCEPTION 'ADMISSION_DATA_AMBIGUOUS';
    END IF;
    IF ord.form IS NOT NULL THEN
        IF p_new_spot_id IS NULL OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE spot=p_new_spot_id) THEN
            PERFORM public.assert_admission_seating_internal(ord.form,p_new_product_id,p_new_spot_id);
        ELSIF EXISTS(SELECT 1 FROM eshop.spots target
          JOIN eshop.spots source ON source.order_product_ticket=opt.id AND source.blueprint IS NOT NULL
          WHERE target.id=p_new_spot_id AND target.blueprint IS DISTINCT FROM source.blueprint) THEN
            RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING';
        END IF;
        PERFORM public.assert_ticket_required_products_internal(ord.form, ARRAY(
          SELECT product FROM eshop.order_product_ticket WHERE "order"=ord.id AND ticket=opt.ticket AND id<>opt.id AND product IS NOT NULL
          UNION ALL SELECT p_new_product_id));
    END IF;
    original_product_id := opt.product;

    -- 2. Find the *original* product JSON and price from the order_ids.data
    SELECT prod, (prod->>'price')::numeric
    INTO original_product_json, original_price
    FROM jsonb_array_elements(ord.data->'tickets') tckt,
         jsonb_array_elements(tckt->'products') prod
    WHERE (tckt->>'id')::bigint = opt.ticket
      AND (prod->>'id')::bigint = original_product_id;

    IF original_price IS NULL THEN
        RAISE EXCEPTION 'Could not find original price for product % on ticket %', original_product_id, opt.ticket;
    END IF;

    -- 3. Generate the *new* product JSON
    new_product_json := public._swap_spots_generate_product_json(p_new_product_id, p_new_spot_id)
      || jsonb_build_object('order_product_ticket_id',opt.id,'base_price',
        (SELECT price FROM eshop.products WHERE id=p_new_product_id),'discount_amount',0);
    new_price := (new_product_json->>'price')::numeric;
    IF new_product_json->>'currency_code' IS DISTINCT FROM ord.currency_code THEN
      RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;

    -- 4. Check if an update is even needed.
    -- If the new JSON is identical to the old, nothing needs to be done.
    IF original_product_json = new_product_json THEN
        RETURN;
    END IF;

    -- 5. Calculate the final price delta
    price_delta := new_price - original_price;
    new_order_price := COALESCE(ord.price, 0) + price_delta;

    -- 6. Build the new order_ids.data JSON
    new_data := jsonb_set(
        ord.data,
        '{tickets}',
        (SELECT jsonb_agg(
            -- Find the matching ticket
            CASE WHEN (tckt->>'id')::bigint = opt.ticket
            THEN jsonb_set(
                tckt,
                '{products}',
                (SELECT jsonb_agg(
                    -- Find the matching product and replace it
                    CASE
                        WHEN (prod->>'id')::bigint = original_product_id
                        THEN new_product_json -- Swap in the new product JSON
                        ELSE prod
                    END
                ) FROM jsonb_array_elements(tckt->'products') prod)
            )
            ELSE tckt
            END
        ) FROM jsonb_array_elements(ord.data->'tickets') tckt)
    );

    -- 7. Perform all database updates

    -- Update payment info
    IF price_delta <> 0 THEN
        IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=ord.payment_info AND public.payment_method_is_online_internal(payment_method)) THEN
            RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id, base_price=new_price, net_price=new_price
    WHERE id = p_opt_id;

    -- The aggregate swap reconciles each affected order once, after all seat
    -- pairs have their final products and totals, and appends one final snapshot.

END;
$$;


-- Only the aggregate applier calls this worker, after locking the complete
-- assignment graph and checking scope, holds and atomic-unit eligibility.
-- The pair helper updates purchased prices; the aggregate owns reconciliation.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_pair_locked_internal(p_first bigint,p_second bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE first_spot eshop.spots;second_spot eshop.spots;
BEGIN
 SELECT * INTO STRICT first_spot FROM eshop.spots WHERE id=p_first;
 SELECT * INTO STRICT second_spot FROM eshop.spots WHERE id=p_second;
 IF first_spot.order_product_ticket IS NOT NULL AND second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSIF first_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
 ELSIF second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSE RETURN;
 END IF;
 UPDATE eshop.spots SET order_product_ticket=CASE WHEN id=p_first THEN second_spot.order_product_ticket ELSE first_spot.order_product_ticket END
 WHERE id IN(p_first,p_second);
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE id IN(first_spot.order_product_ticket,second_spot.order_product_ticket) ORDER BY ticket));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_pair_locked_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.swap_spot_tickets(spot_id_1 bigint,spot_id_2 bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.swap_spot_tickets_client_sync_v1(
    spot_id_1,spot_id_2,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets(bigint,bigint) TO authenticated;

REVOKE ALL ON FUNCTION public._swap_spots_generate_product_json(bigint,bigint),public._swap_spots_update_ticket(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: blueprint/apply_seat_swap_internal.sql
-- Validate only entities actually participating in this swap before locking
-- their parents, then again once the complete assignment closure is locked.
CREATE OR REPLACE FUNCTION public.check_blueprint_swap_scope_internal(p_occasion bigint,p_spots bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion)<>cardinality(p_spots)
  OR EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprints b ON b.id=s.blueprint
   LEFT JOIN eshop.products p ON p.id=s.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
   LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
   LEFT JOIN eshop.orders o ON o.id=i."order" LEFT JOIN eshop.tickets t ON t.id=i.ticket
   WHERE s.id=ANY(p_spots) AND (
    (s.blueprint IS NOT NULL AND b.occasion IS DISTINCT FROM p_occasion)
    OR (s.product IS NOT NULL AND (p.occasion IS DISTINCT FROM p_occasion OR pt.occasion IS DISTINCT FROM p_occasion))
    OR (s.order_product_ticket IS NOT NULL AND (o.occasion IS DISTINCT FROM p_occasion OR t.occasion IS DISTINCT FROM p_occasion)))) THEN
  RAISE insufficient_privilege USING MESSAGE='swap assignment scope unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_swap_scope_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Capture the actual financial owner's effects, never a second price calculation.
-- Preview callers roll this work back; confirmed command callers retain it only
-- when its digest matches the effects previously approved by the operator.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_swap_internal(p_first bigint,p_second bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occ bigint; left_ids bigint[];right_ids bigint[];ids bigint[];v_order_ids bigint[];
 before_orders jsonb;sides jsonb;revisions jsonb;effects jsonb;facts jsonb;result jsonb;i integer;v_order_id bigint;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_first,p_second);
 IF p_first IS NULL OR p_second IS NULL OR p_first=p_second OR occ IS NULL
  OR (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=occ)<>2
  OR public.can_write_orders(occ) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 left_ids:=public.blueprint_selection_unit_spots_internal(p_first);
 right_ids:=public.blueprint_selection_unit_spots_internal(p_second);
 IF cardinality(left_ids)<>cardinality(right_ids) OR left_ids && right_ids THEN
  RAISE EXCEPTION 'BLUEPRINT_UNIT_SIZE_MISMATCH'; END IF;
 ids:=left_ids||right_ids;
 PERFORM public.check_blueprint_swap_scope_internal(occ,ids);
 PERFORM public.lock_spot_assignment_scope_internal(ids,'{}'::bigint[],true);
 PERFORM public.check_blueprint_swap_scope_internal(occ,ids);
 -- Ticket rows are locked before rechecking used atomic-unit members.
 PERFORM public.check_blueprint_selection_units_internal(ids);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',layout_revision) ORDER BY id),'[]')
 INTO revisions FROM eshop.blueprints WHERE id IN(SELECT blueprint FROM eshop.spots WHERE id=ANY(ids));
 SELECT array_agg(DISTINCT i."order") INTO v_order_ids FROM eshop.spots s
 JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(ids);
 IF EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
  WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()))) THEN
  RAISE EXCEPTION 'BLUEPRINT_SEAT_PROTECTED'; END IF;
 before_orders:=public.order_payment_snapshot_internal(v_order_ids);
 WITH lifecycle AS MATERIALIZED (SELECT id,state FROM public.blueprint_spot_facts_internal(occ,ids))
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'title',s.title,'state',lifecycle.state,'productId',s.product,
  'productTitle',p.title,'orderId',o.id,'ticketId',i.ticket,
  'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email')) ORDER BY s.id),'[]'),
 coalesce(jsonb_agg(jsonb_build_object('spot',s.id,'blueprint',s.blueprint,'item',i.id,'ticketState',t.state,
  'product',s.product,'price',p.price,'currency',p.currency_code) ORDER BY s.id),'[]')
 INTO sides,facts FROM eshop.spots s LEFT JOIN eshop.products p ON p.id=s.product
 LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket LEFT JOIN eshop.tickets t ON t.id=i.ticket
 LEFT JOIN eshop.orders o ON o.id=i."order" LEFT JOIN lifecycle ON lifecycle.id=s.id WHERE s.id=ANY(ids);
 FOR i IN 1..cardinality(left_ids) LOOP PERFORM public.apply_blueprint_seat_pair_locked_internal(left_ids[i],right_ids[i]); END LOOP;
 -- Seat-only edits invalidate customer content too. Reconcile final totals once
 -- per order, so swaps within one order cannot create intermediate paid emails.
 FOR v_order_id IN SELECT id FROM eshop.orders WHERE id=ANY(v_order_ids) ORDER BY id LOOP
  PERFORM public.reconcile_order_payment_internal_v1(v_order_id,'product_edit');
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=v_order_id AND payment_info IS NOT NULL) THEN
   PERFORM public.refresh_order_payment_deadline_internal(v_order_id);
  END IF;
  INSERT INTO eshop.orders_history("order",data,state,price,currency_code)
  SELECT id,data,state,price,currency_code FROM eshop.orders WHERE id=v_order_id;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',id,
  'beforeAmount',(before_orders->id::text->>'amount')::numeric,'afterAmount',price,
  'delta',price-(before_orders->id::text->>'amount')::numeric,'currencyCode',currency_code,
  'beforeState',before_orders->id::text->>'state','afterState',state) ORDER BY id),'[]')
 INTO effects FROM eshop.orders WHERE id=ANY(v_order_ids);
 result:=jsonb_build_object('code',200,'spotIds',to_jsonb(ids),'sourceSpotIds',left_ids,'targetSpotIds',right_ids,
  'blueprints',revisions,'sides',sides,'orders',effects);
 RETURN result||jsonb_build_object('confirmationHash',encode(extensions.digest(convert_to(
  jsonb_build_object('first',p_first,'second',p_second,'result',result,'facts',facts,'beforeOrders',before_orders)::text,'UTF8'),'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_swap_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: emails/email_domain.sql
-- Automatic confirmations and ticket emails share the same order snapshot identity.
CREATE OR REPLACE FUNCTION public.order_email_automatic_key_internal(p_order bigint,p_version bigint,p_recipient text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT p_order||':'||p_version||':'||coalesce(p_recipient,'')||':false';
$$;
REVOKE ALL ON FUNCTION public.order_email_automatic_key_internal(bigint,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_automatic_key_internal(bigint,bigint,text) TO service_role;

-- Invoker-only helper. Its ACL prevents public use; public domain commands own permissions.
CREATE OR REPLACE FUNCTION public.enqueue_order_email(p_code text,p_data jsonb,p_org bigint,p_occ bigint,p_unit bigint,p_time timestamptz DEFAULT now(),p_request text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_kind text; v_version bigint; v_key text; v_recipient text; v_existing public.email_messages; v_base_key text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 -- Only private domain producers running as the canonical SQL owner can assign provenance.
 IF current_user<>'postgres' THEN p_data:=p_data-'systemOrderDelivery'; END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=coalesce((p_data->>'order_id')::bigint,(p_data#>>'{ticket_order,order,id}')::bigint) FOR UPDATE;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 IF v_order.id IS NULL OR v_order.occasion<>p_occ THEN RAISE EXCEPTION 'invalid_order_email'; END IF;
 IF v_order.state='stock' THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF v_order.data ? 'ticketBatchOrigin' AND nullif(trim(v_order.data->>'email'),'') IS NULL THEN
  RETURN jsonb_build_object('state','skipped','reason','no_recipient'); END IF;
 IF v_order.state='storno' AND p_code<>'TICKET_ORDER_STORNO' THEN
  RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
 END IF;
 v_kind:=CASE p_code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation' WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
  WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder' WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
  WHEN 'ORDER_TICKETS' THEN 'order_tickets' END;
 IF v_kind IS NULL THEN RAISE EXCEPTION 'unsupported_order_email'; END IF;
 v_version:=CASE WHEN v_kind='order_reminder' THEN v_pi.email_reminder_version ELSE v_order.email_payment_version END;
 v_recipient:=coalesce(p_data->>'recipient',v_order.data->>'email');
 v_key:=coalesce(p_request,p_data->>'command_id',v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':'||coalesce(p_data->>'is_deposit_reminder','false'));
 IF v_kind='order_storno' AND coalesce(p_request,'') NOT LIKE 'manual:%' THEN
  -- requested_by is audit metadata, never proof of an explicit resend.
  v_recipient:=v_order.data->>'email';
  p_data:=jsonb_build_object('order_id',v_order.id);
  v_key:=v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':storno';
  -- Older Edge follow-ups carried requested_by but no explicit resend ID and
  -- used the generic :false key. Reuse that committed identity rather than
  -- manufacture a second automatic message, including cancelled/expired rows.
  SELECT * INTO v_existing FROM public.email_messages
    WHERE organization=p_org AND order_id=v_order.id AND message_kind='order_storno'
      AND recipient=v_recipient AND source_version=v_version
      AND dedupe_key IN (v_key,v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':false')
    ORDER BY (dedupe_key=v_key) DESC,id LIMIT 1;
  IF v_existing.id IS NOT NULL THEN v_key:=v_existing.dedupe_key; END IF;
 END IF;
 IF v_kind IN ('order_tickets','order_confirmation') THEN
  SELECT * INTO v_existing FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version
    AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') ORDER BY id DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
   IF p_data->>'requested_by' IS NOT NULL THEN UPDATE public.email_messages SET post_action=post_action||jsonb_build_object('last_manual_request',jsonb_build_object('actor',p_data->>'requested_by','request',p_request,'at',now())) WHERE id=v_existing.id; END IF;
   RETURN jsonb_build_object('message_id',v_existing.message_id,'state',v_existing.workflow_state,'replayed',true);END IF;
  v_base_key:=public.order_email_automatic_key_internal(v_order.id,v_version,v_recipient);
  IF p_request IS NULL OR NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version) THEN v_key:=v_base_key;END IF;
 END IF;
 RETURN public.enqueue_email(v_kind,jsonb_build_object('organization',p_org,'occasion',p_occ,'unit',p_unit),v_recipient,p_data,v_key,
 CASE WHEN p_code='ORDER_TICKETS' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE p_code END,p_time,
 CASE WHEN v_kind='order_reminder' THEN p_time+interval '7 days' ELSE NULL END,v_order.id,v_version);
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_eligible_order_tickets_internal(p_order bigint,p_include_sent boolean) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_occ public.occasions;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
 IF v_order.data ? 'ticketBatchOrigin' AND coalesce((v_order.data#>>'{ticketBatchOrigin,sendTickets}')::boolean,false) IS NOT TRUE THEN RETURN; END IF;
 IF (v_order.state='paid' OR (p_include_sent AND v_order.state='sent')) AND (v_occ.is_order_synchronization_enabled OR v_order.data ? 'ticketBatchOrigin') AND v_order.data ? 'email'
 AND (coalesce(v_order.price,0)<>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_occ.features) f WHERE f->>'code'='ticket' AND (f->>'is_enabled')::boolean)) THEN
  PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',p_order),v_occ.organization,v_occ.id,v_occ.unit);
 END IF;
END $$;

REVOKE ALL ON FUNCTION public.enqueue_eligible_order_tickets_internal(bigint,boolean)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_eligible_order_tickets_internal(bigint,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_paid_order_tickets(p_order bigint)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.enqueue_eligible_order_tickets_internal(p_order,false);
$$;

CREATE OR REPLACE FUNCTION public.cancel_order_email_intents(p_order bigint) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='payment_changed',lease_token=NULL,lease_until=NULL
 WHERE order_id=p_order AND message_kind IN ('order_payment_notice','order_tickets','order_reminder') AND workflow_state IN ('pending','retry_wait','blocked','preparing');
END $$;

CREATE OR REPLACE FUNCTION public.apply_email_post_actions(p_message uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m record; v_result jsonb;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 FOR m IN SELECT * FROM public.email_messages WHERE workflow_state='accepted' AND post_action_state='pending'
 AND (p_message IS NULL OR message_id=p_message) ORDER BY id LIMIT 20 LOOP
  -- Domain producers lock order before message; follow that order before owning the projection.
  IF m.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=m.order_id FOR UPDATE; END IF;
  SELECT * INTO m FROM public.email_messages WHERE id=m.id AND workflow_state='accepted' AND post_action_state='pending' FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN CONTINUE; END IF;
  BEGIN
   IF m.message_kind='order_tickets' THEN
    -- Never resurrect a used/storno ticket or a reverted/cancelled order.
    UPDATE eshop.orders SET state='sent',updated_at=now() WHERE id=m.order_id AND state='paid' AND email_payment_version=m.source_version;
    IF FOUND THEN
     UPDATE eshop.tickets t SET state='sent',updated_at=now()
     FROM eshop.order_product_ticket opt WHERE opt.ticket=t.id AND opt."order"=m.order_id AND t.state='paid'
      AND t.id IN (SELECT jsonb_array_elements_text(m.post_action->'ticket_ids')::bigint);
     INSERT INTO eshop.orders_history("order",data,state,price,currency_code) SELECT id,data,state,price,currency_code FROM eshop.orders WHERE id=m.order_id;
    END IF;
   END IF;
   IF m.message_kind='app_links' AND m.recipient_user IS NOT NULL THEN PERFORM public.mark_app_links_sent(m.occasion,m.recipient_user); END IF;
   IF m.message_kind='deletion_confirm' AND m.post_action ? 'deletion_request' THEN PERFORM public.set_account_deletion_email_state((m.post_action->>'deletion_request')::uuid,true); END IF;
   IF m.post_action ? 'history_id' THEN PERFORM public.add_sent_to_customer_flag((m.post_action->>'history_id')::bigint); END IF;
   IF m.message_kind='order_reminder' THEN
    UPDATE eshop.payment_info SET data=coalesce(data,'{}')||'{"current_version_reminded":true}'::jsonb
    WHERE id=(m.post_action->>'payment_info_id')::bigint AND email_reminder_version=m.source_version;
   END IF;
   UPDATE public.email_messages SET post_action_state='done',last_error=CASE WHEN last_error='post_action_failed' THEN NULL ELSE last_error END WHERE id=m.id;
  EXCEPTION WHEN OTHERS THEN UPDATE public.email_messages SET last_error='post_action_failed' WHERE id=m.id; END;
 END LOOP;
END $$;

-- Account-domain writes and their durable intent are one DB transaction.
CREATE OR REPLACE FUNCTION public.enqueue_account_email(p_operation text,p_domain jsonb,p_context jsonb,p_recipient text,p_sealed jsonb,p_content_hash text,p_dedupe text,p_code text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_context jsonb:=p_context; v_kind text; v_result jsonb; v_domain_result jsonb; v_user uuid:=(p_domain->>'user_id')::uuid; v_source jsonb:='{}'; v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 PERFORM pg_advisory_xact_lock(hashtextextended('email-account:'||(p_context->>'organization')||':'||coalesce(v_user::text,p_dedupe)||':'||p_operation,0));
 -- Command replay is checked before generating/replacing the domain proof.
 SELECT message_id INTO v_message FROM public.email_messages WHERE organization=(p_context->>'organization')::bigint AND dedupe_key=p_dedupe;
 IF v_message IS NOT NULL THEN RETURN jsonb_build_object('message_id',v_message,'replayed',true,'domain',
  CASE WHEN p_operation='register' THEN (SELECT jsonb_build_object('code',200,'id',recipient_user) FROM public.email_messages WHERE message_id=v_message) ELSE NULL END); END IF;
 -- Older clients have no stable request ID. Join any unresolved proof instead of rotating it on a timeout retry.
 IF p_operation IN ('reset_token','deletion_confirm') AND v_user IS NOT NULL THEN
  SELECT message_id INTO v_message FROM public.email_messages WHERE organization=(p_context->>'organization')::bigint AND recipient_user=v_user
   AND message_kind=CASE WHEN p_operation='reset_token' THEN 'reset_password' ELSE 'deletion_confirm' END
   AND (workflow_state IN ('pending','preparing','sending','retry_wait','unknown') OR (p_operation='reset_token' AND workflow_state='accepted')) AND expires_at>now() ORDER BY id DESC LIMIT 1;
  IF v_message IS NOT NULL THEN RETURN jsonb_build_object('message_id',v_message,'replayed',true);END IF;
 END IF;
 IF p_operation='reset_token' THEN
  v_kind:='reset_password';
  IF NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=v_user AND organization=(p_context->>'organization')::bigint) THEN RAISE EXCEPTION 'email_account_scope_mismatch'; END IF;
  INSERT INTO public.user_reset_token("user",token,created_at) VALUES(v_user,(p_domain->>'token')::uuid,now()) ON CONFLICT("user") DO UPDATE SET token=excluded.token,created_at=excluded.created_at;
  v_source:=jsonb_build_object('reset_hash',encode(extensions.digest(p_domain->>'token','sha256'),'hex'));
 ELSIF p_operation='register' THEN
  v_kind:='registration';
  v_domain_result:=public.create_user_from_registration((p_context->>'organization')::bigint,p_recipient,coalesce(p_domain->>'password',p_domain->>'invitation_code'),p_domain->'data',p_domain->>'unit_title');
  IF v_domain_result->>'code'<>'200' THEN RETURN jsonb_build_object('domain',v_domain_result); END IF;
  v_user:=(v_domain_result->>'id')::uuid;
  -- The delivery deadline expires the message, never the reusable password.
  v_source:=jsonb_build_object('password_version',(SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') FROM auth.users WHERE id=v_user));
 ELSIF p_operation='deletion_confirm' THEN
  v_kind:='deletion_confirm';
  v_domain_result:=public.create_account_deletion_request(v_user,(p_context->>'organization')::bigint,p_domain->>'token_hash',p_expires,p_domain->>'masked_email');
  v_source:=jsonb_build_object('deletion_request',v_domain_result->>'requestId');
 ELSIF p_operation='google_mailbox' THEN
  v_kind:='google_mailbox';
  v_domain_result:=public.google_auth_transition_v1('mailbox_send',(p_domain->>'attempt_id')::uuid,p_domain->>'secret_hash',p_domain->'payload');
  IF (v_domain_result->>'organization')::bigint IS DISTINCT FROM (p_context->>'organization')::bigint OR v_domain_result->>'email' IS DISTINCT FROM p_recipient THEN RAISE EXCEPTION 'email_account_scope_mismatch'; END IF;
  v_source:=jsonb_build_object('google_attempt',p_domain->>'attempt_id','mailbox_hash',p_domain#>>'{payload,mailboxHash}');
 ELSE RAISE EXCEPTION 'invalid_account_email_operation'; END IF;
 IF v_user IS NOT NULL THEN v_context:=v_context||jsonb_build_object('recipient_user',v_user); END IF;
 v_result:=public.enqueue_email(v_kind,v_context,p_recipient,v_source||jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now(),post_action=v_source WHERE message_id=(v_result->>'message_id')::uuid;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result||jsonb_build_object('domain',v_domain_result);
END $$;
REVOKE ALL ON FUNCTION public.enqueue_account_email(text,jsonb,jsonb,text,jsonb,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_account_email(text,jsonb,jsonb,text,jsonb,text,text,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.reset_password_and_enqueue_email(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_answer jsonb; v_context jsonb; v_email text; v_result jsonb; v_existing public.email_messages; v_password_version text;
BEGIN
 -- Reuse the existing hierarchical permission check, including elevated-account protections.
 IF auth.uid() IS NULL OR NOT coalesce(public.get_can_reset_user_password(p_user),false) THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 PERFORM public.lock_member_access_internal_v1((SELECT unit FROM public.occasions WHERE id=p_occasion));
 PERFORM pg_advisory_xact_lock(hashtextextended('sign-in:'||p_user::text||':'||p_occasion::text,0));
 -- Team invitations never own a password transition, including older clients.
 PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user FOR SHARE;
 IF EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user
   AND (is_editor OR is_editor_view OR is_manager)) THEN
  RAISE insufficient_privilege USING MESSAGE='Team invitations cannot reset account passwords'; END IF;
 SELECT * INTO v_existing FROM public.email_messages WHERE recipient_user=p_user AND occasion=p_occasion AND message_kind='sign_in' AND (dedupe_key=p_dedupe OR (workflow_state IN ('pending','preparing','sending','retry_wait','unknown','accepted') AND expires_at>now())) ORDER BY id DESC LIMIT 1;
 IF v_existing.id IS NOT NULL THEN
  RETURN jsonb_build_object('message_id',v_existing.message_id,'replayed',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user) THEN RAISE EXCEPTION 'user_not_in_occasion'; END IF;
 v_answer:=public.reset_user_password(p_user,p_password);
 IF v_answer->>'code'<>'200' THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 SELECT jsonb_build_object('organization',organization,'occasion',id,'unit',unit,'recipient_user',p_user) INTO v_context FROM public.occasions WHERE id=p_occasion;
 v_email:=public.get_user_delivery_email(p_user);
 SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') INTO v_password_version FROM auth.users WHERE id=p_user;
 v_result:=public.enqueue_email('sign_in',v_context,v_email,jsonb_build_object('password_version',v_password_version,'content_hash',p_content_hash),p_dedupe,'SIGN_IN_CODE',now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now() WHERE message_id=(v_result->>'message_id')::uuid;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;

-- Compatibility name for older clients; both names own the same permanent password transition.
CREATE OR REPLACE FUNCTION public.enqueue_sign_in_code_v1(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.reset_password_and_enqueue_email(p_user,p_password,p_occasion,p_sealed,p_content_hash,p_dedupe,p_expires);
$$;
REVOKE ALL ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;
