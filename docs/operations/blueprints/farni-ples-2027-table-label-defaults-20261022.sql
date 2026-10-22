-- Authorized one-plan typography repair. Save the original layout privately
-- before execution. A stale revision or any changed rendered label aborts.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '20s';
SELECT set_config('request.jwt.claim.role', 'service_role', true);
DO $$
DECLARE
  b eshop.blueprints;
  next_layout jsonb;
  shared_label jsonb;
  commit_receipt jsonb;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY[1072600::bigint]);
  SELECT * INTO STRICT b FROM eshop.blueprints
    WHERE id=91 AND occasion=1072600 AND organization=3 FOR UPDATE;
  IF b.layout_revision<>3 THEN
    RAISE EXCEPTION 'Expected layout revision 3, found %',b.layout_revision;
  END IF;
  SELECT n->'style'->'label' INTO STRICT shared_label
    FROM jsonb_array_elements(b.layout->'nodes') n
    WHERE n->>'kind'='table' LIMIT 1;
  IF shared_label->>'size'<>'44.026655999999996'
    OR (SELECT count(*) FROM jsonb_array_elements(b.layout->'nodes') n
        WHERE n->>'kind'='table')<>26
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(b.layout->'nodes') n
        WHERE n->>'kind'='table' AND n->'style'->'label' IS DISTINCT FROM shared_label)
  THEN RAISE EXCEPTION 'Reviewed table typography changed'; END IF;
  next_layout:=jsonb_set(b.layout,'{styles,kinds,table,label}',shared_label);
  next_layout:=jsonb_set(next_layout,'{nodes}',(
    SELECT jsonb_agg(CASE WHEN n->>'kind'='table' THEN
      jsonb_set(n,'{style}',(n->'style')-'label') ELSE n END ORDER BY ordinal)
    FROM jsonb_array_elements(next_layout->'nodes') WITH ORDINALITY t(n,ordinal)));
  -- Exact visual equivalence for every existing object, including entrances.
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(b.layout->'nodes') old_node
    JOIN jsonb_array_elements(next_layout->'nodes') new_node
      ON old_node->>'id'=new_node->>'id'
    WHERE public.blueprint_resolved_label_internal(b.layout,old_node)
      IS DISTINCT FROM public.blueprint_resolved_label_internal(next_layout,new_node))
  THEN RAISE EXCEPTION 'Existing label rendering would change'; END IF;
  PERFORM public.validate_blueprint_layout_internal(next_layout);
  PERFORM public.check_blueprint_text_resources_internal(next_layout,b.occasion);
  IF public.blueprint_text_resource_ids_internal(next_layout,b.occasion)
    IS DISTINCT FROM b.layout_text_resource_ids
  THEN RAISE EXCEPTION 'Text dependencies changed'; END IF;
  UPDATE eshop.blueprints SET layout=next_layout,
    layout_revision=layout_revision+1,updated_at=now() WHERE id=b.id;
  commit_receipt:=public.record_client_sync_commit_v1(
    b.occasion,'inventory.blueprint.table_label_defaults','inventory',
    jsonb_build_array(jsonb_build_object('entityType','blueprint',
      'entityId',b.id::text,'operation','update','safeLabel',b.title,
      'changedFields',jsonb_build_array('layout'))),
    '{}'::text[],'[]'::jsonb,'[]'::jsonb,'service',
    'User-requested matching typography for newly inserted tables; existing labels preserved');
  RAISE NOTICE 'Blueprint %, layout revision %, commit %',
    b.id,b.layout_revision+1,commit_receipt->>'commitId';
END $$;
COMMIT;
