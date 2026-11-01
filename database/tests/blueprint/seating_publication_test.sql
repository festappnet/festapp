-- test-setup: database/tests/blueprint/fixtures.sql
-- test-setup: database/tests/blueprint/seating_fixture.sql
DO $$
DECLARE f jsonb; tr uuid; p jsonb; r jsonb; ids uuid[]; occ bigint; frm bigint;
BEGIN
 f:=public.seating_test_fixture_internal(2,0);tr:=(f->>'transition')::uuid;occ:=(f->>'occasion')::bigint;frm:=(f->>'form')::bigint;
 UPDATE public.forms SET is_open=false WHERE id=frm;
 SET LOCAL ROLE authenticated;
 p:=public.preview_ticket_seat_assignment(tr,f->'mappings')->'data';
 r:=public.set_ticket_seat_assignments(tr,f->'mappings',p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','publication fixture seated');
 p:=public.preview_seating_publication(tr)->'data';
 PERFORM public.assert_eq(jsonb_array_length(p->'blockers'),0,'covered cohort ready');
 ids:=ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(p->'transitionIds'));
 r:=public.publish_seating_transitions(tr,ids,p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','publication committed');
 RESET ROLE;
 PERFORM public.assert_true((SELECT blueprint=(f->>'blueprint')::bigint AND participant_capacity IS NULL AND NOT waitlist_enabled AND NOT is_open FROM public.forms WHERE id=frm),'exact mode switch preserves closed form');
 BEGIN PERFORM public.assert_published_admission_seating_internal(frm,(f->>'product')::bigint,NULL); RAISE EXCEPTION 'seatless bypass'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ADMISSION_SOURCE_REQUIRES_SEATING' THEN RAISE; END IF; END;
END $$;
DO $$
DECLARE f jsonb; tr uuid; p jsonb;
BEGIN
 f:=public.seating_test_fixture_internal();tr:=(f->>'transition')::uuid;
 SET LOCAL ROLE authenticated;
 p:=public.preview_seating_publication(tr)->'data';
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(p->'blockers') b WHERE b->>'reason'='WAITLIST_PENDING'),'only optional publication queue restriction');
 RESET ROLE;
END $$;
DO $$
DECLARE f jsonb; tr uuid; p jsonb; r jsonb; ids uuid[]; frm bigint; extra bigint; oid bigint; tid bigint;
BEGIN
 f:=public.seating_test_fixture_internal(0,0);tr:=(f->>'transition')::uuid;frm:=(f->>'form')::bigint;
 SET LOCAL ROLE authenticated;
 p:=public.preview_seating_publication(tr)->'data';
 ids:=ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(p->'transitionIds'));
 RESET ROLE;
 INSERT INTO public.forms(occasion,is_open) VALUES((f->>'occasion')::bigint,true) RETURNING id INTO extra;
 INSERT INTO public.form_fields(form,product_type,type,is_hidden) SELECT extra,product_type,'product_type',false FROM eshop.products WHERE id=(f->>'product')::bigint;
 SET LOCAL ROLE authenticated;
 r:=public.publish_seating_transitions(tr,ids,p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','conflict','new dependent source invalidates publication');
 p:=public.preview_seating_publication(tr)->'data';
 PERFORM public.assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(p->'blockers') b WHERE b->>'reason'='UNCOVERED_ADMISSION_SOURCE'),'uncovered source concrete blocker');
 RESET ROLE;
 r:=public.start_seating_configuration(extra,(f->>'blueprint')::bigint,gen_random_uuid());
 SET LOCAL ROLE authenticated;
 p:=public.preview_seating_publication(tr)->'data';ids:=ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(p->'transitionIds'));
 r:=public.publish_seating_transitions(tr,ids,p->>'fingerprint',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','empty coherent cohort publication');
 RESET ROLE;
 -- Actual old/direct/editor materializer rejects visible-field seatless input.
 oid:=public.allocate_ticket_order_identity_internal(frm);
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES((f->>'occasion')::bigint,'ordered','BYPASS-'||gen_random_uuid()) RETURNING id INTO tid;
 BEGIN
 PERFORM public.materialize_ticket_products_internal_v1(oid,frm,tid,jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',f->'product'))),NULL);
 RAISE EXCEPTION 'old direct caller admitted without seat';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ADMISSION_SOURCE_REQUIRES_SEATING' THEN RAISE; END IF; END;
 UPDATE public.forms SET blueprint=NULL,is_open=true WHERE id=extra;
 BEGIN PERFORM public.assert_form_seating_source_internal(extra); RAISE EXCEPTION 'reopened ordinary emitter'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ADMISSION_SOURCE_REQUIRES_SEATING' THEN RAISE; END IF; END;
END $$;

DO $$
DECLARE f jsonb; extra bigint; r jsonb;
BEGIN
 f:=public.seating_test_fixture_internal(1,0);
 INSERT INTO public.forms(occasion,title,type,is_open) VALUES((f->>'occasion')::bigint,'Independent ordinary source','ticket',true) RETURNING id INTO extra;
 SET LOCAL ROLE authenticated;
 r:=public.update_form_client_sync_v1(jsonb_build_object('id',extra,'occasion',f->'occasion','blueprint',f->'blueprint'),gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','rejected','another form cannot activate an organizer-managed target through generic save');
 PERFORM public.assert_eq(r#>>'{data,errorCode}','MODE_CHANGED','generic attach has typed mode-change rejection');
 RESET ROLE;
 PERFORM public.assert_true((SELECT blueprint IS NULL FROM public.forms WHERE id=extra),'failed generic attach leaves ordinary mode unchanged');
END $$;

DO $$
DECLARE f jsonb; tr uuid; p jsonb; r jsonb; ids uuid[]; fee_type bigint; fee bigint;
BEGIN
 f:=public.seating_test_fixture_internal(0,0);tr:=(f->>'transition')::uuid;
 p:=public.preview_seating_publication(tr)->'data';ids:=ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(p->'transitionIds'));
 r:=public.publish_seating_transitions(tr,ids,p->>'fingerprint',gen_random_uuid());
 INSERT INTO public.form_fields(form,type,is_hidden) VALUES((f->>'form')::bigint,'ticket',true);
 INSERT INTO eshop.product_types(occasion,title,type) VALUES((f->>'occasion')::bigint,'Application fee','other') RETURNING id INTO fee_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES((f->>'occasion')::bigint,fee_type,'Application fee',0,'CZK') RETURNING id INTO fee;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field,is_required,is_hidden) VALUES((f->>'form')::bigint,'product_type',fee_type,true,true,false);
 SET LOCAL ROLE authenticated;
 r:=public.create_ticket_order_client_sync_v1(jsonb_build_object('form',f->'formKey','email','combined-seating@example.invalid','ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',fee))))),gen_random_uuid(),gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','rejected','application-only fee selection cannot replace the published seat entitlement');
 PERFORM public.assert_eq(r#>>'{data,errorCode}','ADMISSION_SOURCE_REQUIRES_SEATING','active seat mode takes precedence over hidden ticket containers');
 RESET ROLE;
END $$;
