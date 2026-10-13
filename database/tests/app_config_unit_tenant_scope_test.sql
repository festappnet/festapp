BEGIN;
DO $$
DECLARE
  actor uuid; org bigint; other_org bigint; own_unit bigint; foreign_unit bigint;
  response jsonb;
BEGIN
  PERFORM public.create_user_for_test('unit_scope_actor', 'unit_scope_actor@test.local');
  actor := public.get_user_id('unit_scope_actor');
  INSERT INTO public.organizations(title) VALUES ('Unit scope tenant') RETURNING id INTO org;
  INSERT INTO public.organizations(title) VALUES ('Other unit scope tenant') RETURNING id INTO other_org;
  UPDATE public.user_info SET organization=org WHERE id=actor;
  INSERT INTO public.units(title,organization) VALUES ('Own unit',org) RETURNING id INTO own_unit;
  INSERT INTO public.units(title,organization) VALUES ('Foreign unit',other_org) RETURNING id INTO foreign_unit;
  INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view)
    VALUES (own_unit,actor,true,true,true),(foreign_unit,actor,true,true,true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);

  response := public.get_app_config_v218(jsonb_build_object('platform',jsonb_build_object('platform','web'),'organization',org,'unit_id',own_unit));
  PERFORM public.assert_eq((response->>'code')::integer,200,'own unit remains accessible');
  PERFORM public.assert_eq(jsonb_array_length(response#>'{user_info,units}'),1,'only current tenant units listed');
  PERFORM public.assert_eq((response#>>'{user_info,units,0,id}')::bigint,own_unit,'own tenant unit listed');
  response := public.get_app_config_v219(jsonb_build_object('platform',jsonb_build_object('platform','web'),'organization',org,'unit_id',foreign_unit));
  PERFORM public.assert_eq((response->>'code')::integer,404,'foreign unit direct link rejected');
  response := public.get_app_config_v219(jsonb_build_object('platform',jsonb_build_object('platform','web'),'organization',other_org,'unit_id',foreign_unit));
  PERFORM public.assert_eq((response->>'code')::integer,200,'foreign unit remains accessible on its own tenant');
  PERFORM public.assert_eq(jsonb_array_length(response#>'{user_info,units}'),1,'other tenant also scoped');
  PERFORM public.assert_eq((response#>>'{user_info,units,0,id}')::bigint,foreign_unit,'correct unit on other tenant');
  response := public.get_app_config_v218(jsonb_build_object('platform',jsonb_build_object('platform','web'),'organization',org,'unit_id',-982));
  PERFORM public.assert_eq((response->>'code')::integer,404,'missing unit rejected');
  PERFORM public.assert_true(EXISTS(SELECT 1 FROM public.unit_users WHERE unit=foreign_unit AND "user"=actor AND is_manager),'foreign rights preserved');
  PERFORM public.assert_eq((SELECT organization FROM public.units WHERE id=foreign_unit),other_org,'unit ownership preserved');
END;
$$;
ROLLBACK;
