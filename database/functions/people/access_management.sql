CREATE OR REPLACE FUNCTION public.normalize_member_access_request_internal_v1(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE k text;
BEGIN
 IF jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::text)>262144
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_request) x WHERE x NOT IN ('scope','operation','communication','userId','email','expectedVersion','changes','roles','sourceDraft','predecessor')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_intent'; END IF;
 FOREACH k IN ARRAY ARRAY['userId','email','expectedVersion','sourceDraft','predecessor'] LOOP
  IF p_request->k='null'::jsonb THEN p_request:=p_request-k; END IF;
 END LOOP;
 IF p_request ? 'email' THEN p_request:=jsonb_set(p_request,'{email}',to_jsonb(lower(btrim(p_request->>'email')))); END IF;
 IF p_request#>>'{changes,data,email}' IS NOT NULL THEN
  p_request:=jsonb_set(p_request,'{changes,data,email}',to_jsonb(lower(btrim(p_request#>>'{changes,data,email}')))); END IF;
 IF p_request#>>'{changes,email}' IS NOT NULL THEN
  p_request:=jsonb_set(p_request,'{changes,email}',to_jsonb(lower(btrim(p_request#>>'{changes,email}')))); END IF;
 RETURN p_request||jsonb_build_object('communication',coalesce(p_request->>'communication','none'));
END $$;
REVOKE ALL ON FUNCTION public.normalize_member_access_request_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.member_access_preview_internal_v1(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE scope text:=p_request#>>'{scope,type}'; target_id bigint:=(p_request#>>'{scope,id}')::bigint;
 un bigint; org bigint; oc bigint; usr uuid:=(p_request->>'userId')::uuid; mail text; member jsonb; ver bigint:=0;
 op text:=p_request->>'operation'; communication text:=coalesce(p_request->>'communication','none');
 title text; destination text; conf jsonb; draft public.occasion_setup_drafts; existing_invitation public.access_invitations; roles jsonb:=coalesce(p_request->'roles','{}');
BEGIN
 IF NOT (public.can_manage_member_access(scope,target_id) OR communication='invite_to_accept' AND
  public.can_offer_member_access_as_actor_internal_v1(auth.uid(),scope,target_id,roles)) THEN RAISE insufficient_privilege USING MESSAGE='scope_denied'; END IF;
 IF op IS NULL OR op NOT IN ('save_member','send_invitation','save_member_and_invite') OR communication NOT IN
 ('none','participant_credentials','notify_existing_access','invite_to_accept') OR op='save_member' AND communication<>'none'
 OR communication='invite_to_accept' AND op<>'send_invitation'
 OR op='send_invitation' AND (p_request ? 'changes' OR p_request ? 'expectedVersion') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_intent'; END IF;
 IF scope='occasion' THEN
  SELECT unit,organization,id,o.title,'/'||o.link||'/admin' INTO un,org,oc,title,destination FROM public.occasions o WHERE id=target_id;
 ELSE
  SELECT id,organization,u.title,'/unit/'||id||'/edit' INTO un,org,title,destination FROM public.units u WHERE id=target_id;
 END IF;
 IF usr IS NOT NULL THEN
  SELECT lower(btrim(ui.email_readonly)) INTO mail FROM public.user_info ui WHERE ui.id=usr AND (ui.organization=org
   OR scope='occasion' AND EXISTS(SELECT 1 FROM public.occasion_users m WHERE m.occasion=oc AND m."user"=ui.id)
   OR scope='unit' AND EXISTS(SELECT 1 FROM public.unit_users m WHERE m.unit=un AND m."user"=ui.id));
  IF mail IS NULL THEN RAISE insufficient_privilege USING MESSAGE='wrong_identity'; END IF;
  IF p_request ? 'email' AND lower(btrim(p_request->>'email')) IS DISTINCT FROM mail THEN
   RAISE invalid_parameter_value USING MESSAGE='wrong_identity'; END IF;
 ELSE
  mail:=lower(btrim(coalesce(p_request->>'email',p_request#>>'{changes,data,email}',p_request#>>'{changes,email}')));
  IF mail IS NULL OR length(mail)>254 OR mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid_email'; END IF;
  IF (SELECT count(*) FROM public.user_info WHERE organization=org AND lower(btrim(email_readonly))=mail)>1 THEN
   RAISE invalid_parameter_value USING MESSAGE='wrong_identity'; END IF;
  SELECT id INTO usr FROM public.user_info WHERE organization=org AND lower(btrim(email_readonly))=mail;
 END IF;
 IF scope='unit' THEN SELECT to_jsonb(m) INTO member FROM public.unit_users m WHERE unit=un AND "user"=usr;
 ELSE SELECT to_jsonb(m) INTO member FROM public.occasion_users m WHERE occasion=oc AND "user"=usr; END IF;
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type=CASE WHEN scope='unit' THEN 'unit_user' ELSE 'occasion_user' END
 AND v.scope_type=scope AND v.scope_id=target_id AND v.aggregate_id=usr::text;
 IF communication='participant_credentials' AND (scope<>'occasion' OR
   usr IS NOT NULL AND (NOT public.get_can_reset_user_password(usr) OR coalesce((member->>'is_manager')::boolean,false)
    OR coalesce((member->>'is_editor')::boolean,false) OR coalesce((member->>'is_editor_view')::boolean,false))) THEN
  RAISE insufficient_privilege USING MESSAGE='credential_operation_denied'; END IF;
 IF communication='notify_existing_access' AND (member IS NULL AND op='send_invitation') THEN
  RAISE invalid_parameter_value USING MESSAGE='membership_required'; END IF;
 IF p_request ? 'sourceDraft' THEN
  SELECT * INTO draft FROM public.occasion_setup_drafts WHERE id=(p_request->>'sourceDraft')::uuid;
  IF NOT FOUND OR draft.unit<>un OR draft.organization<>org OR (draft.data->>'finalizedOccasion')::bigint IS DISTINCT FROM oc
   OR draft.data->'sendTeamInvitations' IS DISTINCT FROM 'true'::jsonb
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(draft.data->'teamInviteEmails') e WHERE lower(btrim(e))=mail) THEN
   RAISE invalid_parameter_value USING MESSAGE='setup_invitation_not_confirmed'; END IF;
  IF roles IS DISTINCT FROM jsonb_build_object('is_editor',public.occasion_setup_invitation_role(draft.data->'teamInviteRoles',mail)='editor','is_editor_view',true) THEN
   RAISE serialization_failure USING MESSAGE='version_conflict'; END IF;
 END IF;
 IF communication='invite_to_accept' THEN
  PERFORM public.validate_access_roles_internal_v1(scope,roles);
  IF NOT EXISTS(SELECT 1 FROM jsonb_each(roles) r WHERE r.value='true') THEN
   RAISE invalid_parameter_value USING MESSAGE='roles_required'; END IF;
 END IF;
 IF op='send_invitation' AND communication='none' THEN RAISE invalid_parameter_value USING MESSAGE='communication_required'; END IF;
 IF communication='invite_to_accept' AND p_request ? 'sourceDraft' THEN
  SELECT * INTO existing_invitation FROM public.access_invitations i WHERE i.draft=(p_request->>'sourceDraft')::uuid AND i.email=mail ORDER BY i.created_at LIMIT 1;
  IF FOUND THEN
   IF existing_invitation.revoked_at IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='invitation_revoked'; END IF;
   IF existing_invitation.expires_at<=now() THEN RAISE invalid_parameter_value USING MESSAGE='invitation_expired'; END IF;
   IF existing_invitation.offered_roles IS DISTINCT FROM roles THEN RAISE serialization_failure USING MESSAGE='version_conflict'; END IF;
  END IF;
 ELSIF communication='invite_to_accept' AND NOT p_request ? 'predecessor' AND EXISTS
  (SELECT 1 FROM public.access_invitations WHERE unit=un AND occasion IS NOT DISTINCT FROM oc AND email=mail AND revoked_at IS NULL AND accepted_at IS NULL AND expires_at>now()) THEN
  NULL;
 END IF;
 -- Server-derived template facts bind preparation to both identity and intended edit.
 SELECT data INTO conf FROM public.organizations WHERE id=org;
 RETURN jsonb_build_object('actor',auth.uid(),'scope',p_request->'scope','unit',un,'occasion',oc,'organization',org,
  'userId',usr,'email',mail,'recipient',CASE WHEN communication='invite_to_accept' OR usr IS NULL THEN mail ELSE public.get_user_delivery_email(usr) END,
  'member',member,'profile',coalesce(member->'data','{}'::jsonb)||coalesce(p_request#>'{changes,data}','{}'::jsonb),'version',ver,'roles',CASE WHEN communication='invite_to_accept' THEN roles ELSE coalesce(member,'{}')||coalesce(p_request->'changes','{}') END,'changes',p_request->'changes','title',title,'destination',destination,
  'operation',op,'communication',communication,
  'pendingInvitation',communication='invite_to_accept' AND NOT p_request ? 'sourceDraft' AND NOT p_request ? 'predecessor' AND EXISTS(SELECT 1 FROM public.access_invitations i WHERE i.unit=un AND i.occasion IS NOT DISTINCT FROM oc AND i.email=mail AND i.revoked_at IS NULL AND i.accepted_at IS NULL AND i.expires_at>now()),
  'existingInvitation',CASE WHEN existing_invitation.id IS NULL THEN NULL ELSE jsonb_build_object('invitationId',existing_invitation.id,'messageId',existing_invitation.message_id) END,'organizationData',jsonb_build_object('DEFAULT_URL',conf->>'DEFAULT_URL',
   'APP_NAME',conf->>'APP_NAME','DEFAULT_LANGUAGE',coalesce(conf->>'DEFAULT_LANGUAGE','en'),'PLATFORMS',conf->'PLATFORMS'));
END $$;
REVOKE ALL ON FUNCTION public.member_access_preview_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_member_access(p_command_id uuid,p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE preview jsonb; receipt public.client_mutation_receipts; intent_hash text;
BEGIN
 p_request:=public.normalize_member_access_request_internal_v1(p_request);
 preview:=public.member_access_preview_internal_v1(p_request);
 intent_hash:=encode(extensions.digest(p_request::text,'sha256'),'hex');
 SELECT * INTO receipt FROM public.client_mutation_receipts WHERE command_id=p_command_id;
 IF FOUND THEN
  IF receipt.actor_id IS DISTINCT FROM auth.uid() OR receipt.command_name<>'people.access.manage' OR receipt.request_sha256<>intent_hash THEN
   RAISE invalid_parameter_value USING MESSAGE='command_payload_conflict'; END IF;
  IF receipt.status='completed' THEN RETURN jsonb_build_object('replay',receipt.response); END IF;
 END IF;
 IF preview->>'pendingInvitation'='true' THEN RAISE invalid_parameter_value USING MESSAGE='invitation_pending'; END IF;
 RETURN preview||jsonb_build_object('intentHash',intent_hash,'previewHash',encode(extensions.digest(preview::text,'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.preview_member_access(uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_member_access(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.invalidate_member_access_invitations_internal_v1(p_unit bigint,p_occasion bigint,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE mail text;
BEGIN
 -- Callers retain their existing membership locks. Do not acquire a new unit
 -- lock after order/reception teardown has already locked membership rows.
 SELECT lower(btrim(email_readonly)) INTO mail FROM public.user_info WHERE id=p_user;
 UPDATE public.access_invitations SET revoked_at=clock_timestamp()
 WHERE unit=p_unit AND (p_occasion IS NULL OR occasion=p_occasion) AND email=mail AND accepted_at IS NULL AND revoked_at IS NULL;
 UPDATE public.email_messages m SET workflow_state='cancelled',last_error='invitation_revoked'
 WHERE m.workflow_state IN ('pending','blocked','preparing','retry_wait') AND EXISTS
 (SELECT 1 FROM public.access_invitations i WHERE i.message_id=m.message_id AND i.revoked_at IS NOT NULL AND i.unit=p_unit AND i.email=mail);
END $$;
REVOKE ALL ON FUNCTION public.invalidate_member_access_invitations_internal_v1(bigint,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.manage_member_access(p_command_id uuid,p_request jsonb,p_preparation uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE preview jsonb; checked jsonb; prep public.access_email_preparations; receipt public.client_mutation_receipts;
 result jsonb; changed jsonb; invitation public.access_invitations; queued jsonb; usr uuid; scope text:=p_request#>>'{scope,type}';
 target_id bigint:=(p_request#>>'{scope,id}')::bigint; un bigint; oc bigint; org bigint; hash text; action text:=p_request->>'operation';
 comm text:=coalesce(p_request->>'communication','none'); predecessor public.access_invitations;
BEGIN
 p_request:=public.normalize_member_access_request_internal_v1(p_request);
 preview:=public.member_access_preview_internal_v1(p_request);
 un:=(preview->>'unit')::bigint; oc:=(preview->>'occasion')::bigint; org:=(preview->>'organization')::bigint;
 PERFORM public.lock_member_access_internal_v1(un);
 preview:=public.member_access_preview_internal_v1(p_request);
 hash:=encode(extensions.digest(p_request::text,'sha256'),'hex');
 INSERT INTO public.client_mutation_receipts(command_id,command_name,unit,occasion,actor_id,request_sha256)
 VALUES(p_command_id,'people.access.manage',CASE WHEN scope='unit' THEN un END,oc,auth.uid(),hash) ON CONFLICT DO NOTHING;
 SELECT * INTO STRICT receipt FROM public.client_mutation_receipts WHERE command_id=p_command_id FOR UPDATE;
 IF receipt.actor_id IS DISTINCT FROM auth.uid() OR receipt.command_name<>'people.access.manage' OR receipt.request_sha256<>hash
  OR receipt.unit IS DISTINCT FROM (CASE WHEN scope='unit' THEN un END) OR receipt.occasion IS DISTINCT FROM oc THEN
  RAISE invalid_parameter_value USING MESSAGE='command_payload_conflict'; END IF;
 IF receipt.status='completed' THEN RETURN receipt.response; END IF;
 IF preview->>'pendingInvitation'='true' THEN RAISE invalid_parameter_value USING MESSAGE='invitation_pending'; END IF;
 IF preview->'existingInvitation' IS DISTINCT FROM 'null'::jsonb AND preview ? 'existingInvitation' THEN
  result:=jsonb_build_object('status','unchanged','code',200,'data',jsonb_build_object('userId',preview->'userId',
   'access',jsonb_build_object('invitationId',preview#>'{existingInvitation,invitationId}','offered',true),
   'communication',jsonb_build_object('messageId',preview#>'{existingInvitation,messageId}','state','queued')),
   'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
   'sync',jsonb_build_object('replacements','[]'::jsonb));
  RETURN public.finish_client_mutation_v1(p_command_id,result,NULL);
 END IF;
 IF comm<>'none' THEN
  SELECT * INTO prep FROM public.access_email_preparations WHERE id=p_preparation AND actor=auth.uid()
   AND command_id=p_command_id AND intent_hash=hash AND expires_at>now() FOR UPDATE;
  IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='preparation_deferred'; END IF;
  IF prep.preview_hash IS DISTINCT FROM encode(extensions.digest(preview::text,'sha256'),'hex') THEN
   RAISE serialization_failure USING MESSAGE='version_conflict'; END IF;
 END IF;
 usr:=(preview->>'userId')::uuid;
 IF action IN ('save_member','save_member_and_invite') THEN
  -- Preserve the specialized profile/role writers and their own authorization.
  IF preview->'member' IS DISTINCT FROM 'null'::jsonb AND usr IS NOT NULL AND p_request->>'userId' IS NULL THEN
   changed:=jsonb_build_object('status','unchanged','code',200,'data',jsonb_build_object('userId',usr,'version',preview->'version','reasonCode','already_member'),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),'sync',jsonb_build_object('replacements','[]'::jsonb));
  ELSIF scope='unit' THEN
   changed:=public.save_unit_member_internal_v1(un,(p_request->>'userId')::uuid,extensions.gen_random_uuid(),
    (p_request->>'expectedVersion')::bigint,coalesce(p_request->'changes','{}')||jsonb_build_object('kind',coalesce(p_request#>>'{changes,kind}','editor')));
  ELSIF p_request->>'userId' IS NULL THEN
   changed:=public.create_occasion_member_internal_v1(oc,extensions.gen_random_uuid(),
    coalesce(p_request->'changes','{}')||jsonb_build_object('occasion',oc));
  ELSE
   changed:=public.save_profile_internal_v1(oc,usr,extensions.gen_random_uuid(),(p_request->>'expectedVersion')::bigint,
    coalesce(p_request->'changes','{}')||jsonb_build_object('occasion',oc,'user',usr));
  END IF;
  IF (changed->>'code')::int<>200 THEN
   IF comm<>'none' THEN RAISE serialization_failure USING MESSAGE='version_conflict'; END IF;
   changed:=jsonb_set(changed,'{data}',(coalesce(changed->'data','{}'::jsonb)-'message')||jsonb_build_object('reasonCode',CASE (changed->>'code')::int WHEN 403 THEN 'scope_denied' WHEN 409 THEN 'version_conflict' ELSE 'invalid_intent' END));
   changed:=jsonb_set(changed,'{mutation,commandId}',to_jsonb(p_command_id));
   changed:=jsonb_set(changed,'{mutation,receiptId}',to_jsonb(p_command_id));
   RETURN public.finish_client_mutation_v1(p_command_id,changed,NULL);
  END IF;
  usr:=coalesce((changed#>>'{data,userId}')::uuid,usr);
 END IF;
 IF p_request ? 'predecessor' THEN
  SELECT * INTO predecessor FROM public.access_invitations WHERE id=(p_request->>'predecessor')::uuid FOR UPDATE;
  IF NOT FOUND OR predecessor.unit<>un OR predecessor.occasion IS DISTINCT FROM oc OR predecessor.email<>preview->>'email' THEN
   RAISE invalid_parameter_value USING MESSAGE='wrong_identity'; END IF;
  IF EXISTS(SELECT 1 FROM public.email_messages WHERE message_id=predecessor.message_id AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown')) THEN
   RAISE invalid_parameter_value USING MESSAGE='dispatch_unresolved'; END IF;
  UPDATE public.access_invitations SET revoked_at=coalesce(revoked_at,now()) WHERE id=predecessor.id;
 END IF;
 IF comm='notify_existing_access' AND NOT (CASE WHEN scope='unit' THEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=un AND "user"=usr) ELSE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=oc AND "user"=usr) END) THEN
  RAISE invalid_parameter_value USING MESSAGE='membership_required'; END IF;
 IF comm='invite_to_accept' THEN
  IF prep.token_hash IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid_preparation'; END IF;
  INSERT INTO public.access_invitations(draft,scope_type,occasion,unit,organization,email,role,offered_roles,token_hash,created_by,predecessor,recipient_user)
  VALUES((p_request->>'sourceDraft')::uuid,scope,oc,un,org,preview->>'email',
   CASE WHEN (preview#>>'{roles,is_editor}')::boolean THEN 'editor' ELSE 'read_only' END,
   preview->'roles',prep.token_hash,auth.uid(),predecessor.id,usr) RETURNING * INTO invitation;
  queued:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc,'unit',un),preview->>'email',
   jsonb_build_object('invitation_id',invitation.id,'content_hash',prep.prepared->>'p_content_hash'),
   'access:'||p_command_id,'TEAM_INVITATION',now(),invitation.expires_at);
  UPDATE public.access_invitations SET message_id=(queued->>'message_id')::uuid WHERE id=invitation.id;
 ELSIF comm='participant_credentials' THEN
  queued:=public.reset_password_and_enqueue_email(usr,CASE WHEN prep.credential IS NULL THEN NULL ELSE extensions.pgp_sym_decrypt(prep.credential,(SELECT encode(secret,'hex') FROM public.access_preparation_key WHERE singleton)) END,oc,prep.prepared->'p_sealed',
   prep.prepared->>'p_content_hash','access:'||p_command_id,now()+interval '10 minutes');
 ELSIF comm='notify_existing_access' THEN
  IF usr IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=usr) THEN
   RAISE invalid_parameter_value USING MESSAGE='membership_required'; END IF;
  queued:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc,'unit',un,'recipient_user',usr),
   public.get_user_delivery_email(usr),jsonb_build_object('content_hash',prep.prepared->>'p_content_hash','access_scope',scope),
   'access:'||p_command_id,'TEAM_ACCESS_NOTICE',now(),now()+interval '14 days');
 END IF;
 IF queued IS NOT NULL AND comm<>'participant_credentials' THEN
  UPDATE public.email_messages SET prepared=prep.prepared->'p_sealed',prepared_hash=encode(extensions.digest((prep.prepared->'p_sealed')::text,'sha256'),'hex'),
   prepared_at=now(),tracking_policy='disabled' WHERE message_id=(queued->>'message_id')::uuid;
  PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(queued->>'message_id')::uuid),true);
 END IF;
 result:=coalesce(changed,jsonb_build_object('status','applied','code',200,'data','{}'::jsonb,'mutation',jsonb_build_object(
  'commandId',p_command_id,'receiptId',p_command_id,'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),'sync',jsonb_build_object('replacements','[]'::jsonb)));
 result:=jsonb_set(result,'{mutation,commandId}',to_jsonb(p_command_id));
 result:=jsonb_set(result,'{mutation,receiptId}',to_jsonb(p_command_id));
 result:=jsonb_set(result,'{data}',coalesce(result->'data','{}')||jsonb_build_object('userId',usr,
  'membership',jsonb_build_object('userId',usr,'exists',CASE WHEN scope='unit' THEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=un AND "user"=usr) ELSE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=oc AND "user"=usr) END),
  'access',jsonb_build_object('invitationId',invitation.id,'offered',comm='invite_to_accept'),
  'communication',jsonb_build_object('messageId',queued->'message_id','state',CASE WHEN queued IS NULL THEN 'not_requested' ELSE 'queued' END)));
 DELETE FROM public.access_email_preparations WHERE id=prep.id;
 RETURN public.finish_client_mutation_v1(p_command_id,result,(changed#>>'{mutation,commitId}')::uuid);
END $$;
REVOKE ALL ON FUNCTION public.manage_member_access(uuid,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_member_access(uuid,jsonb,uuid) TO authenticated;
