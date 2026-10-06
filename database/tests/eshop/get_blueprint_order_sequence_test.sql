BEGIN;
DO $$
DECLARE org bigint; unit_id bigint; occ bigint; blueprint_id bigint; ord bigint; opt bigint; spot_id bigint; actor uuid; link text := 'sequence-blueprint-'||gen_random_uuid(); result jsonb;
BEGIN
 SELECT id INTO actor FROM auth.users LIMIT 1;
 PERFORM assert_not_null(actor,'Auth fixture exists');
 INSERT INTO public.organizations(title) VALUES('Sequence blueprint test') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Unit',org) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Occasion',org,unit_id,link,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(occ,actor,true);
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data) VALUES(occ,public.next_order_sequence(occ),public.generate_order_symbol(),'paid','{}') RETURNING id INTO ord;
 INSERT INTO eshop.order_product_ticket("order") VALUES(ord) RETURNING id INTO opt;
 INSERT INTO eshop.spots(occasion,title,order_product_ticket) VALUES(occ,'Seat',opt) RETURNING id INTO spot_id;
 INSERT INTO eshop.blueprints(organization,occasion,title,objects) VALUES(org,occ,'Blueprint',jsonb_build_array(jsonb_build_object('id',spot_id,'type','spot'))) RETURNING id INTO blueprint_id;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 result:=public.get_blueprint_for_edit(link);
 PERFORM assert_eq((result->>'code')::integer,200,'Blueprint loads');
 PERFORM assert_eq(jsonb_array_length(result#>'{data,orders}'),1,'Reserved seat order returned');
 PERFORM assert_eq((result#>>'{data,orders,0,order_sequence}')::bigint,1::bigint,'Blueprint order has canonical sequence for shared Dart parser');
 PERFORM assert_eq(result#>>'{data,orders,0,order_symbol}',(SELECT order_symbol FROM eshop.orders WHERE id=ord),'Blueprint symbol retained');
END $$;
ROLLBACK;
