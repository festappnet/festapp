-- No current Dart/JS/Edge/Worker/MCP source calls these historical claims RPCs.
-- Effective function-body references form only this closed seven-function island;
-- catalog policies, triggers and service jobs do not reference it. JWT identity,
-- OAuth scopes and backend activation metadata remain their own protocol inputs.
-- RESTRICT makes a previously unknown catalog dependency a migration failure.
DO $authorization_contraction$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
    AND p.proname NOT IN ('set_claim','delete_claim','get_claims','get_claim','get_my_claims','get_my_claim','is_claims_admin')
    AND p.prosrc ~ '(set_claim|delete_claim|get_claims|get_claim|get_my_claims|get_my_claim|is_claims_admin)[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM pg_policy p
   WHERE coalesce(pg_get_expr(p.polqual,p.polrelid),'')||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'')
     ~ '(set_claim|delete_claim|get_claims|get_claim|get_my_claims|get_my_claim|is_claims_admin)[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM pg_trigger t WHERE NOT t.tgisinternal
   AND pg_get_triggerdef(t.oid) ~ '(set_claim|delete_claim|get_claims|get_claim|get_my_claims|get_my_claim|is_claims_admin)[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM cron.job j WHERE j.command
   ~ '(set_claim|delete_claim|get_claims|get_claim|get_my_claims|get_my_claim|is_claims_admin)[[:space:]]*\(') THEN
  RAISE EXCEPTION 'Claims RPC contraction has an active catalog caller';
 END IF;
END;
$authorization_contraction$;
DROP FUNCTION IF EXISTS public.set_claim(uuid,text,jsonb) RESTRICT;
DROP FUNCTION IF EXISTS public.delete_claim(uuid,text) RESTRICT;
DROP FUNCTION IF EXISTS public.get_claims(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.get_claim(uuid,text) RESTRICT;
DROP FUNCTION IF EXISTS public.get_my_claims() RESTRICT;
DROP FUNCTION IF EXISTS public.get_my_claim(text) RESTRICT;
DROP FUNCTION IF EXISTS public.is_claims_admin() RESTRICT;

-- The unversioned pre-receipt order deleter has no supported caller. Keeping it
-- would bypass current waitlist/email/receipt invariants. The supported 221 and
-- command APIs delegate to the canonical writer instead.
DO $obsolete_order_delete$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc function JOIN pg_namespace namespace ON namespace.oid=function.pronamespace
   WHERE namespace.nspname='public' AND function.proname<>'delete_order'
     AND function.prosrc ~ '\mdelete_order[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM pg_policy policy WHERE
   coalesce(pg_get_expr(policy.polqual,policy.polrelid),'')||coalesce(pg_get_expr(policy.polwithcheck,policy.polrelid),'')
     ~ '\mdelete_order[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM cron.job job WHERE job.command ~ '\mdelete_order[[:space:]]*\(') THEN
  RAISE EXCEPTION 'Obsolete order deleter still has an active catalog caller';
 END IF;
END;
$obsolete_order_delete$;
DROP FUNCTION IF EXISTS public.delete_order(bigint) RESTRICT;

-- Closed pre-command writer islands: no current SQL, policy, job or client
-- caller. Retain the supported wsv2/C3 and bulk/221 command adapters instead.
DO $obsolete_writer_islands$
DECLARE pattern text := '\m(storno_ticket|storno_ticket_221|copy_product_type_with_products|duplicate_form_ws|update_ticket_products_ws|update_order_data_to_sent)[[:space:]]*\(';
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc function JOIN pg_namespace namespace ON namespace.oid=function.pronamespace
   WHERE namespace.nspname='public' AND function.proname NOT IN
     ('storno_ticket','storno_ticket_221','copy_product_type_with_products','duplicate_form_ws','update_ticket_products_ws','update_order_data_to_sent')
     AND function.prosrc ~* pattern)
 OR EXISTS(SELECT 1 FROM pg_policy policy WHERE
   coalesce(pg_get_expr(policy.polqual,policy.polrelid),'')||coalesce(pg_get_expr(policy.polwithcheck,policy.polrelid),'') ~* pattern)
 OR EXISTS(SELECT 1 FROM cron.job job WHERE job.command ~* pattern) THEN
  RAISE EXCEPTION 'Obsolete pre-command writers still have an active catalog caller';
 END IF;
END;
$obsolete_writer_islands$;
DROP FUNCTION IF EXISTS public.storno_ticket(bigint) RESTRICT;
DROP FUNCTION IF EXISTS public.storno_ticket_221(bigint) RESTRICT;
DROP FUNCTION IF EXISTS public.copy_product_type_with_products(bigint) RESTRICT;
DROP FUNCTION IF EXISTS public.duplicate_form_ws(bigint) RESTRICT;
DROP FUNCTION IF EXISTS public.update_ticket_products_ws(bigint,bigint[]) RESTRICT;
DROP FUNCTION IF EXISTS public.update_order_data_to_sent(bigint) RESTRICT;

-- The old service-only physical form deleter has no remaining caller. Keep
-- the supported delete_form_ws adapter and its receipted command owner.
DO $obsolete_form_writer$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname<>'delete_form_ws_obsolete_v1'
      AND p.prosrc ~* '\mdelete_form_ws_obsolete_v1[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM pg_policy p WHERE
    coalesce(pg_get_expr(p.polqual,p.polrelid),'')||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'')
      ~* '\mdelete_form_ws_obsolete_v1[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM cron.job WHERE command ~* '\mdelete_form_ws_obsolete_v1[[:space:]]*\(') THEN
   RAISE EXCEPTION 'Obsolete form deleter still has a catalog caller';
 END IF;
END $obsolete_form_writer$;
DROP FUNCTION IF EXISTS public.delete_form_ws_obsolete_v1(bigint) RESTRICT;

-- The three-argument profile writer was already revoked from every API role.
-- Its name is also used by the supported unit-profile JSONB adapter. Permit
-- only that exact, typed one-argument call while guarding overload contraction.
DO $obsolete_profile_overload$
DECLARE caller record;
BEGIN
 FOR caller IN SELECT p.oid,p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname<>'update_user'
     AND p.prosrc ~* '\mupdate_user[[:space:]]*\(' LOOP
  IF caller.oid IS DISTINCT FROM to_regprocedure('public.update_unit_user(jsonb)')
    OR caller.prosrc !~* '\mv_update_user_payload[[:space:]]+jsonb\M'
    OR regexp_replace(caller.prosrc,'(public\.)?update_user\(v_update_user_payload\)','','g')
       ~* '\mupdate_user[[:space:]]*\(' THEN
   RAISE EXCEPTION 'Unreviewed caller of the retired profile overload: %',caller.oid::regprocedure;
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy p WHERE
   coalesce(pg_get_expr(p.polqual,p.polrelid),'')||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'')
     ~* '\mupdate_user[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM cron.job WHERE command ~* '\mupdate_user[[:space:]]*\(') THEN
   RAISE EXCEPTION 'Profile overload still has a policy or job caller';
 END IF;
END $obsolete_profile_overload$;
DROP FUNCTION IF EXISTS public.update_user(uuid,bigint,jsonb) RESTRICT;

-- User-triggered pull now lists through the actor-bound occasion operation.
DO $obsolete_bank_unit_listing$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
   AND p.proname<>'get_bank_sync_connections_for_unit'
   AND p.prosrc ~* '\mget_bank_sync_connections_for_unit[[:space:]]*\(')
 OR EXISTS(SELECT 1 FROM cron.job WHERE command ~* '\mget_bank_sync_connections_for_unit[[:space:]]*\(') THEN
   RAISE EXCEPTION 'Obsolete unscoped bank listing still has a caller';
 END IF;
END $obsolete_bank_unit_listing$;
DROP FUNCTION IF EXISTS public.get_bank_sync_connections_for_unit(bigint) RESTRICT;

-- Private draft constructor superseded before this migration is published.
-- No client role ever had EXECUTE; all context callers pass the already-loaded
-- live organization fact to the immutable constructor instead.
DROP FUNCTION IF EXISTS public.get_organization_context_capabilities_v1(bigint) RESTRICT;

-- Pre-command capacity/attendance implementations have no supported producer,
-- SQL caller, registry, policy, trigger or job. Their current owners are
-- adjust_spot_capacity_for_pool and set_event_attendance_client_sync_v1.
DO $obsolete_capacity_and_attendance$
DECLARE pattern text := '\m"?(create_spots_for_inventory_pool|update_inclusion_type_group|upsert_event_user)"?[[:space:]]*\(';
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
   AND p.proname NOT IN ('create_spots_for_inventory_pool','update_inclusion_type_group','upsert_event_user')
   AND p.prosrc ~* pattern)
 OR EXISTS(SELECT 1 FROM pg_policy p WHERE
   coalesce(pg_get_expr(p.polqual,p.polrelid),'')||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'') ~* pattern)
 OR EXISTS(SELECT 1 FROM pg_trigger t WHERE NOT t.tgisinternal AND pg_get_triggerdef(t.oid) ~* pattern)
 OR EXISTS(SELECT 1 FROM cron.job WHERE command ~* pattern)
 OR EXISTS(SELECT 1 FROM public.client_sync_component_sources r WHERE
   (r.canonical_writers||r.legacy_writers) && ARRAY['create_spots_for_inventory_pool','update_inclusion_type_group','upsert_event_user']::text[]) THEN
  RAISE EXCEPTION 'Obsolete capacity/attendance implementation still has a caller';
 END IF;
END $obsolete_capacity_and_attendance$;
DROP FUNCTION IF EXISTS public.create_spots_for_inventory_pool(bigint) RESTRICT;
DROP FUNCTION IF EXISTS public.update_inclusion_type_group(jsonb) RESTRICT;
DROP FUNCTION IF EXISTS public.upsert_event_user(integer,uuid) RESTRICT;
