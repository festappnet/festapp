-- Task-owned synthetic fixture only: psql -v fixture_blueprint=2 -f this-file.
-- All geometry persistence goes through the existing receipted save boundary.
SELECT set_config('festapp.fixture_blueprint',:'fixture_blueprint',false);
BEGIN;
DO $$
DECLARE target bigint:=current_setting('festapp.fixture_blueprint')::bigint; b eshop.blueprints; doc jsonb; actor uuid; result jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment) THEN RAISE EXCEPTION 'disposable fixture database required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.blueprints WHERE id=target)]);
 SELECT * INTO b FROM eshop.blueprints WHERE id=target FOR UPDATE;
 IF b.id IS NULL OR b.layout IS NULL OR (SELECT count(*) FROM jsonb_array_elements(b.layout->'nodes') n WHERE n->>'kind'='seat')<>4
  OR (SELECT count(*) FROM jsonb_array_elements(b.layout->'nodes') n WHERE n->>'kind' IN ('table','furniture','capacityArea'))<>3 THEN RAISE EXCEPTION 'expected synthetic E2E geometry required'; END IF;
 SELECT ou."user" INTO actor FROM public.occasion_users ou WHERE ou.occasion=b.occasion AND (ou.is_editor OR ou.is_manager) ORDER BY ou."user" LIMIT 1;
 IF actor IS NULL THEN RAISE EXCEPTION 'fixture geometry editor required'; END IF;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 SELECT jsonb_set(b.layout,'{nodes}',jsonb_agg(CASE
   WHEN node->>'kind'='table' THEN jsonb_set(node,'{transform}','{"x":250,"y":220,"rotation":0}')
   WHEN node->>'kind'='furniture' THEN jsonb_set(node,'{transform}','{"x":650,"y":220,"rotation":0}')
   WHEN node->>'kind'='capacityArea' THEN jsonb_set(node,'{transform}','{"x":450,"y":600,"rotation":0}')
   WHEN node->>'kind'='seat' THEN jsonb_set(node,'{transform}',jsonb_build_object('x',CASE WHEN seat_position%2=1 THEN -60 ELSE 60 END,'y',110,'rotation',0))
   ELSE node END ORDER BY position)) INTO doc
 FROM (SELECT node,position,row_number() OVER(PARTITION BY node->>'parentId' ORDER BY position) seat_position FROM jsonb_array_elements(b.layout->'nodes') WITH ORDINALITY records(node,position)) nodes;
 doc:=jsonb_set(doc,'{canvas}',doc->'canvas'||'{"x":0,"y":0,"width":1000,"height":1000}');
 IF doc=b.layout THEN RAISE NOTICE 'Fixture placement already repaired at revision %',b.layout_revision;RETURN; END IF;
 result:=public.update_blueprint_client_sync_v1(jsonb_build_object('id',b.id,'occasion',b.occasion,'organization',b.organization,'title',b.title,
  'expected_layout_revision',b.layout_revision,'layout',doc,'seatChanges','[]'::jsonb,'groupProductChanges','[]'::jsonb,'areaBindingChanges','[]'::jsonb),extensions.gen_random_uuid());
 IF result->>'status'<>'applied' THEN RAISE EXCEPTION 'fixture placement save rejected: %',result; END IF;
 RAISE NOTICE 'Fixture placement saved through existing command at revision %',result#>>'{data,layout_revision}';
END $$;
COMMIT;
