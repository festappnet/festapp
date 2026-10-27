-- Typed feature operations. Technical/service boundaries remain at their existing callers.
CREATE OR REPLACE FUNCTION public.can_author_forms(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.form_authoring_rule(public.get_is_editor_on_occasion(o.id),public.get_is_editor_on_unit(o.unit)) FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_author_forms(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_author_forms(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_form_catalog(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.form_catalog_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.can_read_orders(p_occasion),public.can_author_forms(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_form_catalog(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_form_catalog(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_copy_form_source(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.form_copy_source_rule((SELECT m.is_editor_view FROM public.occasion_users m WHERE m.occasion=o.id AND m."user"=auth.uid()),public.get_is_editor_view_on_unit(o.unit)) FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_copy_form_source(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_copy_form_source(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_copy_form_target(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_copy_form_target(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_copy_form_target(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_write_news(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_news(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_news(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_write_information(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_information(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_information(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_unit_information(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_view_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_information(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_information(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_write_unit_information(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_write_unit_information(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_unit_information(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_schedule(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_schedule(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_schedule(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_schedule_editor(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  AS $$
 SELECT public.get_is_editor_view_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_read_schedule_editor(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_schedule_editor(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_schedule_participants(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.schedule_participants_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.get_is_editor_on_occasion(p_occasion),public.get_is_admin_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_schedule_participants(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_schedule_participants(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_schedule_feedback(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.schedule_feedback_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.get_is_admin_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_schedule_feedback(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_schedule_feedback(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_speakers(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_speakers(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_speakers(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_speakers_editor(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  AS $$
 SELECT public.get_is_editor_view_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_read_speakers_editor(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_speakers_editor(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_service_items(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  AS $$
 SELECT public.get_is_manager_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_service_items(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_service_items(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_participant_contacts(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.participant_contacts_read_rule(public.get_is_editor_on_occasion(p_occasion),public.get_is_manager_on_occasion(p_occasion),public.get_is_approver_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_participant_contacts(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_participant_contacts(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_import_group_assignments(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.group_assignments_write_rule(public.get_is_editor_on_occasion(o.id),public.get_is_manager_on_occasion(o.id),public.get_is_admin_on_occasion(o.id),public.get_is_editor_on_unit(o.unit)) FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_import_group_assignments(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_import_group_assignments(bigint) TO authenticated,service_role;



CREATE OR REPLACE FUNCTION public.can_copy_inventory_target(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.inventory_copy_target_rule(public.can_write_orders(o.id),public.get_is_manager_on_unit(o.unit)) FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_copy_inventory_target(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_copy_inventory_target(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_activity_plan(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_activity_plan(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_activity_plan(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_activity_editor(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE  SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.map_editor_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.get_is_editor_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_activity_editor(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_activity_editor(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_group(p_occasion bigint,p_group bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.group_write_rule(public.get_is_editor_on_occasion(p_occasion),EXISTS(SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
 WHERE g.id=p_group AND g.occasion=p_occasion AND ug."user"=auth.uid() AND ug.is_admin),NOT public.is_demo_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_write_group(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_group(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_group_editor(p_occasion bigint,p_group bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.group_editor_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.get_is_editor_on_occasion(p_occasion),EXISTS(SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
 WHERE g.id=p_group AND g.occasion=p_occasion AND ug."user"=auth.uid() AND ug.is_admin));
$$;
REVOKE ALL ON FUNCTION public.can_read_group_editor(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_group_editor(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_groups_editor(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.map_editor_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.get_is_editor_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_groups_editor(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_groups_editor(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_places(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_places(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_places(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_move_map_place(p_occasion bigint,p_place bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.place_move_rule(public.get_is_editor_on_occasion(p_occasion),
 EXISTS(SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
 WHERE g.occasion=p_occasion AND g.place=p_place AND ug."user"=auth.uid() AND ug.is_admin),
 p.type='group' AND p.is_hidden,NOT public.is_demo_occasion(p_occasion))
 FROM public.places p WHERE p.id=p_place AND p.occasion=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_move_map_place(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_move_map_place(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_occasion_email_templates(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.email_template_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.can_read_orders(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_occasion_email_templates(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_occasion_email_templates(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_occasion_email_templates(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.email_template_write_rule(public.get_is_editor_on_occasion(p_occasion),public.can_write_orders(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_write_occasion_email_templates(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_occasion_email_templates(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_unit_email_templates(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.unit_template_read_rule(public.get_is_manager_on_unit(p_unit),public.get_is_editor_on_unit(p_unit),public.get_is_editor_view_on_unit(p_unit));
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_email_templates(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_email_templates(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_write_unit_email_templates(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_write_unit_email_templates(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_unit_email_templates(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_organization_email_templates(p_organization bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_admin_on_organization(p_organization);
$$;
REVOKE ALL ON FUNCTION public.can_manage_organization_email_templates(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_organization_email_templates(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_upload_occasion_media(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.occasion_media_upload_rule(public.get_is_editor_on_occasion(p_occasion),public.can_write_orders(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_upload_occasion_media(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_upload_occasion_media(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_upload_unit_media(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_upload_unit_media(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_upload_unit_media(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_unit_configuration(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_manage_unit_configuration(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_unit_configuration(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_unit_legal_profile(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit) AND NOT public.is_demo_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_manage_unit_legal_profile(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_unit_legal_profile(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_unit_administration(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_view_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_administration(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_administration(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_delete_schedule_feedback(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.get_is_admin_on_organization(o.organization) AND NOT public.is_demo_occasion(o.id) FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_delete_schedule_feedback(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_delete_schedule_feedback(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_delete_occasion_in_unit(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_delete_occasion_in_unit(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_delete_occasion_in_unit(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_delete_occasion(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.can_delete_occasion_in_unit(o.unit) FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_delete_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_delete_occasion(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_unit_bank_accounts(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_manage_unit_bank_accounts(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_unit_bank_accounts(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_unit_bank_accounts(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit) OR EXISTS(
 SELECT 1 FROM public.demo_occasions d JOIN public.occasions o ON o.id=d.occasion
 WHERE o.unit=p_unit AND public.can_read_demo_occasion(d.occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_bank_accounts(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_bank_accounts(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_occasion_editor_data(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND public.occasion_editor_read_rule(
   public.get_is_editor_view_on_occasion(p_occasion),public.get_is_manager_on_occasion(p_occasion),
   public.get_is_admin_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_occasion_editor_data(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_occasion_editor_data(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_upload_blueprint_background(p_occasion bigint,p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND CASE
   WHEN p_occasion IS NOT NULL AND p_unit IS NULL THEN public.blueprint_write_rule(
     public.get_is_editor_on_occasion(p_occasion),public.get_is_manager_on_occasion(p_occasion))
   WHEN p_unit IS NOT NULL AND p_occasion IS NULL THEN public.blueprint_write_rule(
     public.get_is_editor_on_unit(p_unit),public.get_is_manager_on_unit(p_unit))
   ELSE false END;
$$;
REVOKE ALL ON FUNCTION public.can_upload_blueprint_background(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_upload_blueprint_background(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_unit_app_landing(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.units unit WHERE unit.id=p_unit AND unit.organization IS NOT NULL
   AND public.unit_landing_read_rule(public.get_is_admin_on_organization(unit.organization),
     public.get_is_editor_view_on_unit(unit.id),public.get_is_editor_on_unit(unit.id),public.get_is_manager_on_unit(unit.id)));
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_app_landing(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_app_landing(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_manage_unit_app_landing(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.units unit WHERE unit.id=p_unit AND unit.organization IS NOT NULL
   AND public.get_is_admin_on_organization(unit.organization));
$$;
REVOKE ALL ON FUNCTION public.can_manage_unit_app_landing(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_unit_app_landing(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_unit_abuse_policy(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND public.unit_abuse_policy_read_rule(public.get_is_manager_on_unit(p_unit),public.get_is_editor_on_unit(p_unit));
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_abuse_policy(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_abuse_policy(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_client_activity(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 -- Organization admin includes the old occasion-admin alternative, which was
 -- that same role with an additional demo fence. Keep the raw tenant scope.
 SELECT EXISTS(SELECT 1 FROM public.occasions occasion WHERE occasion.id=p_occasion
   AND public.client_activity_read_rule(public.get_is_manager_on_occasion(occasion.id),
     public.get_is_manager_on_unit(occasion.unit),public.get_is_admin_on_organization(occasion.organization)));
$$;
REVOKE ALL ON FUNCTION public.can_read_client_activity(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_client_activity(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_occasion_client_commits(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.occasion_commit_read_rule(public.get_is_manager_on_occasion(p_occasion),public.get_is_admin_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_occasion_client_commits(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_occasion_client_commits(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_unit_client_commits(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_client_commits(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_client_commits(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_organization_client_commits(p_organization bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_admin_on_organization(p_organization);
$$;
REVOKE ALL ON FUNCTION public.can_read_organization_client_commits(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_organization_client_commits(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_client_commit(p_commit uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.client_commits commit WHERE commit.commit_id=p_commit
   AND public.client_commit_read_rule(
     commit.occasion IS NOT NULL AND public.can_read_occasion_client_commits(commit.occasion),
     commit.unit IS NOT NULL AND public.can_read_unit_client_commits(commit.unit),
     commit.organization IS NOT NULL AND public.can_read_organization_client_commits(commit.organization)));
$$;
REVOKE ALL ON FUNCTION public.can_read_client_commit(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_client_commit(uuid) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_private_client_sync(p_organization bigint,p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL
   AND EXISTS(SELECT 1 FROM public.occasion_users membership WHERE membership.occasion=p_occasion AND membership."user"=auth.uid())
   AND EXISTS(SELECT 1 FROM public.occasions occasion WHERE occasion.id=p_occasion AND occasion.organization=p_organization
     AND (NOT occasion.is_hidden OR public.get_is_editor_view_on_occasion(occasion.id)));
$$;
REVOKE ALL ON FUNCTION public.can_read_private_client_sync(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_private_client_sync(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_occasion_context_row(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND public.occasion_context_read_rule(
   public.get_is_editor_view_on_occasion(p_occasion),public.get_is_manager_on_occasion(p_occasion),
   EXISTS(SELECT 1 FROM public.occasion_users membership WHERE membership.occasion=p_occasion AND membership."user"=auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.can_read_occasion_context_row(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_occasion_context_row(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_group_data_security_v1(p_group bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.user_group_info group_info WHERE group_info.id=p_group
   AND public.group_data_read_rule(public.get_is_editor_view_on_occasion(group_info.occasion),
     EXISTS(SELECT 1 FROM public.user_groups membership WHERE membership."group"=group_info.id AND membership."user"=auth.uid())));
$$;
REVOKE ALL ON FUNCTION public.can_read_group_data_security_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_read_group_data_security_v1(bigint) TO authenticated,service_role;
ALTER FUNCTION public.can_read_group_data_security_v1(bigint) OWNER TO postgres;
CREATE OR REPLACE FUNCTION public.can_read_group_members(p_group bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.user_group_info group_info WHERE group_info.id=p_group
   AND public.group_members_read_rule(public.get_is_editor_view_on_occasion(group_info.occasion),public.get_is_editor_on_occasion(group_info.occasion),
     EXISTS(SELECT 1 FROM public.user_groups membership WHERE membership."group"=group_info.id AND membership."user"=auth.uid())));
$$;
REVOKE ALL ON FUNCTION public.can_read_group_members(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_group_members(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_news_data_security_v1(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.occasions occasion WHERE occasion.id=p_occasion
   AND public.news_data_read_rule(occasion.is_hidden IS FALSE AND occasion.is_open IS TRUE,auth.uid() IS NOT NULL,
     public.get_is_editor_view_on_occasion(occasion.id),public.get_is_manager_on_occasion(occasion.id),public.get_is_admin_on_occasion(occasion.id),
     EXISTS(SELECT 1 FROM public.occasion_users membership WHERE membership.occasion=occasion.id AND membership."user"=auth.uid())));
$$;
REVOKE ALL ON FUNCTION public.can_read_news_data_security_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_read_news_data_security_v1(bigint) TO anon,authenticated,service_role;
ALTER FUNCTION public.can_read_news_data_security_v1(bigint) OWNER TO postgres;
CREATE OR REPLACE FUNCTION public.can_materialize_public_occasion(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.is_service_role() OR EXISTS(SELECT 1 FROM public.occasions occasion WHERE occasion.id=p_occasion
   AND public.public_publication_actor_rule(public.get_is_editor_on_occasion(occasion.id),public.get_is_admin_on_occasion(occasion.id),
     occasion.unit IS NOT NULL AND public.get_is_editor_on_unit(occasion.unit)));
$$;
REVOKE ALL ON FUNCTION public.can_materialize_public_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_materialize_public_occasion(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_migrate_reviewed_legacy_blueprint(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND public.reviewed_blueprint_write_rule(public.can_write_blueprints(p_occasion),
   public.is_demo_occasion(p_occasion),membership.is_editor,membership.is_manager)
 FROM (SELECT 1) seed LEFT JOIN public.occasion_users membership ON membership.occasion=p_occasion AND membership."user"=auth.uid();
$$;
REVOKE ALL ON FUNCTION public.can_migrate_reviewed_legacy_blueprint(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_migrate_reviewed_legacy_blueprint(bigint) TO authenticated,service_role;

-- Icons are unit-editor authoring; copying an occasion keeps its narrower
-- target-manager requirement. Neither operation inherits create permissions.
CREATE OR REPLACE FUNCTION public.can_write_unit_icons(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_write_unit_icons(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_unit_icons(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_copy_occasion_target(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit);
$$;
REVOKE ALL ON FUNCTION public.can_copy_occasion_target(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_copy_occasion_target(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_unit_legal_profile(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.unit_legal_profile_read_rule(public.get_is_manager_on_unit(u.id),
   public.check_is_admin_of_organization(u.organization)) FROM public.units u WHERE u.id=p_unit),false);
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_legal_profile(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_legal_profile(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_occasion_directory(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.occasion_directory_read_rule(public.get_is_editor_view_on_occasion(p_occasion),public.can_read_orders(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_occasion_directory(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_occasion_directory(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_add_group_members(p_occasion bigint,p_group bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.group_members_write_rule(public.get_is_editor_on_occasion(p_occasion),
   EXISTS(SELECT 1 FROM public.user_groups m JOIN public.user_group_info g ON g.id=m."group"
     WHERE g.id=p_group AND g.occasion=p_occasion AND m."user"=auth.uid() AND m.is_admin));
$$;
REVOKE ALL ON FUNCTION public.can_add_group_members(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_add_group_members(bigint,bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_read_group_places(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.group_places_read_rule(auth.uid() IS NOT NULL,
   EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=auth.uid()),
   public.get_is_editor_on_occasion(p_occasion),public.get_is_editor_view_on_occasion(p_occasion),
   public.is_demo_occasion(p_occasion),public.can_read_orders(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_group_places(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_group_places(bigint) TO authenticated,service_role;

-- The historical occasion-only delete RPC was narrower than the entity
-- template API. Its adapter preserves that existing editor-only admission.
CREATE OR REPLACE FUNCTION public.can_delete_legacy_occasion_email_template(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_editor_on_occasion(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_delete_legacy_occasion_email_template(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_delete_legacy_occasion_email_template(bigint) TO postgres;

CREATE OR REPLACE FUNCTION public.can_manage_organization_settings(p_organization bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_admin_on_organization(p_organization);
$$;
REVOKE ALL ON FUNCTION public.can_manage_organization_settings(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_organization_settings(bigint) TO authenticated,service_role;

-- Administrative catalogue discovery deliberately includes raw unit roles
-- or any privileged membership of that unit's occasions. It is broader than
-- an authoring operation and never grants create/edit by itself.
CREATE OR REPLACE FUNCTION public.can_read_unit_occasion_catalog(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.unit_users m WHERE m.unit=p_unit AND m."user"=auth.uid()
    AND public.unit_discovery_rule(m.is_editor,m.is_manager,m.is_editor_view))
 OR EXISTS(SELECT 1 FROM public.occasions o JOIN public.occasion_users m ON m.occasion=o.id
    WHERE o.unit=p_unit AND m."user"=auth.uid()
    AND public.occasion_staff_navigation_rule(m.is_manager,m.is_editor,m.is_editor_view,m.is_editor_order,m.is_editor_order_view));
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_occasion_catalog(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_occasion_catalog(bigint) TO authenticated,service_role;

-- The pre-V212 catalogue admitted unit membership only. Preserve that
-- narrower public contract while sharing the raw unit discovery rule.
CREATE OR REPLACE FUNCTION public.can_read_legacy_unit_occasion_catalog(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.unit_discovery_rule(m.is_editor,m.is_manager,m.is_editor_view)
   FROM public.unit_users m WHERE m.unit=p_unit AND m."user"=auth.uid()),false);
$$;
REVOKE ALL ON FUNCTION public.can_read_legacy_unit_occasion_catalog(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_legacy_unit_occasion_catalog(bigint) TO authenticated,service_role;
