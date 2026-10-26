BEGIN;
DO $$
DECLARE fx jsonb; other_fx jsonb; oc bigint; uid uuid; editor uuid; role_name text; cfg jsonb; current_rev bigint; response jsonb; first_session jsonb; second_session jsonb;
BEGIN
 fx:=public.scanner_test_fixture();other_fx:=public.scanner_test_fixture();oc:=(fx->>'occasion')::bigint;
 UPDATE public.occasions SET organization=(SELECT organization FROM public.occasions WHERE id=oc),unit=(SELECT unit FROM public.occasions WHERE id=oc) WHERE id=(other_fx->>'occasion')::bigint;
 PERFORM assert_false(has_function_privilege('anon','public.update_scanner_settings(bigint,bigint,jsonb)','EXECUTE'),'scan code does not grant configuration RPC');
 PERFORM assert_false(has_function_privilege('authenticated','public.scanner_can_manage_settings_internal(bigint)','EXECUTE'),'permission helper is private');
 FOREACH role_name IN ARRAY ARRAY['editor','reservation_editor','viewer','foreign_editor'] LOOP
  uid:=gen_random_uuid();
  INSERT INTO auth.users(id,email) VALUES(uid,uid||'@scanner.invalid');
  INSERT INTO public.user_info(id,name,organization) SELECT uid,role_name,organization FROM public.occasions WHERE id=oc;
  INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order,is_editor_view)
  VALUES(CASE WHEN role_name='foreign_editor' THEN (other_fx->>'occasion')::bigint ELSE oc END,uid,role_name IN('editor','foreign_editor'),role_name='reservation_editor',role_name='viewer');
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
  IF role_name IN('editor','reservation_editor') THEN
   response:=public.get_scanner_settings(oc);PERFORM assert_eq(response#>>'{data,occasion_link}',(SELECT link FROM public.occasions WHERE id=oc),'navigation belongs to authorized event');cfg:=response#>'{data,config}';current_rev:=(response#>>'{data,revision}')::bigint;
   response:=public.update_scanner_settings(oc,current_rev,cfg);PERFORM assert_eq(response->>'code','200',role_name||' can edit');
   response:=public.open_scanner_session(NULL,oc);PERFORM assert_true((response#>>'{data,capabilities,settings}')::boolean,role_name||' settings capability');
   IF role_name='editor' THEN editor:=uid; END IF;
  ELSE
   BEGIN PERFORM public.get_scanner_settings(oc);PERFORM assert_fail(role_name||' cannot read settings');EXCEPTION WHEN insufficient_privilege THEN NULL;END;
   BEGIN PERFORM public.update_scanner_settings(oc,1,'{}');PERFORM assert_fail(role_name||' cannot write settings');EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',editor,'role','authenticated')::text,true);
 first_session:=public.open_scanner_session(NULL,oc);second_session:=public.open_scanner_session(NULL,oc);
 response:=public.get_scanner_settings(oc);cfg:=jsonb_set(response#>'{data,config}','{sensitive,price}','false');
 response:=public.update_scanner_settings(oc,(response#>>'{data,revision}')::bigint,cfg);
 PERFORM assert_eq((public.get_scanner_settings(oc))#>>'{data,config,sensitive,price}','false','one shared event configuration');
 BEGIN PERFORM public.scanner_session_internal((first_session#>>'{data,session_id}')::uuid,first_session#>>'{data,token}');PERFORM assert_fail('first device must refresh changed policy');EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
 BEGIN PERFORM public.scanner_session_internal((second_session#>>'{data,session_id}')::uuid,second_session#>>'{data,token}');PERFORM assert_fail('second device must refresh same changed policy');EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL;END;
 response:=public.open_scanner_session(NULL,oc);PERFORM assert_eq(response#>>'{data,settings,sensitive,price}','false','reopened scanner receives global configuration');
 UPDATE public.occasion_users SET is_editor=false WHERE occasion=oc AND "user"=editor;
 BEGIN PERFORM public.scanner_session_internal((response#>>'{data,session_id}')::uuid,response#>>'{data,token}');PERFORM assert_fail('revoked editor is fenced');EXCEPTION WHEN SQLSTATE 'PT403' THEN NULL;END;
END $$;
ROLLBACK;
