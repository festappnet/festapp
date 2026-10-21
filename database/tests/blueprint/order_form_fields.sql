-- Run in a rollback transaction on the owned disposable QA database.
DO $$
DECLARE f jsonb:=current_setting('festapp.qa_fixture')::jsonb; target bigint; fid bigint; customer bigint; attendee bigint; analysis jsonb; prepared jsonb; wrong jsonb; form_key text;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned local database required'; END IF;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 SELECT id INTO target FROM eshop.spots s WHERE blueprint=(f->>'blueprint')::bigint AND order_product_ticket IS NULL AND cardinality(public.blueprint_selection_unit_spots_internal(s.id))=1 ORDER BY id LIMIT 1;
 SELECT id,key::text INTO fid,form_key FROM public.forms WHERE occasion=(f->>'occasion')::bigint AND is_open=true ORDER BY type='ticket' DESC,id DESC LIMIT 1;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order") VALUES(fid,'name','Customer name',true,false,false,90) RETURNING id INTO customer;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order") VALUES(fid,'text','Attendee name',true,false,true,91) RETURNING id INTO attendee;
 analysis:=public.analyze_new_order_spots(ARRAY[target]);
 IF analysis->'order_form'->>'key' IS DISTINCT FROM form_key OR NOT (analysis->'order_form'->'fields' @> jsonb_build_array(jsonb_build_object('id',customer),jsonb_build_object('id',attendee))) THEN RAISE EXCEPTION 'active required fields missing'; END IF;
 prepared:=public.confirm_blueprint_order_change_internal_v1(ARRAY[target],jsonb_build_object('email','qa@example.test','form_key',form_key,'fields',jsonb_build_array(jsonb_build_object(customer::text,'Customer')),'ticket_fields',jsonb_build_object(target::text,jsonb_build_array(jsonb_build_object('text','Attendee',attendee::text,'Attendee'))),'form',gen_random_uuid(),'ticket','[]'::jsonb));
 IF prepared->>'success'<>'true' OR prepared->'orderDetails'->>'form' IS DISTINCT FROM form_key OR prepared->'orderDetails'->'ticket'->0->'fields'->0->>'text'<>'Attendee' THEN RAISE EXCEPTION 'required data payload missing: %',prepared; END IF;
 IF public.extract_ticket_answers_internal(fid,prepared->'orderDetails'->'ticket'->0)->'fields' IS DISTINCT FROM jsonb_build_array(jsonb_build_object(attendee::text,'Attendee')) THEN RAISE EXCEPTION 'attendee answer did not reach canonical persistence shape'; END IF;
 wrong:=public.confirm_blueprint_order_change_internal_v1(ARRAY[target],jsonb_build_object('email','qa@example.test','form_key',gen_random_uuid()));
 IF wrong->>'success'<>'false' THEN RAISE EXCEPTION 'changed active form not rejected'; END IF;
END $$;
