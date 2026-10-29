-- Transaction-local fixtures for payment/history contracts. No provider sends.
SELECT set_config('festapp.email_wake','scheduled',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);

CREATE FUNCTION pg_temp.payment_fixture(p_deposit numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; un bigint; oc bigint; f bigint; fk uuid; pt bigint;
 prod bigint; bank bigint; actor uuid; oid bigint; ticket bigint; result jsonb;
 suffix text:=gen_random_uuid()::text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Payment lifecycle '||suffix) RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Payment lifecycle',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,features,is_order_synchronization_enabled)
 VALUES('Payment lifecycle',org,un,suffix,now(),now()+interval '30 days',
  '[{"code":"form","is_enabled":true},{"code":"ticket","is_enabled":true}]',true) RETURNING id INTO oc;
 PERFORM public.create_user_for_test(suffix,suffix||'@example.invalid');
 actor:=public.get_user_id(suffix);
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,actor,true);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor)
 VALUES(oc,actor,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies)
 VALUES('Payment lifecycle','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO public.forms(occasion,title,link,is_open,bank_account)
 VALUES(oc,'Payment lifecycle',suffix,true,bank) RETURNING id,key INTO f,fk;
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,occasion,price,currency_code,is_hidden,data)
 VALUES('Admission',pt,oc,1000,'CZK',false,
  CASE WHEN p_deposit IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('deposit',jsonb_build_object('amount',p_deposit)) END)
 RETURNING id INTO prod;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field) VALUES(f,'product_type',pt,true);
 SET LOCAL ROLE authenticated;
 result:=public.create_ticket_order_client_sync_v1(jsonb_build_object(
  'form',fk,'email',suffix||'@example.invalid','ticket',jsonb_build_array(
   jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',prod))))),
  gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM public.assert_eq(result->>'status','applied'::text,'fixture checkout commits: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT DISTINCT opt.ticket INTO STRICT ticket FROM eshop.order_product_ticket opt WHERE opt."order"=oid;
 RETURN jsonb_build_object('organization',org,'occasion',oc,'form',f,'product',prod,'actor',actor,
  'order',oid,'ticket',ticket,'bank',bank,'link',suffix,
  'payment',(SELECT payment_info FROM eshop.orders WHERE id=oid));
END $$;

CREATE FUNCTION pg_temp.payment_history(p_order bigint) RETURNS jsonb LANGUAGE sql AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.id),'[]'::jsonb)
 FROM eshop.orders_history h WHERE h."order"=p_order;
$$;

CREATE FUNCTION pg_temp.payment_edit(x jsonb,p_price numeric,p_command uuid DEFAULT gen_random_uuid())
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE result jsonb;
BEGIN
 SET LOCAL ROLE authenticated;
 result:=public.update_ticket_products_client_sync_v1((x->>'ticket')::bigint,
  jsonb_build_array(jsonb_build_object('id',x->'product','price',p_price)),p_command);
 RESET ROLE;
 PERFORM public.assert_eq(result->>'status','applied'::text,'product edit commits: '||result::text);
 RETURN result;
END $$;

CREATE FUNCTION pg_temp.payment_pair(x jsonb,p_amount numeric) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE tid bigint; result jsonb;
BEGIN
 INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,transaction_type)
 VALUES(now(),p_amount,'CZK',(x->>'bank')::bigint,'manual') RETURNING id INTO tid;
 result:=public.apply_transaction_pairing(tid,(x->>'payment')::bigint,'test','system');
 PERFORM public.assert_eq(result->>'status','paired'::text,'payment pairing succeeds');
 RETURN tid;
END $$;

CREATE FUNCTION pg_temp.payment_accept_tickets(x jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE mid uuid;
BEGIN
 SELECT message_id INTO STRICT mid FROM public.email_messages
 WHERE order_id=(x->>'order')::bigint AND message_kind='order_tickets'
 AND source_version=(SELECT email_payment_version FROM eshop.orders WHERE id=(x->>'order')::bigint);
 -- Simulate provider acceptance only; execute the real SQL projection.
 UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now(),
  post_action=jsonb_build_object('ticket_ids',jsonb_build_array(x->'ticket')) WHERE message_id=mid;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.apply_email_post_actions(mid);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 RETURN mid;
END $$;

-- Attach one synthetic held seat to the real checkout OPT, so price-only edits
-- must preserve its database identity and the saved product's seat metadata.
CREATE FUNCTION pg_temp.payment_attach_spot(x jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE sid bigint; optid bigint; bp bigint;
BEGIN
 SELECT id INTO STRICT optid FROM eshop.order_product_ticket
 WHERE "order"=(x->>'order')::bigint AND ticket=(x->>'ticket')::bigint AND product=(x->>'product')::bigint;
 UPDATE public.occasions SET features=features||'[{"code":"blueprint","is_enabled":true}]'::jsonb
 WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.blueprints(occasion,organization,title,objects)
 VALUES((x->>'occasion')::bigint,(x->>'organization')::bigint,'Lifecycle seats','[]') RETURNING id INTO bp;
 UPDATE public.forms SET blueprint=bp WHERE id=(x->>'form')::bigint;
 INSERT INTO eshop.spots(occasion,blueprint,product,order_product_ticket,title)
 VALUES((x->>'occasion')::bigint,bp,(x->>'product')::bigint,optid,'Lifecycle seat') RETURNING id INTO sid;
 UPDATE eshop.orders SET data=jsonb_set(data,'{tickets,0,products,0}',data#>'{tickets,0,products,0}'||
  jsonb_build_object('spot_id',sid,'spot_title','Lifecycle seat')) WHERE id=(x->>'order')::bigint;
 RETURN x||jsonb_build_object('spot',sid);
END $$;

CREATE FUNCTION pg_temp.payment_identity(x jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
  'order',(SELECT jsonb_build_array(id,order_symbol,order_sequence,payment_info) FROM eshop.orders WHERE id=(x->>'order')::bigint),
  'tickets',(SELECT jsonb_agg(jsonb_build_array(t.id,t.ticket_symbol,t.data) ORDER BY t.id) FROM eshop.tickets t
   WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=(x->>'order')::bigint)),
  'links',(SELECT jsonb_agg(to_jsonb(opt) ORDER BY opt.id) FROM eshop.order_product_ticket opt WHERE opt."order"=(x->>'order')::bigint),
  'spots',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM eshop.spots s WHERE s.order_product_ticket IN
   (SELECT id FROM eshop.order_product_ticket WHERE "order"=(x->>'order')::bigint)),
  'spot_metadata',(SELECT jsonb_path_query_array(data,'$.tickets[*].products[*].spot_id')||
   jsonb_path_query_array(data,'$.tickets[*].products[*].spot_title') FROM eshop.orders WHERE id=(x->>'order')::bigint));
$$;

CREATE FUNCTION pg_temp.payment_assert_edit_history(x jsonb,p_before jsonb,p_state text,p_price numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE h jsonb:=pg_temp.payment_history((x->>'order')::bigint); n integer:=jsonb_array_length(p_before); i integer;
BEGIN
 PERFORM public.assert_eq(jsonb_array_length(h),n+1,'one product edit appends exactly one final snapshot');
 FOR i IN 0..n-1 LOOP
  PERFORM public.assert_eq(h->i,p_before->i,'product edit preserves every previous snapshot including author/time');
 END LOOP;
 PERFORM public.assert_eq(h->n->>'state',p_state,'product edit history records final reconciliation state');
 PERFORM public.assert_eq((h->n->>'price')::numeric,p_price,'product edit history records final price');
 PERFORM public.assert_eq(h->n->'data',(SELECT data FROM eshop.orders WHERE id=(x->>'order')::bigint),'product edit history records full current data');
 PERFORM public.assert_eq(h->n->>'currency_code','CZK'::text,'product edit history preserves currency');
 PERFORM public.assert_eq(h->n->>'created_by',x->>'actor','product edit history records command actor');
 PERFORM public.assert_true(h->n->>'created_at' IS NOT NULL,'product edit history records timestamp');
END $$;
