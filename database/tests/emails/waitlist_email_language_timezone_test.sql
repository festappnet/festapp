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
DECLARE x jsonb:=pg_temp.fixture(2); source bigint; token text:=repeat('a',64); ctx jsonb; custom_id bigint;
BEGIN
 PERFORM assert_eq(public.create_ticket_order_internal_v1(pg_temp.checkout(x))->>'code','200'::text,'first ordinary admission fills capacity');
 PERFORM assert_eq(public.create_ticket_order_internal_v1(pg_temp.checkout(x))->>'code','200'::text,'second ordinary admission fills capacity');
 source:=(pg_temp.register(x,1,token)->>'order')::bigint;
 UPDATE public.organizations SET data=coalesce(data,'{}')||'{"timezone":"America/New_York"}'::jsonb WHERE id=(x->>'organization')::bigint;
 UPDATE public.units SET data=coalesce(data,'{}')||'{"timezone":"Europe/London"}'::jsonb WHERE id=(x->>'unit')::bigint;
 UPDATE public.occasions SET data=coalesce(data,'{}')||'{"timezone":"Europe/Prague"}'::jsonb WHERE id=(x->>'occasion')::bigint;
 ctx:=public.get_waitlist_email_render_context_v1(source,NULL,'regression@example.invalid');
 PERFORM assert_eq(ctx->>'timeZone','Europe/Prague'::text,'occasion timezone wins');
 UPDATE public.occasions SET data=data-'timezone' WHERE id=(x->>'occasion')::bigint;
 ctx:=public.get_waitlist_email_render_context_v1(source,NULL,'regression@example.invalid');
 PERFORM assert_eq(ctx->>'timeZone','Europe/London'::text,'unit timezone inherited when occasion unset');
 UPDATE public.units SET data=data-'timezone' WHERE id=(x->>'unit')::bigint;
 ctx:=public.get_waitlist_email_render_context_v1(source,NULL,'regression@example.invalid');
 PERFORM assert_eq(ctx->>'timeZone','America/New_York'::text,'organization timezone fallback');
 UPDATE public.occasions SET data=data||'{"timezone":"invalid/zone"}'::jsonb WHERE id=(x->>'occasion')::bigint;
 ctx:=public.get_waitlist_email_render_context_v1(source,NULL,'regression@example.invalid');
 PERFORM assert_eq(ctx->>'timeZone','America/New_York'::text,'invalid occasion setting safely falls back');
 UPDATE public.organizations SET data=data-'timezone' WHERE id=(x->>'organization')::bigint;
 ctx:=public.get_waitlist_email_render_context_v1(source,NULL,'regression@example.invalid');
 PERFORM assert_eq(ctx->>'timeZone','Europe/Prague'::text,'canonical TimeHelper default used when all settings missing');
 PERFORM assert_true((SELECT html LIKE '%{{participant_phrase}}%' AND html NOT LIKE '%stornu%' FROM public.email_templates WHERE code='waitlist_confirmation' AND organization IS NULL AND unit IS NULL AND occasion IS NULL),'confirmation global copy uses grammatical phrase without cancellation sentence');
 PERFORM assert_true((SELECT html LIKE '%{{offered_places}}%' AND html NOT LIKE '%(UTC)%' FROM public.email_templates WHERE code='waitlist_offer' AND organization IS NULL AND unit IS NULL AND occasion IS NULL),'offer global copy uses grammatical phrase and resolved time');
 INSERT INTO public.email_templates(code,subject,html,occasion) VALUES('waitlist_offer','Custom {{offered_count}}','Custom {{participant_count}} {{offer_expires_at}}',(x->>'occasion')::bigint) RETURNING id INTO custom_id;
 PERFORM assert_eq((SELECT html FROM public.email_templates WHERE id=custom_id),'Custom {{participant_count}} {{offer_expires_at}}'::text,'custom numeric substitutions remain stored untouched');
 PERFORM assert_true(NOT has_function_privilege('anon','public.get_waitlist_email_render_context_v1(bigint,uuid,text)','EXECUTE'),'timezone context remains service only');
END $$;
ROLLBACK;
