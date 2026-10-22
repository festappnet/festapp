-- Three user-requested mixed plans: majority default with individual exceptions.
-- Private backup: /tmp/festapp-mixed-table-labels-before.json
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE
  reviewed jsonb := '[{"id":22,"occasion":81,"layout_revision":3,"layout_sha256":"a858c508f3fbf4a7c06a75ddd36990157b731508c83571e9637d7040df79237e"},{"id":32,"occasion":100,"layout_revision":7,"layout_sha256":"1989bea7da7df8411a897411009b421f9c9d1e0a5335f96efa6f014f6b81c722"},{"id":87,"occasion":1072585,"layout_revision":3,"layout_sha256":"8ede91ddfe50d387020f5888ffae68bf483f5737f3935acfeeebc70fc53a9b1e"}]'::jsonb;
  item jsonb; b eshop.blueprints; shared_label jsonb; next_layout jsonb;
  receipt jsonb; table_count integer;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(
    SELECT DISTINCT (x->>'occasion')::bigint FROM jsonb_array_elements(reviewed) x
    ORDER BY (x->>'occasion')::bigint));
  FOR item IN SELECT value FROM jsonb_array_elements(reviewed) LOOP
    SELECT * INTO STRICT b FROM eshop.blueprints WHERE id=(item->>'id')::bigint
      AND occasion=(item->>'occasion')::bigint AND organization=3 FOR UPDATE;
    IF b.layout_revision<>(item->>'layout_revision')::bigint OR
      encode(extensions.digest(convert_to(b.layout::text,'UTF8'),'sha256'),'hex')
        IS DISTINCT FROM item->>'layout_sha256'
    THEN RAISE EXCEPTION 'Blueprint % changed since review',b.id; END IF;
    SELECT count(*) INTO table_count FROM jsonb_array_elements(b.layout->'nodes') n WHERE n->>'kind'='table';
    SELECT public.blueprint_resolved_label_internal(b.layout,n) INTO STRICT shared_label
      FROM jsonb_array_elements(b.layout->'nodes') n WHERE n->>'kind'='table'
      GROUP BY public.blueprint_resolved_label_internal(b.layout,n)
      HAVING count(*)>table_count/2 ORDER BY count(*) DESC LIMIT 1;
    next_layout:=jsonb_set(b.layout,'{styles,kinds,table,label}',
      coalesce(b.layout#>'{styles,kinds,table,label}','{}'::jsonb)||shared_label);
    next_layout:=jsonb_set(next_layout,'{nodes}',(
      SELECT jsonb_agg(CASE WHEN n->>'kind'='table' THEN
        jsonb_set(n,'{style}',(coalesce(n->'style','{}'::jsonb)-'label') ||
          CASE WHEN custom_label='{}'::jsonb THEN '{}'::jsonb
          ELSE jsonb_build_object('label',custom_label) END)
        ELSE n END ORDER BY ordinal)
      FROM jsonb_array_elements(b.layout->'nodes') WITH ORDINALITY t(n,ordinal)
      CROSS JOIN LATERAL (SELECT coalesce(jsonb_object_agg(key,value),'{}'::jsonb) custom_label
        FROM jsonb_each(public.blueprint_resolved_label_internal(b.layout,n))
        WHERE value IS DISTINCT FROM shared_label->key) custom));
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(b.layout->'nodes') old_node
      JOIN jsonb_array_elements(next_layout->'nodes') new_node
        ON old_node->>'id'=new_node->>'id'
      WHERE public.blueprint_resolved_label_internal(b.layout,old_node)
        IS DISTINCT FROM public.blueprint_resolved_label_internal(next_layout,new_node))
    THEN RAISE EXCEPTION 'Blueprint % existing label rendering would change',b.id; END IF;
    PERFORM public.validate_blueprint_layout_internal(next_layout);
    PERFORM public.check_blueprint_text_resources_internal(next_layout,b.occasion);
    IF public.blueprint_text_resource_ids_internal(next_layout,b.occasion)
      IS DISTINCT FROM b.layout_text_resource_ids
    THEN RAISE EXCEPTION 'Blueprint % text dependencies changed',b.id; END IF;
    UPDATE eshop.blueprints SET layout=next_layout,
      layout_revision=layout_revision+1,updated_at=now() WHERE id=b.id;
    receipt:=public.record_client_sync_commit_v1(b.occasion,
      'inventory.blueprint.table_label_defaults','inventory',
      jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',b.id::text,
        'operation','update','safeLabel',b.title,'changedFields',jsonb_build_array('layout'))),
      '{}'::text[],'[]'::jsonb,'[]'::jsonb,'service',
      'User-requested majority default; minority overrides preserve every existing table label');
    RAISE NOTICE 'Blueprint %, revision %, tables %, commit %',b.id,
      b.layout_revision+1,table_count,receipt->>'commitId';
  END LOOP;
END $$;
COMMIT;
