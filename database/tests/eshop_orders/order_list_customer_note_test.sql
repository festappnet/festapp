-- test-setup: database/functions/eshop_orders/get_orders.sql
-- test-setup: database/functions/eshop_orders/get_orders_tab_data.sql
DO $$
DECLARE org bigint; un bigint; oc bigint; actor uuid; bundle jsonb; item jsonb;
 suffix text:=gen_random_uuid()::text;
 customer_note text:=E'Prosím u jednoho stolu.\nDěkuji.';
BEGIN
 INSERT INTO public.organizations(title) VALUES('Order note regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Order note regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Order note regression',org,un,'note-'||suffix,now(),now()+interval '1 day') RETURNING id INTO oc;
 PERFORM public.create_user_for_test('order_note_reader','order-note-reader@example.invalid');
 actor:=public.get_user_id('order_note_reader');
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,actor,true);
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data,note_hidden,price,currency_code)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered',
  jsonb_build_object('name','Test','note',customer_note,'customAnswer','only in detail'),
  'Internal organizer note',100,'CZK');
 PERFORM pg_temp.adopt_public_link_fixtures();
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 bundle:=public.get_orders_tab_data('note-'||suffix);
 item:=bundle#>'{orders,0}';
 PERFORM assert_eq(item#>>'{data,note}',customer_note,'order list preserves the customer note');
 PERFORM assert_false((item->'data') ? 'customAnswer','list keeps its bounded data projection');
 PERFORM assert_eq(item->>'note_hidden','Internal organizer note','internal note remains a separate field');
 bundle:=public.get_orders('note-'||suffix,NULL,'{"include_full_order_data":true}');
 PERFORM assert_eq(bundle#>>'{data,orders,0,data,note}',customer_note,'detail keeps the same customer note');
 RESET ROLE;
END $$;
