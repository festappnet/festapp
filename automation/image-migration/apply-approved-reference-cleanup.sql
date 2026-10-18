-- Operator transaction input: pg_temp.asset_reference_disposition_input(payload).
-- Exact owner-approved five missing references, not a registry/object cleanup.
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
SET LOCAL search_path=public,extensions;
SELECT pg_advisory_xact_lock(hashtextextended('festapp-storage-r2-retirement',0));
DO $disposition$
DECLARE b jsonb; e jsonb; current_value jsonb; identities text[];
 scope bigint; components text[]; impacts jsonb; changed bigint;
BEGIN
 IF session_user<>'postgres' OR current_database()<>'festapp_rehearsal_20260909220601'
 OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=3 AND title='vstupenky.online') THEN
  RAISE EXCEPTION 'Canonical reference-disposition target mismatch';
 END IF;
 SELECT payload INTO STRICT b FROM pg_temp.asset_reference_disposition_input;
 IF b->>'approval' IS DISTINCT FROM 'five-broken-r2-references-20261018' OR (b->>'removed_references')::integer IS DISTINCT FROM 5
 OR b->>'inventory_sha256' IS DISTINCT FROM (SELECT inventory_sha256 FROM public.canonical_asset_cutover WHERE singleton)
 OR EXISTS(SELECT 1 FROM public.client_commits WHERE source='storage.r2.approved-reference-cleanup') THEN
  RAISE EXCEPTION 'Unapproved or already applied reference disposition';
 END IF;
 SELECT array_agg(format('%s.%s:%s',j.value->>'table',j.value->>'field',j.value->>'id')
 ORDER BY j.value->>'table',j.value->>'field',j.value->>'id')
 INTO identities FROM jsonb_array_elements(b->'edits') j(value);
 IF identities IS DISTINCT FROM ARRAY['email_wrappers.html:20','events.data:1390','events.data:1448','occasions.data:376315'] THEN
  RAISE EXCEPTION 'Unexpected reference-disposition scope';
 END IF;
 LOCK TABLE public.email_wrappers,public.events,public.occasions IN SHARE ROW EXCLUSIVE MODE;
 IF NOT EXISTS(SELECT 1 FROM public.events WHERE id=1390 AND occasion=1072551)
 OR NOT EXISTS(SELECT 1 FROM public.events WHERE id=1448 AND occasion=1072551)
 OR NOT EXISTS(SELECT 1 FROM public.email_wrappers WHERE id=20 AND occasion=1072509)
 OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=376315 AND organization=3) THEN
  RAISE EXCEPTION 'Reference ownership scope changed';
 END IF;
 FOR e IN SELECT value FROM jsonb_array_elements(b->'edits') ORDER BY value->>'table',value->>'id' LOOP
  EXECUTE format('SELECT to_jsonb(t)->%L FROM public.%I t WHERE id=$1 FOR UPDATE',e->>'field',e->>'table')
  INTO STRICT current_value USING (e->>'id')::bigint;
  IF current_value IS DISTINCT FROM e->'original' THEN RAISE EXCEPTION 'Reference field changed since approval capture'; END IF;
  IF e->>'table'='events' AND e->'replacement' IS DISTINCT FROM (current_value-'header_image') THEN
   RAISE EXCEPTION 'Event replacement would change other content';
  ELSIF e->>'table'='occasions' AND e->'replacement' IS DISTINCT FROM (current_value-'image') THEN
   RAISE EXCEPTION 'Occasion replacement would change other content';
  END IF;
  IF e->>'table'='email_wrappers' THEN
   IF jsonb_typeof(e->'replacement')<>'string' OR (e->>'removed_images')::integer IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'Wrapper must remove exactly two approved img tags';
   END IF;
   EXECUTE 'UPDATE public.email_wrappers SET html=$1 WHERE id=$2' USING e->>'replacement',(e->>'id')::bigint;
  ELSE
   EXECUTE format('UPDATE public.%I SET data=$1 WHERE id=$2',e->>'table') USING e->'replacement',(e->>'id')::bigint;
  END IF;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'Reference-disposition row disappeared'; END IF;
 END LOOP;
 -- Preserve normal sync and its existing rollout scope in the same transaction.
 FOREACH scope IN ARRAY ARRAY[376315,1072509,1072551]::bigint[] LOOP
  SELECT COALESCE(array_agg(component ORDER BY component),'{}') INTO components
   FROM public.client_sync_scopes WHERE scope_type='occasion' AND scope_id=scope;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component',s.component,'userId',s.user_id)
   ORDER BY s.component,s.user_id),'[]') INTO impacts FROM public.client_sync_private_scopes s
   WHERE s.occasion=scope AND EXISTS(SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=scope AND ou."user"=s.user_id);
  PERFORM public.record_client_sync_commit_v1(scope,'storage.r2.approved-reference-cleanup','catalog','[]',
   components,impacts,'[]','system','owner-approved-five-missing-references-20261018');
 END LOOP;
END $disposition$;
