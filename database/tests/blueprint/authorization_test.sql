-- test-setup: database/tests/blueprint/fixtures.sql

DO $$
DECLARE f jsonb; r jsonb; command uuid:=gen_random_uuid(); request jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal();request:=f->'request';
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 UPDATE public.occasion_users SET is_editor=false,is_manager=false,is_editor_order=true WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.update_blueprint_client_sync_v1(request,command);RAISE EXCEPTION 'order-only geometry save accepted';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM public.assert_eq(SQLERRM,'blueprint editor required','order-only geometry write denied'); END;
 RESET ROLE;
 BEGIN PERFORM public.save_blueprint_layout_internal_v1(request);RAISE EXCEPTION 'order-only internal geometry save accepted';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM public.assert_eq(SQLERRM,'blueprint editor required','internal owner enforces same geometry permission'); END;
 PERFORM public.assert_eq((SELECT layout_revision::int FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint),0,'forbidden geometry leaves revision');
 PERFORM public.assert_eq((SELECT count(*)::int FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint),0,'forbidden geometry leaves bindings');
 PERFORM public.assert_eq((SELECT count(*)::int FROM public.client_mutation_receipts WHERE command_id=command),0,'forbidden geometry creates no receipt');
 UPDATE public.occasion_users SET is_editor=true,is_editor_order=false WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 r:=public.update_blueprint_client_sync_v1(request,command);
 RESET ROLE;
 PERFORM public.assert_eq(r->>'status','applied','geometry editor succeeds independently of order permission');
 PERFORM public.assert_eq((r#>>'{data,layout_revision}')::int,1,'editor save accepted revision');
 UPDATE public.occasion_users SET is_editor=false,is_manager=true WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 request:=jsonb_set(request,'{expected_layout_revision}','1');request:=jsonb_set(request,'{seatChanges}','[]');
 SET LOCAL ROLE authenticated;
 r:=public.update_blueprint_client_sync_v1(request,gen_random_uuid());
 RESET ROLE;
 PERFORM public.assert_eq(r->>'status','applied','occasion manager can edit geometry');
 PERFORM public.assert_eq((r#>>'{data,layout_revision}')::int,2,'manager save accepted revision');
END $$;
