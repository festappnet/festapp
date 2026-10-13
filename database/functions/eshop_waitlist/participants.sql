CREATE OR REPLACE FUNCTION public.allocate_ticket_order_identity_internal(p_form bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o bigint; occ bigint; seq bigint; attempt integer;
BEGIN
 SELECT occasion INTO STRICT occ FROM public.forms WHERE id=p_form FOR UPDATE;
 seq:=public.next_order_sequence(occ);
 FOR attempt IN 1..10 LOOP
  INSERT INTO eshop.orders(form,occasion,order_symbol,order_sequence,state)
   VALUES(p_form,occ,public.generate_order_symbol(),seq,'ordered')
   ON CONFLICT ON CONSTRAINT orders_order_symbol_key DO NOTHING RETURNING id INTO o;
  IF o IS NOT NULL THEN RETURN o; END IF;
 END LOOP;
 RAISE EXCEPTION 'Order symbol allocation exhausted';
END $$;
CREATE OR REPLACE FUNCTION public.lock_order_capacity_scope_internal(p_orders bigint[])
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM 1 FROM public.forms WHERE id IN(SELECT form FROM eshop.orders WHERE id=ANY(p_orders)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.orders WHERE id=ANY(p_orders) ORDER BY id FOR UPDATE;
END $$;
CREATE OR REPLACE FUNCTION public.lock_ticket_order_products_internal(p_order bigint,p_input jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];
BEGIN
 SELECT coalesce(array_agg(DISTINCT id),'{}') INTO ids FROM (
  SELECT product id FROM eshop.order_product_ticket WHERE "order"=p_order
  UNION ALL SELECT (f->>'product_type')::bigint FROM jsonb_array_elements(coalesce(p_input->'ticket','[]')) t
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'fields','[]')) f WHERE f ? 'product_type'
  UNION ALL SELECT s.product FROM jsonb_array_elements(coalesce(p_input->'ticket','[]')) t JOIN eshop.spots s ON s.id=(t->>'spot')::bigint) selected;
 PERFORM 1 FROM eshop.products WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id WHERE pic.product=ANY(ids)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(ids)) ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.allocate_ticket_order_identity_internal(bigint),public.lock_order_capacity_scope_internal(bigint[]),
 public.lock_ticket_order_products_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;

-- One transport normalization for ordinary, offered and waiting people. Older
-- clients identify ticket fields by their exact _subFieldId and typed key;
-- current clients additionally send the stable numeric field ID.
CREATE OR REPLACE FUNCTION public.normalize_form_participant_answers_internal(p_form bigint,p_people jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE people jsonb:='[]'; person jsonb; answer jsonb; fields jsonb; field_id bigint; numeric_keys text[];
 definition public.form_fields; value jsonb; seen bigint[];
BEGIN
 IF jsonb_typeof(p_people) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid participant answers'; END IF;
 FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
  fields:='[]'; seen:='{}';
  IF person ? 'fields' AND jsonb_typeof(person->'fields') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid participant fields'; END IF;
  FOR answer IN SELECT * FROM jsonb_array_elements(coalesce(person->'fields','[]')) LOOP
   IF jsonb_typeof(answer) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid participant field'; END IF;
   SELECT coalesce(array_agg(key),'{}') INTO numeric_keys FROM jsonb_object_keys(answer) key WHERE key ~ '^[0-9]+$';
   IF cardinality(numeric_keys)>1 THEN RAISE EXCEPTION 'FORM_FIELD_AMBIGUOUS'; END IF;
   field_id:=NULL;
   IF answer ? '_subFieldId' THEN
    IF coalesce(answer->>'_subFieldId','') !~ '^[1-9][0-9]{0,17}$' THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
    field_id:=(answer->>'_subFieldId')::bigint;
    IF cardinality(numeric_keys)=1 AND numeric_keys[1]<>field_id::text THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
   ELSIF cardinality(numeric_keys)=1 THEN
    IF numeric_keys[1] !~ '^[1-9][0-9]{0,17}$' THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
    field_id:=numeric_keys[1]::bigint;
   END IF;
   IF field_id IS NOT NULL THEN
    SELECT * INTO definition FROM public.form_fields WHERE id=field_id AND form=p_form AND is_ticket_field AND NOT is_hidden;
    IF NOT FOUND THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
    IF field_id=ANY(seen) THEN RAISE EXCEPTION 'FORM_FIELD_AMBIGUOUS'; END IF;
    seen:=seen||field_id;
    IF NOT answer ? field_id::text AND NOT answer ? definition.type THEN RAISE EXCEPTION 'FORM_FIELD_TYPE_MISMATCH'; END IF;
    IF answer ? field_id::text AND answer ? definition.type AND answer->(field_id::text) IS DISTINCT FROM answer->definition.type THEN
     RAISE EXCEPTION 'FORM_FIELD_VALUE_CONFLICT'; END IF;
    -- A typed name cannot stand in for another field type with the same ID.
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(answer) key WHERE key<>field_id::text AND key<>definition.type
     AND key NOT IN ('_subFieldId','currency_code') AND NOT (definition.type='product_type' AND key='price')) THEN
      RAISE EXCEPTION 'FORM_FIELD_TYPE_MISMATCH'; END IF;
    value:=coalesce(answer->(field_id::text),answer->definition.type);
    IF definition.type='product_type' THEN
     IF NOT EXISTS(SELECT 1 FROM eshop.products product WHERE product.id=(value#>>'{}')::bigint
       AND product.product_type=definition.product_type) THEN RAISE EXCEPTION 'PRODUCT_SCOPE_MISMATCH'; END IF;
     -- Existing product selections carry a UI price hint. Discard it here;
     -- the shared finalizer obtains the authoritative price from the product.
     answer:=answer-'price';
    END IF;
    answer:=answer||jsonb_build_object(field_id::text,value,definition.type,value,'_subFieldId',field_id);
   END IF;
   fields:=fields||jsonb_build_array(answer);
  END LOOP;
  people:=people||jsonb_build_array(jsonb_set(person,'{fields}',fields,true));
 END LOOP;
 RETURN people;
END $$;
REVOKE ALL ON FUNCTION public.normalize_form_participant_answers_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;

-- Domain answers contain stable personal field IDs only. Transport aliases,
-- product choices and client metadata remain outside the participant ledger.
CREATE OR REPLACE FUNCTION public.extract_participant_answers_internal(p_form bigint,p_person jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('fields',coalesce(jsonb_agg(jsonb_build_object(answer.key,answer.value)
   ORDER BY definition."order" NULLS LAST,definition.id),'[]'))
 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_person->'fields')='array' THEN p_person->'fields' ELSE '[]' END) field
 CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(field)='object' THEN field ELSE '{}' END) answer
 JOIN public.form_fields definition ON definition.id::text=answer.key
 WHERE definition.form=p_form AND definition.is_ticket_field AND NOT definition.is_hidden
  AND definition.type NOT IN ('product_type','spot','ticket','html');
$$;
REVOKE ALL ON FUNCTION public.extract_participant_answers_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;
