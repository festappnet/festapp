-- Scope: 12 reviewed uniform-table plans in vstupenky.online (organization 3).
-- Mixed table typography, table-free plans and already-correct plans are excluded.
-- Private before-image: /tmp/festapp-table-defaults-batch-before.json.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE
  reviewed jsonb := '[{"id":1,"occasion":13,"layout_revision":3,"layout_sha256":"9232fe42baddb1f7c41b0769ffeea55f3abbd6f0b138ebd80fd5982b506b7d40"},{"id":2,"occasion":19,"layout_revision":3,"layout_sha256":"4f0053870185d626fdba8f07a08edff3df126d431f92c8303078cdfee9ec343f"},{"id":4,"occasion":25,"layout_revision":3,"layout_sha256":"c68d620d6f875a3ef75a8c4a932d853927222214719b1493255512303ab86139"},{"id":5,"occasion":27,"layout_revision":2,"layout_sha256":"f6b522a0654e661b186693af8d0fb03dd2141215a8a1f132c05a145badceb8ea"},{"id":23,"occasion":82,"layout_revision":3,"layout_sha256":"b1d4e8bd04eaa12d2cf21f2035d6fa381fc052e5c51b308f3c034e4c8d44e03c"},{"id":25,"occasion":83,"layout_revision":2,"layout_sha256":"9a2a821aeadd0c2263dc2a70b990f8e3c867b254a223f4299cd1c23b6e26e256"},{"id":27,"occasion":92,"layout_revision":3,"layout_sha256":"abbdc125fc405ca7c1016af6293ff9c981f97e6daf55221bd15f116e3d6f7d74"},{"id":29,"occasion":97,"layout_revision":3,"layout_sha256":"78230faa95d1f084df4f1ab9175606b2fa22c729e88f54a37366410f5ae29753"},{"id":33,"occasion":101,"layout_revision":2,"layout_sha256":"50b8035092c52eceb9a7b1edceb112fdac1fce02d7f8b4e0229784c5bce63283"},{"id":36,"occasion":111,"layout_revision":3,"layout_sha256":"b19e67001e83eab23418fb5607ca3ea3a063d799896ffe2647ccd9f47b2d9f44"},{"id":44,"occasion":32316,"layout_revision":4,"layout_sha256":"33605b697339006c4969cff83ad3c844ad337c25d8d89e738c68c2807d1888eb"},{"id":90,"occasion":1072597,"layout_revision":3,"layout_sha256":"2e933d257a09f2970af00fce2bcd76ebfbc7d8c241e082e4d35caee495cf2b9f"}]'::jsonb;
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
    SELECT n->'style'->'label' INTO STRICT shared_label
      FROM jsonb_array_elements(b.layout->'nodes') n WHERE n->>'kind'='table' LIMIT 1;
    SELECT count(*) INTO table_count FROM jsonb_array_elements(b.layout->'nodes') n
      WHERE n->>'kind'='table';
    IF table_count<2 OR shared_label->'size' IS NULL OR
      EXISTS(SELECT 1 FROM jsonb_array_elements(b.layout->'nodes') n
        WHERE n->>'kind'='table' AND n->'style'->'label' IS DISTINCT FROM shared_label)
    THEN RAISE EXCEPTION 'Blueprint % no longer has uniform table labels',b.id; END IF;
    next_layout:=jsonb_set(b.layout,'{styles,kinds,table,label}',
      coalesce(b.layout#>'{styles,kinds,table,label}','{}'::jsonb)||shared_label);
    next_layout:=jsonb_set(next_layout,'{nodes}',(
      SELECT jsonb_agg(CASE WHEN n->>'kind'='table'
        THEN jsonb_set(n,'{style}',(n->'style')-'label') ELSE n END ORDER BY ordinal)
      FROM jsonb_array_elements(next_layout->'nodes') WITH ORDINALITY t(n,ordinal)));
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
      'User-requested uniform table typography defaults; existing labels and deliberate differences preserved');
    RAISE NOTICE 'Blueprint %, revision %, tables %, commit %',b.id,
      b.layout_revision+1,table_count,receipt->>'commitId';
  END LOOP;
END $$;
COMMIT;
