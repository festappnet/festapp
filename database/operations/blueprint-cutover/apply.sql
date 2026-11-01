CREATE OR REPLACE FUNCTION pg_temp.blueprint_cutover_source(p_blueprint bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions SET timezone='UTC' AS $$
SELECT jsonb_build_object('id',b.id,'organization',b.organization,'occasion',b.occasion,'title',b.title,'configuration',b.configuration,'objects',b.objects,'groups',b.groups,'background_svg',b.background_svg,'occasionMeta',(SELECT jsonb_build_object('id',o.id,'organization',o.organization,'unit',o.unit,'end_time',o.end_time,'is_hidden',o.is_hidden,'is_open',o.is_open,'occasion_hidden',o.occasion_hidden) FROM public.occasions o WHERE o.id=b.occasion),'forms',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'occasion',f.occasion,'is_open',f.is_open,'type',f.type) ORDER BY f.id) FROM public.forms f WHERE f.blueprint=b.id),'[]'),'spots',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'occasion',s.occasion,'title',s.title,'product',s.product,'state',s.state,'inventory_context',s.inventory_context,'resource',s.resource,'resource_slot',s.resource_slot) ORDER BY s.id) FROM eshop.spots s WHERE s.blueprint=b.id),'[]'),'products',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'occasion',p.occasion,'product_type',p.product_type,'title',p.title,'price',p.price,'currency_code',p.currency_code) ORDER BY p.id) FROM eshop.products p WHERE p.id IN (SELECT s.product FROM eshop.spots s WHERE s.blueprint=b.id)),'[]')) FROM eshop.blueprints b WHERE b.id=p_blueprint;
$$;
REVOKE ALL ON FUNCTION pg_temp.blueprint_cutover_source(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One-shot reviewed maintenance, never a runtime conversion path.
-- Caller supplies one protected pg_temp.blueprint_cutover_manifest(payload jsonb)
-- row and wraps this file, the forward DDL and migration ledger in ONE transaction.
CREATE OR REPLACE FUNCTION pg_temp.apply_blueprint_layout_cutover()
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $cutover$
DECLARE manifest jsonb; proposal jsonb; b eshop.blueprints; binding jsonb; resource record;
 collection text; kind text; scope text; current_source jsonb; before_facts text; after_facts text;
 v_organization_ids bigint[]; v_occasion_ids bigint[]; expected_ids bigint[]; actual_ids bigint[];
 impacts jsonb; outcome jsonb; item jsonb; descriptor jsonb;
BEGIN
 SELECT payload INTO STRICT manifest FROM pg_temp.blueprint_cutover_manifest;
 IF manifest->>'schemaVersion' IS DISTINCT FROM '1' OR jsonb_typeof(manifest->'plans') IS DISTINCT FROM 'array'
 OR jsonb_typeof(manifest->'scopeOrganizationIds') IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'BLUEPRINT_CUTOVER_INVALID_MANIFEST'; END IF;
 SELECT array_agg(x::bigint ORDER BY x::bigint) INTO v_organization_ids
 FROM jsonb_array_elements_text(manifest->'scopeOrganizationIds') x;
 IF v_organization_ids IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements(manifest->'plans') p
 WHERE NOT (p#>>'{source,organization}')::bigint=ANY(v_organization_ids)) THEN
  RAISE EXCEPTION 'BLUEPRINT_CUTOVER_SCOPE_MISMATCH'; END IF;
 SELECT array_agg(DISTINCT occasion ORDER BY occasion) INTO v_occasion_ids FROM eshop.blueprints WHERE organization=ANY(v_organization_ids);
 PERFORM public.lock_blueprint_scope_internal(v_occasion_ids);
 -- Match ordinary writer lock order: canonical scope first, layout table second.
 LOCK TABLE eshop.blueprints IN SHARE ROW EXCLUSIVE MODE;
 PERFORM 1 FROM public.forms WHERE occasion=ANY(v_occasion_ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.occasions WHERE id=ANY(v_occasion_ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.products WHERE occasion=ANY(v_occasion_ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.blueprints WHERE organization=ANY(v_organization_ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE occasion=ANY(v_occasion_ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(array_agg((p#>>'{source,id}')::bigint ORDER BY (p#>>'{source,id}')::bigint),'{}') INTO expected_ids
 FROM jsonb_array_elements(manifest->'plans') p;
 SELECT coalesce(array_agg(id ORDER BY id),'{}') INTO actual_ids FROM eshop.blueprints
 WHERE organization=ANY(v_organization_ids) AND (layout IS NULL OR layout->>'schemaVersion' IS DISTINCT FROM '2');
 IF expected_ids IS DISTINCT FROM actual_ids THEN RAISE EXCEPTION 'BLUEPRINT_CUTOVER_INCOMPLETE_OR_STALE_INVENTORY'; END IF;
 -- Hash full stored commercial facts, including hold/order links. No PII or
 -- reservation secrets leave the database through this evidence boundary.
 SELECT encode(extensions.digest(convert_to(jsonb_build_object(
  'spots',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM eshop.spots s WHERE occasion=ANY(v_occasion_ids)),
  'orders',(SELECT coalesce(jsonb_agg(to_jsonb(o) ORDER BY id),'[]') FROM eshop.orders o WHERE occasion=ANY(v_occasion_ids)),
  'items',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE o.occasion=ANY(v_occasion_ids)),
  'tickets',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM eshop.tickets t WHERE occasion=ANY(v_occasion_ids)),
  'products',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]') FROM eshop.products p WHERE occasion=ANY(v_occasion_ids)),
  'forms',(SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY id),'[]') FROM public.forms f WHERE occasion=ANY(v_occasion_ids)),
  'payment',(SELECT coalesce(jsonb_agg(to_jsonb(pi) ORDER BY pi.id),'[]') FROM eshop.payment_info pi WHERE id IN(SELECT payment_info FROM eshop.orders WHERE occasion=ANY(v_occasion_ids)))
 )::text,'UTF8'),'sha256'),'hex') INTO before_facts;
 FOR proposal IN SELECT p FROM jsonb_array_elements(manifest->'plans') p ORDER BY (p#>>'{source,id}')::bigint LOOP
  SELECT * INTO STRICT b FROM eshop.blueprints WHERE id=(proposal#>>'{source,id}')::bigint;
  current_source:=pg_temp.blueprint_cutover_source(b.id);
  IF current_source IS DISTINCT FROM proposal->'source'
    OR b.layout IS DISTINCT FROM nullif(proposal->'beforeLayout','null'::jsonb)
    OR b.layout_revision IS DISTINCT FROM (proposal->>'beforeRevision')::bigint THEN
   RAISE EXCEPTION 'BLUEPRINT_CUTOVER_SOURCE_CHANGED: %',b.id; END IF;
  PERFORM public.validate_blueprint_layout_internal(proposal->'layout');
  IF jsonb_array_length(proposal->'seatBindings')<>(SELECT count(*) FROM eshop.spots WHERE blueprint=b.id)
    OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id)
    OR EXISTS(SELECT 1 FROM eshop.blueprint_group_products WHERE blueprint=b.id)
    OR EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings WHERE blueprint=b.id) THEN
   RAISE EXCEPTION 'BLUEPRINT_CUTOVER_BINDING_SET_MISMATCH: %',b.id; END IF;
  scope:='occasion:'||b.occasion;
  FOREACH collection IN ARRAY ARRAY['textLayouts','numberSymbols'] LOOP
   kind:=CASE collection WHEN 'textLayouts' THEN 'text' ELSE 'number' END;
   FOR resource IN SELECT key,value FROM jsonb_each(proposal#>ARRAY['prepared',collection]) LOOP
    descriptor:=resource.value;
    IF EXISTS(SELECT 1 FROM public.blueprint_text_resources r WHERE r.scope_key=scope AND r.resource_id=descriptor->>'id'
      AND (r.payload IS DISTINCT FROM descriptor OR r.resource_kind<>kind)) THEN
     RAISE EXCEPTION 'BLUEPRINT_CUTOVER_RESOURCE_COLLISION'; END IF;
    INSERT INTO public.blueprint_text_resources(scope_key,occasion,resource_id,resource_kind,payload)
    VALUES(scope,b.occasion,descriptor->>'id',kind,descriptor) ON CONFLICT DO NOTHING;
   END LOOP;
  END LOOP;
  PERFORM public.check_blueprint_text_resources_internal(proposal->'layout',b.occasion);
  PERFORM public.check_blueprint_image_resource_internal(proposal->'layout',b.occasion);
  PERFORM public.check_blueprint_bitmap_resources_internal(proposal->'layout',b.occasion);
  FOR binding IN SELECT x FROM jsonb_array_elements(proposal->'seatBindings') x LOOP
   IF NOT EXISTS(SELECT 1 FROM eshop.spots s WHERE s.id=(binding->>'spotId')::bigint
    AND s.blueprint=b.id AND s.occasion=b.occasion
    AND s.product IS NOT DISTINCT FROM (binding->>'productId')::bigint
    AND (s.product IS NULL OR EXISTS(SELECT 1 FROM eshop.products p WHERE p.id=s.product AND p.occasion=b.occasion))
    AND coalesce(s.title,'')=binding->>'title'
    AND coalesce(s.state='black',false)=(binding->>'blocked')::boolean)
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(proposal#>'{layout,nodes}') n
     WHERE n->>'id'=binding->>'nodeId' AND n->>'kind'='seat') THEN
    RAISE EXCEPTION 'BLUEPRINT_CUTOVER_SPOT_FACTS_CHANGED: %',b.id; END IF;
   INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
   VALUES(b.id,(binding->>'nodeId')::uuid,(binding->>'spotId')::bigint,
    (binding->>'selectionUnitId')::uuid,(binding->>'groupNodeId')::uuid,
    (binding->>'blocked')::boolean,binding->>'productAssignmentMode');
  END LOOP;
  FOR binding IN SELECT x FROM jsonb_array_elements(proposal->'groupProducts') x LOOP
   IF NOT EXISTS(SELECT 1 FROM eshop.products p WHERE p.id=(binding->>'productId')::bigint AND p.occasion=b.occasion) THEN
    RAISE EXCEPTION 'BLUEPRINT_CUTOVER_FOREIGN_PRODUCT'; END IF;
   INSERT INTO eshop.blueprint_group_products(blueprint,group_node,product)
   VALUES(b.id,(binding->>'groupNodeId')::uuid,(binding->>'productId')::bigint);
  END LOOP;
  UPDATE eshop.blueprints SET layout=proposal->'layout',layout_revision=layout_revision+1,
   layout_text_resource_ids=public.blueprint_text_resource_ids_internal(proposal->'layout',b.occasion),updated_at=now()
  WHERE id=b.id;
  -- A system commit uses the same private projection invalidation as ordinary
  -- inventory edits. No customer identity is impersonated and no mail is queued.
  SELECT coalesce(jsonb_agg(jsonb_build_object('component','private_inventory','userId',ou."user")),'[]')
  INTO impacts FROM public.occasion_users ou WHERE ou.occasion=b.occasion;
  outcome:=public.record_client_sync_commit_v1(b.occasion,'inventory.blueprint.canonical_cutover','inventory',
   jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',b.id::text,'operation','update',
    'safeLabel',left(b.title,240),'changedFields',jsonb_build_array('layout','bindings'))),
   '{}'::text[],impacts,'[]'::jsonb,'system','One-time canonical layout cutover');
 END LOOP;
 UPDATE eshop.blueprints SET configuration=NULL,objects=NULL,groups=NULL,background_svg=NULL
 WHERE organization=ANY(v_organization_ids);
 -- Every active plan in this scope is now usable through the sole contract.
 FOR b IN SELECT * FROM eshop.blueprints WHERE organization=ANY(v_organization_ids) ORDER BY id LOOP
  PERFORM public.validate_blueprint_layout_internal(b.layout);
  IF EXISTS(SELECT 1 FROM eshop.spots s WHERE s.blueprint=b.id AND NOT EXISTS(
    SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.spot=s.id))
   OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(b.layout->'nodes') n WHERE n->>'id'=sb.node_id::text AND n->>'kind'='seat')) THEN
   RAISE EXCEPTION 'BLUEPRINT_CUTOVER_FINAL_BINDING_MISMATCH: %',b.id; END IF;
 END LOOP;
 SELECT encode(extensions.digest(convert_to(jsonb_build_object(
  'spots',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM eshop.spots s WHERE occasion=ANY(v_occasion_ids)),
  'orders',(SELECT coalesce(jsonb_agg(to_jsonb(o) ORDER BY id),'[]') FROM eshop.orders o WHERE occasion=ANY(v_occasion_ids)),
  'items',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]') FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE o.occasion=ANY(v_occasion_ids)),
  'tickets',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM eshop.tickets t WHERE occasion=ANY(v_occasion_ids)),
  'products',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]') FROM eshop.products p WHERE occasion=ANY(v_occasion_ids)),
  'forms',(SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY id),'[]') FROM public.forms f WHERE occasion=ANY(v_occasion_ids)),
  'payment',(SELECT coalesce(jsonb_agg(to_jsonb(pi) ORDER BY pi.id),'[]') FROM eshop.payment_info pi WHERE id IN(SELECT payment_info FROM eshop.orders WHERE occasion=ANY(v_occasion_ids)))
 )::text,'UTF8'),'sha256'),'hex') INTO after_facts;
 IF before_facts IS DISTINCT FROM after_facts THEN RAISE EXCEPTION 'BLUEPRINT_CUTOVER_COMMERCIAL_FACTS_CHANGED'; END IF;
 RETURN jsonb_build_object('plans',cardinality(expected_ids),'commercialFactsSha256',after_facts,'physicalAndFinancialFactsUnchanged',true);
END $cutover$;

REVOKE ALL ON FUNCTION pg_temp.apply_blueprint_layout_cutover() FROM PUBLIC,anon,authenticated,service_role;
