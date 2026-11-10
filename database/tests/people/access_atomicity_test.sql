DO $$
DECLARE actor uuid; org bigint; un bigint; request jsonb; preview jsonb; prep uuid; result jsonb; cmd uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title) VALUES('Access atomicity') RETURNING id INTO org;
 actor:=public.create_user_in_organization_with_data_pure(org,'atomic-manager@example.invalid','disposable-password','{}');
 INSERT INTO public.units(title,organization) VALUES('Access atomicity',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,actor,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true); PERFORM set_config('request.jwt.claim.role','authenticated',true);
 request:=jsonb_build_object('scope',jsonb_build_object('type','unit','id',un),'operation','save_member_and_invite',
  'communication','notify_existing_access','email','rollback@example.invalid','changes',
  jsonb_build_object('kind','editor','is_manager',false,'is_editor',true,'is_editor_view',true,'data',jsonb_build_object('email','rollback@example.invalid','name','Jana')));
 preview:=public.preview_member_access(cmd,request);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 prep:=public.stage_member_access_email(actor,cmd,preview->>'intentHash',preview->>'previewHash',
  '{"p_sealed":{"fixture":"sealed"},"p_content_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 -- Force the real queue INSERT to fail after the account/membership writer ran.
 ALTER TABLE public.email_messages ADD CONSTRAINT access_atomicity_fixture CHECK(recipient<>'rollback@example.invalid') NOT VALID;
 BEGIN
  PERFORM public.manage_member_access(cmd,request,prep);
  RAISE EXCEPTION 'queue failure was swallowed';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
 ASSERT NOT EXISTS(SELECT 1 FROM public.user_info WHERE organization=org AND email_readonly='rollback@example.invalid'),'enqueue failure must roll back account creation';
 ASSERT NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=cmd),'enqueue failure must roll back receipt';
 ALTER TABLE public.email_messages DROP CONSTRAINT access_atomicity_fixture;
 result:=public.manage_member_access(cmd,request,prep);
 ASSERT result->>'code'='200' AND result#>>'{data,communication,messageId}' IS NOT NULL,'same intent must recover atomically';
 ASSERT EXISTS(SELECT 1 FROM public.unit_users WHERE unit=un AND "user"=(result#>>'{data,userId}')::uuid AND is_editor),'intended role must commit with queue';
 ASSERT public.manage_member_access(cmd,jsonb_set(request,'{email}','" ROLLBACK@example.invalid "'),NULL)=result,'normalized request identity must replay';
 cmd:=gen_random_uuid();
 request:=jsonb_build_object('scope',jsonb_build_object('type','unit','id',un),'operation','save_member','communication','none',
  'userId',result#>'{data,userId}','expectedVersion',999,'changes',jsonb_build_object('kind','roles','is_editor',false));
 result:=public.manage_member_access(cmd,request,NULL);
 ASSERT result->>'status'='conflict' AND result#>>'{data,reasonCode}'='version_conflict','version conflict must stay typed';
 ASSERT result#>>'{mutation,commandId}'=cmd::text AND result#>>'{mutation,receiptId}'=cmd::text,'conflict must carry the outer immutable receipt identity';
 ASSERT public.manage_member_access(cmd,request,NULL)=result,'typed conflict must replay the same outer receipt';
 ASSERT NOT has_function_privilege('authenticated','public.stage_member_access_email(uuid,uuid,text,text,jsonb,text,text)','EXECUTE'),'client must not stage trusted email content';
 ASSERT NOT has_table_privilege('authenticated','public.access_email_preparations','SELECT'),'client must not read prepared credentials';
 ASSERT NOT has_function_privilege('service_role','public.manage_member_access(uuid,jsonb,uuid)','EXECUTE'),'bare service role must not bypass authenticated auth policy';
END $$;
