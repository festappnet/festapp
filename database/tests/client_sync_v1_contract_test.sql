BEGIN;

DO $$
DECLARE
  v_missing text[];
  v_unsecured text[];
  v_trigger_count integer;
  v_before bigint;
  v_after bigint;
BEGIN
  SELECT array_agg(expected.name) INTO v_missing
  FROM unnest(ARRAY[
    'get_private_client_sync_v1','get_client_commits_v1','get_client_commit_v1',
    'get_client_activity_v1',
    'claim_client_projection_dirty_v1','get_public_client_sync_component_v1',
    'complete_client_sync_publication_classes_v1','mark_news_read_client_sync_v1',
    'save_event_client_sync_v1','delete_event_client_sync_v1',
    'set_event_attendance_client_sync_v1',
    'publish_activities_client_sync_v1',
    'save_inventory_pool_client_sync_v1',
    'get_map_editor_bundle_v1','save_place_client_sync_v1',
    'delete_place_client_sync_v1','move_place_client_sync_v1',
    'save_place_type_client_sync_v1','delete_place_type_client_sync_v1',
    'save_path_client_sync_v1','delete_path_client_sync_v1',
    'save_icon_client_sync_v1','delete_icon_client_sync_v1',
    'get_information_editor_bundle_v1','save_information_client_sync_v1',
    'delete_information_client_sync_v1',
    'save_news_client_sync_v1','delete_news_client_sync_v1',
    'publish_news_client_sync_v1',
    'get_speakers_editor_bundle_v1','get_event_editor_v1',
    'save_speaker_client_sync_v1',
    'delete_speaker_client_sync_v1','save_speaker_topic_client_sync_v1',
    'delete_speaker_topic_client_sync_v1','save_event_speakers_client_sync_v1',
    'set_saved_program_client_sync_v1',
    'get_user_groups_editor_bundle_v1','save_user_group_client_sync_v1',
    'delete_user_group_client_sync_v1','get_occasion_users_editor_bundle_v1',
    'save_profile_client_sync_v1','create_occasion_user_client_sync_v1',
    'delete_occasion_user_client_sync_v1','replace_group_assignments_client_sync_v1',
    'import_profiles_client_sync_v1','report_cleaning_issue_client_sync_v1',
    'resolve_cleaning_place_client_sync_v1',
    'set_cleaning_notifications_muted_client_sync_v1',
    'set_cleaning_reporter_blocked_client_sync_v1',
    'get_resources_for_inventory_pool_v1','save_resource_client_sync_v1',
    'delete_resource_client_sync_v1','delete_inventory_pool_client_sync_v1',
    'get_occasion_for_edit_v1','save_occasion_client_sync_v1',
    'create_occasion_client_sync_v1',
    'create_service_item_client_sync_v1','update_service_item_client_sync_v1',
    'game_update_settings_client_sync_v1',
    'sync_source_via_http_client_sync_v1',
    'create_counseling_slots_client_sync_v1',
    'delete_empty_counseling_slots_client_sync_v1',
    'delete_counseling_slot_client_sync_v1','game_guess_client_sync_v1',
    'get_exclusive_groups_for_edit_v1','save_exclusive_group_client_sync_v1',
    'delete_exclusive_group_client_sync_v1',
    'create_companion_client_sync_v1','delete_owned_companion_client_sync_v1',
    'assign_existing_companion_client_sync_v1',
    'unassign_existing_companion_client_sync_v1',
    'submit_event_feedback_client_sync_v1',
    'delete_event_feedback_client_sync_v1',
    'begin_client_mutation_v1','finish_client_mutation_v1',
    'begin_anonymous_client_mutation_v1','begin_unit_client_mutation_v1',
    'get_unit_edit_data_v1','save_unit_client_sync_v1',
    'duplicate_occasion_client_sync_v1','delete_occasion_client_sync_v1',
    'update_spot_assignments_client_sync_v1',
    'update_product_inventory_contexts_client_sync_v1',
    'update_product_client_sync_v1',
    'update_form_client_sync_v1','update_blueprint_client_sync_v1',
    'update_ticket_products_client_sync_v1',
    'swap_spot_tickets_client_sync_v1',
    'delete_order_client_sync_v1',
    'create_ticket_order_client_sync_v1',
    'confirm_blueprint_order_change_client_sync_v1',
    'replace_blueprint_order_client_sync_v1',
    'storno_tickets_client_sync_v1','storno_order_client_sync_v1',
    'create_form_client_sync_v1','delete_form_client_sync_v1',
    'duplicate_form_to_occasion_client_sync_v1',
    'delete_product_client_sync_v1','apply_planned_changes_client_sync_v1',
    'enqueue_ticket_order_confirmation_v1','claim_email',
    'finish_email_attempt',
    'record_account_deletion_sync_v1',
    'add_user_to_occasion_client_sync_v1',
    'delete_unit_user_client_sync_v1',
    'complete_private_inventory_mutation_v1',
    'complete_private_profile_mutation_v1',
    'complete_profile_inventory_membership_mutation_v1',
    'delete_service_item_client_sync_v1',
    'import_users_from_tickets_client_sync_v1',
    'complete_client_mutation_outcome_v1','complete_client_mutation_applied_v1'
    ,'release_client_projection_claims_v1'
    ,'get_client_sync_artifact_retention_candidates_v1'
    ,'delete_client_sync_artifact_metadata_v1'
    ,'compact_client_mutation_receipts_v1'
  ]) expected(name)
  WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=expected.name);
  PERFORM assert_true(v_missing IS NULL,'all client_sync_v1 RPCs exist in public');
  PERFORM assert_true(pg_get_functiondef(
      'public.get_client_commits_v1(bigint,timestamptz,uuid,integer,jsonb)'::regprocedure)
      LIKE '%LEAST(GREATEST(p_limit,1),501)%',
    'commit audit supports a 500-row page plus next-page probe');
  PERFORM assert_true(pg_get_functiondef(
      'public.get_client_commits_v1(bigint,timestamptz,uuid,integer,jsonb)'::regprocedure)
      LIKE '%s.can_occasion AND c.occasion=p_occasion%',
    'occasion audit permission cannot expose sibling occasion commits');
  PERFORM assert_true(pg_get_functiondef(
      'public.get_client_commit_v1(uuid)'::regprocedure)
      LIKE '%get_is_manager_on_unit(c.unit)%',
    'audit detail accepts the same unit-manager scope as the list');
  PERFORM assert_true(pg_get_functiondef(
      'public.get_client_activity_v1(bigint,timestamptz,timestamptz)'::regprocedure)
      NOT LIKE '%''actorDisplay''%'
      AND pg_get_functiondef(
        'public.get_client_activity_v1(bigint,timestamptz,timestamptz)'::regprocedure)
        NOT LIKE '%''actorId''%',
    'activity overview exposes no actor identity');
  PERFORM assert_true(pg_get_functiondef(
      'public.get_client_activity_v1(bigint,timestamptz,timestamptz)'::regprocedure)
      LIKE '%c.occasion = p_occasion%'
      AND pg_get_functiondef(
        'public.get_client_activity_v1(bigint,timestamptz,timestamptz)'::regprocedure)
        NOT LIKE '%c.unit = s.unit%'
      AND pg_get_functiondef(
        'public.get_client_activity_v1(bigint,timestamptz,timestamptz)'::regprocedure)
        NOT LIKE '%c.organization = s.organization%',
    'activity permission never broadens the requested occasion dataset');
  PERFORM assert_true(pg_get_functiondef(
      'public.get_client_activity_v1(bigint,timestamptz,timestamptz)'::regprocedure)
      LIKE '%activeActorCount%'
      AND pg_get_functiondef(
        'public.get_client_activity_v1(bigint,timestamptz,timestamptz)'::regprocedure)
        LIKE '%generate_series%',
    'activity overview returns daily metrics including zero days');
  PERFORM assert_true(has_function_privilege(
      'authenticated',
      'public.get_client_activity_v1(bigint,timestamptz,timestamptz)',
      'EXECUTE'),
    'authenticated managers can load aggregate activity');
  PERFORM assert_true(pg_get_functiondef(
      'public.save_speaker_client_sync_v1(bigint,uuid,bigint,jsonb)'::regprocedure)
      LIKE '%requested_topic.topic_id%',
    'speaker aggregate qualifies topic references');

  SELECT array_agg(c.relname) INTO v_unsecured
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname=ANY(ARRAY[
    'client_sync_scopes','client_sync_private_scopes','client_commits',
    'client_mutation_receipts','client_aggregate_versions',
    'client_commit_items','client_commit_components','client_projection_dirty_keys',
    'event_public_state','cleaning_public_state','news_notification_outbox'])
    AND NOT c.relrowsecurity;
  PERFORM assert_true(v_unsecured IS NULL,'all client sync state tables have RLS');

  SELECT count(*) INTO v_trigger_count FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND NOT t.tgisinternal AND
    t.tgname<>'handle_updated_at' AND
    (c.relname LIKE 'client_sync_%' OR c.relname IN ('events','event_users','event_users_saved','places','news'));
  PERFORM assert_eq(v_trigger_count::text,'0','client sync creates no persistent application trigger');

  SELECT count(*) INTO v_before FROM public.client_commits;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM public.get_private_client_sync_v1(jsonb_build_object('occasionId',-1),'{}');
  SELECT count(*) INTO v_after FROM public.client_commits;
  PERFORM assert_eq(v_after::text,v_before::text,'private handshake has no write side effect');

  PERFORM assert_true(NOT has_table_privilege('authenticated','public.client_commits','SELECT'),
    'authenticated cannot select commit ledger directly');
  PERFORM assert_true(NOT has_table_privilege('authenticated','public.client_sync_scopes','UPDATE'),
    'authenticated cannot update component heads directly');
  PERFORM assert_true(NOT has_table_privilege('authenticated','public.client_mutation_receipts','SELECT'),
    'authenticated cannot inspect mutation replay receipts');
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='client_mutation_receipts'
      AND column_name='actor_client_id' AND is_nullable='YES'),
    'anonymous feedback receipts have a non-user identity slot');
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='client_mutation_receipts'
      AND column_name='unit'),
    'mutation receipts support a unit scope');
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='client_commits'
      AND column_name='unit'),
    'audit commits support a unit scope');
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='client_commits'
      AND column_name='organization'),
    'cross-occasion service commits support an organization scope');
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='email_messages'
      AND column_name='lease_token') AND EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public'
      AND indexname='email_messages_ticket_order_command_idx'),
    'ticket confirmation effects have a durable idempotent queue identity');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='news_notification_outbox'
      AND column_name='required_content_revision') AND EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public'
      AND indexname='news_notification_outbox_ready_idx'),
    'news pushes have a durable publication-revision gate');
  PERFORM assert_true(pg_get_functiondef(
      'public.publish_news_client_sync_v1(bigint,boolean,text,boolean,text,text,jsonb,uuid)'::regprocedure)
      LIKE '%INSERT INTO public.news_notification_outbox%',
    'combined news publication queues its push behind content_catalog');
  PERFORM assert_true(pg_get_functiondef(
      'public.complete_client_sync_publication_classes_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,jsonb,text,uuid[],uuid[])'::regprocedure)
      LIKE '%DELETE FROM public.news_notification_outbox%',
    'canonical catalog completion releases publication-ready news pushes');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='complete_client_sync_publication_v1'),
    'superseded all-or-nothing publisher completion is absent');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM public.client_sync_component_sources s
    WHERE s.cutover_ready),
    'additive migration cannot make a source writer cutover-ready by itself');
  PERFORM assert_true(NOT EXISTS (
      SELECT 1 FROM public.occasions o
      WHERE COALESCE((o.data->>'client_sync_v1')::boolean,false))
    OR NOT EXISTS (
      SELECT 1 FROM public.client_sync_component_sources s
      WHERE s.registry_version=(
        SELECT max(v.registry_version) FROM public.client_sync_component_sources v)
        AND NOT s.cutover_ready),
    'enabled client sync cannot coexist with an unready registry source');
  PERFORM assert_true(NOT EXISTS (
      SELECT 1 FROM public.occasions o
      WHERE COALESCE((o.data->>'client_sync_v1')::boolean,false))
    OR NOT EXISTS (
      SELECT 1 FROM information_schema.role_table_grants g
      WHERE g.grantee IN ('anon','authenticated')
        AND g.table_schema='public' AND g.table_name='images'
        AND g.privilege_type IN ('INSERT','UPDATE','DELETE')),
    'enabled client sync closes ordinary occasion image DML');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM public.client_sync_component_sources s
    CROSS JOIN LATERAL unnest(s.canonical_writers) writer(name)
    WHERE s.disposition IN ('migrate','boundary') AND NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname=writer.name)),
    'every migrated or bounded source names only existing explicit writer RPCs');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM public.client_sync_component_sources s
    CROSS JOIN LATERAL unnest(s.canonical_writers) writer(name)
    WHERE writer.name ~ '(^|\.)(mutate|dispatch|execute)(_|$)'),
    'component registry contains no generic mutation dispatcher');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM public.client_sync_component_sources s
    WHERE s.disposition='boundary'),
    'all in-scope source writers have a canonical owner');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='client_commits'
      AND column_name IN ('idempotency_key','authoritative_result')),
    'audit commits do not duplicate mutation receipt replay state');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='client_commit_components'
      AND column_name='user_id' AND is_nullable='YES'),
    'public component revisions do not use a sentinel user id');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.begin_client_mutation_v1(uuid,text,bigint,uuid,text)','EXECUTE'),
    'receipt begin helper is internal to explicit domain commands');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.finish_client_mutation_v1(uuid,jsonb,uuid)','EXECUTE'),
    'receipt finish helper is internal to explicit domain commands');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.complete_client_mutation_outcome_v1(uuid,text,integer,jsonb)','EXECUTE'),
    'standard mutation outcome helper is internal');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.complete_client_mutation_applied_v1(uuid,bigint,text,text,jsonb,text[],jsonb,jsonb,jsonb,text[],jsonb,text,text,jsonb,bigint[])','EXECUTE'),
    'applied mutation finalizer is internal');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.apply_allocations(bigint)','EXECUTE')
    AND NOT has_function_privilege('authenticated',
      'public.assign_spot_to_resource(bigint,bigint)','EXECUTE')
    AND NOT has_function_privilege('authenticated',
      'public.adjust_spot_capacity_for_pool(bigint)','EXECUTE')
    AND NOT has_function_privilege('authenticated',
      'public._swap_spots_update_ticket(bigint,bigint,bigint)','EXECUTE'),
    'commerce implementation helpers are not client gateways');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='apply_client_sync_mutation_internal_v1'),
    'cross-domain mutation dispatcher is absent');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='mark_news_read_client_sync_v1'
      AND p.proargnames @> ARRAY['p_command_id']::text[]
      AND NOT (p.proargnames @> ARRAY['p_idempotency_key']::text[])),
    'canonical news command exposes command id at the intent boundary');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='save_event_client_sync_v1'
      AND p.proargnames @> ARRAY['p_command_id','p_expected_version','p_event']::text[]),
    'event aggregate command exposes command id, version and aggregate DTO');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='save_place_client_sync_v1'
      AND p.proargnames @> ARRAY['p_command_id','p_expected_version','p_place']::text[]),
    'place aggregate command exposes command id, version and closed DTO');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='save_speaker_client_sync_v1'
      AND p.proargnames @> ARRAY['p_command_id','p_expected_version','p_speaker']::text[]),
    'speaker aggregate command owns speaker topic links and optimistic concurrency');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='save_event_speakers_client_sync_v1'
      AND p.proargnames @> ARRAY['p_command_id','p_expected_version','p_speaker_ids']::text[]),
    'event speaker command shares the event aggregate version');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.mutate_map_entity_internal_v1(text,text,bigint,uuid,bigint,bigint,jsonb)',
    'EXECUTE'),'generic map implementation helper is not a client gateway');
  PERFORM assert_true(NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='record_client_sync_commit_v1'
      AND p.proargnames && ARRAY['p_idempotency_key','p_authoritative_result']::text[]),
    'commit helper owns audit/revisions only; receipts own replay');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='public.update_ticket_products_internal_v1(bigint,jsonb)'::regprocedure
      AND p.proconfig @> ARRAY['search_path=public, eshop, extensions']),
    'ticket product implementation resolves its permission helper on a trusted path');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='public.update_occasion_internal_v1(jsonb)'::regprocedure
      AND p.proconfig @> ARRAY['search_path=public, extensions']),
    'occasion implementation resolves its legacy helpers on a trusted path');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.release_client_projection_claims_v1(uuid[])','EXECUTE'),
    'ordinary clients cannot release publisher claims');
  PERFORM assert_true(has_function_privilege('service_role',
    'public.release_client_projection_claims_v1(uuid[])','EXECUTE'),
    'service role owns token-scoped claim release');
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='client_mutation_receipts'
      AND column_name='expired_at'),
    'receipt compaction has a permanent tombstone timestamp');
  PERFORM assert_true(pg_get_functiondef(
    'public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)'::regprocedure)
      LIKE '%client_sync_v1 before hiding%',
    'ordinary occasion save cannot hide an enabled sync scope');
  PERFORM assert_true(pg_get_functiondef(
    'public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)'::regprocedure)
      LIKE '%get_is_editor_on_unit%',
    'occasion save accepts the unit editor role used by occasion settings');
  PERFORM assert_true(pg_get_functiondef(
    'public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'::regprocedure)
      LIKE '%get_is_editor_on_unit%',
    'occasion domain save preserves unit editor authorization');
  PERFORM assert_true(pg_get_functiondef(
    'public.complete_client_mutation_applied_v1(uuid,bigint,text,text,jsonb,text[],jsonb,jsonb,jsonb,text[],jsonb,text,text,jsonb,bigint[])'::regprocedure)
      LIKE '%get_public_client_sync_component_core_v1%',
    'authenticated mutation finalization uses the internal public materializer');
  PERFORM assert_true(pg_get_functiondef(
    'public.get_public_client_sync_component_core_v1(text,text,bigint)'::regprocedure)
      LIKE '%get_is_editor_on_unit%',
    'internal public materialization accepts the unit editor save role');
  PERFORM assert_true(pg_get_functiondef(
    'public.delete_occasion_client_sync_v1(bigint,uuid)'::regprocedure)
      LIKE '%client_sync_v1 before deleting%',
    'ordinary occasion delete requires guarded disable first');
  PERFORM assert_true(pg_get_functiondef(
    'public.create_occasion_client_sync_v1(uuid,jsonb)'::regprocedure)
      LIKE '%client_sync_v1%false%',
    'ordinary occasion create forces the activation flag false');
  PERFORM assert_true(pg_get_functiondef(
    'public.duplicate_occasion_client_sync_v1(bigint,uuid)'::regprocedure)
      LIKE '%client_sync_v1%false%',
    'occasion duplication cannot copy an enabled activation flag');
  PERFORM assert_eq((SELECT count(*) FROM pg_trigger t
    WHERE NOT t.tgisinternal AND pg_get_triggerdef(t.oid) ILIKE '%client_sync%'),
    0::bigint,'client sync hardening adds no persistent application trigger');
END $$;

ROLLBACK;
