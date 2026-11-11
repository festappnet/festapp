CREATE OR REPLACE FUNCTION pg_temp.execute_access(cmd uuid,request jsonb,token text DEFAULT NULL,credential text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; prep uuid; actor uuid:=auth.uid(); result jsonb;
BEGIN
 p:=public.preview_member_access(cmd,request);
 IF p ? 'replay' THEN RETURN p->'replay'; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 prep:=public.stage_member_access_email(actor,cmd,p->>'intentHash',p->>'previewHash',
  jsonb_build_object('p_sealed',jsonb_build_object('sealed','fixture'),'p_content_hash',repeat('a',64)),
  CASE WHEN token IS NULL THEN NULL ELSE encode(extensions.digest(token,'sha256'),'hex') END,credential);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 result:=public.manage_member_access(cmd,request,prep);
 RETURN result;
END $$;
DO $$
DECLARE actor uuid; recipient uuid; org bigint; un bigint; oc bigint; scope text; target_id bigint; token text; cmd uuid;
 request jsonb; result jsonb; inv uuid; initial_password text; accepted jsonb; merged uuid; successor uuid; other_org bigint;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Access invitation contracts','{"DEFAULT_URL":"https://example.invalid","APP_NAME":"Festapp"}') RETURNING id INTO org;
 actor:=public.create_user_in_organization_with_data_pure(org,'actor@example.invalid','original-password','{}');
 recipient:=public.create_user_in_organization_with_data_pure(org,'member@example.invalid','original-password','{}');
 INSERT INTO public.units(title,organization) VALUES('Access contracts',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,actor,true);
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES('Access contracts',gen_random_uuid()::text,org,un,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_manager) VALUES(oc,actor,true);
 SELECT encrypted_password INTO initial_password FROM auth.users WHERE id=recipient;
 FOREACH scope IN ARRAY ARRAY['unit','occasion'] LOOP
  target_id:=CASE WHEN scope='unit' THEN un ELSE oc END; token:=encode(extensions.gen_random_bytes(32),'hex'); cmd:=gen_random_uuid();
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  request:=jsonb_build_object('scope',jsonb_build_object('type',scope,'id',target_id),'operation','send_invitation',
   'communication','invite_to_accept','email',' MEMBER@example.invalid ','roles',jsonb_build_object('is_editor',true,'is_editor_view',true));
  result:=pg_temp.execute_access(cmd,request,token);
  ASSERT result#>>'{data,communication,messageId}' IS NOT NULL,format('required email must commit: %s',result);
  ASSERT pg_temp.execute_access(cmd,request,token)=result,'retry must replay receipt without preparing';
  inv:=(result#>>'{data,access,invitationId}')::uuid;
  ASSERT NOT EXISTS(SELECT 1 FROM public.unit_users WHERE unit=un AND "user"=recipient) OR scope='occasion','offer must not grant unit membership';
  ASSERT public.get_access_invitation(token)->>'email'='member@example.invalid','public URL resolves both scopes';
  IF scope='occasion' THEN ASSERT public.get_occasion_team_invitation(token)->>'email'='member@example.invalid','old event link adapter resolves';
  ELSE ASSERT public.get_occasion_team_invitation(token) IS NULL,'old clients must upgrade for the new unit scope'; END IF;
  BEGIN
   PERFORM public.accept_access_invitation(token);
   RAISE EXCEPTION 'wrong identity accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub',recipient::text,true);
  IF scope='occasion' THEN accepted:=public.accept_occasion_team_invitation(token);
  ELSE accepted:=public.accept_access_invitation(token); END IF;
  ASSERT accepted->>'accepted'='true','token must accept';
  ASSERT public.accept_access_invitation(token)->>'accepted'='true','accept retry must be safe';
  ASSERT (SELECT encrypted_password FROM auth.users WHERE auth.users.id=recipient)=initial_password,'team invitation must not change password';
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  ASSERT public.revoke_access_invitation(inv)->>'accepted'='true','revoking accepted offer must not delete access';
 END LOOP;
 -- Notice sends do not replay role/profile snapshots, and a service actor cannot forge content.
 request:=jsonb_build_object('scope',jsonb_build_object('type','unit','id',un),'operation','send_invitation',
  'communication','notify_existing_access','userId',recipient);
 result:=pg_temp.execute_access(gen_random_uuid(),request);
 ASSERT result#>>'{data,communication,messageId}' IS NOT NULL,'notice must queue';
 BEGIN
  PERFORM public.preview_member_access(gen_random_uuid(),jsonb_set(request,'{communication}','"participant_credentials"'));
  RAISE EXCEPTION 'unit credential reset accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 -- Pending offer is invalidated atomically by the old deletion adapter.
 token:=encode(extensions.gen_random_bytes(32),'hex');
 request:=jsonb_build_object('scope',jsonb_build_object('type','occasion','id',oc),'operation','send_invitation',
  'communication','invite_to_accept','email','member@example.invalid','roles',jsonb_build_object('is_editor',true));
 result:=pg_temp.execute_access(gen_random_uuid(),request,token);
 PERFORM public.delete_unit_user(recipient,un);
 ASSERT public.get_access_invitation(token)->>'reasonCode'='invitation_revoked','old deletion must invalidate pending grants';
 PERFORM set_config('request.jwt.claim.sub',recipient::text,true);
 BEGIN
  PERFORM public.accept_access_invitation(token);
  RAISE EXCEPTION 'revoked invite accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 -- An explicitly selected merged account retains its identity across tenant contexts.
 INSERT INTO public.organizations(title) VALUES('Merged identity home') RETURNING id INTO other_org;
 merged:=public.create_user_in_organization_with_data_pure(other_org,'merged@example.invalid','unchanged-password','{}');
 INSERT INTO public.occasion_users(occasion,"user") VALUES(oc,merged);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 token:=encode(extensions.gen_random_bytes(32),'hex');
 request:=jsonb_build_object('scope',jsonb_build_object('type','occasion','id',oc),'operation','send_invitation',
  'communication','invite_to_accept','userId',merged,'roles',jsonb_build_object('is_editor',true));
 result:=pg_temp.execute_access(gen_random_uuid(),request,token);
 ASSERT (SELECT recipient_user FROM public.access_invitations WHERE id=(result#>>'{data,access,invitationId}')::uuid)=merged,'offer must bind selected account';
 PERFORM set_config('request.jwt.claim.sub',merged::text,true);
 ASSERT public.accept_access_invitation(token)->>'accepted'='true','merged member accepts as the selected identity';
 ASSERT NOT EXISTS(SELECT 1 FROM public.user_info WHERE organization=org AND email_readonly='merged@example.invalid'),'accept must not create a second tenant account';
 -- Deleting a bound identity cannot retarget its pending token to a new account.
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 token:=encode(extensions.gen_random_bytes(32),'hex');
 result:=pg_temp.execute_access(gen_random_uuid(),request,token);
 DELETE FROM public.occasion_users WHERE occasion=oc AND "user"=merged;
 DELETE FROM public.user_info WHERE id=merged;
 DELETE FROM auth.users WHERE id=merged;
 successor:=public.create_user_in_organization_with_data_pure(other_org,'merged@example.invalid','successor-password','{}');
 PERFORM set_config('request.jwt.claim.sub',successor::text,true);
 BEGIN
  PERFORM public.accept_access_invitation(token);
  RAISE EXCEPTION 'deleted identity retargeted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 ASSERT NOT EXISTS(SELECT 1 FROM public.access_email_preparations WHERE access_email_preparations.actor=(SELECT ui.id FROM public.user_info ui WHERE ui.organization=org AND ui.email_readonly='actor@example.invalid')),'successful commands must consume preparations';
END $$;
