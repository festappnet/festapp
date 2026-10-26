-- Private, immutable expression rules over verified facts. Resource predicates load
-- facts from live tables; the context owner reuses rows it already loaded in
-- the same request. Callers cannot execute these with fabricated role facts.
-- These expressions have no table lookup, mutable call, definer privilege or
-- unqualified function reference. Omitting SET lets PostgreSQL inline them.
-- Transactional command helpers keep their explicit search_path contract.
CREATE OR REPLACE FUNCTION public.active_membership(p_member boolean,p_demo boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT NOT p_demo AND coalesce(p_member,false);
$$;
CREATE OR REPLACE FUNCTION public.readable_membership(p_member boolean,p_demo boolean,p_demo_read boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_demo_read OR public.active_membership(p_member,p_demo);
$$;
CREATE OR REPLACE FUNCTION public.order_read_rule(p_member boolean,p_demo boolean,p_demo_read boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT public.readable_membership(p_member,p_demo,p_demo_read);
$$;
CREATE OR REPLACE FUNCTION public.order_write_rule(p_member boolean,p_demo boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT public.active_membership(p_member,p_demo);
$$;
CREATE OR REPLACE FUNCTION public.occasion_create_rule(p_manager boolean,p_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_manager OR p_editor;
$$;
CREATE OR REPLACE FUNCTION public.occasion_edit_rule(p_current_unit_editor boolean,p_target_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_current_unit_editor AND p_target_unit_editor;
$$;
CREATE OR REPLACE FUNCTION public.order_delete_rule(p_unit_manager boolean,p_unit_editor boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_unit_manager OR p_unit_editor OR p_admin;
$$;
CREATE OR REPLACE FUNCTION public.ticket_layout_rule(p_authenticated boolean,p_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_authenticated AND coalesce(p_unit_editor,false);
$$;
CREATE OR REPLACE FUNCTION public.map_editor_read_rule(p_viewer boolean,p_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_viewer OR p_editor;
$$;
CREATE OR REPLACE FUNCTION public.occasion_users_write_rule(p_manager boolean,p_admin boolean,p_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_manager OR p_admin OR p_unit_editor;
$$;
REVOKE ALL ON FUNCTION public.active_membership(boolean,boolean),
 public.readable_membership(boolean,boolean,boolean),
 public.order_read_rule(boolean,boolean,boolean),
 public.order_write_rule(boolean,boolean),
 public.occasion_create_rule(boolean,boolean),
 public.occasion_edit_rule(boolean,boolean),
 public.order_delete_rule(boolean,boolean,boolean),
 public.ticket_layout_rule(boolean,boolean),
 public.map_editor_read_rule(boolean,boolean),
 public.occasion_users_write_rule(boolean,boolean,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
-- Historical SECURITY DEFINER boundaries are owned by postgres; granting this
-- trusted owner does not grant its member roles (anon/authenticated) execution.
GRANT EXECUTE ON FUNCTION public.active_membership(boolean,boolean),
 public.readable_membership(boolean,boolean,boolean),
 public.order_read_rule(boolean,boolean,boolean),
 public.order_write_rule(boolean,boolean),
 public.occasion_create_rule(boolean,boolean),
 public.occasion_edit_rule(boolean,boolean),
 public.order_delete_rule(boolean,boolean,boolean),
 public.ticket_layout_rule(boolean,boolean),
 public.map_editor_read_rule(boolean,boolean),
 public.occasion_users_write_rule(boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.unit_users_read_rule(p_manager boolean,p_editor boolean,p_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_manager,false) OR coalesce(p_editor,false) OR coalesce(p_viewer,false);
$$;
CREATE OR REPLACE FUNCTION public.participant_manage_rule(p_manager boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_manager OR p_admin;
$$;
CREATE OR REPLACE FUNCTION public.administration_navigation_rule(p_demo_read boolean,p_editor boolean,p_manager boolean,p_unit_viewer boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_demo_read OR p_editor OR p_manager OR coalesce(p_unit_viewer,false) OR p_admin;
$$;
REVOKE ALL ON FUNCTION public.unit_users_read_rule(boolean,boolean,boolean),
 public.participant_manage_rule(boolean,boolean),
 public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.unit_users_read_rule(boolean,boolean,boolean),
 public.participant_manage_rule(boolean,boolean),
 public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean) TO postgres;

-- Feature policies consume the same verified, request-local membership facts.
CREATE OR REPLACE FUNCTION public.form_authoring_rule(p_editor boolean,p_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_editor OR p_unit_editor; $$;
CREATE OR REPLACE FUNCTION public.form_catalog_read_rule(p_viewer boolean,p_order_reader boolean,p_author boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_viewer OR p_order_reader OR p_author; $$;
CREATE OR REPLACE FUNCTION public.form_copy_source_rule(p_viewer boolean,p_unit_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_viewer,false) OR coalesce(p_unit_viewer,false); $$;
CREATE OR REPLACE FUNCTION public.scanner_settings_rule(p_authenticated boolean,p_editor boolean,p_order_writer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_authenticated AND (p_editor OR p_order_writer); $$;
CREATE OR REPLACE FUNCTION public.reception_enabled(p_features jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT pg_catalog.jsonb_path_exists(coalesce(p_features,'[]'::jsonb),'$[*] ? (@.code == "reception" && @.is_enabled == true)');
$$;
CREATE OR REPLACE FUNCTION public.reception_use_rule(p_enabled boolean,p_receptionist boolean,p_manager boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_enabled AND (coalesce(p_receptionist,false) OR p_manager OR p_admin); $$;
REVOKE ALL ON FUNCTION public.form_authoring_rule(boolean,boolean),public.form_catalog_read_rule(boolean,boolean,boolean),
 public.form_copy_source_rule(boolean,boolean),public.scanner_settings_rule(boolean,boolean,boolean),
 public.reception_enabled(jsonb),public.reception_use_rule(boolean,boolean,boolean,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.form_authoring_rule(boolean,boolean),public.form_catalog_read_rule(boolean,boolean,boolean),
 public.form_copy_source_rule(boolean,boolean),public.scanner_settings_rule(boolean,boolean,boolean),
 public.reception_enabled(jsonb),public.reception_use_rule(boolean,boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.schedule_participants_read_rule(p_viewer boolean,p_editor boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_viewer OR p_editor OR p_admin; $$;
REVOKE ALL ON FUNCTION public.schedule_participants_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.schedule_participants_read_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.schedule_feedback_read_rule(p_viewer boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_viewer OR p_admin; $$;
REVOKE ALL ON FUNCTION public.schedule_feedback_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.schedule_feedback_read_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.participant_contacts_read_rule(p_editor boolean,p_manager boolean,p_approver boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_editor OR p_manager OR p_approver; $$;
REVOKE ALL ON FUNCTION public.participant_contacts_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.participant_contacts_read_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.group_assignments_write_rule(p_editor boolean,p_manager boolean,p_admin boolean,p_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_editor OR public.occasion_users_write_rule(p_manager,p_admin,p_unit_editor); $$;
REVOKE ALL ON FUNCTION public.group_assignments_write_rule(boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.group_assignments_write_rule(boolean,boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.blueprint_write_rule(p_editor boolean,p_manager boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_editor OR p_manager; $$;
REVOKE ALL ON FUNCTION public.blueprint_write_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.blueprint_write_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.inventory_copy_target_rule(p_order_writer boolean,p_unit_manager boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_order_writer OR p_unit_manager; $$;
REVOKE ALL ON FUNCTION public.inventory_copy_target_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.inventory_copy_target_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.group_write_rule(p_editor boolean,p_group_admin boolean,p_writable boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_writable AND (p_editor OR coalesce(p_group_admin,false)); $$;
REVOKE ALL ON FUNCTION public.group_write_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.group_write_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.group_editor_read_rule(p_viewer boolean,p_editor boolean,p_group_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_viewer OR p_editor OR coalesce(p_group_admin,false); $$;
REVOKE ALL ON FUNCTION public.group_editor_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.group_editor_read_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.place_move_rule(p_editor boolean,p_group_admin boolean,p_private_place boolean,p_writable boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_writable AND (p_editor OR (coalesce(p_group_admin,false) AND p_private_place)); $$;
REVOKE ALL ON FUNCTION public.place_move_rule(boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.place_move_rule(boolean,boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.email_template_read_rule(p_viewer boolean,p_order_reader boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_viewer OR p_order_reader; $$;
REVOKE ALL ON FUNCTION public.email_template_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.email_template_read_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.email_template_write_rule(p_editor boolean,p_order_writer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_editor OR p_order_writer; $$;
REVOKE ALL ON FUNCTION public.email_template_write_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.email_template_write_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.unit_template_read_rule(p_manager boolean,p_editor boolean,p_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_manager OR p_editor OR coalesce(p_viewer,false); $$;
REVOKE ALL ON FUNCTION public.unit_template_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.unit_template_read_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.occasion_media_upload_rule(p_editor boolean,p_order_writer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_editor OR p_order_writer; $$;
REVOKE ALL ON FUNCTION public.occasion_media_upload_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.occasion_media_upload_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.companion_assignment_rule(p_authenticated boolean,p_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_authenticated AND p_editor; $$;
REVOKE ALL ON FUNCTION public.companion_assignment_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.companion_assignment_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.occasion_editor_read_rule(p_viewer boolean,p_manager boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_viewer,false) OR coalesce(p_manager,false) OR coalesce(p_admin,false);
$$;
REVOKE ALL ON FUNCTION public.occasion_editor_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.occasion_editor_read_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.unit_landing_read_rule(p_admin boolean,p_viewer boolean,p_editor boolean,p_manager boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_admin,false) OR coalesce(p_viewer,false) OR coalesce(p_editor,false) OR coalesce(p_manager,false);
$$;
REVOKE ALL ON FUNCTION public.unit_landing_read_rule(boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.unit_landing_read_rule(boolean,boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.unit_abuse_policy_read_rule(p_manager boolean,p_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_manager,false) OR coalesce(p_editor,false); $$;
REVOKE ALL ON FUNCTION public.unit_abuse_policy_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.unit_abuse_policy_read_rule(boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.client_activity_read_rule(p_manager boolean,p_unit_manager boolean,p_organization_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_manager,false) OR coalesce(p_unit_manager,false) OR coalesce(p_organization_admin,false);
$$;
REVOKE ALL ON FUNCTION public.client_activity_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.client_activity_read_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.occasion_commit_read_rule(p_manager boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_manager,false) OR coalesce(p_admin,false); $$;
REVOKE ALL ON FUNCTION public.occasion_commit_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.occasion_commit_read_rule(boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.client_commit_read_rule(p_occasion_access boolean,p_unit_access boolean,p_organization_access boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_occasion_access,false) OR coalesce(p_unit_access,false) OR coalesce(p_organization_access,false);
$$;
REVOKE ALL ON FUNCTION public.client_commit_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.client_commit_read_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.occasion_context_read_rule(p_viewer boolean,p_manager boolean,p_member boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_viewer,false) OR coalesce(p_manager,false) OR coalesce(p_member,false); $$;
REVOKE ALL ON FUNCTION public.occasion_context_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.occasion_context_read_rule(boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.group_data_read_rule(p_viewer boolean,p_member boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_viewer,false) OR coalesce(p_member,false); $$;
REVOKE ALL ON FUNCTION public.group_data_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.group_data_read_rule(boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.group_members_read_rule(p_viewer boolean,p_editor boolean,p_member boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_viewer,false) OR coalesce(p_editor,false) OR coalesce(p_member,false); $$;
REVOKE ALL ON FUNCTION public.group_members_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.group_members_read_rule(boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.news_data_read_rule(p_public boolean,p_authenticated boolean,p_viewer boolean,p_manager boolean,p_admin boolean,p_member boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT p_public OR p_authenticated AND (coalesce(p_viewer,false) OR coalesce(p_manager,false) OR coalesce(p_admin,false) OR coalesce(p_member,false));
$$;
REVOKE ALL ON FUNCTION public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.public_publication_actor_rule(p_editor boolean,p_admin boolean,p_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_editor,false) OR coalesce(p_admin,false) OR coalesce(p_unit_editor,false); $$;
REVOKE ALL ON FUNCTION public.public_publication_actor_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.public_publication_actor_rule(boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.reviewed_blueprint_write_rule(p_regular boolean,p_demo boolean,p_raw_editor boolean,p_raw_manager boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_regular OR p_demo AND public.blueprint_write_rule(coalesce(p_raw_editor,false),coalesce(p_raw_manager,false)); $$;
REVOKE ALL ON FUNCTION public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.event_attendance_read_rule(p_event_allowed boolean,p_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_event_allowed,false) OR coalesce(p_viewer,false); $$;
REVOKE ALL ON FUNCTION public.event_attendance_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.event_attendance_read_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.unit_legal_profile_read_rule(p_manager boolean,p_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_manager,false) OR coalesce(p_admin,false); $$;
REVOKE ALL ON FUNCTION public.unit_legal_profile_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.unit_legal_profile_read_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.occasion_directory_read_rule(p_viewer boolean,p_order_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_viewer,false) OR coalesce(p_order_viewer,false); $$;
REVOKE ALL ON FUNCTION public.occasion_directory_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.occasion_directory_read_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.unit_discovery_rule(p_editor boolean,p_manager boolean,p_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_editor,false) OR coalesce(p_manager,false) OR coalesce(p_viewer,false); $$;
REVOKE ALL ON FUNCTION public.unit_discovery_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.unit_discovery_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.occasion_staff_navigation_rule(p_manager boolean,p_editor boolean,p_viewer boolean,p_order_editor boolean,p_order_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_manager,false) OR coalesce(p_editor,false) OR coalesce(p_viewer,false) OR coalesce(p_order_editor,false) OR coalesce(p_order_viewer,false); $$;
REVOKE ALL ON FUNCTION public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.operator_occasion_discovery_rule(p_unit_editor boolean,p_unit_manager boolean,p_unit_viewer boolean,p_manager boolean,p_editor boolean,p_viewer boolean,p_order_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_unit_editor,false) OR coalesce(p_unit_manager,false) OR coalesce(p_unit_viewer,false) OR coalesce(p_manager,false) OR coalesce(p_editor,false) OR coalesce(p_viewer,false) OR coalesce(p_order_viewer,false); $$;
REVOKE ALL ON FUNCTION public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.context_private_access_rule(p_viewer boolean,p_order_viewer boolean,p_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_viewer,false) OR coalesce(p_order_viewer,false) OR coalesce(p_unit_editor,false); $$;
REVOKE ALL ON FUNCTION public.context_private_access_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.context_private_access_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.unit_workspace_navigation_rule(p_listed boolean,p_editor boolean,p_manager boolean,p_viewer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_listed,false) OR coalesce(p_editor,false) OR coalesce(p_manager,false) OR coalesce(p_viewer,false); $$;
REVOKE ALL ON FUNCTION public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean) TO postgres;

-- Adding members preserves the older group-admin alternative, independently
-- from editing a group's configuration and its demo write restriction.
CREATE OR REPLACE FUNCTION public.group_members_write_rule(p_editor boolean,p_group_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_editor,false) OR coalesce(p_group_admin,false); $$;
REVOKE ALL ON FUNCTION public.group_members_write_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.group_members_write_rule(boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.group_places_read_rule(p_authenticated boolean,p_member boolean,p_editor boolean,p_viewer boolean,p_demo boolean,p_demo_read boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_authenticated,false) AND (coalesce(p_member,false) OR coalesce(p_editor,false) OR coalesce(p_viewer,false))
   AND (NOT p_demo OR coalesce(p_demo_read,false));
$$;
REVOKE ALL ON FUNCTION public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.occasion_list_read_rule(p_viewer boolean,p_unit_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_viewer,false) OR coalesce(p_unit_editor,false); $$;
REVOKE ALL ON FUNCTION public.occasion_list_read_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.occasion_list_read_rule(boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.demo_own_work_rule(p_unit_manager boolean,p_unit_editor boolean,p_occasion_manager boolean,p_occasion_editor boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT public.occasion_create_rule(p_unit_manager,p_unit_editor) OR public.blueprint_write_rule(p_occasion_editor,p_occasion_manager);
$$;
REVOKE ALL ON FUNCTION public.demo_own_work_rule(boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.demo_own_work_rule(boolean,boolean,boolean,boolean) TO postgres;

-- Closed-occasion enrolment intentionally combines the target user's raw
-- unit roles with the actor's occasion-admin fact. Role propagation itself
-- keeps the original unit flags and is not a new permission store.
CREATE OR REPLACE FUNCTION public.closed_occasion_enrolment_rule(p_target_manager boolean,p_target_editor boolean,p_target_viewer boolean,p_actor_admin boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT public.unit_discovery_rule(p_target_editor,p_target_manager,p_target_viewer) OR coalesce(p_actor_admin,false);
$$;
REVOKE ALL ON FUNCTION public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean) TO postgres;

-- Navigation admission preserves the original flag; data operations remain separate.
CREATE OR REPLACE FUNCTION public.schedule_entry_navigation_rule(p_approver boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_approver,false); $$;
REVOKE ALL ON FUNCTION public.schedule_entry_navigation_rule(boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.schedule_entry_navigation_rule(boolean) TO postgres;

-- Navigation admission preserves the original flag; data operations remain separate.
CREATE OR REPLACE FUNCTION public.cleaning_crew_navigation_rule(p_crew boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_crew,false); $$;
REVOKE ALL ON FUNCTION public.cleaning_crew_navigation_rule(boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.cleaning_crew_navigation_rule(boolean) TO postgres;
