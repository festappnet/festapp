-- Explicit canonical ACLs and trusted search paths, preserving API role access.
BEGIN;
-- Source: database/functions/eshop/release_blueprint_holds_client_sync_v1.sql
-- Administrative release of temporary holds. Buyers still use select_spot.
CREATE OR REPLACE FUNCTION public.release_blueprint_holds_client_sync_v1(
 p_spots bigint[], p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); occ bigint; ids bigint[]; bp bigint; started jsonb; users uuid[]; fingerprint text;
BEGIN
 IF actor IS NULL OR coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>256 THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 SELECT min(b.occasion),min(s.blueprint) INTO occ,bp FROM eshop.spots s JOIN eshop.blueprints b ON b.id=s.blueprint WHERE s.id=ANY(p_spots);
 IF occ IS NULL OR public.can_write_orders(occ) IS NOT TRUE OR
  (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND blueprint=bp) <>
  cardinality(ARRAY(SELECT DISTINCT x FROM unnest(p_spots) x)) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM public.check_occasion_writable(occ);
 fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('spots',p_spots)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.blueprint.holds.release',occ,actor,fingerprint);
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM unnest(p_spots) requested
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(ids) AND (blueprint IS DISTINCT FROM bp OR order_product_ticket IS NOT NULL)) THEN
  RAISE check_violation USING MESSAGE='Spot is already ordered'; END IF;
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO users FROM public.occasion_users ou WHERE ou.occasion=occ;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now()
 WHERE id=ANY(ids) AND order_product_ticket IS NULL;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.blueprint.holds.release',
  jsonb_build_array(jsonb_build_object('entityType','spot','entityId',NULL,'operation','update','safeLabel','Temporary reservation released','changedFields',jsonb_build_array('reservation'))),
  users,jsonb_build_object('spotIds',to_jsonb(ids)));
END $$;
REVOKE ALL ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) TO authenticated;

-- Source: database/functions/security/application_function_acls.sql
-- Preserve the effective canonical API role matrix while making every ACL explicit.
REVOKE ALL ON FUNCTION public.delete_occasion_email_template(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_occasion_email_template(bigint,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_blueprint(uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_blueprint(uuid,uuid,bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_blueprint_for_edit(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_blueprint_for_edit(text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_form_for_edit(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_for_edit(text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_event_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_event_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_event_feedback_client_sync_v1(bigint,bigint,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_event_feedback_client_sync_v1(bigint,bigint,uuid,uuid) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_event_feedback_for_edit_client_sync_v1(bigint,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_event_feedback_for_edit_client_sync_v1(bigint,bigint,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_event_feedback_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_event_feedback_internal_v1(bigint,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.delete_exclusive_group_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_exclusive_group_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_exclusive_group_command_data_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_exclusive_group_command_data_v1(bigint) TO service_role;
REVOKE ALL ON FUNCTION public.get_exclusive_groups_for_edit_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_exclusive_groups_for_edit_v1(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_exclusive_group_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_exclusive_group_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.set_saved_program_client_sync_v1(bigint,bigint[],text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_saved_program_client_sync_v1(bigint,bigint[],text,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.set_saved_program_client_sync_v1_transactional(bigint,bigint[],text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_saved_program_client_sync_v1_transactional(bigint,bigint[],text,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.submit_event_feedback_client_sync_v1(bigint,bigint,text,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback_client_sync_v1(bigint,bigint,text,text,uuid,uuid) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.submit_event_feedback_internal_v1(bigint,text,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback_internal_v1(bigint,text,text,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.delete_owned_companion_internal_v1(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_owned_companion_internal_v1(bigint,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.delete_information_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_information_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_information_command_data_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_information_command_data_v1(bigint) TO service_role;
REVOKE ALL ON FUNCTION public.get_information_editor_bundle_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_information_editor_bundle_v1(bigint,text) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_information_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_information_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_path_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_path_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_place_type_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_place_type_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_map_editor_bundle_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_map_editor_bundle_v1(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_path_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_path_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_place_type_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_place_type_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_news_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_news_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_news_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_news_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.check_is_admin_of_organization(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.check_is_admin_of_organization(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_all_occasions_for_edit_v212(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_all_occasions_for_edit_v212(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_available_occasions(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_available_occasions(bigint,bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_public_occasions(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_public_occasions(bigint,bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_unit_for_edit(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_for_edit(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_all_occasions_for_edit(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_all_occasions_for_edit(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_all_occasions_for_edit_v182(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_all_occasions_for_edit_v182(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_summary(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_summary(uuid,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.resolve_scanner_conflict(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_scanner_conflict(uuid,text) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.scan_ticket_v2(text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.scan_ticket_v2(text,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.scanner_session_internal(uuid,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.open_scanner_session(text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.open_scanner_session(text,bigint,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.revoke_scanner_session(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_scanner_session(uuid,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_settings(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_settings(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.update_scanner_settings(bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_scanner_settings(bigint,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.prepare_scanner_snapshot(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_scanner_snapshot(uuid,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_snapshot_page(uuid,text,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_snapshot_page(uuid,text,uuid,integer) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_counseling_slots_client_sync_v1(bigint,timestamp with time zone,timestamp with time zone,integer,bigint,integer,text,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_counseling_slots_client_sync_v1(bigint,timestamp with time zone,timestamp with time zone,integer,bigint,integer,text,integer,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_counseling_slots_domain_command_internal_v1(bigint,timestamp with time zone,timestamp with time zone,integer,bigint,integer,text,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_counseling_slots_domain_command_internal_v1(bigint,timestamp with time zone,timestamp with time zone,integer,bigint,integer,text,integer,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(bigint,timestamp with time zone,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(bigint,timestamp with time zone,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_speaker_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_speaker_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_speaker_topic_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_speaker_topic_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_speaker_command_data_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_speaker_command_data_v1(bigint) TO service_role;
REVOKE ALL ON FUNCTION public.get_speakers_editor_bundle_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_speakers_editor_bundle_v1(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_speaker_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_speaker_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_speaker_topic_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_speaker_topic_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text) TO service_role;
REVOKE ALL ON FUNCTION public.get_unit_edit_data_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_edit_data_v1(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_unit_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_unit_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.update_unit_internal_v1(bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_unit_internal_v1(bigint,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.get_is_editor_on_occasion(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_editor_on_occasion(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_is_editor_on_unit(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_editor_on_unit(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_is_editor_order_on_occasion(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_editor_order_on_occasion(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_is_editor_order_view_on_occasion(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_editor_order_view_on_occasion(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_is_editor_view_on_occasion(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_editor_view_on_occasion(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_is_manager_on_occasion(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_manager_on_occasion(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_is_manager_on_unit(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_manager_on_unit(bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.add_user_to_occasion_client_sync_v1(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion_client_sync_v1(bigint,uuid,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_companion_client_sync_v1(bigint,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_companion_client_sync_v1(bigint,text,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_companion_in_organization_internal_v1(bigint,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_companion_in_organization_internal_v1(bigint,bigint,uuid,text) TO service_role;
REVOKE ALL ON FUNCTION public.create_occasion_user_client_sync_v1(bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_occasion_user_client_sync_v1(bigint,uuid,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_occasion_user_command_data_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_user_command_data_v1(bigint,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb) TO authenticated,service_role;

COMMIT;
