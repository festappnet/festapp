-- Event team invitations are acceptance proofs, never account passwords.
CREATE TABLE IF NOT EXISTS public.occasion_team_invitations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 draft uuid NOT NULL REFERENCES public.occasion_setup_drafts(id) ON DELETE CASCADE,
 occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
 organization bigint NOT NULL REFERENCES public.organizations(id),
 email text NOT NULL CHECK(email=lower(btrim(email))),
 role text NOT NULL DEFAULT 'editor' CHECK(role IN ('editor','read_only')),
 token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[0-9a-f]{64}$'),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '14 days',
 created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 accepted_by uuid REFERENCES auth.users(id) ON DELETE CASCADE, accepted_at timestamptz,
 message_id uuid REFERENCES public.email_messages(message_id),
 UNIQUE(draft,email), CHECK ((accepted_by IS NULL)=(accepted_at IS NULL))
);
ALTER TABLE public.occasion_team_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_team_invitations FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.normalize_occasion_setup_invite_emails(p_emails text[])
RETURNS text[] LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE result text[];
BEGIN
 IF coalesce(cardinality(p_emails),0)>20 THEN RAISE invalid_parameter_value USING MESSAGE='At most 20 invitations'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_emails) e WHERE e IS NULL OR length(btrim(e))>254
   OR btrim(e) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid invitation email'; END IF;
 SELECT coalesce(array_agg(e ORDER BY e),'{}'::text[]) INTO result
 FROM (SELECT DISTINCT lower(btrim(e)) e FROM unnest(p_emails) e) normalized;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.normalize_occasion_setup_invite_emails(text[]) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.occasion_setup_invitation_role(p_roles jsonb,p_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF p_roles IS NOT NULL AND (jsonb_typeof(p_roles) IS DISTINCT FROM 'object') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid invitation roles'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each_text(coalesce(p_roles,'{}')) r
   WHERE r.key<>lower(btrim(r.key)) OR r.value IS NULL OR r.value NOT IN ('editor','read_only')) THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid invitation role'; END IF;
 RETURN coalesce(p_roles->>p_email,'editor');
END $$;
REVOKE ALL ON FUNCTION public.occasion_setup_invitation_role(jsonb,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.preview_occasion_setup_invitations(p_id uuid,p_emails text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; emails text[]; event_id bigint; event_link text; event_title text; recipients jsonb; org_data jsonb;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(d.unit) OR public.get_is_editor_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF NOT public.get_is_manager_on_unit(d.unit) THEN RETURN jsonb_build_object('canManage',false,'recipients','[]'::jsonb); END IF;
 IF p_emails IS NULL THEN
  IF d.data ? 'finalizedOccasion' AND d.data->'sendTeamInvitations' IS DISTINCT FROM 'true'::jsonb THEN
   RAISE invalid_parameter_value USING MESSAGE='Invitation sending not confirmed'; END IF;
  IF jsonb_typeof(coalesce(d.data->'teamInviteEmails','[]'::jsonb)) IS DISTINCT FROM 'array' THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid invitation emails'; END IF;
  p_emails:=ARRAY(SELECT jsonb_array_elements_text(coalesce(d.data->'teamInviteEmails','[]'::jsonb)));
 END IF;
 emails:=public.normalize_occasion_setup_invite_emails(p_emails);
 event_id:=(d.data->>'finalizedOccasion')::bigint;
 IF event_id IS NOT NULL THEN SELECT link,title INTO event_link,event_title FROM public.occasions WHERE id=event_id AND unit=d.unit AND organization=d.organization;
 ELSE event_link:=d.data->>'link'; event_title:=d.data->>'title'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('email',e,'kind',CASE WHEN EXISTS(
   SELECT 1 FROM public.unit_users uu WHERE uu.unit=d.unit AND uu."user"=ui.id) THEN 'member'
   WHEN ui.id IS NOT NULL THEN 'account' ELSE 'new' END,
   'role',public.occasion_setup_invitation_role(d.data->'teamInviteRoles',e),
   'alreadyEditor',coalesce((SELECT ou.is_editor OR ou.is_manager OR (ou.is_editor_view AND public.occasion_setup_invitation_role(d.data->'teamInviteRoles',e)='read_only') FROM public.occasion_users ou
      WHERE ou.occasion=event_id AND ou."user"=ui.id),false)) ORDER BY e),'[]')
 INTO recipients FROM unnest(emails) e LEFT JOIN public.user_info ui
 ON ui.organization=d.organization AND lower(btrim(ui.email_readonly))=e;
 SELECT jsonb_build_object('APP_NAME',data->>'APP_NAME','DEFAULT_URL',data->>'DEFAULT_URL') INTO org_data FROM public.organizations WHERE id=d.organization;
 RETURN jsonb_build_object('canManage',true,'sendConfirmed',d.data->'sendTeamInvitations'='true'::jsonb,'recipients',recipients,'event',jsonb_build_object(
   'id',event_id,'link',event_link,'title',event_title,'unit',d.unit,'organization',d.organization),
   'organizationData',org_data);
END $$;
REVOKE ALL ON FUNCTION public.preview_occasion_setup_invitations(uuid,text[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_occasion_setup_invitations(uuid,text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_occasion_setup_invitation(p_id uuid,p_email text,p_token_hash text,p_sealed jsonb,p_content_hash text,p_role text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; invitation public.occasion_team_invitations; email_value text:=lower(btrim(p_email));
 emails text[]; event_id bigint; recipient uuid; queued jsonb; selected_role text;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.get_is_manager_on_unit(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Unit manager required'; END IF;
 IF d.data->'sendTeamInvitations' IS DISTINCT FROM 'true'::jsonb OR jsonb_typeof(d.data->'teamInviteEmails') IS DISTINCT FROM 'array' THEN
  RAISE invalid_parameter_value USING MESSAGE='Invitation sending not confirmed'; END IF;
 emails:=public.normalize_occasion_setup_invite_emails(ARRAY(SELECT jsonb_array_elements_text(d.data->'teamInviteEmails')));
 IF email_value IS NULL OR NOT email_value=ANY(emails) THEN RAISE invalid_parameter_value USING MESSAGE='Recipient not selected'; END IF;
 selected_role:=public.occasion_setup_invitation_role(d.data->'teamInviteRoles',email_value);
 IF p_role IS DISTINCT FROM selected_role THEN RAISE serialization_failure USING MESSAGE='Invitation role changed'; END IF;
 event_id:=(d.data->>'finalizedOccasion')::bigint;
 IF event_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=event_id AND unit=d.unit AND organization=d.organization) THEN
  RAISE invalid_parameter_value USING MESSAGE='Finalize the event before sending'; END IF;
 PERFORM public.check_occasion_writable(event_id);
 PERFORM pg_advisory_xact_lock(hashtextextended('team-invite:'||p_id::text||':'||email_value,0));
 SELECT * INTO invitation FROM public.occasion_team_invitations WHERE draft=p_id AND email=email_value;
 IF FOUND THEN
  IF invitation.role IS DISTINCT FROM selected_role THEN RAISE serialization_failure USING MESSAGE='Sent invitation role cannot change'; END IF;
  IF invitation.expires_at<=now() THEN RAISE invalid_parameter_value USING MESSAGE='Invitation expired'; END IF;
  RETURN jsonb_build_object('invitation_id',invitation.id,'message_id',invitation.message_id,'replayed',true,'accepted',invitation.accepted_at IS NOT NULL,'status','queued');
 END IF;
 SELECT id INTO recipient FROM public.user_info WHERE organization=d.organization AND lower(btrim(email_readonly))=email_value;
 IF EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=event_id AND "user"=recipient AND (is_editor OR is_manager OR (is_editor_view AND selected_role='read_only')))
 THEN
  RETURN jsonb_build_object('skipped',true,'alreadyEditor',true,'status','already_editor'); END IF;
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' OR p_content_hash IS NULL OR p_content_hash !~ '^[0-9a-f]{64}$'
   OR jsonb_typeof(p_sealed) IS DISTINCT FROM 'object' OR octet_length(p_sealed::text)>1048576 THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid prepared invitation'; END IF;
 INSERT INTO public.occasion_team_invitations(draft,occasion,unit,organization,email,role,token_hash,created_by)
 VALUES(p_id,event_id,d.unit,d.organization,email_value,selected_role,p_token_hash,auth.uid()) RETURNING * INTO invitation;
 -- recipient_user stays NULL: invitation identity is the entered canonical email,
 -- not the account's potentially different delivery override.
 queued:=public.enqueue_email('custom',jsonb_build_object('organization',d.organization,'occasion',event_id,'unit',d.unit),
  email_value,jsonb_build_object('invitation_id',invitation.id,'content_hash',p_content_hash),
  'team-invitation:'||invitation.id::text,'TEAM_INVITATION',now(),invitation.expires_at);
 UPDATE public.occasion_team_invitations SET message_id=(queued->>'message_id')::uuid WHERE id=invitation.id;
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),
  prepared_at=now(),tracking_policy='disabled' WHERE message_id=(queued->>'message_id')::uuid;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(queued->>'message_id')::uuid),true);
 RETURN queued||jsonb_build_object('invitation_id',invitation.id,'status','queued');
END $$;
REVOKE ALL ON FUNCTION public.enqueue_occasion_setup_invitation(uuid,text,text,jsonb,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enqueue_occasion_setup_invitation(uuid,text,text,jsonb,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_team_invitation(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN NULL; END IF;
 SELECT jsonb_build_object('email',i.email,'title',o.title,'unitTitle',u.title,'organization',i.organization,
  'link',o.link,'role',i.role,'accepted',i.accepted_at IS NOT NULL,'existingAccount',EXISTS(SELECT 1 FROM public.user_info ui
    WHERE ui.organization=i.organization AND lower(btrim(ui.email_readonly))=i.email)) INTO result
 FROM public.occasion_team_invitations i JOIN public.occasions o ON o.id=i.occasion AND o.unit=i.unit AND o.organization=i.organization
 JOIN public.units u ON u.id=i.unit
 WHERE i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND i.expires_at>now()
 AND NOT public.is_demo_occasion(i.occasion)
 AND EXISTS(SELECT 1 FROM public.unit_users uu WHERE uu.unit=i.unit AND uu."user"=i.created_by AND uu.is_manager);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_team_invitation(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_occasion_team_invitation(text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.accept_occasion_team_invitation(p_token text,p_password text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE invitation public.occasion_team_invitations; recipient uuid; new_account boolean:=false; before_row jsonb; version bigint;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid invitation'; END IF;
 SELECT * INTO invitation FROM public.occasion_team_invitations
 WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') FOR UPDATE;
 IF NOT FOUND OR invitation.expires_at<=now() OR NOT EXISTS(SELECT 1 FROM public.unit_users uu
   WHERE uu.unit=invitation.unit AND uu."user"=invitation.created_by AND uu.is_manager)
 OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=invitation.occasion AND unit=invitation.unit AND organization=invitation.organization) THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid invitation'; END IF;
 PERFORM public.check_occasion_writable(invitation.occasion);
 -- Serialize identity creation with every canonical tenant account writer.
 PERFORM pg_advisory_xact_lock(hashtextextended('user-sign-in-email:'||invitation.organization::text,0));
 SELECT id INTO recipient FROM public.user_info WHERE organization=invitation.organization
  AND lower(btrim(email_readonly))=invitation.email;
 IF invitation.accepted_at IS NOT NULL THEN
  IF auth.uid() IS DISTINCT FROM invitation.accepted_by THEN RAISE insufficient_privilege USING MESSAGE='Invitation already accepted'; END IF;
  RETURN jsonb_build_object('accepted',true,'newAccount',false,'link',(SELECT link FROM public.occasions WHERE id=invitation.occasion));
 END IF;
 IF recipient IS NOT NULL THEN
  IF auth.uid() IS DISTINCT FROM recipient THEN RAISE insufficient_privilege USING MESSAGE='Sign in with the invited account'; END IF;
 ELSE
  IF auth.uid() IS NOT NULL THEN RAISE insufficient_privilege USING MESSAGE='Sign out before creating the invited account'; END IF;
  IF p_password IS NULL OR length(p_password)<8 OR octet_length(p_password)>1024 THEN
   RAISE invalid_parameter_value USING MESSAGE='Password must have at least 8 characters'; END IF;
  recipient:=public.create_user_in_organization_with_data_pure(invitation.organization,invitation.email,p_password,'{}'::jsonb);
  new_account:=true;
 END IF;
 -- A token confers only this event's selected team role. It cannot create unit roles,
 -- change an existing account, reset credentials or downgrade other permissions.
 SELECT to_jsonb(ou) INTO before_row FROM public.occasion_users ou
 WHERE occasion=invitation.occasion AND "user"=recipient FOR UPDATE;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,data)
 SELECT invitation.occasion,recipient,invitation.role='editor',true,jsonb_build_object('name',ui.name,'surname',ui.surname,'email',ui.email_readonly)
 FROM public.user_info ui WHERE ui.id=recipient
 ON CONFLICT(occasion,"user") DO UPDATE SET
  is_editor=public.occasion_users.is_editor OR excluded.is_editor,
  is_editor_view=public.occasion_users.is_editor_view OR excluded.is_editor_view;
 UPDATE public.occasion_team_invitations SET accepted_by=recipient,accepted_at=now() WHERE id=invitation.id;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion_user','occasion',invitation.occasion,recipient::text,1)
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
 RETURNING public.client_aggregate_versions.version INTO version;
 -- Token acceptance is the command owner. Publish the normal profile revision
 -- and private impact, with the invitation record retaining the proved actor.
 PERFORM public.record_client_sync_commit_v1(invitation.occasion,'profile.team_invitation.accept','profile',
  jsonb_build_array(jsonb_build_object('entityType','occasion_user','entityId',recipient,'operation',CASE WHEN before_row IS NULL THEN 'insert' ELSE 'update' END,
    'safeLabel','Team invitation accepted','changedFields',jsonb_build_array('membership','rights'))),'{}'::text[],
  jsonb_build_array(jsonb_build_object('component','private_profile','userId',recipient)),'[]'::jsonb,
  CASE WHEN auth.uid() IS NULL THEN 'unknown' ELSE 'user' END,'Invited event team member accepted');
 RETURN jsonb_build_object('accepted',true,'newAccount',new_account,'link',(SELECT link FROM public.occasions WHERE id=invitation.occasion));
END $$;
REVOKE ALL ON FUNCTION public.accept_occasion_team_invitation(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_occasion_team_invitation(text,text) TO anon,authenticated;

-- Neutral default invitation content contains no account credential fields.
INSERT INTO public.email_templates(code,subject,html)
SELECT 'TEAM_INVITATION','Pozvánka ke správě akce - {{eventTitle}}',
 '<h2>Pozvánka do týmu akce {{eventTitle}}</h2><p>{{appName}} zve ke spolupráci na správě akce s oprávněním {{roleLabel}}.</p><p><a href="{{invitationUrl}}">Zobrazit a přijmout pozvánku</a></p><p>Pozvánka platí 14 dní. Přijetí vyžaduje přihlášení k pozvanému účtu nebo vytvoření nového účtu s vlastním heslem.</p>'
WHERE NOT EXISTS(SELECT 1 FROM public.email_templates WHERE code='TEAM_INVITATION'
 AND organization IS NULL AND unit IS NULL AND occasion IS NULL);


-- Existing team access notifications share no account-password transition.
INSERT INTO public.email_templates(code,subject,html)
SELECT 'TEAM_ACCESS_NOTICE','Přístup k akci - {{eventTitle}}',
 '<h2>Přístup k akci {{eventTitle}}</h2><p>V aplikaci {{appName}} je dostupná akce s oprávněním {{roleLabel}}.</p><p><a href="{{eventUrl}}">Otevřít správu akce</a></p><p>Přihlaste se svým účtem. Pokud heslo neznáte, použijte na přihlašovací stránce odkaz pro obnovu hesla. Tato zpráva heslo nemění.</p>'
WHERE NOT EXISTS(SELECT 1 FROM public.email_templates WHERE code='TEAM_ACCESS_NOTICE'
 AND organization IS NULL AND unit IS NULL AND occasion IS NULL);
