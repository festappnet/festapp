-- Transaction-local fixtures. All email envelopes are sealed test doubles; no provider is invoked.
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
CREATE FUNCTION pg_temp.fixture(cap integer DEFAULT 1) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; un bigint; oc bigint; f bigint; fk uuid; pt bigint; prod bigint; bank bigint; actor uuid; suffix text:=gen_random_uuid()::text;
BEGIN
 INSERT INTO organizations(title) VALUES('Waitlist regression '||suffix) RETURNING id INTO org;
 INSERT INTO units(title,organization) VALUES('Waitlist regression',org) RETURNING id INTO un;
 INSERT INTO occasions(title,unit,organization,link,start_time,end_time) VALUES('Waitlist regression',un,org,suffix,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO forms(occasion,link,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds) VALUES(oc,suffix,cap,cap IS NOT NULL,CASE WHEN cap IS NOT NULL THEN 3600 END) RETURNING id,key INTO f,fk;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Regression bank','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('spot','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion) VALUES('Admission',pt,100,'CZK',oc) RETURNING id INTO prod;
 INSERT INTO form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 SELECT id INTO actor FROM auth.users ORDER BY id LIMIT 1;
 IF actor IS NULL THEN RAISE EXCEPTION 'Bootstrap auth user required'; END IF;
 INSERT INTO occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor) VALUES(oc,actor,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 RETURN jsonb_build_object('organization',org,'unit',un,'occasion',oc,'form',f,'key',fk,'type',pt,'product',prod,'actor',actor,'link',suffix);
END $$;
CREATE FUNCTION pg_temp.checkout(x jsonb,tickets bigint[] DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',
 CASE WHEN tickets IS NULL THEN jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))
 ELSE (SELECT jsonb_agg(jsonb_build_object('ticketId',id,'fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))) FROM unnest(tickets) id) END);
$$;
CREATE FUNCTION pg_temp.delivery(code text,token text,oid bigint DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('orderId',oid,'recipient','regression@example.invalid','templateCode',code,
 'tokenHash',encode(extensions.digest(token,'sha256'),'hex'),'contentHash',repeat('f',64),'sealed',jsonb_build_object('ciphertext','sealed-test-double'));
$$;
CREATE FUNCTION pg_temp.register(x jsonb,n integer,token text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; payload jsonb;
BEGIN
 payload:=jsonb_build_object('form',x->'key','email','regression@example.invalid','tickets',(SELECT jsonb_agg(jsonb_build_object('fields','[]'::jsonb)) FROM generate_series(1,n)));
 r:=public.execute_waitlist_command_client_sync_v1('register',payload,gen_random_uuid(),gen_random_uuid(),NULL,jsonb_build_array(pg_temp.delivery('waitlist_confirmation',coalesce(token,encode(extensions.gen_random_bytes(32),'hex')))));
 IF r#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Register failed %',r; END IF;
 RETURN jsonb_build_object('order',(r#>>'{data,order,id}')::bigint,'response',r,'payload',payload);
END $$;
CREATE FUNCTION pg_temp.offer(x jsonb,oid bigint,n integer,token text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; proposal jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 proposal:=public.get_waitlist_offer_proposal((x->>'form')::bigint);
 r:=public.execute_waitlist_command_client_sync_v1('send',jsonb_build_object('formId',x->'form','revision',proposal->'revision','expiresAt',clock_timestamp()+interval '1 hour','recipients',jsonb_build_array(jsonb_build_object('orderId',oid,'count',n))),gen_random_uuid(),gen_random_uuid(),(x->>'actor')::uuid,jsonb_build_array(pg_temp.delivery('waitlist_offer',coalesce(token,encode(extensions.gen_random_bytes(32),'hex')),oid)));
 IF r#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Offer failed %',r; END IF;
 RETURN jsonb_build_object('id',r#>>'{data,offers,0,offerId}','response',r);
END $$;
CREATE FUNCTION pg_temp.accept(x jsonb,w jsonb,tickets bigint[],command uuid DEFAULT gen_random_uuid(),token text DEFAULT NULL,actor uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',w->'id','ticketIds',to_jsonb(tickets),'token',token,'orderDetails',pg_temp.checkout(x,tickets)),command,'ac000000-0000-0000-0000-000000000001'::uuid,coalesce(actor,(x->>'actor')::uuid));
$$;
-- Read-only test convenience view: every identity, answer and owner comes from
-- existing tickets/OPT/orders. Lifecycle is the public server projection.
CREATE VIEW pg_temp.ticket_rows AS
 SELECT t.*,o.id current_order_id,o.form form_id,coalesce(o.source_waitlist_order_id,o.id) origin_order_id,
 t.data answers,t.waitlist_queue_at queue_at,t.id ticket_id,
 public.get_effective_waitlist_ticket_lifecycle_internal(t.id) lifecycle
 FROM eshop.tickets t JOIN (SELECT DISTINCT "order",ticket FROM eshop.order_product_ticket) link ON link.ticket=t.id
 JOIN eshop.orders o ON o.id=link."order";
CREATE FUNCTION pg_temp.ticket_ids(p_order bigint) RETURNS bigint[] LANGUAGE sql AS $$
 SELECT coalesce(array_agg(DISTINCT ticket ORDER BY ticket),'{}'::bigint[]) FROM eshop.order_product_ticket WHERE "order"=p_order;
$$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(1); y jsonb:=pg_temp.fixture(1); r jsonb; oid bigint; regular bigint; other bigint; w jsonb;
 manage text:=repeat('1',64); offer_token text:=repeat('2',64); command uuid:=gen_random_uuid(); view_token text:=repeat('3',64);
 delivery jsonb:=jsonb_build_object('tokenHash',encode(extensions.digest(view_token,'sha256'),'hex'),'sealed',jsonb_build_object('ciphertext','synthetic'),'contentHash',repeat('f',64));
 next_delivery jsonb; viewer uuid; pid bigint; ids bigint[]; child bigint;
BEGIN
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); regular:=(r#>>'{order,id}')::bigint;
 oid:=(pg_temp.register(x,2,manage)->>'order')::bigint;
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(y)); other:=(pg_temp.register(y,1)->>'order')::bigint;
 PERFORM public.update_order_and_tickets_to_storno_221(regular);
 w:=pg_temp.offer(x,oid,1,offer_token);
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.resolve_customer_order_access_v1(offer_token,other,(w->>'id')::uuid,command,delivery); RAISE EXCEPTION 'tampered root accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='tampered root accepted' THEN RAISE; END IF; END;
 UPDATE eshop.waitlist_capabilities SET revoked_at=now() WHERE order_id=oid AND kind='offer';
 BEGIN PERFORM public.resolve_customer_order_access_v1(offer_token,oid,(w->>'id')::uuid,command,delivery); RAISE EXCEPTION 'revoked bootstrap'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='revoked bootstrap' THEN RAISE; END IF; END;
 UPDATE eshop.waitlist_capabilities SET revoked_at=NULL,expires_at=now()-interval '1 second' WHERE order_id=oid AND kind='offer';
 BEGIN PERFORM public.resolve_customer_order_access_v1(offer_token,oid,(w->>'id')::uuid,command,delivery); RAISE EXCEPTION 'expired bootstrap'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='expired bootstrap' THEN RAISE; END IF; END;
 r:=public.resolve_customer_order_access_v1(manage,oid,NULL,command,delivery);
 PERFORM assert_eq(r->>'code','200'::text,'active manage bootstraps');
 PERFORM assert_true((r#>>'{source,expiresAt}')::timestamptz>now()+interval '89 days','independent access expiry');
 BEGIN PERFORM public.resolve_customer_order_access_v1(view_token,oid,NULL,gen_random_uuid(),delivery); RAISE EXCEPTION 'view resolved write access'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='view resolved write access' THEN RAISE; END IF; END;
 r:=public.get_registered_order_overview_source_v1(oid,command);
 PERFORM assert_eq(r#>>'{source,tokenHash}',delivery->>'tokenHash','registration replay uses durable source');
 BEGIN PERFORM public.get_registered_order_overview_source_v1(other,command); RAISE EXCEPTION 'wrong registration root'; EXCEPTION WHEN no_data_found THEN NULL; END;
 -- Reissue is editor-only, audited and idempotent; old generation is revoked.
 PERFORM create_user_for_test('overview_viewer','overview-viewer-'||gen_random_uuid()::text||'@example.invalid'); viewer:=get_user_id('overview_viewer');
 INSERT INTO occasion_users(occasion,"user",is_editor_order_view,is_editor_order) VALUES((x->>'occasion')::bigint,viewer,true,false);
 next_delivery:=delivery||jsonb_build_object('tokenHash',encode(extensions.digest(repeat('4',64),'sha256'),'hex'));
 BEGIN PERFORM public.resolve_customer_order_access_v1(NULL,oid,NULL,gen_random_uuid(),next_delivery,viewer,true); RAISE EXCEPTION 'viewer reissued'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 command:=gen_random_uuid();
 r:=public.resolve_customer_order_access_v1(NULL,oid,NULL,command,next_delivery,(x->>'actor')::uuid,true);
 PERFORM assert_eq(public.get_customer_order_overview(view_token,oid)->>'code','403'::text,'reissue revokes old read');
 BEGIN PERFORM public.enqueue_order_overview_reissue_v1(oid,command,viewer,'{"ciphertext":"test"}',repeat('a',64)); RAISE EXCEPTION 'viewer emailed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.enqueue_order_overview_reissue_v1(oid,command,(x->>'actor')::uuid,'{"ciphertext":"test"}',repeat('a',64));
 PERFORM public.enqueue_order_overview_reissue_v1(oid,command,(x->>'actor')::uuid,'{"ciphertext":"retry-nonce"}',repeat('a',64));
 PERFORM assert_eq((SELECT count(*) FROM email_messages WHERE order_id=oid AND code='ORDER_OVERVIEW'),1::bigint,'one gated redelivery on retry');
 PERFORM assert_true((SELECT public.email_intent_valid(m) FROM public.email_messages m WHERE order_id=oid AND code='ORDER_OVERVIEW'),'active reissue eligible in canonical gate');
 UPDATE eshop.orders SET state='storno' WHERE id=oid;
 PERFORM assert_true((SELECT public.email_intent_valid(m) FROM public.email_messages m WHERE order_id=oid AND code='ORDER_OVERVIEW'),'cancelled history can be redelivered');
 UPDATE eshop.orders SET state='waitlisted' WHERE id=oid;
 PERFORM assert_true((SELECT tracking_policy='disabled' AND prepared->>'ciphertext'='test' FROM email_messages WHERE order_id=oid AND code='ORDER_OVERVIEW'),'encrypted immutable redelivery without tracking');
 PERFORM assert_eq(public.resolve_customer_order_access_v1(NULL,oid,NULL,command,next_delivery,(x->>'actor')::uuid,true)->'source',r->'source','reissue replay preserves source');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders_history WHERE "order"=oid AND data->>'action'='order_overview_reissued'),1::bigint,'one audit entry');
 view_token:=repeat('4',64);
 -- Missing event end refuses new issuance; no partial source persists.
 ALTER TABLE public.occasions ALTER COLUMN end_time DROP NOT NULL;
 UPDATE occasions SET end_time=NULL WHERE id=(y->>'occasion')::bigint;
 BEGIN PERFORM public.issue_order_overview_internal(other,delivery,gen_random_uuid()); RAISE EXCEPTION 'missing end accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='missing end accepted' THEN RAISE; END IF; END;
 UPDATE occasions SET end_time=now()+interval '1 day' WHERE id=(y->>'occasion')::bigint;
 ALTER TABLE public.occasions ALTER COLUMN end_time SET NOT NULL;
 -- Cross-context child provenance fails closed, even with the same recipient.
 child:=public.allocate_ticket_order_identity_internal((y->>'form')::bigint);
 UPDATE eshop.orders SET source_waitlist_order_id=oid WHERE id=child;
 PERFORM assert_eq(public.get_customer_order_overview(view_token,oid)->>'code','403'::text,'cross-tenant child rejects read');
 DELETE FROM eshop.orders WHERE id=child;
 UPDATE eshop.tickets SET state='storno' WHERE id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=oid);
 BEGIN PERFORM public.resolve_customer_order_access_v1(manage,oid,NULL,gen_random_uuid(),delivery); RAISE EXCEPTION 'ended waiting bootstrapped'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='ended waiting bootstrapped' THEN RAISE; END IF; END;
 PERFORM assert_eq(public.get_customer_order_overview(view_token,oid)->>'code','200'::text,'ended waiting keeps independent view');
 UPDATE eshop.waitlist_capabilities SET expires_at=now()-interval '1 second' WHERE token_hash=next_delivery->>'tokenHash';
 PERFORM assert_true(NOT (SELECT public.email_intent_valid(m) FROM public.email_messages m WHERE order_id=oid AND code='ORDER_OVERVIEW'),'expired reissue fails send-time gate');
 BEGIN PERFORM public.resolve_customer_order_access_v1(manage,oid,NULL,gen_random_uuid(),delivery); RAISE EXCEPTION 'implicit renewal accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='implicit renewal accepted' THEN RAISE; END IF; END;
 UPDATE eshop.order_overview_sources SET expires_at=now()-interval '1 second'
 WHERE token_hash IN(SELECT token_hash FROM eshop.waitlist_capabilities WHERE order_id=oid AND kind='order_view');
 PERFORM assert_eq(public.cleanup_order_overview_sources_internal(1),1,'source cleanup bounded');
 PERFORM public.cleanup_order_overview_sources_internal(100);
 BEGIN PERFORM public.resolve_customer_order_access_v1(NULL,oid,NULL,command,delivery,(x->>'actor')::uuid,true); RAISE EXCEPTION 'expired command renewed'; EXCEPTION WHEN OTHERS THEN IF SQLERRM='expired command renewed' THEN RAISE; END IF; END;
 -- Public view cannot call internal financial or issuance functions.
 PERFORM assert_true(NOT has_function_privilege('anon','public.issue_order_overview_internal(bigint,jsonb,uuid)','EXECUTE'),'issuer private');
 PERFORM assert_true(NOT has_function_privilege('anon','public.customer_order_payment_internal(bigint)','EXECUTE'),'payment helper private');
 RAISE NOTICE 'PASS access bootstrap, invalid scopes, reissue, replay, expiry, private ACL';
END $$;
ROLLBACK;
