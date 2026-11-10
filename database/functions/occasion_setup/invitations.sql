-- Setup selects confirmed recipients; the people owner executes their commands.
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
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
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
