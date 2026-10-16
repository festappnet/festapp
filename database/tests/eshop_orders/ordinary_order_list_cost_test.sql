-- Ordinary lists must not enumerate every ticket/offer lifecycle to get actions.
-- This transaction-local test double catches the expensive call at its real seam.
CREATE OR REPLACE FUNCTION public.get_waitlist_summary_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN RAISE EXCEPTION 'Ordinary order unexpectedly aggregated ticket lifecycles'; END $$;

DO $$
DECLARE org bigint; un bigint; oc bigint; actor uuid; bundle jsonb;
 suffix text := gen_random_uuid()::text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Ordinary list regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Ordinary list regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Ordinary list regression',org,un,'ordinary-'||suffix,now(),now()+interval '1 day') RETURNING id INTO oc;
 PERFORM public.create_user_for_test('ordinary_reader','ordinary-reader@example.invalid');
 actor:=public.get_user_id('ordinary_reader');
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,actor,true);
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data,price,currency_code)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered','{}',100,'CZK');
 PERFORM pg_temp.adopt_public_link_fixtures();
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 bundle:=public.get_orders_tab_data('ordinary-'||suffix);
 PERFORM assert_eq(jsonb_array_length(bundle->'orders'),1,'ordinary list still returns the order');
 PERFORM assert_eq(bundle#>>'{orders,0,isActive}','true','ordinary order remains active');
 PERFORM assert_eq(bundle#>'{orders,0,allowedActions}','["view","note","edit","cancel","paid"]'::jsonb,'ordinary order keeps exactly its existing actions');
 bundle:=public.get_orders('ordinary-'||suffix,NULL,'{"include_orders_history":true,"include_full_order_data":true}');
 PERFORM assert_eq((bundle->>'code')::int,200,'history skips the same unnecessary aggregation');
 RESET ROLE;
END $$;
