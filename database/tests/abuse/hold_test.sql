-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/helpers/canonical_blueprint_order_fixture.sql
DO $$
DECLARE org bigint; un bigint; occ bigint; bp bigint; fk uuid; seat bigint; seat2 bigint;
 buyer uuid:=gen_random_uuid(); thief uuid:=gen_random_uuid(); expiry timestamptz; r jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Hold fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Fixture',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO eshop.blueprints(organization,occasion,title) VALUES(org,occ,'Seats') RETURNING id INTO bp;
 INSERT INTO public.forms(occasion,blueprint,title,is_open) VALUES(occ,bp,'Seats',true) RETURNING key INTO fk;
 INSERT INTO eshop.spots(occasion,blueprint,title) VALUES(occ,bp,'One') RETURNING id INTO seat;
 INSERT INTO eshop.spots(occasion,blueprint,title) VALUES(occ,bp,'Two') RETURNING id INTO seat2;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Admission','spot');
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
 SELECT occ,id,'Admission',100,'CZK' FROM eshop.product_types WHERE occasion=occ;
 UPDATE eshop.spots SET product=(SELECT id FROM eshop.products WHERE occasion=occ LIMIT 1) WHERE occasion=occ;
 INSERT INTO public.form_fields(form,product_type,type)
 SELECT id,(SELECT id FROM eshop.product_types WHERE occasion=occ LIMIT 1),'product_type' FROM public.forms WHERE key=fk;
 PERFORM pg_temp.prepare_order_blueprint_fixture(fk);
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','anon',true);
 EXECUTE 'SET LOCAL ROLE anon';
 r:=public.select_spot(fk,buyer,seat,true);
 PERFORM assert_eq((r->>'code')::int,200,'legitimate buyer can hold a seat');
 PERFORM assert_eq((public.select_spot(fk,thief,seat,true)->>'code')::int,403,'foreign secret cannot take over active hold');
 PERFORM assert_eq((public.select_spot(fk,thief,seat,false)->>'code')::int,403,'foreign secret cannot release active hold');
 PERFORM assert_eq((public.select_spot(fk,NULL,seat,true)->>'code')::int,400,'NULL secret is rejected');
 EXECUTE 'RESET ROLE';
 SELECT secret_expiration_time INTO expiry FROM eshop.spots WHERE id=seat;
 EXECUTE 'SET LOCAL ROLE anon';
 PERFORM public.select_spot(fk,buyer,seat,true);
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT secret_expiration_time FROM eshop.spots WHERE id=seat),expiry,'retry never extends maximum hold lifetime');
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='hold.active.buyer';
 BEGIN PERFORM public.select_spot(fk,buyer,seat2,true); RAISE EXCEPTION 'active hold cap bypassed'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 UPDATE eshop.spots SET secret_expiration_time=now()-interval '1 second' WHERE id=seat;
 PERFORM assert_eq((public.select_spot(fk,thief,seat,true)->>'code')::int,200,'expired hold can be acquired by another buyer');
 UPDATE public.forms SET is_open=false WHERE key=fk;
 PERFORM assert_eq((public.select_spot(fk,buyer,seat2,true)->>'code')::int,403,'closed form cannot be held through direct RPC');
END $$;
