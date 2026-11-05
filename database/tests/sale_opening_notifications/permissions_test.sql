DO $$
DECLARE org bigint; uid bigint; occ bigint; other_occ bigint; actor uuid; row public.occasion_users; projection jsonb; bits integer; expected boolean;
BEGIN
 PERFORM create_user_for_test('sale_contact_matrix','sale-contact-matrix@example.invalid'); actor:=get_user_id('sale_contact_matrix');
 INSERT INTO public.organizations(title) VALUES('Matice oprávnění') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO uid;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Ples',gen_random_uuid()::text,org,uid,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Cizí akce',gen_random_uuid()::text,org,uid,now(),now()+interval '1 day') RETURNING id INTO other_occ;
 INSERT INTO public.occasion_users(occasion,"user") VALUES(occ,actor);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true); PERFORM set_config('request.jwt.claim.role','authenticated',true);
 FOR bits IN 0..7 LOOP
  UPDATE public.occasion_users SET is_editor=(bits&1)>0,is_manager=(bits&2)>0,is_approver=(bits&4)>0 WHERE occasion=occ AND "user"=actor RETURNING * INTO row;
  expected:=bits<>0;
  PERFORM assert_eq(public.can_read_sale_opening_subscribers(occ),expected,'Contact role matrix '||bits);
  projection:=public.get_context_capabilities_v1(occ,row,NULL::public.unit_users,false,false,false,false,true,true,false);
  PERFORM assert_eq((projection->>'forms.sale_opening_subscribers.read')::boolean,expected,'SQL capability uses the same typed contact rule '||bits);
  PERFORM assert_false(public.can_read_sale_opening_subscribers(other_occ),'Contact permission never crosses occasion');
 END LOOP;
 -- Form graphics/order-view access by itself cannot read contact PII.
 UPDATE public.occasion_users SET is_editor=false,is_manager=false,is_approver=false,is_editor_view=true,is_editor_order_view=true WHERE occasion=occ AND "user"=actor;
 PERFORM assert_false(public.can_read_sale_opening_subscribers(occ),'View-only authors cannot read subscriber contacts');
 INSERT INTO public.unit_users(unit,"user",is_editor) VALUES(uid,actor,true);
 PERFORM assert_true(public.can_author_forms(occ),'Unit editor can author form graphics');
 PERFORM assert_false(public.can_read_sale_opening_subscribers(occ),'Unit form authoring alone never grants contact PII');
END $$;
