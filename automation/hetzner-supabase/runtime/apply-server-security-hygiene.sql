\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('festapp-server-security-remediation',0));
DO $$
BEGIN
  IF current_database()<>'festapp_rehearsal_20260909220601' OR
    NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=1) THEN
    RAISE EXCEPTION 'Canonical target mismatch';
  END IF;
  IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261016172000') THEN
    RAISE EXCEPTION 'Migration already recorded; use readback rather than replay';
  END IF;
END $$;
-- Embedded canonical migration 20261016172000_server_security_hygiene.sql
-- Canonical sources: database/functions/security/server_security_search_paths.sql, database/functions/security/server_security_hygiene.sql

-- Explicit reviewed application signatures from the 2026-10-16 live catalog.
-- Extension-owned routines are excluded. Existing body/ACL/identity semantics stay intact.
DO $$
DECLARE signature text;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'public.add_sync_map(text,bigint,bigint,text,bigint,bigint)',
    'public.analyze_new_order_spots(bigint[])',
    'public.check_access_to_occasion(bigint)',
    'public.check_is_editor_on_occasion(bigint)',
    'public.check_is_editor_on_unit(bigint)',
    'public.check_is_editor_order_view_on_occasion(bigint)',
    'public.check_is_editor_view_on_occasion(bigint)',
    'public.check_is_manager_on_unit(bigint)',
    'public.create_user(bigint,text,text)',
    'public.create_user_in_organization_with_data(bigint,text,text,jsonb)',
    'public.create_user_in_organization_with_data_ws(bigint,text,text,jsonb)',
    'public.create_user_with_data(bigint,text,text,jsonb)',
    'public.delete_entity_email_template(text,bigint,text)',
    'public.delete_form_ws_obsolete_v1(bigint)',
    'public.delete_inventory_pool(bigint)',
    'public.delete_occasion_email_template(bigint,text)',
    'public.delete_order(bigint)',
    'public.delete_resource(bigint)',
    'public.delete_unit(bigint)',
    'public.duplicate_form_ws(bigint)',
    'public.game_get_correctly_guessed_checkpoints(bigint)',
    'public.get_activities_for_edit(bigint)',
    'public.get_all_occasions(bigint)',
    'public.get_all_occasions_for_edit(bigint)',
    'public.get_all_occasions_for_edit_v182(bigint)',
    'public.get_all_occasions_for_edit_v212(bigint)',
    'public.get_all_user_basics_for_scan(text)',
    'public.get_all_user_basics_from_occasion(bigint)',
    'public.get_all_user_basics_from_occasion_unit(bigint)',
    'public.get_all_user_group_info(bigint,text)',
    'public.get_all_users_from_unit(bigint)',
    'public.get_all_viewable_forms_for_copying()',
    'public.get_available_occasions(bigint,bigint)',
    'public.get_available_platforms(bigint)',
    'public.get_current_organization_data()',
    'public.get_current_quote(bigint)',
    'public.get_events(bigint,boolean)',
    'public.get_exists_on_occasion(bigint)',
    'public.get_exists_on_occasion_user(uuid,bigint)',
    'public.get_inventory_pool_bundle(bigint)',
    'public.get_is_approved_on_occasion(bigint)',
    'public.get_is_approver_on_occasion(bigint)',
    'public.get_is_editor_on_any_occasion()',
    'public.get_is_editor_view_on_unit(bigint)',
    'public.get_is_event_allowed(bigint)',
    'public.get_is_manager_on_any_occasion()',
    'public.get_last_sign_in_at_for_users(uuid[],bigint)',
    'public.get_my_events_and_activities(bigint,boolean)',
    'public.get_news_with_views(bigint)',
    'public.get_occasion_users_for_editor(bigint)',
    'public.get_products_for_ticket_all_available(bigint)',
    'public.get_public_occasions(bigint,bigint)',
    'public.get_resources_for_inventory_pool(bigint)',
    'public.get_spot_management_bundle(bigint)',
    'public.get_spots_for_inclusion_type_group(bigint)',
    'public.get_unit(bigint)',
    'public.get_unit_for_edit(bigint)',
    'public.get_user_group_info(bigint)',
    'public.get_user_groups(bigint)',
    'public.get_user_groups_by_occasion(bigint)',
    'public.get_user_info_for_users(uuid[],bigint)',
    'public.get_user_inventory()',
    'public.get_users_from_occasion_with_orders(bigint)',
    'public.groups_get_user_groups()',
    'public.scan_ticket_v2(text,text)',
    'public.set_user_password(uuid,bigint,text)',
    'public.storno_ticket(bigint)',
    'public.storno_ticket_221(bigint)',
    'public.synchronize_my_schedule(bigint[],boolean)',
    'public.update_activities(bigint)',
    'public.update_bank_account_user(bigint,text,boolean,boolean)',
    'public.update_entity_email_banner(text,bigint,text)',
    'public.update_inclusion_type_group(jsonb)',
    'public.update_order_and_tickets_to_sent_ws(bigint,bigint[])',
    'public.update_order_and_tickets_to_storno_with_security(bigint)',
    'public.update_resource(jsonb)',
    'public.update_ticket_products_ws(bigint,bigint[])',
    'public.update_unit_user(jsonb)',
    'public.update_user(uuid,bigint,jsonb)'] LOOP
    IF to_regprocedure(signature) IS NOT NULL THEN
      EXECUTE format('ALTER FUNCTION %s SET search_path = public, extensions',signature);
    END IF;
  END LOOP;
END $$;

-- Apply this migration as supabase_admin (extension owner), not postgres.
-- The local migration CLI may SET ROLE postgres on an admin connection.
RESET ROLE;
DO $$ BEGIN
  IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) THEN
    RAISE EXCEPTION 'Security hygiene requires the extension-owning superuser; no partial ACL repair allowed';
  END IF;
END $$;
-- RLS does not protect TRUNCATE. No application client owns this privilege.
DO $$
DECLARE t record; f record;
BEGIN
  FOR t IN SELECT c.oid::regclass AS name FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p') LOOP
    EXECUTE format('REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE %s FROM PUBLIC,anon,authenticated', t.name);
  END LOOP;
  -- Restrict outbound SQL/network and cross-database extension entrypoints.
  -- postgres-owned definers can still call them; application producers use net.http_post.
  FOR f IN SELECT p.oid::regprocedure AS name FROM pg_proc p
      JOIN pg_depend d ON d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
      JOIN pg_extension e ON e.oid=d.refobjid WHERE e.extname IN ('dblink','http') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.name);
  END LOOP;
END $$;

-- End canonical migration
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20261016172000','server_security_hygiene',ARRAY['-- sha256:dc73dc9a5f938f5732c3285f89086f625a6140a7473c740c297df1898b6fa1a6']);
NOTIFY pgrst,'reload schema';
COMMIT;
