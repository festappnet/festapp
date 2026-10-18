SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
CREATE FUNCTION pg_temp.reference_fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; un bigint; oc bigint; f bigint; alias_form bigint; account bigint; alias_account bigint; other bigint; ns text; prod bigint; pt bigint; fk uuid;
BEGIN
 INSERT INTO organizations(title) VALUES('Local reference fixture') RETURNING id INTO org;
 INSERT INTO units(title,organization) VALUES('Local reference fixture',org) RETURNING id INTO un;
 INSERT INTO occasions(title,organization,unit,link,start_time,end_time) VALUES('References',org,un,gen_random_uuid()::text,now(),now()+interval '2 days') RETURNING id INTO oc;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies) VALUES('Local','FIO','19-2000145399/0800',ARRAY['CZK','EUR']) RETURNING id INTO account;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies) VALUES('Alias','FIO','CZ6508000000192000145399',ARRAY['CZK','EUR']) RETURNING id INTO alias_account;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies) VALUES('Other','FIO','1234/2010',ARRAY['CZK']) RETURNING id INTO other;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(un,account,0),(un,alias_account,1),(un,other,2);
 INSERT INTO forms(occasion,bank_account,is_open,data) VALUES(oc,account,true,'{"variable_symbol":{"type":"sequence","starting_number":1205}}') RETURNING id,key INTO f,fk;
 INSERT INTO forms(occasion,bank_account,is_open) VALUES(oc,alias_account,true) RETURNING id INTO alias_form;
 ns:=public.enroll_payment_reference_account(account);
 PERFORM public.enroll_payment_reference_account(alias_account);PERFORM public.enroll_payment_reference_account(other);
 INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES(org,'active',repeat('a',64));
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true WHERE id IN(SELECT namespace_id FROM eshop.payment_reference_accounts WHERE bank_account_id IN(account,alias_account,other));
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,occasion,price,currency_code,is_hidden) VALUES('Admission',pt,oc,100,'CZK',false) RETURNING id INTO prod;
 INSERT INTO form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 RETURN jsonb_build_object('org',org,'unit',un,'occasion',oc,'form',f,'aliasForm',alias_form,'key',fk,'account',account,'alias',alias_account,'other',other,'namespace',ns,'product',prod);
END $$;
CREATE FUNCTION pg_temp.reference_payment(p_form bigint,p_bank bigint) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE order_id bigint; payment bigint;
BEGIN
 order_id:=public.allocate_ticket_order_identity_internal(p_form);
 INSERT INTO eshop.payment_info(bank_account,amount,currency_code) VALUES(p_bank,100,'CZK') RETURNING id INTO payment;
 UPDATE eshop.orders SET payment_info=payment,price=100,state='created' WHERE id=order_id;
 RETURN payment;
END $$;
CREATE FUNCTION pg_temp.reference_reserve(p_form bigint,p_bank bigint,p_source text,p_policy jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE payment bigint:=pg_temp.reference_payment(p_form,p_bank); symbol bigint;
BEGIN
 symbol:=public.reserve_payment_reference_internal(payment,p_form,p_source,p_policy,repeat('b',64));
 UPDATE eshop.payment_info SET variable_symbol=symbol WHERE id=payment;
 RETURN jsonb_build_object('payment',payment,'symbol',symbol);
END $$;
DO $$
DECLARE x jsonb:=pg_temp.reference_fixture(); f bigint:=(x->>'form')::bigint; af bigint:=(x->>'aliasForm')::bigint;
 bank bigint:=(x->>'account')::bigint; alias_bank bigint:=(x->>'alias')::bigint; ns text:=x->>'namespace';
 r jsonb; other jsonb; p bigint; value bigint; old_payment bigint; initial_count bigint; result jsonb; input jsonb;
 command uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); failed boolean; i integer;
BEGIN
 PERFORM assert_eq(public.canonical_payment_reference_account_internal(' 19-2000145399 / 0800 '),'CZ6508000000192000145399','local and IBAN aliases normalize identically');
 PERFORM assert_eq((SELECT namespace_id FROM eshop.payment_reference_accounts WHERE bank_account_id=alias_bank),ns,'aliases share namespace');
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=false WHERE id=ns;
 PERFORM public.import_payment_reference(bank,'occupied:1205',1205,repeat('a',64));
 PERFORM public.import_payment_reference(alias_bank,'occupied:1206',1206,repeat('a',64));
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true WHERE id=ns;
 r:=pg_temp.reference_reserve(f,bank,'first','{"mode":"sequence","from":"1205"}');
 PERFORM assert_eq((r->>'symbol')::bigint,1207::bigint,'sequence skips reservations from every alias');
 p:=(r->>'payment')::bigint;
 PERFORM assert_eq(public.reserve_payment_reference_internal(p,f,'first','{"mode":"sequence","from":"01205"}',repeat('b',64)),1207::bigint,'normalized policy replays same purpose');
 failed:=false; BEGIN PERFORM public.reserve_payment_reference_internal(p,f,'first','{"mode":"sequence","from":"1206"}',repeat('b',64)); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_SOURCE_CONFLICT'; END;
 PERFORM assert_true(failed,'changed policy cannot reuse source');
 failed:=false; BEGIN PERFORM public.reserve_payment_reference_internal(p,f,'first','{"mode":"sequence","from":"1205"}',repeat('c',64)); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_SOURCE_CONFLICT'; END;
 PERFORM assert_true(failed,'changed hash cannot reuse source');
 r:=pg_temp.reference_reserve(af,alias_bank,'second','{"mode":"sequence","from":"1205"}');
 PERFORM assert_eq((r->>'symbol')::bigint,1208::bigint,'other form and alias share exact namespace');
 other:=pg_temp.reference_reserve(af,(x->>'other')::bigint,'other-account','{"mode":"exact","value":"1207"}');
 PERFORM assert_eq((other->>'symbol')::bigint,1207::bigint,'different physical accounts have independent namespaces');
 failed:=false; BEGIN PERFORM pg_temp.reference_reserve(af,alias_bank,'conflict','{"mode":"exact","value":"0001207"}'); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_CONFLICT'; END;
 PERFORM assert_true(failed,'leading zero exact collision cannot renumber');
 old_payment:=p;
 UPDATE eshop.orders SET payment_info=NULL WHERE payment_info=p;
 DELETE FROM eshop.payment_info WHERE id=p;
 PERFORM assert_eq((SELECT original_payment_info_id FROM eshop.payment_reference_reservations WHERE namespace_id=ns AND source_ref='first'),old_payment,'deleted payment keeps reservation audit ID');
 PERFORM assert_true((SELECT payment_info_id IS NULL FROM eshop.payment_reference_reservations WHERE namespace_id=ns AND source_ref='first'),'live FK detaches without erasing history');
 r:=pg_temp.reference_reserve(f,bank,'after-delete','{"mode":"sequence","from":"1"}');
 PERFORM assert_eq((r->>'symbol')::bigint,1209::bigint,'lower configured floor or deletion never recycles references');
 initial_count:=(SELECT count(*) FROM eshop.payment_reference_reservations);
 BEGIN
  PERFORM pg_temp.reference_reserve(f,bank,'rolled-back','{"mode":"exact","value":"991"}');
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='rollback fixture';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations),initial_count,'order/reference rollback is atomic');
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=false WHERE id=ns;
 failed:=false; BEGIN PERFORM pg_temp.reference_reserve(f,bank,'locked','{"mode":"random","preferred_digits":4}'); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_REGISTRY_LOCKED'; END;
 PERFORM assert_true(failed,'active account cannot fall back while registry is locked');
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true WHERE id=ns;
 failed:=false; BEGIN PERFORM public.generate_payment_variable_symbol(bank,f); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_RESERVATION_REQUIRED'; END;
 PERFORM assert_true(failed,'private legacy generator cannot serve active form');
 -- Finalizer + immutable mutation receipt, with no external service or provider.
 input:=jsonb_build_object('form',x->'key','email','reference-test@example.invalid','ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))));
 result:=public.create_ticket_order_client_sync_v1(input,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','public checkout uses local reservation');
 p:=(result#>>'{data,order,payment_info,id}')::bigint;
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations WHERE payment_info_id=p),1::bigint,'exactly one reservation committed with payment');
 result:=public.create_ticket_order_client_sync_v1(input,command,client);
 PERFORM assert_eq((result#>>'{data,order,payment_info,id}')::bigint,p,'receipt retry returns same payment');
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations WHERE payment_info_id=p),1::bigint,'receipt retry consumes no extra VS');
 PERFORM assert_eq(public.create_ticket_order(input)->>'errorCode','COMMAND_IDENTITY_REQUIRED','identity-free cached RPC cannot create active orders');
 UPDATE eshop.orders SET state='storno' WHERE payment_info=p;
 result:=public.create_ticket_order_client_sync_v1(input,command,client);
 PERFORM assert_eq(result#>>'{data,errorCode}','ORDER_NOT_PAYABLE','receipt cannot resurrect cancelled instructions');
 -- A one-digit full space returns a bounded retryable error; two digits extend.
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=false WHERE id=(SELECT namespace_id FROM eshop.payment_reference_accounts WHERE bank_account_id=(x->>'other')::bigint);
 FOR i IN 1..9 LOOP PERFORM public.import_payment_reference((x->>'other')::bigint,'digit:'||i,i,repeat('a',64)); END LOOP;
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true WHERE id=(SELECT namespace_id FROM eshop.payment_reference_accounts WHERE bank_account_id=(x->>'other')::bigint);
 failed:=false; BEGIN PERFORM pg_temp.reference_reserve(af,(x->>'other')::bigint,'random-full','{"mode":"random","preferred_digits":1,"max_digits":1}'); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_RETRY_REQUIRED'; END;
 PERFORM assert_true(failed,'bounded random contention does not claim exhaustion');
 r:=pg_temp.reference_reserve(af,(x->>'other')::bigint,'random-extend','{"mode":"random","preferred_digits":1,"max_digits":2}');
 PERFORM assert_true((r->>'symbol')::bigint BETWEEN 10 AND 99,'random extends within configured maximum');
 failed:=false; BEGIN PERFORM pg_temp.reference_reserve(f,bank,'invalid','{"mode":"exact","value":"0"}'); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_POLICY_INVALID'; END;
 PERFORM assert_true(failed,'new exact zero is invalid');
 -- Last available number is assigned once, then sequence exhaustion is explicit.
 r:=pg_temp.reference_reserve(f,bank,'top','{"mode":"sequence","from":"9999999999"}');
 PERFORM assert_eq((r->>'symbol')::bigint,9999999999::bigint,'sequence upper bound is valid once');
 failed:=false; BEGIN PERFORM pg_temp.reference_reserve(f,bank,'overflow','{"mode":"sequence","from":"1"}'); EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_SEQUENCE_EXHAUSTED'; END;
 PERFORM assert_true(failed,'sequence never wraps or switches to random');
 PERFORM assert_false(has_function_privilege('anon','public.reserve_order_payment_reference_internal(bigint,bigint)','EXECUTE'),'anonymous cannot call allocator helper');
 PERFORM assert_false(has_table_privilege('authenticated','eshop.payment_reference_reservations','INSERT'),'users cannot forge registry rows');
 PERFORM assert_false(has_table_privilege('authenticated','eshop.payment_info','UPDATE'),'direct mutable-symbol table bypass is revoked');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.reference_fixture(); f bigint:=(x->>'form')::bigint; bank bigint:=(x->>'account')::bigint;
 p bigint; actor uuid; command uuid:=gen_random_uuid(); r jsonb; before_count bigint; failed boolean; unrelated jsonb;
BEGIN
 PERFORM create_user_for_test('reference-editor','reference-editor@example.invalid');actor:=get_user_id('reference-editor');
 INSERT INTO occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES((x->>'occasion')::bigint,actor,true,true);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 p:=pg_temp.reference_payment(f,bank);
 r:=public.reserve_draft_payment_reference(p,42,command);
 PERFORM assert_eq(r#>>'{data,variable_symbol}','42','authenticated editor reserves an exact unpublished draft');
 PERFORM assert_eq(public.reserve_draft_payment_reference(p,42,command),r,'manual command is receipted and idempotent');
 failed:=false;BEGIN PERFORM public.reserve_draft_payment_reference(p,43,gen_random_uuid());EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PUBLISHED_PAYMENT_REFERENCE_IMMUTABLE';END;
 PERFORM assert_true(failed,'an assigned/published symbol cannot be edited again');
 failed:=false;BEGIN PERFORM public.update_bank_account(bank,'5678/2010','Changed','FIO',ARRAY['CZK','EUR']);EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_ACCOUNT_IDENTITY_IMMUTABLE';END;
 PERFORM assert_true(failed,'reference-only enrollment freezes physical identity without bank ingestion');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 failed:=false;BEGIN PERFORM public.enroll_payment_reference_account(bank);EXCEPTION WHEN insufficient_privilege THEN failed:=true;END;
 PERFORM assert_true(failed,'authenticated clients cannot enroll arbitrary receiving identities');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 -- A dense prefix is selected in one indexed statement, with no 1000-loop cap.
 INSERT INTO eshop.payment_reference_reservations(namespace_id,variable_symbol,source_ref,policy,payload_sha256)
 SELECT x->>'namespace',n,'dense:'||n,'{"mode":"historical"}',repeat('a',64) FROM generate_series(1,2000) n
 ON CONFLICT(namespace_id,variable_symbol) DO NOTHING;
 r:=pg_temp.reference_reserve(f,bank,'dense-next','{"mode":"sequence","from":"1"}');
 PERFORM assert_eq((r->>'symbol')::bigint,2001::bigint,'dense prefix uses numeric account index');
 UPDATE eshop.payment_reference_scopes SET phase='inactive' WHERE organization_id=(x->>'org')::bigint;
 PERFORM public.activate_payment_reference_scope((x->>'org')::bigint,repeat('d',64),true);
 PERFORM assert_eq((SELECT phase FROM eshop.payment_reference_scopes WHERE organization_id=(x->>'org')::bigint),'active','reviewed scope activates after current live imports are covered');
 unrelated:=pg_temp.reference_fixture();
 UPDATE eshop.payment_reference_scopes SET phase='inactive' WHERE organization_id=(unrelated->>'org')::bigint;
 failed:=false;BEGIN PERFORM public.activate_payment_reference_scope((x->>'org')::bigint,repeat('d',64),true);EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_UNMIGRATED_SHARED_WRITER';END;
 PERFORM assert_true(failed,'an unselected shared writer blocks activation');
 failed:=false;BEGIN PERFORM public.generate_payment_variable_symbol((unrelated->>'account')::bigint,(unrelated->>'form')::bigint);EXCEPTION WHEN OTHERS THEN failed:=SQLERRM='PAYMENT_REFERENCE_SHARED_ACCOUNT_REQUIRES_ENROLLMENT';END;
 PERFORM assert_true(failed,'a later unactivated writer cannot issue independently into an already protected physical namespace');
 before_count:=(SELECT count(*) FROM eshop.payment_reference_reservations);
 UPDATE eshop.products SET price=0 WHERE id=(x->>'product')::bigint;
 r:=public.create_ticket_order_client_sync_v1(jsonb_build_object('form',x->'key','email','free@example.invalid','ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))),gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','free checkout retains existing behavior');
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations),before_count,'free checkout consumes no reference');
 UPDATE eshop.products SET price=100,currency_code='EUR' WHERE id=(x->>'product')::bigint;
 UPDATE forms SET bank_account=(x->>'alias')::bigint WHERE id=f;
 r:=public.create_ticket_order_client_sync_v1(jsonb_build_object('form',x->'key','email','eur@example.invalid','ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))),gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','activated EUR checkout reserves before publishing RF');
 PERFORM assert_eq(r#>>'{data,order,payment_info,creditor_reference}',public.generate_creditor_reference((r#>>'{data,order,payment_info,variable_symbol}')::bigint),'EUR RF derives from the committed reserved VS');
 PERFORM assert_false(has_column_privilege('authenticated','eshop.bank_accounts','account_number','UPDATE'),'direct receiving-identity mutation is revoked');
END $$;
