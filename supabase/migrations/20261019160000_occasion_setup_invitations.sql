-- Canonical sources: occasion_setup/invitations.sql; emails/email_queue.sql (email_intent_valid), emails/email_domain.sql (reset_password_and_enqueue_email), users/get_occasion_users_for_edit.sql (get_occasion_sign_in_email_statuses)
BEGIN;

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


CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.occasion_team_invitations i
   JOIN public.occasions o ON o.id=i.occasion AND o.unit=i.unit AND o.organization=i.organization
   JOIN public.unit_users uu ON uu.unit=i.unit AND uu."user"=i.created_by AND uu.is_manager
   WHERE i.message_id=p_message.message_id AND i.accepted_at IS NULL AND i.expires_at>now()
    AND i.email=p_message.recipient AND i.occasion=p_message.occasion AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id' AND h.warning_code IS NOT NULL
      AND c.state IN ('connected','degraded') AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.reset_password_and_enqueue_email(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_answer jsonb; v_context jsonb; v_email text; v_result jsonb; v_existing public.email_messages; v_password_version text;
BEGIN
 -- Reuse the existing hierarchical permission check, including elevated-account protections.
 IF auth.uid() IS NULL OR NOT coalesce(public.get_can_reset_user_password(p_user),false) THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sign-in:'||p_user::text||':'||p_occasion::text,0));
 -- Team invitations never own a password transition, including older clients.
 PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user FOR SHARE;
 IF EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user
   AND (is_editor OR is_editor_view OR is_manager)) THEN
  RAISE insufficient_privilege USING MESSAGE='Team invitations cannot reset account passwords'; END IF;
 SELECT * INTO v_existing FROM public.email_messages WHERE recipient_user=p_user AND occasion=p_occasion AND message_kind='sign_in' AND (dedupe_key=p_dedupe OR (workflow_state IN ('pending','preparing','sending','retry_wait','unknown','accepted') AND expires_at>now())) ORDER BY id DESC LIMIT 1;
 IF v_existing.id IS NOT NULL THEN
  RETURN jsonb_build_object('message_id',v_existing.message_id,'replayed',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user) THEN RAISE EXCEPTION 'user_not_in_occasion'; END IF;
 v_answer:=public.reset_user_password(p_user,p_password);
 IF v_answer->>'code'<>'200' THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 SELECT jsonb_build_object('organization',organization,'occasion',id,'unit',unit,'recipient_user',p_user) INTO v_context FROM public.occasions WHERE id=p_occasion;
 v_email:=public.get_user_delivery_email(p_user);
 SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') INTO v_password_version FROM auth.users WHERE id=p_user;
 v_result:=public.enqueue_email('sign_in',v_context,v_email,jsonb_build_object('password_version',v_password_version,'content_hash',p_content_hash),p_dedupe,'SIGN_IN_CODE',now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now() WHERE message_id=(v_result->>'message_id')::uuid;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_occasion_sign_in_email_statuses(
  p_occasion bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT COALESCE(public.get_is_editor_view_on_occasion(p_occasion), false)
     AND NOT COALESCE(public.get_is_editor_order_view_on_occasion(p_occasion), false) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  WITH evidence AS (
    SELECT le.recipient_user AS "user",le.created_at AS sent_at
    FROM public.log_emails le
    JOIN public.email_templates et ON et.id::text = le.template
    WHERE le.occasion = p_occasion
      AND le.recipient_user IS NOT NULL
      AND et.code = 'SIGN_IN_CODE'
    UNION ALL
    SELECT m.recipient_user,m.accepted_at FROM public.email_messages m
    WHERE m.occasion=p_occasion AND (m.message_kind='sign_in' OR (m.message_kind='custom' AND m.code='TEAM_ACCESS_NOTICE'))
      AND m.recipient_user IS NOT NULL AND m.accepted_at IS NOT NULL
    UNION ALL
    SELECT i.accepted_by,m.accepted_at FROM public.occasion_team_invitations i
    JOIN public.email_messages m ON m.message_id=i.message_id
    WHERE i.occasion=p_occasion AND i.accepted_by IS NOT NULL AND m.accepted_at IS NOT NULL
  ), accepted AS (
    SELECT "user",count(*)::integer send_count,min(sent_at) first_sent_at,max(sent_at) last_sent_at FROM evidence GROUP BY "user"
  )
  SELECT COALESCE(
    jsonb_agg(to_jsonb(accepted) ORDER BY accepted."user"),
    '[]'::jsonb
  )
  INTO v_result
  FROM accepted;

  RETURN v_result;
END;
$$;
NOTIFY pgrst, 'reload schema';
COMMIT;
