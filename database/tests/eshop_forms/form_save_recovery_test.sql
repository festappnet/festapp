BEGIN;
DO $$
DECLARE org bigint; un bigint; oc bigint; f bigint; actor uuid:=gen_random_uuid();
 cmd uuid:=gen_random_uuid(); applied uuid:=gen_random_uuid(); result jsonb; input jsonb; saved jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Recovery test') RETURNING id INTO org;
 INSERT INTO public.units(organization,title) VALUES(org,'Unit') RETURNING id INTO un;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,un,'Recovery',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(actor);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view)
 VALUES(oc,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 result:=public.create_form_internal_v1(oc,NULL,'Original'); f:=(result->>'id')::bigint;
 input:=jsonb_build_object('id',f,'occasion',oc,'title','Old uncertain edit');
 -- No receipt means the original transaction never committed. Recovery must
 -- seal the UUID without applying its old document, including delayed replay.
 result:=public.recover_form_save_client_sync_v1(input,cmd);
 PERFORM assert_eq(result->>'status','rejected','uncommitted save is sealed');
 PERFORM assert_eq(result#>>'{data,message}','FORM_SAVE_NOT_APPLIED','explicit outcome');
 result:=public.update_form_client_sync_v1(input,cmd);
 PERFORM assert_eq(result->>'status','rejected','late original request cannot apply');
 PERFORM assert_eq((SELECT title FROM public.forms WHERE id=f),'Original','recovery preserves form');
 -- An actual completed save is returned exactly, without a second version bump.
 saved:=public.update_form_client_sync_v1(input,applied);
 result:=public.recover_form_save_client_sync_v1(input,applied);
 PERFORM assert_eq(result,saved,'lost successful acknowledgement is recovered');
 BEGIN
   PERFORM public.recover_form_save_client_sync_v1(input||jsonb_build_object('title','Different'),applied);
   RAISE EXCEPTION 'changed bytes were accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN
   PERFORM public.recover_form_save_client_sync_v1(input,applied);
   RAISE EXCEPTION 'foreign actor was accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM assert_true(NOT has_function_privilege('anon','public.recover_form_save_client_sync_v1(jsonb,uuid)','EXECUTE'),'anonymous recovery denied');
END;
$$;
ROLLBACK;
