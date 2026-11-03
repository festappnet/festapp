BEGIN;

-- Security-only expansion for the existing client_sync_v1 write seam. This
-- migration changes no function body, grant, data or tenant capability. The
-- exact signature gate prevents an unnoticed overload from escaping the
-- canonical SECURITY DEFINER search-path contract.
DO $preflight$
DECLARE
  v_names constant text[] := ARRAY[
    'add_user_to_occasion_client_sync_v1',
    'create_occasion_client_sync_v1',
    'create_occasion_user_client_sync_v1',
    'create_service_item_client_sync_v1',
    'delete_event_client_sync_v1',
    'delete_exclusive_group_client_sync_v1',
    'delete_icon_client_sync_v1',
    'delete_information_client_sync_v1',
    'delete_news_client_sync_v1',
    'delete_occasion_client_sync_v1',
    'delete_occasion_user_client_sync_v1',
    'delete_path_client_sync_v1',
    'delete_place_client_sync_v1',
    'delete_place_type_client_sync_v1',
    'delete_service_item_client_sync_v1',
    'delete_unit_user_client_sync_v1',
    'delete_user_group_client_sync_v1',
    'duplicate_occasion_client_sync_v1',
    'game_guess_client_sync_v1',
    'game_update_settings_client_sync_v1',
    'import_profiles_client_sync_v1',
    'import_users_from_tickets_client_sync_v1',
    'mark_news_read_client_sync_v1',
    'move_place_client_sync_v1',
    'publish_news_client_sync_v1',
    'replace_group_assignments_client_sync_v1',
    'save_event_client_sync_v1',
    'save_exclusive_group_client_sync_v1',
    'save_icon_client_sync_v1',
    'save_information_client_sync_v1',
    'save_news_client_sync_v1',
    'save_occasion_client_sync_v1',
    'save_path_client_sync_v1',
    'save_place_client_sync_v1',
    'save_place_type_client_sync_v1',
    'save_profile_client_sync_v1',
    'save_unit_client_sync_v1',
    'save_user_group_client_sync_v1',
    'set_event_attendance_client_sync_v1',
    'set_saved_program_client_sync_v1',
    'update_service_item_client_sync_v1'
  ];
  v_signatures integer;
  v_distinct_names integer;
BEGIN
  SELECT count(*), count(DISTINCT p.proname)
  INTO v_signatures, v_distinct_names
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = ANY(v_names);

  IF v_signatures <> cardinality(v_names)
    OR v_distinct_names <> cardinality(v_names)
  THEN
    RAISE EXCEPTION 'unexpected client_sync RPC signature count: % signatures / % names',
      v_signatures, v_distinct_names;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(v_names)
      AND NOT p.prosecdef
  ) THEN
    RAISE EXCEPTION 'client_sync RPC lost SECURITY DEFINER';
  END IF;
END
$preflight$;

ALTER FUNCTION public.add_user_to_occasion_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.create_occasion_client_sync_v1(p_command_id uuid, p_config jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.create_occasion_user_client_sync_v1(p_occasion bigint, p_command_id uuid, p_profile jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.create_service_item_client_sync_v1(p_occasion bigint, p_type text, p_code text, p_title text, p_reference bigint, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_event_client_sync_v1(p_occasion bigint, p_event_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_exclusive_group_client_sync_v1(p_occasion bigint, p_group_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_icon_client_sync_v1(p_occasion bigint, p_icon_id bigint, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_information_client_sync_v1(p_occasion bigint, p_information_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_news_client_sync_v1(p_occasion bigint, p_news_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_occasion_client_sync_v1(p_occasion bigint, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_occasion_user_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_path_client_sync_v1(p_occasion bigint, p_path_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_place_client_sync_v1(p_occasion bigint, p_place_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_place_type_client_sync_v1(p_occasion bigint, p_place_type_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_service_item_client_sync_v1(p_occasion bigint, p_type text, p_code text, p_force boolean, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_unit_user_client_sync_v1(p_user uuid, p_unit bigint, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.delete_user_group_client_sync_v1(p_occasion bigint, p_group_id bigint, p_command_id uuid, p_expected_version bigint) SET search_path TO public, extensions;
ALTER FUNCTION public.duplicate_occasion_client_sync_v1(p_occasion bigint, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.game_guess_client_sync_v1(p_checkpoint bigint, p_guess text, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.game_update_settings_client_sync_v1(p_occasion bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.import_profiles_client_sync_v1(p_occasion bigint, p_command_id uuid, p_rows jsonb, p_delete_user_ids jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.import_users_from_tickets_client_sync_v1(p_occasion bigint, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.mark_news_read_client_sync_v1(p_occasion bigint, p_news_id bigint, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.move_place_client_sync_v1(p_occasion bigint, p_place_id bigint, p_command_id uuid, p_expected_version bigint, p_lat double precision, p_lng double precision) SET search_path TO public, extensions;
ALTER FUNCTION public.publish_news_client_sync_v1(p_occasion bigint, p_add_to_news boolean, p_news_message text, p_send_notification boolean, p_notification_heading text, p_notification_content text, p_recipients jsonb, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.replace_group_assignments_client_sync_v1(p_occasion bigint, p_command_id uuid, p_assignments jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_event_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_event jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_exclusive_group_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_group jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_icon_client_sync_v1(p_occasion bigint, p_command_id uuid, p_icon jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_information_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_information jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_news_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_news jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_occasion_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_config jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_path_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_path jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_place_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_place jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_place_type_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_place_type jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_profile_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint, p_profile jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_unit_client_sync_v1(p_unit bigint, p_command_id uuid, p_expected_version bigint, p_unit_data jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.save_user_group_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_group jsonb) SET search_path TO public, extensions;
ALTER FUNCTION public.set_event_attendance_client_sync_v1(p_event_id bigint, p_participant_id uuid, p_action text, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.set_saved_program_client_sync_v1(p_occasion bigint, p_event_ids bigint[], p_mode text, p_command_id uuid) SET search_path TO public, extensions;
ALTER FUNCTION public.update_service_item_client_sync_v1(p_occasion bigint, p_type text, p_code text, p_title text, p_reference bigint, p_command_id uuid) SET search_path TO public, extensions;

DO $postcondition$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(ARRAY[
        'add_user_to_occasion_client_sync_v1', 'create_occasion_client_sync_v1',
        'create_occasion_user_client_sync_v1', 'create_service_item_client_sync_v1',
        'delete_event_client_sync_v1', 'delete_exclusive_group_client_sync_v1',
        'delete_icon_client_sync_v1', 'delete_information_client_sync_v1',
        'delete_news_client_sync_v1', 'delete_occasion_client_sync_v1',
        'delete_occasion_user_client_sync_v1', 'delete_path_client_sync_v1',
        'delete_place_client_sync_v1', 'delete_place_type_client_sync_v1',
        'delete_service_item_client_sync_v1', 'delete_unit_user_client_sync_v1',
        'delete_user_group_client_sync_v1', 'duplicate_occasion_client_sync_v1',
        'game_guess_client_sync_v1', 'game_update_settings_client_sync_v1',
        'import_profiles_client_sync_v1', 'import_users_from_tickets_client_sync_v1',
        'mark_news_read_client_sync_v1', 'move_place_client_sync_v1',
        'publish_news_client_sync_v1', 'replace_group_assignments_client_sync_v1',
        'save_event_client_sync_v1', 'save_exclusive_group_client_sync_v1',
        'save_icon_client_sync_v1', 'save_information_client_sync_v1',
        'save_news_client_sync_v1', 'save_occasion_client_sync_v1',
        'save_path_client_sync_v1', 'save_place_client_sync_v1',
        'save_place_type_client_sync_v1', 'save_profile_client_sync_v1',
        'save_unit_client_sync_v1', 'save_user_group_client_sync_v1',
        'set_event_attendance_client_sync_v1', 'set_saved_program_client_sync_v1',
        'update_service_item_client_sync_v1'
      ])
      AND (
        NOT p.prosecdef
        OR NOT COALESCE(
          p.proconfig @> ARRAY['search_path=public, extensions'],
          false
        )
      )
  ) THEN
    RAISE EXCEPTION 'non-canonical client_sync RPC overload remains';
  END IF;
END
$postcondition$;

COMMIT;
