-- test-setup: database/tests/blueprint/fixtures.sql
DO $$
DECLARE f jsonb; r jsonb; form_id bigint; bp bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 form_id:=(f->>'form')::bigint;bp:=(f->>'blueprint')::bigint;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true}]' WHERE id=(f->>'occasion')::bigint;
 UPDATE public.forms SET blueprint=NULL,is_open=false WHERE id=form_id;
 INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden,"order")
 SELECT form_id,'spot',true,true,false,-1 WHERE NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=form_id AND type='spot');
 SET LOCAL ROLE authenticated;
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 RESET ROLE;
 PERFORM public.assert_eq(r->>'status','applied','saved plan accepted');
 PERFORM public.assert_eq((SELECT blueprint FROM public.forms WHERE id=form_id),bp,'saving the plan automatically connects the enabled seat selector');
 PERFORM public.assert_false((SELECT is_open FROM public.forms WHERE id=form_id),'connecting a plan preserves the closed form');
END $$;

DO $$
DECLARE f jsonb; r jsonb; source_id bigint; occ bigint; bp bigint; seat_type bigint; spot_types bigint; products bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();source_id:=(f->>'form')::bigint;occ:=(f->>'occasion')::bigint;bp:=(f->>'blueprint')::bigint;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true}]' WHERE id=occ;
 UPDATE public.forms SET blueprint=NULL,is_open=false WHERE id=source_id;
 INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden,"order") VALUES(source_id,'spot',true,true,false,-1);
 SET LOCAL ROLE authenticated;
 r:=public.update_form_client_sync_v1(jsonb_build_object('id',source_id,'occasion',occ),gen_random_uuid());
 RESET ROLE;
 PERFORM public.assert_eq(r->>'status','applied','ordinary form save connects the existing plan');
 PERFORM public.assert_eq((SELECT blueprint FROM public.forms WHERE id=source_id),bp,'form save and plan save share the same binding');
 -- A closed form remains previewable to its author and closed to visitors.
 PERFORM public.assert_false((SELECT is_open FROM public.forms WHERE id=source_id),'saving does not open sales');
 UPDATE public.form_fields SET is_hidden=true WHERE form=source_id AND type='spot';
 SET LOCAL ROLE authenticated;
 r:=public.update_form_client_sync_v1(jsonb_build_object('id',source_id,'occasion',occ),gen_random_uuid());
 RESET ROLE;
 PERFORM public.assert_eq(r->>'status','applied','disabling an unused selector is a normal form save');
 PERFORM public.assert_true((SELECT blueprint IS NULL FROM public.forms WHERE id=source_id),'disabled seat selector uses ordinary product choices');
 -- A newly created form after the plan uses the same automatic association.
 seat_type:=(SELECT DISTINCT p.product_type FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
   JOIN eshop.products p ON p.id=s.product WHERE sb.blueprint=bp);
 PERFORM public.assert_not_null(seat_type,'fixture plan seats are bound to one admission group');
 spot_types:=(SELECT count(*) FROM eshop.product_types WHERE occasion=occ AND type='spot');
 products:=(SELECT count(*) FROM eshop.products WHERE occasion=occ);
 r:=public.insert_form_for_occasion_internal_v1(occ,NULL,'Další registrace');
 PERFORM public.assert_eq((r->>'blueprint')::bigint,bp,'new forms connect the saved plan');
 PERFORM public.assert_false((r->>'is_open')::boolean,'new form sales stay closed');
 -- #960: the plan's seat group is shared on purpose; no unseated starter offer beside the plan.
 PERFORM public.assert_eq((SELECT product_type FROM public.form_fields WHERE form=(r->>'id')::bigint AND type='product_type' AND is_ticket_field),
   seat_type,'new seated form binds the group of the plan seat products');
 PERFORM public.assert_eq((SELECT count(*) FROM eshop.product_types WHERE occasion=occ AND type='spot'),spot_types,'no new primary group beside the plan');
 PERFORM public.assert_eq((SELECT count(*) FROM eshop.products WHERE occasion=occ),products,'no unseated starter variant is created');
 PERFORM public.assert_false(EXISTS(SELECT 1 FROM eshop.products p WHERE p.occasion=occ AND p.product_type=seat_type
   AND NOT EXISTS(SELECT 1 FROM eshop.spots s WHERE s.product=p.id AND s.blueprint=bp)),'every offered admission variant is a plan seat product');
END $$;

-- #960: the plan group is chosen from actual seat bindings, majority first, lowest ID on ties.
DO $$
DECLARE f jsonb; r jsonb; occ bigint; bp bigint; seats_type bigint; other_type bigint; other_product bigint;
 stray_type bigint; stray_product bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();occ:=(f->>'occasion')::bigint;bp:=(f->>'blueprint')::bigint;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 PERFORM public.assert_eq(public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid())->>'status','applied','plan saved');
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true}]' WHERE id=occ;
 seats_type:=(SELECT product_type FROM eshop.products WHERE id=(f->>'product')::bigint);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Balcony','spot') RETURNING id INTO other_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,other_type,'Balcony',200,'CZK') RETURNING id INTO other_product;
 -- Unbound spot rows of the plan never vote, however many there are.
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Stray','spot') RETURNING id INTO stray_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,stray_type,'Stray',50,'CZK') RETURNING id INTO stray_product;
 INSERT INTO eshop.spots(occasion,blueprint,title,product) SELECT occ,bp,'Stray '||i,stray_product FROM generate_series(1,10) i;
 UPDATE eshop.spots SET product=other_product WHERE id IN(
   SELECT spot FROM eshop.blueprint_seat_bindings WHERE blueprint=bp ORDER BY spot LIMIT 3);
 r:=public.insert_form_for_occasion_internal_v1(occ,NULL,'Majority');
 PERFORM public.assert_eq((SELECT product_type FROM public.form_fields WHERE form=(r->>'id')::bigint AND type='product_type' AND is_ticket_field),
   other_type,'the group of most bound seats wins over an older group');
 UPDATE eshop.spots SET product=(f->>'product')::bigint WHERE id=(
   SELECT spot FROM eshop.blueprint_seat_bindings WHERE blueprint=bp ORDER BY spot LIMIT 1);
 r:=public.insert_form_for_occasion_internal_v1(occ,NULL,'Tie');
 PERFORM public.assert_eq((SELECT product_type FROM public.form_fields WHERE form=(r->>'id')::bigint AND type='product_type' AND is_ticket_field),
   seats_type,'a tie picks the lowest group ID');
 PERFORM public.assert_false(EXISTS(SELECT 1 FROM eshop.products WHERE occasion=occ AND title='Variant 1'),'no unseated starter on a bound plan');
END $$;

DO $$
DECLARE f jsonb; form_id bigint; bp bigint; second_bp bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();form_id:=(f->>'form')::bigint;bp:=(f->>'blueprint')::bigint;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 PERFORM public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 UPDATE public.occasions SET features='[{"code":"blueprint","is_enabled":true}]' WHERE id=(f->>'occasion')::bigint;
 INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden) VALUES(form_id,'spot',true,true,false);
 UPDATE public.forms SET blueprint=NULL WHERE id=form_id;
 INSERT INTO eshop.blueprints(occasion,organization,layout) SELECT occasion,organization,layout FROM eshop.blueprints WHERE id=bp RETURNING id INTO second_bp;
 BEGIN
   PERFORM public.sync_form_blueprint_internal(form_id);
   RAISE EXCEPTION 'ambiguous plan silently selected';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'BLUEPRINT_SELECTION_REQUIRED' THEN RAISE; END IF;
 END;
 -- An explicit saved association is stable even if another plan exists.
 UPDATE public.forms SET blueprint=bp WHERE id=form_id;
 PERFORM public.sync_form_blueprint_internal(form_id);
 PERFORM public.assert_eq((SELECT blueprint FROM public.forms WHERE id=form_id),bp,'another plan never steals an explicit form binding');
END $$;
