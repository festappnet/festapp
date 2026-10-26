BEGIN;
DO $$
DECLARE org bigint; un bigint; oc bigint; fid bigint; seat_field bigint; name_field bigint;
 payload jsonb; people jsonb; err jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Required seat regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Required seat regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time)
 VALUES('Required seat regression',un,org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,link) VALUES(oc,gen_random_uuid()::text) RETURNING id INTO fid;
 INSERT INTO public.form_fields(form,type,is_required,is_hidden,is_ticket_field)
 VALUES(fid,'spot',true,false,true) RETURNING id INTO seat_field;
 INSERT INTO public.form_fields(form,type,is_required,is_hidden,is_ticket_field)
 VALUES(fid,'name',true,false,true) RETURNING id INTO name_field;
 payload:='{"fields":[]}'::jsonb;
 people:=jsonb_build_array(jsonb_build_object('spot',123,'fields',jsonb_build_array(jsonb_build_object(name_field::text,'Test'))));
 PERFORM public.validate_waitlist_answers_internal(fid,payload,public.normalize_form_ticket_answers_internal(fid,people),false);
 BEGIN
  PERFORM public.validate_waitlist_answers_internal(fid,payload,jsonb_build_array((people->0)-'spot'),false);
  RAISE EXCEPTION 'Missing seat accepted';
 EXCEPTION WHEN OTHERS THEN
  IF left(SQLERRM,1)<>'{' THEN RAISE; END IF;
  err:=SQLERRM::jsonb;
  IF err->>'errorCode'<>'REQUIRED_FIELD_MISSING' OR (err->>'fieldId')::bigint<>seat_field THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM public.validate_waitlist_answers_internal(fid,payload,'[{"spot":123,"fields":[]}]',false);
  RAISE EXCEPTION 'Missing personal answer accepted';
 EXCEPTION WHEN OTHERS THEN
  IF left(SQLERRM,1)<>'{' THEN RAISE; END IF;
  err:=SQLERRM::jsonb;
  IF err->>'errorCode'<>'REQUIRED_FIELD_MISSING' OR (err->>'fieldId')::bigint<>name_field THEN RAISE; END IF;
 END;
 PERFORM public.validate_waitlist_answers_internal(fid,payload,jsonb_build_array((people->0)-'spot'),true);
 RAISE NOTICE 'PASS: normalized selected seat, missing seat, missing personal answer, and waitlist';
END $$;
ROLLBACK;
