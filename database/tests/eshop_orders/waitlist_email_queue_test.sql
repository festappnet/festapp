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
DECLARE x jsonb:=pg_temp.fixture(2); y jsonb; f bigint:=(x->>'form')::bigint; regular bigint; source bigint; r jsonb; w jsonb; person bigint; msg public.email_messages; lease uuid:=gen_random_uuid(); attempt uuid; token text:=repeat('1',64); manage text:=repeat('2',64); oid bigint; uid bigint; cid bigint;
BEGIN
 FOR i IN 1..2 LOOP r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x)); END LOOP;
 source:=(pg_temp.register(x,2,manage)->>'order')::bigint;
 FOR regular IN SELECT id FROM eshop.orders WHERE form=f AND state<>'waitlisted' LOOP PERFORM public.update_order_and_tickets_to_storno_221(regular); END LOOP;
 w:=pg_temp.offer(x,source,2,token);
 PERFORM assert_false(has_function_privilege('anon','public.get_waitlist_email_render_context_v1(bigint,uuid,text)','EXECUTE'),'renderer anon ACL');
 PERFORM assert_false(has_function_privilege('authenticated','public.get_waitlist_email_render_context_v1(bigint,uuid,text)','EXECUTE'),'renderer authenticated ACL');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN PERFORM public.get_waitlist_email_render_context_v1(source,(w->>'id')::uuid,'regression@example.invalid'); RAISE EXCEPTION 'nonservice render accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 r:=public.get_waitlist_email_render_context_v1(source,(w->>'id')::uuid,'regression@example.invalid');
 PERFORM assert_eq(r->>'tokenHash',encode(extensions.digest(token,'sha256'),'hex'),'renderer offer hash');
 PERFORM assert_eq(r->>'manageTokenHash',encode(extensions.digest(manage,'sha256'),'hex'),'renderer manage hash');
 PERFORM assert_jsonb_contains(r,'{"participantCount":2,"offeredCount":2,"manageEnvelope":{"ciphertext":"sealed-test-double"}}','renderer current counts and sealed envelope');
 PERFORM assert_true(NOT r ? 'token' AND NOT r ? 'manageToken' AND r->>'orderId'=source::text,'renderer no plaintext token');
 BEGIN PERFORM public.get_waitlist_email_render_context_v1(source,(w->>'id')::uuid,'other@example.invalid'); RAISE EXCEPTION 'wrong recipient render accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%waitlist_email_source_invalid%' THEN RAISE; END IF; END;
 y:=pg_temp.fixture(1);
 BEGIN PERFORM public.get_waitlist_email_render_context_v1(source,gen_random_uuid(),'regression@example.invalid'); RAISE EXCEPTION 'foreign offer render accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%waitlist_email_source_invalid%' THEN RAISE; END IF; END;
 -- Templates resolve occasion, then unit, then organization, then global defaults.
 PERFORM assert_true((public.get_email_template_and_wrapper('waitlist_offer',jsonb_build_object('occasion',x->'occasion'))#>>'{template,html}') IS NOT NULL,'global default seeded');
 INSERT INTO email_templates(code,organization,subject,html) VALUES('waitlist_offer',(x->>'organization')::bigint,'Org custom','Org body') RETURNING id INTO oid;
 PERFORM assert_eq((public.get_email_template_and_wrapper('waitlist_offer',jsonb_build_object('occasion',x->'occasion'))#>>'{template,id}')::bigint,oid,'organization inheritance');
 INSERT INTO email_templates(code,unit,subject,html) VALUES('waitlist_offer',(x->>'unit')::bigint,'Unit custom','Unit body') RETURNING id INTO uid;
 PERFORM assert_eq((public.get_email_template_and_wrapper('waitlist_offer',jsonb_build_object('occasion',x->'occasion'))#>>'{template,id}')::bigint,uid,'unit inheritance');
 INSERT INTO email_templates(code,occasion,subject,html) VALUES('waitlist_offer',(x->>'occasion')::bigint,'Occasion custom','Occasion body') RETURNING id INTO cid;
 PERFORM assert_eq((public.get_email_template_and_wrapper('waitlist_offer',jsonb_build_object('occasion',x->'occasion'))#>>'{template,id}')::bigint,cid,'occasion inheritance');
 -- Prepare exactly the queued offer using a sealed fake; global outbound pause stays on.
 SELECT * INTO msg FROM email_messages WHERE message_kind='waitlist_offer' AND order_id=source AND data->>'offer_id'=w->>'id';
 UPDATE email_messages SET workflow_state='preparing',lease_token=lease,lease_until=now()+interval '90 seconds' WHERE id=msg.id;
 INSERT INTO email_attempts(message_id,lease_token,state) VALUES(msg.message_id,lease,'preparing') RETURNING attempt_id INTO attempt;
 PERFORM public.prepare_email(msg.message_id,lease,'{"ciphertext":"fake-snapshot"}',jsonb_build_object('waitlist_pending_count',2));
 SELECT ticket_id INTO person FROM eshop.waitlist_offer_slots WHERE offer_id=(w->>'id')::uuid ORDER BY id LIMIT 1;
 r:=pg_temp.accept(x,w,ARRAY[person]); PERFORM assert_eq(r#>>'{data,code}','200'::text,'partial acceptance changes queued snapshot');
 PERFORM set_config('request.jwt.claim.sub','',true);
 r:=public.begin_email_send(attempt,lease);
 PERFORM assert_eq(r->>'disposition','deferred'::text,'changed snapshot never grants send');
 PERFORM assert_true((SELECT workflow_state='pending' AND prepared IS NULL AND prepared_hash IS NULL AND lease_token IS NULL AND last_error='offer_snapshot_changed' FROM email_messages WHERE id=msg.id),'stale snapshot discarded for same canonical queue');
 PERFORM assert_true((SELECT state='cancelled' AND began_at IS NULL AND error_code='offer_snapshot_changed' FROM email_attempts WHERE attempt_id=attempt),'no provider permit started');
 r:=public.get_waitlist_email_render_context_v1(source,(w->>'id')::uuid,'regression@example.invalid');
 PERFORM assert_eq((r->>'offeredCount')::integer,1,'rerender live remaining slots');
 PERFORM assert_eq((r->>'participantCount')::integer,1,'rerender current source people');
 PERFORM assert_eq((SELECT html FROM email_templates WHERE id=cid),'Occasion body'::text,'custom template untouched by lifecycle');
 -- An expiry/cancel between prepare and send also invalidates the source.
 lease:=gen_random_uuid();
 UPDATE email_messages SET workflow_state='preparing',lease_token=lease,lease_until=now()+interval '90 seconds' WHERE id=msg.id;
 INSERT INTO email_attempts(message_id,lease_token,state) VALUES(msg.message_id,lease,'preparing') RETURNING attempt_id INTO attempt;
 PERFORM public.prepare_email(msg.message_id,lease,'{"ciphertext":"new-snapshot"}',jsonb_build_object('waitlist_pending_count',1));
 UPDATE eshop.waitlist_offers SET created_at=now()-interval '2 hours',expires_at=clock_timestamp()-interval '1 second' WHERE id=(w->>'id')::uuid;
 r:=public.begin_email_send(attempt,lease); PERFORM assert_eq(r->>'disposition','cancelled'::text,'expired offer blocked before provider');
 PERFORM assert_true((SELECT began_at IS NULL FROM email_attempts WHERE attempt_id=attempt),'expired no provider permit');
 BEGIN PERFORM public.get_waitlist_email_render_context_v1(source,(w->>'id')::uuid,'regression@example.invalid'); RAISE EXCEPTION 'expired source render accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%waitlist_email_source_invalid%' THEN RAISE; END IF; END;
 RAISE NOTICE 'PASS canonical queue snapshot refresh/expiry fence/service context hashes/ACL/template hierarchy';
END $$;
ROLLBACK;
