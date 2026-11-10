CREATE OR REPLACE FUNCTION public.access_invitation_valid_internal_v1(i public.access_invitations)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (i.recipient_user IS NULL OR EXISTS(SELECT 1 FROM public.user_info WHERE id=i.recipient_user)) AND i.revoked_at IS NULL AND i.expires_at>now() AND public.can_offer_member_access_as_actor_internal_v1(i.created_by,i.scope_type,
  CASE WHEN i.scope_type='unit' THEN i.unit ELSE i.occasion END,i.offered_roles)
 AND EXISTS(SELECT 1 FROM public.units u WHERE u.id=i.unit AND u.organization=i.organization)
 AND (i.scope_type='unit' OR EXISTS(SELECT 1 FROM public.occasions o WHERE o.id=i.occasion AND o.unit=i.unit AND o.organization=i.organization));
$$;
REVOKE ALL ON FUNCTION public.access_invitation_valid_internal_v1(public.access_invitations) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_access_invitation(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE invitation public.access_invitations; result jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN NULL; END IF;
 SELECT * INTO invitation FROM public.access_invitations WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF invitation.revoked_at IS NOT NULL THEN RETURN jsonb_build_object('reasonCode','invitation_revoked'); END IF;
 IF invitation.expires_at<=now() THEN RETURN jsonb_build_object('reasonCode','invitation_expired'); END IF;
 IF NOT public.access_invitation_valid_internal_v1(invitation) THEN RETURN NULL; END IF;
 SELECT jsonb_build_object('email',invitation.email,'title',coalesce(o.title,u.title),'unitTitle',u.title,'organization',invitation.organization,
  'scope',jsonb_build_object('type',invitation.scope_type,'id',coalesce(invitation.occasion,invitation.unit)),
  'link',CASE WHEN invitation.scope_type='unit' THEN invitation.unit::text ELSE o.link END,
  'destination',CASE WHEN invitation.scope_type='unit' THEN '/unit/'||invitation.unit||'/edit' ELSE '/'||o.link||'/admin' END,
  'roles',invitation.offered_roles,'role',invitation.role,'accepted',invitation.accepted_at IS NOT NULL,
  'existingAccount',EXISTS(SELECT 1 FROM public.user_info WHERE id=invitation.recipient_user OR invitation.recipient_user IS NULL AND organization=invitation.organization AND lower(btrim(email_readonly))=invitation.email))
 INTO result FROM public.units u LEFT JOIN public.occasions o ON o.id=invitation.occasion WHERE u.id=invitation.unit;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_access_invitation(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_access_invitation(text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.accept_access_invitation(p_token text,p_password text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE invitation public.access_invitations; recipient uuid; fresh boolean:=false; roles jsonb; un bigint;
 before_row jsonb; ver bigint; commit_row public.client_commits; projection jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE invalid_parameter_value USING MESSAGE='invalid_invitation'; END IF;
 SELECT unit INTO un FROM public.access_invitations WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 IF un IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid_invitation'; END IF;
 PERFORM public.lock_member_access_internal_v1(un);
 SELECT * INTO STRICT invitation FROM public.access_invitations WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 IF invitation.recipient_user IS NOT NULL THEN
  SELECT id INTO recipient FROM public.user_info WHERE id=invitation.recipient_user;
  IF recipient IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invitation_revoked'; END IF;
 ELSE
  IF (SELECT count(*) FROM public.user_info WHERE organization=invitation.organization AND lower(btrim(email_readonly))=invitation.email)>1 THEN
   RAISE insufficient_privilege USING MESSAGE='wrong_identity'; END IF;
  SELECT id INTO recipient FROM public.user_info WHERE organization=invitation.organization AND lower(btrim(email_readonly))=invitation.email;
 END IF;
 -- Legacy order/reception teardown owns its membership row before invalidating
 -- offers. Take that same row before the invitation row to avoid an inverted
 -- lock order while retaining the canonical unit/identity locks for creation.
 IF recipient IS NOT NULL THEN
  IF invitation.scope_type='unit' THEN
   PERFORM 1 FROM public.unit_users WHERE unit=un AND "user"=recipient FOR UPDATE;
  ELSE
   PERFORM 1 FROM public.occasion_users WHERE occasion=invitation.occasion AND "user"=recipient FOR UPDATE;
  END IF;
 END IF;
 SELECT * INTO STRICT invitation FROM public.access_invitations WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') FOR UPDATE;
 IF invitation.revoked_at IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='invitation_revoked'; END IF;
 IF invitation.expires_at<=now() THEN RAISE invalid_parameter_value USING MESSAGE='invitation_expired'; END IF;
 IF NOT public.access_invitation_valid_internal_v1(invitation) THEN RAISE insufficient_privilege USING MESSAGE='scope_denied'; END IF;
 -- Fence live inviter authorization against concurrent revocation.
 PERFORM 1 FROM public.unit_users WHERE unit=un AND "user"=invitation.created_by FOR SHARE;
 PERFORM 1 FROM public.organization_users WHERE organization=invitation.organization AND "user"=invitation.created_by FOR SHARE;
 IF invitation.occasion IS NOT NULL THEN PERFORM 1 FROM public.occasion_users WHERE occasion=invitation.occasion AND "user"=invitation.created_by FOR SHARE; END IF;
 IF NOT public.access_invitation_valid_internal_v1(invitation) THEN RAISE insufficient_privilege USING MESSAGE='scope_denied'; END IF;
 IF invitation.recipient_user IS NOT NULL THEN
  SELECT id INTO recipient FROM public.user_info WHERE id=invitation.recipient_user;
  IF recipient IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invitation_revoked'; END IF;
 ELSE
  IF (SELECT count(*) FROM public.user_info WHERE organization=invitation.organization AND lower(btrim(email_readonly))=invitation.email)>1 THEN
   RAISE insufficient_privilege USING MESSAGE='wrong_identity'; END IF;
  SELECT id INTO recipient FROM public.user_info WHERE organization=invitation.organization AND lower(btrim(email_readonly))=invitation.email;
 END IF;
 IF invitation.accepted_at IS NOT NULL THEN
  IF auth.uid() IS DISTINCT FROM invitation.accepted_by THEN RAISE insufficient_privilege USING MESSAGE='wrong_identity'; END IF;
  RETURN public.get_access_invitation(p_token)||jsonb_build_object('accepted',true,'newAccount',false);
 END IF;
 IF recipient IS NOT NULL THEN
  IF auth.uid() IS DISTINCT FROM recipient THEN RAISE insufficient_privilege USING MESSAGE='wrong_identity'; END IF;
 ELSE
  IF auth.uid() IS NOT NULL THEN RAISE insufficient_privilege USING MESSAGE='wrong_identity'; END IF;
  IF p_password IS NULL OR length(p_password)<8 OR octet_length(p_password)>1024 THEN RAISE invalid_parameter_value USING MESSAGE='invalid_password'; END IF;
  recipient:=public.create_user_in_organization_with_data_pure(invitation.organization,invitation.email,p_password,'{}');
  fresh:=true;
 END IF;
 roles:=invitation.offered_roles;
 PERFORM public.validate_access_roles_internal_v1(invitation.scope_type,roles);
 IF invitation.scope_type='unit' THEN
  SELECT to_jsonb(m) INTO before_row FROM public.unit_users m WHERE unit=un AND "user"=recipient FOR UPDATE;
  INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view)
  VALUES(un,recipient,coalesce((roles->>'is_manager')::boolean,false),coalesce((roles->>'is_editor')::boolean,false),coalesce((roles->>'is_editor_view')::boolean,false))
  ON CONFLICT(unit,"user") DO UPDATE SET is_manager=coalesce(public.unit_users.is_manager,false) OR excluded.is_manager,
   is_editor=coalesce(public.unit_users.is_editor,false) OR excluded.is_editor,
   is_editor_view=coalesce(public.unit_users.is_editor_view,false) OR excluded.is_editor_view;
 ELSE
  SELECT to_jsonb(m) INTO before_row FROM public.occasion_users m WHERE occasion=invitation.occasion AND "user"=recipient FOR UPDATE;
  INSERT INTO public.occasion_users(occasion,"user",data) SELECT invitation.occasion,recipient,
   jsonb_build_object('name',ui.name,'surname',ui.surname,'email',ui.email_readonly) FROM public.user_info ui WHERE ui.id=recipient
  ON CONFLICT(occasion,"user") DO NOTHING;
  UPDATE public.occasion_users SET
   is_manager=coalesce(is_manager,false) OR coalesce((roles->>'is_manager')::boolean,false),
   is_editor=coalesce(is_editor,false) OR coalesce((roles->>'is_editor')::boolean,false),
   is_editor_view=coalesce(is_editor_view,false) OR coalesce((roles->>'is_editor_view')::boolean,false),
   is_editor_order=coalesce(is_editor_order,false) OR coalesce((roles->>'is_editor_order')::boolean,false),
   is_editor_order_view=coalesce(is_editor_order_view,false) OR coalesce((roles->>'is_editor_order_view')::boolean,false),
   is_receptionist=coalesce(is_receptionist,false) OR coalesce((roles->>'is_receptionist')::boolean,false),
   is_approver=coalesce(is_approver,false) OR coalesce((roles->>'is_approver')::boolean,false),
   is_cleaning_crew=coalesce(is_cleaning_crew,false) OR coalesce((roles->>'is_cleaning_crew')::boolean,false),
   is_cleaning_blocked=coalesce(is_cleaning_blocked,false) OR coalesce((roles->>'is_cleaning_blocked')::boolean,false)
  WHERE occasion=invitation.occasion AND "user"=recipient;
 END IF;
 UPDATE public.access_invitations SET recipient_user=recipient,accepted_by=recipient,accepted_at=clock_timestamp() WHERE id=invitation.id;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES(CASE WHEN invitation.scope_type='unit' THEN 'unit_user' ELSE 'occasion_user' END,invitation.scope_type,
  coalesce(invitation.occasion,un),recipient::text,1)
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
 RETURNING version INTO ver;
 IF invitation.scope_type='occasion' THEN
  PERFORM public.record_client_sync_commit_v1(invitation.occasion,'profile.team_invitation.accept','profile',
   jsonb_build_array(jsonb_build_object('entityType','occasion_user','entityId',recipient,'operation',CASE WHEN before_row IS NULL THEN 'insert' ELSE 'update' END,
   'safeLabel','Team invitation accepted','changedFields',jsonb_build_array('membership','rights'))),'{}'::text[],
   jsonb_build_array(jsonb_build_object('component','private_profile','userId',recipient)),'[]',
   CASE WHEN auth.uid() IS NULL THEN 'unknown' ELSE 'user' END,'Invited member accepted');
 ELSE
  INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
  VALUES(un,recipient,'user','profile.team_invitation.accept','profile') RETURNING * INTO commit_row;
  INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES(commit_row.commit_id,0,'unit_user',recipient::text,'update','Team invitation accepted',ARRAY['membership','rights']);
  PERFORM public.publish_unit_user_access_change_internal_v1(commit_row.commit_id,un,recipient);
  PERFORM public.fanout_unit_catalog_v1(commit_row.commit_id,un);
 END IF;
 RETURN public.get_access_invitation(p_token)||jsonb_build_object('accepted',true,'newAccount',fresh);
END $$;
REVOKE ALL ON FUNCTION public.accept_access_invitation(text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.accept_access_invitation(text,text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.revoke_access_invitation(p_invitation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE invitation public.access_invitations;
BEGIN
 SELECT * INTO STRICT invitation FROM public.access_invitations WHERE id=p_invitation;
 IF NOT public.can_offer_member_access_as_actor_internal_v1(auth.uid(),invitation.scope_type,coalesce(invitation.occasion,invitation.unit),invitation.offered_roles) THEN RAISE insufficient_privilege USING MESSAGE='scope_denied'; END IF;
 PERFORM public.lock_member_access_internal_v1(invitation.unit);
 SELECT * INTO STRICT invitation FROM public.access_invitations WHERE id=p_invitation FOR UPDATE;
 IF NOT public.can_offer_member_access_as_actor_internal_v1(auth.uid(),invitation.scope_type,coalesce(invitation.occasion,invitation.unit),invitation.offered_roles) THEN RAISE insufficient_privilege USING MESSAGE='scope_denied'; END IF;
 UPDATE public.access_invitations SET revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE id=p_invitation AND accepted_at IS NULL;
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='invitation_revoked'
 WHERE message_id=invitation.message_id AND invitation.accepted_at IS NULL AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 RETURN jsonb_build_object('revoked',invitation.accepted_at IS NULL,'accepted',invitation.accepted_at IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.revoke_access_invitation(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_access_invitation(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_member_access_status(p_scope text,p_id bigint,p_user uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF NOT public.can_manage_member_access(p_scope,p_id) THEN RAISE insufficient_privilege USING MESSAGE='scope_denied'; END IF;
 SELECT jsonb_build_object('invitations',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'email',i.email,'roles',i.offered_roles,
  'acceptedAt',i.accepted_at,'revokedAt',i.revoked_at,'expiresAt',i.expires_at,'messageId',i.message_id)) FROM public.access_invitations i
  WHERE (p_scope='unit' AND i.scope_type='unit' AND i.unit=p_id OR p_scope='occasion' AND i.occasion=p_id)
  AND (p_user IS NULL OR i.recipient_user=p_user OR i.email=(SELECT lower(btrim(email_readonly)) FROM public.user_info WHERE id=p_user))),'[]'),
  'messages',coalesce((SELECT jsonb_agg(jsonb_build_object('messageId',m.message_id,'userId',m.recipient_user,'recipient',m.recipient,'code',m.code,
   'state',CASE WHEN m.workflow_state='unknown' THEN 'dispatch_unresolved' WHEN m.bounced_at IS NOT NULL OR m.provider_failure IN ('reject','rendering_failure') THEN 'failed' WHEN m.workflow_state='accepted' THEN CASE WHEN m.delivered_at IS NOT NULL THEN 'delivered' ELSE 'provider_accepted' END
    WHEN m.workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown') THEN 'queued'
    WHEN m.workflow_state='dead' THEN 'failed' ELSE m.workflow_state END,'providerAcceptedAt',m.accepted_at,'deliveredAt',m.delivered_at))
   FROM public.email_messages m WHERE (p_scope='unit' AND m.occasion IS NULL AND m.unit=p_id OR p_scope='occasion' AND m.occasion=p_id)
   AND m.code IN ('SIGN_IN_CODE','TEAM_ACCESS_NOTICE','TEAM_INVITATION') AND (p_user IS NULL OR m.recipient_user=p_user OR EXISTS
    (SELECT 1 FROM public.access_invitations i WHERE i.message_id=m.message_id AND i.email=(SELECT lower(btrim(email_readonly)) FROM public.user_info WHERE id=p_user)))),'[]')) INTO result;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_member_access_status(text,bigint,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_member_access_status(text,bigint,uuid) TO authenticated;

-- Published link/RPC adapters for installed clients; retire only after link expiry
-- and enforced upgrade. The public /team-invitation path remains unchanged.
CREATE OR REPLACE FUNCTION public.get_occasion_team_invitation(p_token text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$ SELECT CASE WHEN r ? 'reasonCode' OR r#>>'{scope,type}'='unit' THEN NULL ELSE r END FROM (SELECT public.get_access_invitation(p_token) r) v; $$;
CREATE OR REPLACE FUNCTION public.accept_occasion_team_invitation(p_token text,p_password text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.access_invitations WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND scope_type='unit') THEN
  RAISE invalid_parameter_value USING MESSAGE='upgrade_required'; END IF;
 RETURN public.accept_access_invitation(p_token,p_password);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_team_invitation(text),public.accept_occasion_team_invitation(text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_team_invitation(text),public.accept_occasion_team_invitation(text,text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.resend_access_invitation(p_invitation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE i public.access_invitations;
BEGIN
 SELECT * INTO STRICT i FROM public.access_invitations WHERE id=p_invitation;
 IF NOT public.can_offer_member_access_as_actor_internal_v1(auth.uid(),i.scope_type,coalesce(i.occasion,i.unit),i.offered_roles) THEN RAISE insufficient_privilege USING MESSAGE='scope_denied'; END IF;
 IF EXISTS(SELECT 1 FROM public.email_messages WHERE message_id=i.message_id AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown')) THEN
  RAISE invalid_parameter_value USING MESSAGE='dispatch_unresolved'; END IF;
 RETURN jsonb_build_object('scope',jsonb_build_object('type',i.scope_type,'id',coalesce(i.occasion,i.unit)),
  'operation','send_invitation','communication','invite_to_accept','email',i.email,'roles',i.offered_roles,'predecessor',i.id);
END $$;
REVOKE ALL ON FUNCTION public.resend_access_invitation(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.resend_access_invitation(uuid) TO authenticated;
