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
