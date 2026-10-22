-- Blueprint layout integration B. Canonical sources listed below; no production activation.

-- Source: database/functions/blueprint/schema.sql
-- Host commercial state is separate from the portable geometry.
ALTER TABLE eshop.blueprints ADD COLUMN IF NOT EXISTS layout jsonb;
ALTER TABLE eshop.blueprints ADD COLUMN IF NOT EXISTS layout_revision bigint NOT NULL DEFAULT 0 CHECK (layout_revision >= 0);
CREATE TABLE IF NOT EXISTS eshop.blueprint_seat_bindings (
 blueprint bigint NOT NULL REFERENCES eshop.blueprints(id) ON DELETE CASCADE,
 node_id uuid NOT NULL, spot bigint NOT NULL UNIQUE REFERENCES eshop.spots(id),
 selection_unit uuid, group_node uuid, blocked boolean NOT NULL DEFAULT false,
 PRIMARY KEY(blueprint,node_id)
);
CREATE INDEX IF NOT EXISTS blueprint_seat_selection_unit_idx ON eshop.blueprint_seat_bindings(blueprint,selection_unit);
CREATE TABLE IF NOT EXISTS eshop.blueprint_group_products (
 blueprint bigint NOT NULL REFERENCES eshop.blueprints(id) ON DELETE CASCADE,
 group_node uuid NOT NULL, product bigint NOT NULL REFERENCES eshop.products(id), PRIMARY KEY(blueprint,group_node)
);
CREATE TABLE IF NOT EXISTS eshop.blueprint_area_bindings (
 blueprint bigint NOT NULL REFERENCES eshop.blueprints(id) ON DELETE CASCADE,
 node_id uuid NOT NULL, inventory_context bigint NOT NULL REFERENCES public.inventory_contexts(id),
 product bigint NOT NULL REFERENCES eshop.products(id), PRIMARY KEY(blueprint,node_id), UNIQUE(blueprint,inventory_context)
);
ALTER TABLE eshop.blueprint_seat_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.blueprint_group_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.blueprint_area_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.blueprint_seat_bindings,eshop.blueprint_group_products,eshop.blueprint_area_bindings FROM PUBLIC,anon,authenticated;

-- Existing canonical SECURITY DEFINER writers (including occasion copy) retain
-- the postgres owner across CREATE OR REPLACE. Application roles stay revoked.
ALTER TABLE eshop.blueprint_seat_bindings OWNER TO postgres;
ALTER TABLE eshop.blueprint_group_products OWNER TO postgres;
ALTER TABLE eshop.blueprint_area_bindings OWNER TO postgres;


-- Source: database/functions/blueprint/guards.sql
-- Every blueprint writer takes this scope before form/order/product/inventory/spot
-- locks. Sorted occasion IDs allow bulk ticket commands spanning occasions.
CREATE OR REPLACE FUNCTION public.lock_blueprint_scope_internal(p_occasions bigint[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE n bigint;
BEGIN
 FOR n IN SELECT DISTINCT x FROM unnest(p_occasions) x WHERE x IS NOT NULL ORDER BY x LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('blueprint:'||n::text,0));
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.check_blueprint_selection_units_internal(p_spots bigint[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings selected
   JOIN eshop.blueprint_seat_bindings member ON member.blueprint=selected.blueprint AND member.selection_unit=selected.selection_unit
   WHERE selected.spot=ANY(p_spots) AND selected.selection_unit IS NOT NULL
   AND NOT member.spot=ANY(coalesce(p_spots,'{}'::bigint[]))) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_SELECTION_UNIT';
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings selected
   JOIN eshop.blueprint_seat_bindings member ON member.blueprint=selected.blueprint AND member.selection_unit=selected.selection_unit
   JOIN eshop.spots s ON s.id=member.spot JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket JOIN eshop.tickets t ON t.id=opt.ticket
   WHERE selected.spot=ANY(p_spots) AND selected.selection_unit IS NOT NULL AND t.state='used') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SELECTION_UNIT_USED';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.blueprint_selection_unit_spots_internal(p_spot bigint)
RETURNS bigint[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(array_agg(member.spot ORDER BY member.spot),ARRAY[p_spot])
 FROM eshop.blueprint_seat_bindings selected JOIN eshop.blueprint_seat_bindings member
 ON member.blueprint=selected.blueprint AND member.selection_unit=selected.selection_unit
 WHERE selected.spot=p_spot AND selected.selection_unit IS NOT NULL
$$;



-- Source: database/functions/blueprint/resources.sql
ALTER TABLE public.ticket_font_assets ADD COLUMN IF NOT EXISTS layout_outline jsonb;
CREATE OR REPLACE FUNCTION public.register_blueprint_layout_font(p_font_id text,p_outline jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE asset public.ticket_font_assets; merged jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE insufficient_privilege USING MESSAGE='font service required'; END IF;
 SELECT * INTO asset FROM public.ticket_font_assets WHERE id=p_font_id FOR UPDATE;
 IF NOT FOUND OR p_outline->>'id' IS DISTINCT FROM p_font_id OR p_outline->>'hash' IS DISTINCT FROM asset.metadata->>'sha256'
  OR p_outline->>'family' IS DISTINCT FROM asset.metadata->>'family' OR jsonb_typeof(p_outline->'glyphs') IS DISTINCT FROM 'object'
  OR coalesce((p_outline->>'unitsPerEm')::numeric,0)<=0 OR p_outline->>'ascent' IS NULL OR p_outline->>'descent' IS NULL
  OR octet_length(p_outline::text)>8388608 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_outline) k WHERE k NOT IN ('id','hash','family','unitsPerEm','ascent','descent','glyphs')) THEN
  RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_INVALID_FONT_OUTLINE'; END IF;
 IF asset.layout_outline IS NOT NULL AND asset.layout_outline-'glyphs' IS DISTINCT FROM p_outline-'glyphs' THEN
  RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_FONT_METRICS_CHANGED'; END IF;
 merged:=jsonb_set(p_outline,'{glyphs}',coalesce(asset.layout_outline->'glyphs','{}')||(p_outline->'glyphs'));
 UPDATE public.ticket_font_assets SET layout_outline=merged WHERE id=p_font_id;
 RETURN merged;
END $$;


CREATE OR REPLACE FUNCTION public.blueprint_layout_resources_internal(p_layout jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('protocol',1,'fonts',coalesce(jsonb_object_agg(a.id,a.layout_outline),'{}'),'assets','{}'::jsonb)
 FROM public.ticket_font_assets a WHERE a.layout_outline IS NOT NULL AND a.id IN (
  SELECT p_layout#>>'{defaultTextStyle,fontId}' UNION SELECT n#>>'{properties,fontId}' FROM jsonb_array_elements(coalesce(p_layout->'nodes','[]')) n
  UNION SELECT n->>'fontId' FROM jsonb_array_elements(coalesce(p_layout->'nodes','[]')) n)
$$;



-- Source: database/functions/blueprint/availability.sql
-- Same counts and context quantities as finalize_ticket_order/apply_allocations.
-- This snapshot never reserves quantity; checkout remains authoritative.
CREATE OR REPLACE FUNCTION public.blueprint_product_availability_internal(p_product bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE p eshop.products; c record; total bigint; occupied bigint; cap bigint; available bigint:=2147483647; capacity bigint:=2147483647;
BEGIN
 SELECT * INTO p FROM eshop.products WHERE id=p_product;
 IF NOT FOUND THEN RETURN jsonb_build_object('capacity',0,'available',0,'reason','PRODUCT_NOT_FOUND'); END IF;
 IF coalesce(p.maximum,0)>0 THEN
  capacity:=p.maximum;
  available:=greatest(0,p.maximum-(SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id));
 END IF;
 FOR c IN SELECT pic.inventory_context,pic.quantity,ip.sellable_capacity FROM eshop.product_inventory_contexts pic
  JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=p.id LOOP
  SELECT count(*),count(*) FILTER(WHERE order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>statement_timestamp()))
   INTO total,occupied FROM eshop.spots WHERE inventory_context=c.inventory_context;
  cap:=least(total,coalesce(c.sellable_capacity,total));
  capacity:=least(capacity,cap/greatest(c.quantity,1));
  available:=least(available,greatest(0,cap-occupied)/greatest(c.quantity,1));
 END LOOP;
 RETURN jsonb_build_object('capacity',capacity,'available',CASE WHEN p.is_hidden THEN 0 ELSE available END,
  'reason',CASE WHEN p.is_hidden THEN 'PRODUCT_HIDDEN' WHEN available=0 THEN 'PRODUCT_CAPACITY_EXCEEDED' ELSE NULL END);
END $$;
CREATE OR REPLACE FUNCTION public.blueprint_area_availability_internal(p_blueprint bigint,p_form bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('nodeId',b.node_id,'productId',b.product,'inventoryContextId',b.inventory_context)||
  CASE WHEN p_form IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
   WHERE ff.form=p_form AND p.id=b.product AND ff.type='product_type' AND ff.is_ticket_field AND NOT ff.is_hidden)
  THEN jsonb_build_object('capacity',(public.blueprint_product_availability_internal(b.product)->'capacity'),'available',0,'reason','PRODUCT_NOT_IN_FORM')
  ELSE public.blueprint_product_availability_internal(b.product) END ORDER BY b.node_id),'[]')
 FROM eshop.blueprint_area_bindings b WHERE b.blueprint=p_blueprint
$$;



-- Source: database/functions/blueprint/projections.sql
-- Private host bindings only contain commercial identities; occupancy details
-- remain in the permission-checked admin reader's existing projection.
CREATE OR REPLACE FUNCTION public.blueprint_binding_projection_internal(p_blueprint bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object(
 'seatBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',b.node_id,'spotId',b.spot,'productId',s.product,'title',s.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked) ORDER BY b.node_id)
  FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint),'[]'),
 'groupProducts',coalesce((SELECT jsonb_agg(jsonb_build_object('groupNodeId',group_node,'productId',product) ORDER BY group_node) FROM eshop.blueprint_group_products WHERE blueprint=p_blueprint),'[]'),
 'areaBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',node_id,'inventoryContextId',inventory_context,'productId',product) ORDER BY node_id) FROM eshop.blueprint_area_bindings WHERE blueprint=p_blueprint),'[]'))
$$;
CREATE OR REPLACE FUNCTION public.blueprint_public_binding_projection_internal(p_blueprint bigint,p_secret uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.blueprint_binding_projection_internal(p_blueprint)||jsonb_build_object('seatBindings',coalesce(
 (SELECT jsonb_agg(jsonb_build_object('nodeId',b.node_id,'spotId',b.spot,'productId',s.product,'title',s.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked,'status',CASE
 WHEN b.blocked OR s.product IS NULL THEN 'unavailable' WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
 WHEN s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp() THEN CASE WHEN s.secret=p_secret THEN 'selected_by_me' ELSE 'selected' END
 ELSE 'available' END) ORDER BY b.node_id) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint),'[]'))
$$;



-- Source: database/functions/blueprint/validation.sql
CREATE OR REPLACE FUNCTION public.validate_blueprint_polygon_internal(p_points jsonb,p_closed boolean)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE i int;j int;size int; a jsonb;b jsonb;c jsonb;d jsonb;ab_c numeric;ab_d numeric;cd_a numeric;cd_b numeric; area numeric:=0;
BEGIN
 IF jsonb_typeof(p_points) IS DISTINCT FROM 'array' OR jsonb_array_length(p_points) NOT BETWEEN (CASE WHEN p_closed THEN 3 ELSE 2 END) AND 512 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VERTICES'; END IF;
 size:=jsonb_array_length(p_points);
 FOR a IN SELECT * FROM jsonb_array_elements(p_points) LOOP
  IF jsonb_typeof(a)<>'array' OR jsonb_array_length(a)<>2 OR jsonb_typeof(a->0)<>'number' OR jsonb_typeof(a->1)<>'number' OR abs((a->>0)::numeric)>1000000000 OR abs((a->>1)::numeric)>1000000000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VERTICES'; END IF;
 END LOOP;
 IF NOT p_closed THEN RETURN; END IF;
 FOR i IN 0..size-1 LOOP
  a:=p_points->i;b:=p_points->((i+1)%size);
  area:=area+(a->>0)::numeric*(b->>1)::numeric-(b->>0)::numeric*(a->>1)::numeric;
  FOR j IN i+1..size-1 LOOP
   IF j=i+1 OR (i=0 AND j=size-1) THEN CONTINUE; END IF;
   c:=p_points->j;d:=p_points->((j+1)%size);
   ab_c:=((b->>0)::numeric-(a->>0)::numeric)*((c->>1)::numeric-(a->>1)::numeric)-((b->>1)::numeric-(a->>1)::numeric)*((c->>0)::numeric-(a->>0)::numeric);
   ab_d:=((b->>0)::numeric-(a->>0)::numeric)*((d->>1)::numeric-(a->>1)::numeric)-((b->>1)::numeric-(a->>1)::numeric)*((d->>0)::numeric-(a->>0)::numeric);
   cd_a:=((d->>0)::numeric-(c->>0)::numeric)*((a->>1)::numeric-(c->>1)::numeric)-((d->>1)::numeric-(c->>1)::numeric)*((a->>0)::numeric-(c->>0)::numeric);
   cd_b:=((d->>0)::numeric-(c->>0)::numeric)*((b->>1)::numeric-(c->>1)::numeric)-((d->>1)::numeric-(c->>1)::numeric)*((b->>0)::numeric-(c->>0)::numeric);
   IF ab_c*ab_d<=0 AND cd_a*cd_b<=0 AND greatest(least((a->>0)::numeric,(b->>0)::numeric),least((c->>0)::numeric,(d->>0)::numeric))<=least(greatest((a->>0)::numeric,(b->>0)::numeric),greatest((c->>0)::numeric,(d->>0)::numeric))
    AND greatest(least((a->>1)::numeric,(b->>1)::numeric),least((c->>1)::numeric,(d->>1)::numeric))<=least(greatest((a->>1)::numeric,(b->>1)::numeric),greatest((c->>1)::numeric,(d->>1)::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SELF_INTERSECTION'; END IF;
  END LOOP;
 END LOOP;
 IF abs(area)<0.000000001 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_DEGENERATE_POLYGON'; END IF;
END $$;


-- Storage boundary validation. Numeric limits and authoring keys mirror the
-- public layout protocol; commercial identities never belong in the document.
CREATE OR REPLACE FUNCTION public.validate_blueprint_layout_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE n jsonb; value jsonb; field text; index_nodes jsonb; current_node jsonb; seen text[]; depth int; a jsonb; ids text[]; referenced text; font jsonb; ch text; shape text;
 geometry_keys text[]:=ARRAY['shape','cornerRadius','appearanceOverrides','seatStyle','seatWidth','seatHeight','seatGap','seatSpacing','seatEdgePadding','objectStyle','fill','stroke','strokeWidth','strokeStyle','dash','opacity','points','holes','pathPattern','zigzagTeeth','zigzagAmplitude','arrowHeadLength','text','fontId','labelOrientation','fontStyle','size','color','align','lineHeight','bold','italic','symbol','role','obstacle','manual','manualRotation','slot','assembly','rows','seatsPerRow','blocks','aisle','spacing','rowSpacing','arc','left','right','rear','decks','upperRows','upperRear','deck','compartments','seats','capacity','furniture','guestSide'];
BEGIN
 IF jsonb_typeof(p_doc) IS DISTINCT FROM 'object' OR p_doc->>'schemaVersion' IS DISTINCT FROM '1' OR p_doc->>'symbolSetVersion' IS DISTINCT FROM '1'
  OR jsonb_typeof(p_doc->'nodes') IS DISTINCT FROM 'array' OR jsonb_typeof(p_doc->'canvas') IS DISTINCT FROM 'object' THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LAYOUT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc) key WHERE key<>ALL(ARRAY['appearance','schemaVersion','symbolSetVersion','canvas','defaultTextStyle','nodes','sections','selectionUnits','attachments','generators','background','presets'])) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_UNKNOWN_LAYOUT_FIELD'; END IF;
 IF jsonb_array_length(p_doc->'nodes')>25000 OR (SELECT count(*) FROM jsonb_array_elements(p_doc->'nodes') x WHERE x->>'kind'='seat')>20000 THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_LIMIT'; END IF;
 IF EXISTS(WITH RECURSIVE entries(value,key,depth) AS (
   SELECT p_doc,''::text,0 UNION ALL SELECT child.value,child.key,entries.depth+1 FROM entries CROSS JOIN LATERAL (
    SELECT object.value,object.key FROM jsonb_each(CASE WHEN jsonb_typeof(entries.value)='object' THEN entries.value ELSE '{}'::jsonb END) object
    UNION ALL SELECT element.value,''::text FROM jsonb_array_elements(CASE WHEN jsonb_typeof(entries.value)='array' THEN entries.value ELSE '[]'::jsonb END) element
   ) child WHERE entries.depth<=64)
   SELECT 1 FROM entries WHERE entries.depth>64 OR lower(regexp_replace(key,'[_-]','','g')) IN
    ('spot','spotid','product','productid','price','unitprice','currency','orderid','ticket','ticketid','secret','secretid','token','accesstoken','refreshtoken','customer','customerid','email','payment','paymentid','reservation','reservationid','hold','holdid','selected','pending','status','camera','viewport') LIMIT 1) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_NON_PORTABLE_LAYOUT'; END IF;
 -- No assets are accepted until the host has a persisted safe manifest.
 IF p_doc->'background' IS NOT NULL AND p_doc->'background'<>'null'::jsonb THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_ASSET_RESOURCE_NOT_READY'; END IF;
 FOREACH field IN ARRAY ARRAY['sections','selectionUnits','attachments','generators','presets'] LOOP
  IF p_doc ? field AND jsonb_typeof(p_doc->field) IS DISTINCT FROM 'array' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LAYOUT_COLLECTION'; END IF;
 END LOOP;
 FOREACH field IN ARRAY ARRAY['x','y','width','height'] LOOP
  value:=p_doc->'canvas'->field;
  IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR abs(value::numeric)>1000000000
   OR (field IN ('width','height') AND (value::numeric<64 OR value::numeric>1000000)) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CANVAS'; END IF;
 END LOOP;
 IF coalesce(p_doc#>>'{canvas,fill}','') !~ '^#[0-9a-fA-F]{8}$'
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc->'canvas') key WHERE key<>ALL(ARRAY['x','y','width','height','fill','floorStyle']))
  OR (p_doc#>>'{canvas,floorStyle}' IS NOT NULL AND p_doc#>>'{canvas,floorStyle}' NOT IN ('plain','wood','tile','carpet')) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CANVAS'; END IF;
 IF jsonb_typeof(p_doc->'defaultTextStyle') IS DISTINCT FROM 'object' OR coalesce(p_doc#>>'{defaultTextStyle,color}','') !~ '^#[0-9a-fA-F]{8}$'
  OR jsonb_typeof(p_doc#>'{defaultTextStyle,size}') IS DISTINCT FROM 'number' OR (p_doc#>>'{defaultTextStyle,size}')::numeric NOT BETWEEN 1 AND 4096
  OR nullif(p_doc#>>'{defaultTextStyle,fontId}','') IS NULL
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc->'defaultTextStyle') key WHERE key<>ALL(ARRAY['fontId','size','color','align','lineHeight','bold','italic','fontStyle'])) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT_STYLE'; END IF;
 IF p_doc#>>'{defaultTextStyle,align}' IS NOT NULL AND p_doc#>>'{defaultTextStyle,align}' NOT IN ('left','center','right')
  OR p_doc#>>'{defaultTextStyle,fontStyle}' IS NOT NULL AND p_doc#>>'{defaultTextStyle,fontStyle}' NOT IN ('normal','italic')
  OR p_doc#>'{defaultTextStyle,lineHeight}' IS NOT NULL AND (jsonb_typeof(p_doc#>'{defaultTextStyle,lineHeight}')<>'number' OR (p_doc#>>'{defaultTextStyle,lineHeight}')::numeric NOT BETWEEN 0.8 AND 3) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT_STYLE'; END IF;
 FOREACH field IN ARRAY ARRAY['bold','italic'] LOOP IF p_doc->'defaultTextStyle' ? field AND jsonb_typeof(p_doc->'defaultTextStyle'->field)<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT_STYLE'; END IF; END LOOP;
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}') INTO index_nodes FROM jsonb_array_elements(p_doc->'nodes') x;
 IF (SELECT count(*) FROM jsonb_array_elements(p_doc->'nodes'))<>(SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(p_doc->'nodes') x) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_NODE'; END IF;
 FOR n IN SELECT * FROM jsonb_array_elements(p_doc->'nodes') LOOP
  IF jsonb_typeof(n) IS DISTINCT FROM 'object' OR coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   OR coalesce(n->>'kind','') NOT IN ('group','table','seat','furniture','capacityArea','shape','text')
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(n) key WHERE key<>ALL(geometry_keys||ARRAY['id','kind','parentId','transform','width','height','z','locked','label'])) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE',DETAIL=jsonb_build_object('nodeId',n->>'id')::text; END IF;
  IF jsonb_typeof(n->'transform') IS DISTINCT FROM 'object'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(n->'transform') key WHERE key NOT IN ('x','y','rotation')) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GEOMETRY'; END IF;
  FOREACH field IN ARRAY ARRAY['width','height','x','y','rotation'] LOOP
   value:=CASE WHEN field IN ('width','height') THEN n->field ELSE n->'transform'->field END;
   IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR abs(value::numeric)>1000000000 OR (field IN ('width','height') AND value::numeric<=0) THEN
    RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GEOMETRY',DETAIL=jsonb_build_object('nodeId',n->>'id')::text; END IF;
  END LOOP;
  IF n ? 'z' AND (jsonb_typeof(n->'z')<>'number' OR (n->>'z')::numeric<>trunc((n->>'z')::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_Z'; END IF;
  FOREACH field IN ARRAY ARRAY['locked','bold','italic','manual','manualRotation','obstacle'] LOOP
   IF n ? field AND jsonb_typeof(n->field)<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_BOOLEAN'; END IF;
  END LOOP;
  FOREACH field IN ARRAY ARRAY['fill','stroke','color'] LOOP
   IF n ? field AND coalesce(n->>field,'') !~ '^#[0-9a-fA-F]{8}$' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_COLOR'; END IF;
  END LOOP;
  FOREACH field IN ARRAY ARRAY['cornerRadius','strokeWidth','seatWidth','seatHeight','seatGap','seatSpacing','seatEdgePadding','opacity','size','lineHeight','zigzagAmplitude','arrowHeadLength','spacing','rowSpacing'] LOOP
   IF n ? field THEN
    value:=n->field;
    IF jsonb_typeof(value)<>'number' OR value::numeric<0 OR value::numeric>1000000000
     OR (field='opacity' AND value::numeric>1) OR (field='size' AND value::numeric NOT BETWEEN 1 AND 4096)
     OR (field='lineHeight' AND value::numeric NOT BETWEEN 0.8 AND 3)
     OR (field='arrowHeadLength' AND value::numeric<=0)
     OR (field IN ('seatWidth','seatHeight') AND value::numeric NOT BETWEEN 1 AND 1000000) THEN
     RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_STYLE'; END IF;
   END IF;
  END LOOP;
  IF n->>'objectStyle' IS NOT NULL AND n->>'objectStyle' NOT IN ('round','simple','minimal','wood','lounge','transit','hall','banquet')
   OR n->>'seatStyle' IS NOT NULL AND n->>'seatStyle' NOT IN ('roundUpholstered','round','plain','wood','upholstered','transit','banquet')
   OR n->>'fontStyle' IS NOT NULL AND n->>'fontStyle' NOT IN ('normal','italic')
   OR n->>'align' IS NOT NULL AND n->>'align' NOT IN ('left','center','right') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_STYLE'; END IF;
  IF n ? 'dash' AND (jsonb_typeof(n->'dash')<>'array' OR EXISTS(SELECT 1 FROM jsonb_array_elements(n->'dash') dash WHERE jsonb_typeof(dash)<>'number' OR dash::numeric<=0)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DASH'; END IF;
  IF n ? 'capacity' AND (jsonb_typeof(n->'capacity')<>'number' OR (n->>'capacity')::numeric<0 OR (n->>'capacity')::numeric<>trunc((n->>'capacity')::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
  shape:=n->>'shape';
  IF shape IS NOT NULL AND shape NOT IN ('rect','rectangle','roundedRect','ellipse','oval','circle','round','polygon','polyline','line','arrow') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SHAPE'; END IF;
  IF n->>'labelOrientation' IS NOT NULL AND n->>'labelOrientation' NOT IN ('screen','object') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LABEL_ORIENTATION'; END IF;
  IF n->>'symbol' IS NOT NULL AND n->>'symbol' NOT IN ('chair','bench','sofa','wheelchair','driver') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SYMBOL'; END IF;
  IF n->>'strokeStyle' IS NOT NULL AND n->>'strokeStyle' NOT IN ('solid','dashed','dotted') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STROKE'; END IF;
  IF n->>'text' IS NOT NULL AND (jsonb_typeof(n->'text')<>'string' OR length(n->>'text')>4096) OR n->>'kind'='text' AND n->>'text' IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT'; END IF;
  IF n ? 'label' AND jsonb_typeof(n->'label')<>'string' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LABEL'; END IF;
  IF n ? 'points' THEN PERFORM public.validate_blueprint_polygon_internal(n->'points',shape='polygon');
  ELSIF shape='polygon' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MISSING_VERTICES'; END IF;
  IF n ? 'holes' THEN
   IF shape<>'polygon' OR jsonb_typeof(n->'holes')<>'array' OR jsonb_array_length(n->'holes')>128 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_HOLES'; END IF;
   FOR value IN SELECT * FROM jsonb_array_elements(n->'holes') LOOP PERFORM public.validate_blueprint_polygon_internal(value,true); END LOOP;
  END IF;
  current_node:=n; seen:=ARRAY[n->>'id'];depth:=1;
  WHILE current_node->>'parentId' IS NOT NULL LOOP
   referenced:=current_node->>'parentId';
   IF referenced=ANY(seen) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_PARENT_CYCLE'; END IF;
   current_node:=index_nodes->referenced;
   IF current_node IS NULL OR current_node->>'kind' NOT IN ('group','table','furniture') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PARENT'; END IF;
   seen:=array_append(seen,referenced);depth:=depth+1;
   IF depth>16 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_DEPTH_LIMIT'; END IF;
  END LOOP;
 END LOOP;
 -- All authoring IDs use a common UUID namespace, including sections/units.
 SELECT array_agg(x->>'id') INTO ids FROM jsonb_array_elements(p_doc->'nodes') x;
 FOR n IN SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) item UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'selectionUnits','[]')) item
  UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'generators','[]')) item UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) item LOOP
  IF coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' OR n->>'id'=ANY(ids) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_OR_INVALID_ID'; END IF;
  ids:=array_append(ids,n->>'id');
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) LOOP
  IF coalesce(index_nodes->(a->>'seatId')->>'kind','')<>'seat' OR coalesce(index_nodes->(a->>'targetId')->>'kind','')<>'table'
   OR index_nodes->(a->>'seatId')->>'parentId' IS DISTINCT FROM a->>'targetId'
   OR coalesce(a->>'kind','') NOT IN ('edge','perimeter') OR jsonb_typeof(a->'t') IS DISTINCT FROM 'number' OR (a->>'t')::numeric NOT BETWEEN 0 AND 1
   OR jsonb_typeof(a->'gap') IS DISTINCT FROM 'number' OR (a->>'gap')::numeric<0 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_ATTACHMENT'; END IF;
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) LOOP
  IF coalesce(index_nodes->(a->>'rootId')->>'kind','')<>'group' OR coalesce(a->>'title','')='' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SECTION'; END IF;
  IF a->'outline' IS NOT NULL AND a->'outline'<>'null'::jsonb THEN PERFORM public.validate_blueprint_polygon_internal(a->'outline',true); END IF;
 END LOOP;
 IF EXISTS(SELECT attachment->>'seatId' FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) attachment GROUP BY attachment->>'seatId' HAVING count(*)>1)
  OR EXISTS(SELECT section->>'rootId' FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) section GROUP BY section->>'rootId' HAVING count(*)>1) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_AUTHORING_REFERENCE'; END IF;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'generators','[]')) LOOP
  referenced:=coalesce(a->>'rootId',a->>'assemblyId');
  IF coalesce(a->>'kind','') NOT IN ('rows','row','arc','bus','compartments','table') OR coalesce(index_nodes->referenced->>'kind','')<>(CASE WHEN a->>'kind'='table' THEN 'table' ELSE 'group' END)
   OR (a ? 'version' AND a->>'version'<>'1') OR (a ? 'rootId' AND a ? 'assemblyId' AND a->>'rootId'<>a->>'assemblyId') THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GENERATOR'; END IF;
  IF a ? 'nodeIds' AND (jsonb_typeof(a->'nodeIds')<>'array' OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(a->'nodeIds') member WHERE NOT index_nodes ? member)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GENERATOR_MEMBER'; END IF;
 END LOOP;
 IF jsonb_array_length(coalesce(p_doc->'presets','[]'))>100 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_PRESET_LIMIT'; END IF;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) LOOP
  IF coalesce(a->>'title','')='' OR jsonb_typeof(a->'document') IS DISTINCT FROM 'object' OR jsonb_array_length(coalesce(a#>'{document,nodes}','[]'))>2000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRESET'; END IF;
  PERFORM public.validate_blueprint_layout_internal(a->'document');
 END LOOP;
 -- Ready font outlines must cover actual label/text characters after reopening.
 FOR n IN SELECT * FROM jsonb_array_elements(p_doc->'nodes') LOOP
  referenced:=coalesce(n->>'fontId',p_doc#>>'{defaultTextStyle,fontId}');
  SELECT layout_outline INTO font FROM public.ticket_font_assets WHERE id=referenced;
  IF font IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_RESOURCE_NOT_READY'; END IF;
  FOR ch IN SELECT regexp_split_to_table(coalesce(n->>'text',n->>'label',''),'') LOOP
   IF ch NOT IN ('',E'\n',E'\r') AND NOT (font->'glyphs' ? ch) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_GLYPH_NOT_READY',DETAIL=jsonb_build_object('nodeId',n->>'id')::text; END IF;
  END LOOP;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM public.ticket_font_assets WHERE id=p_doc#>>'{defaultTextStyle,fontId}' AND layout_outline IS NOT NULL) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_RESOURCE_NOT_READY'; END IF;
END $$;



-- Source: database/functions/blueprint/save.sql
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_internal_v1(p_blueprint jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean;
 pool public.inventory_pools; capacity_int bigint;
 node_index jsonb; unit_index jsonb; seat_count bigint;
 doc jsonb:=p_blueprint->'layout'; result jsonb; expected bigint; issue text; all_seats uuid[]; supplied uuid[];
BEGIN
 IF nullif(p_blueprint->>'id','') IS NULL THEN
  IF (coalesce(public.get_is_editor_on_occasion((p_blueprint->>'occasion')::bigint),false) OR coalesce(public.get_is_manager_on_occasion((p_blueprint->>'occasion')::bigint),false)) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  INSERT INTO eshop.blueprints(occasion,organization,title) SELECT id,organization,p_blueprint->>'title' FROM public.occasions WHERE id=(p_blueprint->>'occasion')::bigint RETURNING * INTO b;
 ELSE
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint FOR UPDATE;
 END IF;
 IF b.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_NOT_FOUND'; END IF;
 IF (coalesce(public.get_is_editor_on_occasion(b.occasion),false) OR coalesce(public.get_is_manager_on_occasion(b.occasion),false)) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 PERFORM public.check_occasion_writable(b.occasion);
 expected:=(p_blueprint->>'expected_layout_revision')::bigint;
 IF expected IS NULL OR expected<>b.layout_revision THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
 PERFORM public.validate_blueprint_layout_internal(doc);
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}'),count(*) FILTER(WHERE x->>'kind'='seat') INTO node_index,seat_count FROM jsonb_array_elements(doc->'nodes') x;
 -- Membership is projected from the document, never trusted from an overlay.
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u WHERE
   (u->>'id')::uuid IS NULL OR jsonb_array_length(u->'nodeIds')=0 OR coalesce(u->>'kind','atomic')<>'atomic')
  OR EXISTS(SELECT member FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member GROUP BY member HAVING count(*)>1)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member
   WHERE coalesce(node_index->member->>'kind','')<>'seat') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SELECTION_UNITS'; END IF;
 SELECT coalesce(jsonb_object_agg(member,u->>'id'),'{}') INTO unit_index
 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member;
 -- Keep the existing financial resource lock ordering, before spot row locks.
 PERFORM 1 FROM eshop.products WHERE occasion=b.occasion ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE blueprint=b.id ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT change->>'nodeId' FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) change GROUP BY change->>'nodeId' HAVING count(*)>1) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_DUPLICATE_SEAT_CHANGE'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid;
  SELECT * INTO binding FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN
   IF binding.node_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_NOT_FOUND',DETAIL=c::text; END IF;
   SELECT * INTO s FROM eshop.spots WHERE id=binding.spot;
   IF s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
   DELETE FROM eshop.spots WHERE id=s.id;
   CONTINUE;
  END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'seat' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SEAT_CHANGE',DETAIL=c::text; END IF;
  IF NOT c ? 'productId' OR NOT c ? 'blocked' OR NOT c ? 'groupNodeId' OR NOT c ? 'selectionUnitId' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_SEAT_CHANGE',DETAIL=c::text; END IF;
  product_id:=(c->>'productId')::bigint; group_id:=(c->>'groupNodeId')::uuid; unit_id:=(c->>'selectionUnitId')::uuid; blocked_value:=(c->>'blocked')::boolean;
  IF blocked_value IS NULL OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_PRODUCT',DETAIL=c::text; END IF;
  IF group_id IS NOT NULL AND coalesce(node_index->group_id::text->>'kind','') NOT IN ('group','table','furniture') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP',DETAIL=c::text; END IF;
  IF unit_id IS DISTINCT FROM (unit_index->>node::text)::uuid THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_UNIT_MEMBERSHIP_MISMATCH',DETAIL=c::text; END IF;
  spot_id:=(c->>'spotId')::bigint;
  IF binding.node_id IS NOT NULL AND spot_id IS DISTINCT FROM binding.spot THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_IDENTITY_CHANGED',DETAIL=c::text; END IF;
  IF spot_id IS NOT NULL THEN
   SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=b.id AND occasion=b.occasion;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_SCOPE_MISMATCH',DETAIL=c::text; END IF;
   IF (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()))
    AND (s.product IS DISTINCT FROM product_id OR s.title IS DISTINCT FROM c->>'title'
     OR coalesce(binding.blocked,false) IS DISTINCT FROM blocked_value OR binding.selection_unit IS DISTINCT FROM unit_id OR binding.group_node IS DISTINCT FROM group_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   UPDATE eshop.spots SET product=product_id,title=c->>'title',updated_at=now() WHERE id=spot_id;
  ELSE
   INSERT INTO eshop.spots(blueprint,occasion,product,title) VALUES(b.id,b.occasion,product_id,c->>'title') RETURNING id INTO spot_id;
  END IF;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
   VALUES(b.id,node,spot_id,unit_id,group_id,blocked_value)
   ON CONFLICT(blueprint,node_id) DO UPDATE SET selection_unit=excluded.selection_unit,group_node=excluded.group_node,blocked=excluded.blocked;
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND coalesce(node_index->sb.node_id::text->>'kind','')<>'seat')
  OR (SELECT count(*) FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id)<>seat_count
  OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.selection_unit IS DISTINCT FROM
   (unit_index->>sb.node_id::text)::uuid) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_SET_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.group_node IS NOT NULL AND coalesce(node_index->sb.group_node::text->>'kind','') NOT IN ('group','table','furniture')) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'groupProductChanges','[]')) LOOP
  IF NOT c ? 'productId' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_GROUP_CHANGE',DETAIL=c::text; END IF;
  node:=(c->>'groupNodeId')::uuid; product_id:=(c->>'productId')::bigint;
  IF coalesce(node_index->node::text->>'kind','') NOT IN ('table','group','furniture')
   OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP_PRODUCT',DETAIL=c::text; END IF;
  DELETE FROM eshop.blueprint_group_products WHERE blueprint=b.id AND group_node=node;
  IF product_id IS NOT NULL THEN INSERT INTO eshop.blueprint_group_products VALUES(b.id,node,product_id); END IF;
 END LOOP;
 DELETE FROM eshop.blueprint_group_products gp WHERE blueprint=b.id AND NOT node_index ? gp.group_node::text;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'areaBindingChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid; product_id:=(c->>'productId')::bigint;
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN CONTINUE; END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'capacityArea'
   OR NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=product_id AND pic.inventory_context=(c->>'inventoryContextId')::bigint AND p.occasion=b.occasion AND ip.occasion=b.occasion) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_AREA_BINDING',DETAIL=c::text; END IF;
  IF c ? 'capacity' THEN
   capacity_int:=(c->>'capacity')::bigint;
   IF capacity_int IS NULL OR capacity_int<0 OR capacity_int>1000000 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
   SELECT ip.* INTO pool FROM public.inventory_pools ip JOIN public.inventory_contexts ic ON ic.inventory_pool=ip.id WHERE ic.id=(c->>'inventoryContextId')::bigint;
   PERFORM public.update_inventory_pool_bundle(jsonb_build_object('pool',to_jsonb(pool)||jsonb_build_object('sellable_capacity',capacity_int)));
  END IF;
  INSERT INTO eshop.blueprint_area_bindings VALUES(b.id,node,(c->>'inventoryContextId')::bigint,product_id);
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab WHERE blueprint=b.id AND coalesce(node_index->ab.node_id::text->>'kind','')<>'capacityArea') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_AREA_BINDING_SET_MISMATCH'; END IF;
 UPDATE eshop.blueprints SET layout=doc,layout_revision=layout_revision+1,updated_at=now(),title=coalesce(p_blueprint->>'title',title) WHERE id=b.id RETURNING * INTO b;
 result:=public.blueprint_binding_projection_internal(b.id)||jsonb_build_object('code',200,'blueprint_id',b.id,'layout_revision',b.layout_revision,
  'document_hash',encode(extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),'hex'));
 IF octet_length(result::text)>4194304 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_RESULT_TOO_LARGE'; END IF;
 RETURN result;
END $$;



-- Source: database/functions/blueprint/update_blueprint_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.update_blueprint_client_sync_v1(
  p_blueprint jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_blueprint bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_result jsonb; v_reason text; v_detail text; v_issue jsonb;
BEGIN
  IF p_blueprint IS NULL OR jsonb_typeof(p_blueprint)<>'object'
    OR octet_length(p_blueprint::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid blueprint aggregate'; END IF;
  v_occasion:=NULLIF(p_blueprint->>'occasion','')::bigint;
  v_blueprint:=NULLIF(p_blueprint->>'id','')::bigint;
  IF v_blueprint IS NOT NULL THEN SELECT occasion INTO v_occasion FROM eshop.blueprints WHERE id=v_blueprint; END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR (CASE WHEN p_blueprint ? 'layout' THEN
      coalesce(public.get_is_editor_on_occasion(v_occasion),false) OR coalesce(public.get_is_manager_on_occasion(v_occasion),false)
      ELSE public.get_is_editor_order_on_occasion(v_occasion) END) IS NOT TRUE
    OR (v_blueprint IS NOT NULL AND NOT EXISTS (SELECT 1 FROM eshop.blueprints b
      WHERE b.id=v_blueprint AND b.occasion=v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE=CASE WHEN p_blueprint ? 'layout' THEN 'blueprint editor required' ELSE 'order editor required' END; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'blueprint',p_blueprint)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.blueprint.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.spots s
    ON s.order_product_ticket=opt.id
  WHERE ou.occasion=v_occasion AND s.occasion=v_occasion;
  BEGIN
    IF p_blueprint ? 'layout' THEN
      v_result:=public.save_blueprint_layout_internal_v1(p_blueprint);
    ELSE
      IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=v_blueprint AND layout IS NOT NULL) THEN
        RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_REQUIRED'; END IF;
      v_result:=public.update_blueprint_internal_v1(p_blueprint);
      IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
        RAISE check_violation USING MESSAGE='BLUEPRINT_LEGACY_REJECTED',DETAIL=v_result::text; END IF;
    END IF;
  EXCEPTION WHEN check_violation OR raise_exception OR invalid_text_representation OR not_null_violation OR unique_violation OR foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_reason=MESSAGE_TEXT,v_detail=PG_EXCEPTION_DETAIL;
    v_issue:=jsonb_build_object('reason',v_reason);
    IF left(coalesce(v_detail,''),1)='{' THEN
      BEGIN v_issue:=v_issue||jsonb_strip_nulls(jsonb_build_object('nodeId',(v_detail::jsonb)->'nodeId','spotId',(v_detail::jsonb)->'spotId','groupNodeId',(v_detail::jsonb)->'groupNodeId'));
      EXCEPTION WHEN invalid_text_representation THEN NULL; END;
    END IF;
    v_result:=jsonb_build_object('code',409,'reason',CASE WHEN SQLSTATE IN ('23514','P0001') THEN v_reason ELSE 'BLUEPRINT_INVALID_INPUT' END,
      'issues',jsonb_build_array(v_issue),
      'layout_revision',(SELECT layout_revision FROM eshop.blueprints WHERE id=v_blueprint));
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,v_result);
  END;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.blueprint.save',jsonb_build_array(jsonb_build_object(
      'entityType','blueprint','entityId',v_result->>'blueprint_id',
      'operation',CASE WHEN v_blueprint IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_blueprint->>'title',240),'changedFields',jsonb_build_array(
        'spots','configuration'))),v_users,v_result);
END; $$;



CREATE OR REPLACE FUNCTION public.update_blueprint(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_blueprint_client_sync_v1(
    input_data,extensions.gen_random_uuid())->'data';
END; $$;





-- Source: database/functions/eshop/select_spot.sql
CREATE OR REPLACE FUNCTION public.select_spot_single_internal_v1(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; occ bigint; org bigint; un bigint; s eshop.spots; policy jsonb; scopes jsonb; costs jsonb; r jsonb; held bigint; duration_seconds integer; form_data jsonb; form_open boolean; fid bigint;
BEGIN
 IF secret_id IS NULL OR selecting IS NULL THEN RETURN jsonb_build_object('code',400,'message','Invalid reservation'); END IF;
 SELECT f.blueprint,f.occasion,o.organization,o.unit,f.id,f.is_open INTO bp,occ,org,un,fid,form_open FROM public.forms f
 JOIN public.occasions o ON o.id=f.occasion WHERE f.key=form_key;
 IF bp IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form blueprint not found'); END IF;
 PERFORM public.check_occasion_writable(occ);
 IF selecting AND public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN
  form_data:=public.get_effective_form_data(fid);
  IF form_open IS NOT TRUE OR
   (coalesce(form_data#>>'{schedule,start_time}',form_data->>'start_time'))::timestamptz>statement_timestamp() OR
   (coalesce(form_data#>>'{schedule,end_time}',form_data->>'end_time'))::timestamptz<statement_timestamp() THEN
   RETURN jsonb_build_object('code',403,'message','Form is not open'); END IF;
 END IF;
 -- A buyer's active inventory is serialized before the individual spot lock.
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=bp FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Spot not found'); END IF;
 IF s.order_product_ticket IS NOT NULL THEN RETURN jsonb_build_object('code',409,'message','Spot is already ordered'); END IF;
 IF s.secret_expiration_time<=statement_timestamp() THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=spot_id;
  s.secret:=NULL; s.secret_expiration_time:=NULL;
 END IF;
 IF s.secret IS NOT NULL AND s.secret IS DISTINCT FROM secret_id THEN
  RETURN jsonb_build_object('code',403,'message','Spot is held by another buyer'); END IF;
 IF NOT selecting THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now() WHERE id=spot_id;
  RETURN jsonb_build_object('code',200,'message','Spot deselected');
 END IF;
 -- A retry cannot move the original expiration, including after another tab reload.
 IF s.secret=secret_id THEN RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time); END IF;
 policy:=public.abuse_effective_rules_v1('spot.hold',un,org);
 scopes:=jsonb_build_object('recipient',secret_id,'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT count(*) INTO held FROM eshop.spots WHERE secret=secret_id AND secret_expiration_time>statement_timestamp() AND order_product_ticket IS NULL;
 costs:=jsonb_build_object('hold.active.buyer',held+1);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 SELECT (x->>'base_limit')::integer INTO duration_seconds FROM jsonb_array_elements(public.abuse_effective_rules_v1('hold.duration',un,org)->'rules') x;
 IF duration_seconds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 UPDATE eshop.spots SET secret=secret_id,secret_expiration_time=statement_timestamp()+make_interval(secs=>duration_seconds),updated_at=now() WHERE id=spot_id RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time);
END $$;

CREATE OR REPLACE FUNCTION public.select_spot(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; member_id bigint; r jsonb; occ bigint; bp bigint;
BEGIN
 SELECT occasion,blueprint INTO occ,bp FROM public.forms WHERE key=form_key;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 ids:=public.blueprint_selection_unit_spots_internal(spot_id);
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 BEGIN
  IF selecting AND EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
   WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL)) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
  FOREACH member_id IN ARRAY ids LOOP
   r:=public.select_spot_single_internal_v1(form_key,secret_id,member_id,selecting);
   IF coalesce((r->>'code')::integer,500)<>200 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_HOLD_REJECTED'; END IF;
  END LOOP;
 EXCEPTION WHEN check_violation THEN
  RETURN coalesce(r,jsonb_build_object('code',409,'reason',SQLERRM,'message',SQLERRM));
 END;
 RETURN r||jsonb_build_object('spotIds',to_jsonb(ids));
END $$;




-- Source: database/functions/eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    v_ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid)]);
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(coalesce(input_data->'ticket','[]')) t WHERE t->>'spot' IS NOT NULL));
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_ticket_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id AND (NOT p_offer OR product IS NOT NULL)) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT * INTO spot_data
                FROM eshop.spots
                WHERE id = (ticket_data->>'spot')::BIGINT
                  AND occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings b WHERE b.spot=spot_data.id AND b.blocked) OR spot_data.product IS NULL THEN
                    RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            v_ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            IF p_offer THEN
              ticket_id:=(ticket_data->>'ticketId')::bigint;
              UPDATE eshop.tickets t SET state='ordered',ticket_symbol=v_ticket_symbol,
                note=ticket_note,data=public.extract_ticket_answers_internal(form_id,ticket_data),updated_at=now
              WHERE t.id=ticket_id AND t.state='waitlisted' AND t.ticket_symbol IS NULL
                AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=order_id AND x.product IS NULL)
                AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots x WHERE x.ticket_id=t.id AND x.outcome='accepted');
              IF NOT FOUND THEN RAISE EXCEPTION 'Invalid waiting ticket finalization'; END IF;
              DELETE FROM eshop.order_product_ticket WHERE "order"=order_id AND ticket=ticket_id AND product IS NULL;
            ELSE
              IF ticket_data ? 'ticketId' THEN RAISE EXCEPTION 'Ticket identity is server assigned'; END IF;
              INSERT INTO eshop.tickets (state,occasion,ticket_symbol,note,data,created_at,updated_at)
              VALUES('ordered',occasion_id,v_ticket_symbol,ticket_note,public.extract_ticket_answers_internal(form_id,ticket_data),now,now) RETURNING id INTO ticket_id;
            END IF;
            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=order_id AND x.ticket=ticket_id) THEN
              INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,NULL);
            END IF;
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', v_ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        IF calculated_price>0 AND NOT public.payment_reference_scope_enabled_internal(form_id) THEN
          generated_variable_symbol := public.generate_payment_variable_symbol(bank_account_id, form_id);
        END IF;
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;
        IF calculated_price>0 AND public.payment_reference_scope_enabled_internal(form_id) THEN
          UPDATE eshop.orders SET payment_info=payment_info_id WHERE id=order_id;
          generated_variable_symbol:=public.reserve_order_payment_reference_internal(payment_info_id,form_id);
          UPDATE eshop.payment_info SET variable_symbol=generated_variable_symbol WHERE id=payment_info_id;
        END IF;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- NULL inherits the occasion default; zero is an explicit immediate deadline.
          form_deadline_duration := coalesce(form_deadline_duration,
            (SELECT (feature->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) feature WHERE feature->>'code'='form'),604800);
          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- One queue boundary resolves form and occasion reminder settings.
                    PERFORM public.queue_payment_reminders(occasion_id,0);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;




-- Source: database/functions/eshop/swap_spot_tickets.sql
CREATE OR REPLACE FUNCTION public._swap_spots_generate_product_json(
    p_product_id BIGINT,
    p_spot_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions
AS $$
DECLARE
    product_data RECORD;
BEGIN
    -- This query joins product, its type, and the spot (if provided)
    -- to get all data needed for the JSON object.
    SELECT
        p.id,
        p.price,
        p.title,
        p.description,
        p.currency_code,
        pt.title AS type_title,
        pt.type AS type,
        s.title AS spot_title
    INTO
        product_data
    FROM
        eshop.products AS p
    JOIN
        eshop.product_types AS pt ON p.product_type = pt.id
    LEFT JOIN
        eshop.spots AS s ON s.id = p_spot_id -- Use p_spot_id for spot_title
    WHERE
        p.id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product data not found for product_id %', p_product_id;
    END IF;

    -- Build the JSON object.
    -- jsonb_strip_nulls ensures that if 'spot_title' is NULL
    -- (because p_spot_id was NULL), the key is removed entirely.
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'id', product_data.id,
        'type', product_data.type,
        'price', product_data.price,
        'title', product_data.title,
        'spot_title', product_data.spot_title,
        'type_title', product_data.type_title,
        'description', product_data.description,
        'currency_code', product_data.currency_code
    ));
END;
$$;

CREATE OR REPLACE FUNCTION public._swap_spots_update_ticket(
    p_opt_id BIGINT,
    p_new_product_id BIGINT,
    p_new_spot_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    opt RECORD;
    ord RECORD;
    original_product_id BIGINT;
    original_product_json JSONB;
    original_price NUMERIC;

    new_product_json JSONB;
    new_price NUMERIC;
    new_data JSONB;
    new_order_price NUMERIC;
    new_state TEXT;

    price_delta NUMERIC;
    history_needed BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    SELECT * INTO ord FROM eshop.orders WHERE id = opt."order" FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', opt."order"; END IF;

    original_product_id := opt.product;

    -- 2. Find the *original* product JSON and price from the order_ids.data
    SELECT prod, (prod->>'price')::numeric
    INTO original_product_json, original_price
    FROM jsonb_array_elements(ord.data->'tickets') tckt,
         jsonb_array_elements(tckt->'products') prod
    WHERE (tckt->>'id')::bigint = opt.ticket
      AND (prod->>'id')::bigint = original_product_id;

    IF original_price IS NULL THEN
        RAISE EXCEPTION 'Could not find original price for product % on ticket %', original_product_id, opt.ticket;
    END IF;

    -- 3. Generate the *new* product JSON
    new_product_json := public._swap_spots_generate_product_json(p_new_product_id, p_new_spot_id);
    new_price := (new_product_json->>'price')::numeric;
    IF new_product_json->>'currency_code' IS DISTINCT FROM ord.currency_code THEN
      RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;

    -- 4. Check if an update is even needed.
    -- If the new JSON is identical to the old, nothing needs to be done.
    IF original_product_json = new_product_json THEN
        RETURN;
    END IF;

    -- 5. Calculate financials and state
    price_delta := new_price - original_price;
    history_needed := (original_product_id IS DISTINCT FROM p_new_product_id);
    new_order_price := COALESCE(ord.price, 0) + price_delta;

    -- Recalculate order state
    SELECT CASE
        WHEN COALESCE(pi.paid, 0) >= new_order_price AND new_order_price > 0 THEN 'paid'
        WHEN new_order_price <= 0 THEN 'paid'
        ELSE 'ordered'
    END INTO new_state
    FROM (SELECT COALESCE((SELECT paid FROM eshop.payment_info WHERE id=ord.payment_info),0) AS paid) pi;

    -- 6. Build the new order_ids.data JSON
    new_data := jsonb_set(
        ord.data,
        '{tickets}',
        (SELECT jsonb_agg(
            -- Find the matching ticket
            CASE WHEN (tckt->>'id')::bigint = opt.ticket
            THEN jsonb_set(
                tckt,
                '{products}',
                (SELECT jsonb_agg(
                    -- Find the matching product and replace it
                    CASE
                        WHEN (prod->>'id')::bigint = original_product_id
                        THEN new_product_json -- Swap in the new product JSON
                        ELSE prod
                    END
                ) FROM jsonb_array_elements(tckt->'products') prod)
            )
            ELSE tckt
            END
        ) FROM jsonb_array_elements(ord.data->'tickets') tckt)
    );

    -- 7. Perform all database updates

    -- Update payment info
    IF price_delta <> 0 THEN
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        state = new_state,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id
    WHERE id = p_opt_id;

    -- 8. Create history log *only if* the product ID actually changed
    IF history_needed THEN
        INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
        VALUES (ord.id, new_data, new_state, new_order_price, ord.currency_code);
    END IF;

END;
$$;


CREATE OR REPLACE FUNCTION public.swap_spot_pair_internal_v1(spot_id_1 BIGINT, spot_id_2 BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    spot1 RECORD;
    spot2 RECORD;
    occasion_id_common BIGINT;
    has_permission BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Input Validation
    IF spot_id_1 IS NULL OR spot_id_2 IS NULL THEN
        RAISE EXCEPTION 'Both spot_id_1 and spot_id_2 must be provided' USING ERRCODE = '22023';
    END IF;
    IF spot_id_1 = spot_id_2 THEN
        RAISE EXCEPTION 'Cannot swap a spot with itself' USING ERRCODE = '22023';
    END IF;

    -- 2. Fetch Spot Data
    SELECT * INTO spot1 FROM eshop.spots WHERE id = spot_id_1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Spot 1 not found (ID: %)', spot_id_1 USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO spot2 FROM eshop.spots WHERE id = spot_id_2 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Spot 2 not found (ID: %)', spot_id_2 USING ERRCODE = 'P0002'; END IF;

    -- 3. Permission and Occasion Check
    IF spot1.occasion IS NULL OR spot2.occasion IS NULL THEN
         RAISE EXCEPTION 'Spots are missing occasion information' USING ERRCODE = '22004';
    END IF;
    IF spot1.occasion <> spot2.occasion THEN
        RAISE EXCEPTION 'Spots do not belong to the same occasion (Spot1: %, Spot2: %)', spot1.occasion, spot2.occasion USING ERRCODE = 'P0001';
    END IF;
    occasion_id_common := spot1.occasion;

    -- Check permission
    BEGIN
        SELECT get_is_editor_order_on_occasion(occasion_id_common) INTO has_permission;
    EXCEPTION
        WHEN undefined_function THEN RAISE EXCEPTION 'Permission check function get_is_editor_order_on_occasion() does not exist.' USING ERRCODE = '42883';
        WHEN OTHERS THEN RAISE EXCEPTION 'Error during permission check: %', SQLERRM;
    END;
    IF has_permission <> TRUE THEN
        RAISE EXCEPTION 'User is not authorized to edit order_ids for this occasion' USING ERRCODE = '42501';
    END IF;

    -- 4. Main Swap Logic: Branch based on assignment status
    -- This logic is now greatly simplified by the helper functions.

    IF spot1.order_product_ticket IS NOT NULL AND spot2.order_product_ticket IS NOT NULL THEN
        -- ----------------------------------------------------------------
        -- CASE A: BOTH SPOTS ARE ASSIGNED
        -- ----------------------------------------------------------------

        -- Ticket 1 (from spot 1) moves to Spot 2, so it must adopt Spot 2's product.
        PERFORM public._swap_spots_update_ticket(spot1.order_product_ticket, spot2.product, spot_id_2);

        -- Ticket 2 (from spot 2) moves to Spot 1, so it must adopt Spot 1's product.
        PERFORM public._swap_spots_update_ticket(spot2.order_product_ticket, spot1.product, spot_id_1);

    ELSIF spot1.order_product_ticket IS NOT NULL OR spot2.order_product_ticket IS NOT NULL THEN
        -- ----------------------------------------------------------------
        -- CASE B/C: ONE SPOT IS ASSIGNED, ONE IS UNASSIGNED
        -- ----------------------------------------------------------------

        IF spot1.order_product_ticket IS NOT NULL THEN
            -- Spot 1 is assigned, Spot 2 is unassigned.
            -- Ticket 1 moves to Spot 2 and adopts Spot 2's product.
            PERFORM public._swap_spots_update_ticket(spot1.order_product_ticket, spot2.product, spot_id_2);
        ELSE
            -- Spot 2 is assigned, Spot 1 is unassigned.
            -- Ticket 2 moves to Spot 1 and adopts Spot 1's product.
            PERFORM public._swap_spots_update_ticket(spot2.order_product_ticket, spot1.product, spot_id_1);
        END IF;

    ELSE
        -- ----------------------------------------------------------------
        -- CASE D: BOTH SPOTS ARE UNASSIGNED
        -- ----------------------------------------------------------------
        -- Nothing to do.
        RETURN;
    END IF;

    -- 5. Final Spot Update
    -- This block runs for Cases A, B, and C.
    -- We ONLY swap the 'order_product_ticket' FK. The 'product' column
    -- on the spot (spot1.product, spot2.product) never changes.
    UPDATE eshop.spots
    SET
        order_product_ticket = CASE
            WHEN id = spot_id_1 THEN spot2.order_product_ticket -- Spot 1 gets Ticket 2
            WHEN id = spot_id_2 THEN spot1.order_product_ticket -- Spot 2 gets Ticket 1
        END
    WHERE id IN (spot_id_1, spot_id_2);

END;
$$;


CREATE OR REPLACE FUNCTION public.swap_spot_tickets_internal_v1(spot_id_1 bigint,spot_id_2 bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids1 bigint[]; ids2 bigint[]; order_ids bigint[]; occ bigint; i integer;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(spot_id_1,spot_id_2);
 IF occ IS NULL OR (SELECT count(*) FROM eshop.spots WHERE id IN(spot_id_1,spot_id_2) AND occasion=occ)<>2 THEN
  RAISE EXCEPTION 'BLUEPRINT_SPOT_SCOPE_MISMATCH'; END IF;
 IF public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 ids1:=public.blueprint_selection_unit_spots_internal(spot_id_1);
 ids2:=public.blueprint_selection_unit_spots_internal(spot_id_2);
 IF cardinality(ids1)<>cardinality(ids2) OR ids1 && ids2 THEN RAISE EXCEPTION 'BLUEPRINT_UNIT_SIZE_MISMATCH'; END IF;
 PERFORM public.check_blueprint_selection_units_internal(ids1||ids2);
 SELECT array_agg(DISTINCT opt."order") INTO order_ids FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE s.id=ANY(ids1||ids2);
 PERFORM public.lock_order_capacity_scope_internal(order_ids);
 PERFORM public.lock_ticket_order_products_internal(o.id) FROM eshop.orders o WHERE id=ANY(order_ids) ORDER BY id;
 -- Destination products may differ from products currently held by those order_ids.
 PERFORM 1 FROM eshop.products WHERE id IN(SELECT product FROM eshop.spots WHERE id=ANY(ids1||ids2)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id IN(SELECT payment_info FROM eshop.orders WHERE id=ANY(order_ids)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids1||ids2) ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
  WHERE s.id=ANY(ids1||ids2) AND (b.blocked OR s.product IS NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()))) THEN
  RAISE EXCEPTION 'BLUEPRINT_SEAT_PROTECTED'; END IF;
 FOR i IN 1..cardinality(ids1) LOOP PERFORM public.swap_spot_pair_internal_v1(ids1[i],ids2[i]); END LOOP;
END $$;


CREATE OR REPLACE FUNCTION public.swap_spot_tickets(spot_id_1 bigint,spot_id_2 bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.swap_spot_tickets_client_sync_v1(
    spot_id_1,spot_id_2,extensions.gen_random_uuid());
END; $$;




-- Source: database/functions/blueprint/swap_spot_tickets_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.swap_spot_tickets_client_sync_v1(
  p_spot_1 bigint,p_spot_2 bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[];
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id IN(p_spot_1,p_spot_2)));
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id IN (p_spot_1,p_spot_2);
  IF v_actor IS NULL OR p_spot_1 IS NULL OR p_spot_2 IS NULL
    OR p_spot_1=p_spot_2 OR v_occasion IS NULL
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id IN (p_spot_1,p_spot_2) AND s.occasion=v_occasion)<>2
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spot1',p_spot_1,'spot2',p_spot_2)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.spots.swap',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM eshop.spots s JOIN eshop.order_product_ticket opt
    ON opt.id=s.order_product_ticket JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE s.id IN (p_spot_1,p_spot_2);
  PERFORM public.swap_spot_tickets_internal_v1(p_spot_1,p_spot_2);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.spots.swap',jsonb_build_array(jsonb_build_object(
      'entityType','spot_assignment','entityId',NULL,'operation','update',
      'safeLabel','Spot ticket swap','changedFields',jsonb_build_array(
        'order_product_ticket','product'))),v_users,jsonb_build_object(
          'spotIds',jsonb_build_array(p_spot_1,p_spot_2)));
END; $$;





-- Source: database/functions/blueprint/preview_blueprint_swap.sql
-- SQL work is deliberately rolled back after capturing the authoritative result.
-- The existing financial owner is executed; preview maintains no alternate maths.
CREATE OR REPLACE FUNCTION public.preview_blueprint_swap(p_spot_1 bigint,p_spot_2 bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; order_ids bigint[]; before_orders jsonb; sides jsonb; result jsonb; occ bigint;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_spot_1,p_spot_2);
 IF occ IS NULL THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 ids:=public.blueprint_selection_unit_spots_internal(p_spot_1)||public.blueprint_selection_unit_spots_internal(p_spot_2);
 SELECT array_agg(DISTINCT opt."order") INTO order_ids FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE s.id=ANY(ids);
 PERFORM public.lock_order_capacity_scope_internal(order_ids);
 SELECT coalesce(jsonb_object_agg(id::text,price),'{}') INTO before_orders FROM eshop.orders WHERE id=ANY(order_ids);
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'title',s.title,'orderId',o.id,'ticketId',opt.ticket,
  'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email')) ORDER BY s.id),'[]')
 INTO sides FROM eshop.spots s LEFT JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket LEFT JOIN eshop.orders o ON o.id=opt."order" WHERE s.id=ANY(ids);
 BEGIN
  PERFORM public.swap_spot_tickets_internal_v1(p_spot_1,p_spot_2);
  SELECT jsonb_build_object('code',200,'spotIds',to_jsonb(ids),'sides',sides,'orders',coalesce(jsonb_agg(jsonb_build_object(
   'orderId',id,'beforeAmount',(before_orders->>id::text)::numeric,'afterAmount',price,
   'delta',price-(before_orders->>id::text)::numeric,'currencyCode',currency_code) ORDER BY id),'[]')) INTO result FROM eshop.orders WHERE id=ANY(order_ids);
  RAISE SQLSTATE 'BP001' USING MESSAGE='rollback successful swap preview';
 EXCEPTION WHEN SQLSTATE 'BP001' THEN NULL;
 WHEN OTHERS THEN result:=jsonb_build_object('code',409,'reason',SQLERRM,'issues',jsonb_build_array(jsonb_build_object('reason',SQLERRM)));
 END;
 RETURN result;
END $$;

GRANT EXECUTE ON FUNCTION public.preview_blueprint_swap(bigint,bigint) TO authenticated;


-- Source: database/functions/eshop/analyze_new_order_spots.sql
CREATE OR REPLACE FUNCTION public.analyze_new_order_spots(
  p_spot_ids bigint[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_conflicts jsonb;
  v_new_order_items jsonb;
  v_occasion_id BIGINT;
  v_total numeric; v_currency text;
BEGIN
  -- =======================================================================
  -- 0. VALIDATION & SECURITY
  -- =======================================================================

  -- Handle empty input
  IF p_spot_ids IS NULL OR array_length(p_spot_ids, 1) IS NULL THEN
     RETURN jsonb_build_object('conflicts', '[]'::jsonb, 'new_order_items', '[]'::jsonb);
  END IF;

  -- Get Occasion ID from the first spot
  SELECT occasion INTO v_occasion_id
  FROM eshop.spots
  WHERE id = p_spot_ids[1];

  IF v_occasion_id IS NULL THEN
     RAISE EXCEPTION 'Spot ID % not found.', p_spot_ids[1];
  END IF;

  -- Consistency Check: Ensure all selected spots belong to the SAME occasion
  PERFORM 1
  FROM eshop.spots
  WHERE id = ANY(p_spot_ids)
  AND occasion != v_occasion_id;

  IF FOUND THEN
     RAISE EXCEPTION 'All selected spots must belong to the same occasion.';
  END IF;

  -- Permission Check: User must have "Order View" rights on this occasion
  IF public.get_is_editor_order_view_on_occasion(v_occasion_id) IS NOT TRUE THEN
     RAISE EXCEPTION 'Permission denied. User does not have view rights for occasion %.', v_occasion_id;
  END IF;

  IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spot_ids) AND occasion=v_occasion_id)<>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id)) THEN
    RAISE EXCEPTION 'BLUEPRINT_SPOT_SCOPE_MISMATCH'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion_id]);
  PERFORM public.check_blueprint_selection_units_internal(p_spot_ids);

  -- =======================================================================
  -- 1. IDENTIFY CONFLICTS
  -- =======================================================================
  WITH impacted_base AS (
    SELECT
      s.id as spot_id,
      o.id as order_id,
      o.data as order_data,
      o.state as order_state,
      t.id as ticket_id,
      t.ticket_symbol
    FROM eshop.spots s
    JOIN eshop.order_product_ticket opt ON s.order_product_ticket = opt.id
    JOIN eshop.tickets t ON opt.ticket = t.id
    JOIN eshop.orders o ON opt.order = o.id
    WHERE s.id = ANY(p_spot_ids)
    -- Include any state that implies the spot is technically "occupied"
  ),
  impacted_enriched AS (
    -- Safely extract the specific ticket from JSON
    SELECT
      ib.*,
      (
        SELECT item
        FROM jsonb_array_elements(ib.order_data->'tickets') item
        WHERE (item->>'id')::bigint = ib.ticket_id
        LIMIT 1
      ) as ticket_json
    FROM impacted_base ib
  ),
  order_stats AS (
    -- Calculate if whole order is cancelled
    SELECT
      order_id,
      COUNT(DISTINCT ticket_id) as affected_ticket_count,
      COALESCE(jsonb_array_length(order_data->'tickets'), 0) as total_ticket_count
    FROM impacted_enriched
    GROUP BY order_id, order_data
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'order_id', ie.order_id,
      -- Extract individual fields as requested
      'email', ie.order_data->>'email',
      'name', ie.order_data->>'name',
      'surname', ie.order_data->>'surname',
      'note', ie.order_data->>'note',

      'ticket_id', ie.ticket_id,
      'ticket_symbol', ie.ticket_symbol,
      'is_fully_cancelled', (os.affected_ticket_count >= os.total_ticket_count AND os.total_ticket_count > 0),
      -- The products array from the JSON (Spot + Extras)
      'products', ie.ticket_json->'products',
      -- Sum the price (safely handle nulls)
      'total_price', (
         SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
         FROM jsonb_array_elements(ie.ticket_json->'products') prod
      )
    )
  )
  INTO v_conflicts
  FROM impacted_enriched ie
  JOIN order_stats os ON ie.order_id = os.order_id;

  -- =======================================================================
  -- 2. PREPARE NEW ORDER ITEMS
  -- =======================================================================
  SELECT jsonb_agg(jsonb_build_object(
    'spot_id', s.id,
    'spot_title', s.title,
    'product_title', p.title,
    'price', p.price,
    'currency', p.currency_code
  ))
  INTO v_new_order_items
  FROM eshop.spots s
  LEFT JOIN eshop.products p ON s.product = p.id
  WHERE s.id = ANY(p_spot_ids);

  IF (SELECT count(DISTINCT item->>'currency') FROM jsonb_array_elements(coalesce(v_new_order_items,'[]')) item)>1 THEN RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;
  SELECT coalesce(sum((item->>'price')::numeric),0),min(item->>'currency') INTO v_total,v_currency FROM jsonb_array_elements(coalesce(v_new_order_items,'[]')) item;
  RETURN jsonb_build_object(
    'conflicts', COALESCE(v_conflicts, '[]'::jsonb),
    'new_order_items', COALESCE(v_new_order_items, '[]'::jsonb),
    'total_price',v_total,'currency',v_currency
  );
END;
$$;

-- Source: database/functions/eshop/confirm_blueprint_order_change.sql
CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_internal_v1(
  p_spot_ids BIGINT[],
  p_input_data JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_analysis JSONB;
  v_ticket_ids_to_cancel BIGINT[];
  v_occasion_id BIGINT;
  v_form_key UUID;
  v_ticket_payloads JSONB := '[]'::JSONB;
  v_order_details JSONB;
  v_new_spot_rec RECORD;
  v_email TEXT;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
  PERFORM public.check_blueprint_selection_units_internal(p_spot_ids);
  -- Extract Email for validation
  v_email := p_input_data->>'email';

  IF v_email IS NULL OR v_email = '' THEN
      RAISE EXCEPTION 'Email is required in input data.';
  END IF;

  -- 1. Analyze impacts
  v_analysis := public.analyze_new_order_spots(p_spot_ids);

  -- 2. Extract Ticket IDs for Storno
  SELECT ARRAY_AGG((elem->>'ticket_id')::BIGINT)
  INTO v_ticket_ids_to_cancel
  FROM jsonb_array_elements(v_analysis->'conflicts') elem
  WHERE elem->>'ticket_id' IS NOT NULL;

  -- 3. Perform Storno (if any conflicts exist)
  IF v_ticket_ids_to_cancel IS NOT NULL AND array_length(v_ticket_ids_to_cancel, 1) > 0 THEN
      PERFORM public.storno_tickets_bulk_internal_v1(v_ticket_ids_to_cancel);
  END IF;

  -- 4. Clean up Secrets on selected spots
  UPDATE eshop.spots
  SET secret = NULL, secret_expiration_time = NULL
  WHERE id = ANY(p_spot_ids);

  -- 5. Prepare Data for New Order

  -- Get occasion ID
  SELECT occasion INTO v_occasion_id FROM eshop.spots WHERE id = p_spot_ids[1];

  -- Security Check: User must be editor
  IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
      RAISE EXCEPTION 'Permission denied. User is not an editor for occasion %', v_occasion_id;
  END IF;

  -- Validation: All spots must be on same occasion
  PERFORM 1 FROM eshop.spots
  WHERE id = ANY(p_spot_ids) AND occasion != v_occasion_id;

  IF FOUND THEN
      RAISE EXCEPTION 'All selected spots must belong to the same occasion.';
  END IF;

  -- Find a suitable Form
  SELECT key INTO v_form_key
  FROM public.forms
  WHERE occasion = v_occasion_id AND is_open = true
  ORDER BY type = 'ticket' DESC, id DESC
  LIMIT 1;

  IF v_form_key IS NULL THEN
      RAISE EXCEPTION 'No open form found for this occasion to create the new order.';
  END IF;

  -- Build "ticket" array for the payload
  FOR v_new_spot_rec IN
      SELECT s.id, s.product
      FROM eshop.spots s
      WHERE s.id = ANY(p_spot_ids)
  LOOP
      v_ticket_payloads := v_ticket_payloads || JSONB_BUILD_OBJECT(
          'spot', v_new_spot_rec.id,
          'fields', '[]'::JSONB
      );
  END LOOP;

  -- Construct payload for Edge Function
  -- We start with basic fields, then MERGE (||) the p_input_data
  -- This allows passing 'name', 'surname', 'note' in input_data automatically.
  v_order_details := JSONB_BUILD_OBJECT(
      'form', v_form_key,
      'ticket', v_ticket_payloads,
      'lang', 'cs'
  ) || p_input_data;

  -- Return Success + Payload
  RETURN JSONB_BUILD_OBJECT(
      'success', true,
      'message', 'Storno performed. Ready to create new order.',
      'orderDetails', v_order_details
  );

EXCEPTION WHEN OTHERS THEN
  RETURN JSONB_BUILD_OBJECT('success', false, 'message', SQLERRM);
END;
$$;




-- Source: database/functions/eshop_orders/internal_storno_tickets_221.sql
CREATE OR REPLACE FUNCTION internal_storno_tickets_221(ticket_ids_to_storno BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions

AS $$
DECLARE
    opt_ids BIGINT[];
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(ticket_ids_to_storno)));
    PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(ticket_ids_to_storno)));
    IF ticket_ids_to_storno IS NULL OR array_length(ticket_ids_to_storno, 1) = 0 THEN
        RETURN; -- Nothing to do
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)));
    PERFORM public.lock_ticket_order_products_internal(o.id) FROM eshop.orders o WHERE o.id IN
      (SELECT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)) ORDER BY o.id;
    UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN
      (SELECT o.form FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE x.ticket=ANY(ticket_ids_to_storno));
    UPDATE eshop.waitlist_offer_slots SET outcome='cancelled',updated_at=clock_timestamp()
      WHERE ticket_id=ANY(ticket_ids_to_storno) AND outcome='pending';
    -- 1. Get all related order_product_ticket IDs
    SELECT ARRAY_AGG(opt.id) INTO opt_ids
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ANY(ticket_ids_to_storno);

    -- 2. (NEW) Delete any occasion_users linked to these tickets.
    -- We delete directly because the parent function already
    -- verified the user has 'editor' permissions.
    DELETE FROM public.occasion_users
    WHERE ticket = ANY(ticket_ids_to_storno);

    -- 3. Update the tickets themselves to 'storno'
    UPDATE eshop.tickets
    SET state = 'storno', updated_at = NOW()
    WHERE id = ANY(ticket_ids_to_storno);

    -- 4. Nullify the relevant spots
    IF opt_ids IS NOT NULL THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL,
            secret = NULL,
            secret_expiration_time = NULL,
            updated_at = NOW(),
            resource = NULL,
            state = NULL
        WHERE order_product_ticket = ANY(opt_ids);
    END IF;

    -- 5. Nullify the product link on the order_product_ticket records
    UPDATE eshop.order_product_ticket
    SET product = NULL
    WHERE ticket = ANY(ticket_ids_to_storno);

END;
$$;

-- Source: database/functions/eshop_orders/storno_tickets_bulk.sql
CREATE OR REPLACE FUNCTION public.storno_tickets_bulk_internal_v1(p_ticket_ids BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_order_id BIGINT;
    v_occasion_id BIGINT;
    v_tickets_in_order BIGINT[];
    v_tickets_to_cancel_in_order BIGINT[];
    v_remaining_count INT;
    v_ticket_id_to_remove BIGINT;
    v_original_data JSONB;
    v_updated_tickets_json JSONB;
    v_ticket_elem JSONB;
    v_product_elem JSONB;
    v_removed_price NUMERIC(10, 2);
    v_current_price NUMERIC(10, 2);
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(p_ticket_ids)));
    PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(p_ticket_ids)));
    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_ticket_ids)));
    -- 1. Identify all unique orders involved in this batch AND their occasion
    -- We need the occasion ID to perform the security check
    FOR v_order_id, v_occasion_id IN
        SELECT DISTINCT o.id, o.occasion
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE t.id = ANY(p_ticket_ids)
        ORDER BY o.id
    LOOP
        -- 2. SECURITY CHECK
        -- Verify that the current user has editor permissions on the occasion associated with the order.
        IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
            RAISE EXCEPTION 'Permission denied to storno tickets for order % on occasion %', v_order_id, v_occasion_id;
        END IF;

        -- Already-cancelled tickets are an idempotent no-op after authorization.
        -- They must not invoke the edit guard or create a second cancellation intent.
        IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
          WHERE opt."order"=v_order_id AND t.id=ANY(p_ticket_ids) AND t.state IS DISTINCT FROM 'storno') THEN
          CONTINUE;
        END IF;
        PERFORM public.check_order_is_mutable(v_order_id);
        -- Serialize cancellations on the same order before counting survivors.
        PERFORM 1 FROM eshop.orders WHERE id = v_order_id FOR UPDATE;

        -- 3. Get all active tickets currently in this order
        SELECT ARRAY_AGG(t.id)
        INTO v_tickets_in_order
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        WHERE opt."order" = v_order_id
        AND (t.state IS NULL OR t.state != 'storno');

        -- 4. Get intersection: Tickets in this order that we want to cancel
        SELECT ARRAY_AGG(id)
        INTO v_tickets_to_cancel_in_order
        FROM UNNEST(v_tickets_in_order) AS id
        WHERE id = ANY(p_ticket_ids);

        -- A replay or a selection containing only cancelled tickets has no effect.
        IF coalesce(cardinality(v_tickets_to_cancel_in_order), 0) = 0 THEN
            CONTINUE;
        END IF;

        -- 5. Calculate how many would remain
        v_remaining_count := array_length(v_tickets_in_order, 1) - array_length(v_tickets_to_cancel_in_order, 1);

        -- -----------------------------------------------------
        -- SCENARIO A: Full Order Cancellation
        -- -----------------------------------------------------
        IF v_remaining_count <= 0 THEN
            -- Helper function to cancel the entire order
            PERFORM update_order_and_tickets_to_storno_ws_internal_v1(v_order_id);
            -- Commit cancellation and its durable email intent together. Replays
            -- cannot reach this branch once the active tickets are cancelled.
            IF EXISTS (SELECT 1 FROM eshop.orders WHERE id=v_order_id
                AND position('@' in data->>'email')>0 AND length(data->>'email')<=320) THEN
            PERFORM public.enqueue_order_email('TICKET_ORDER_STORNO',
                jsonb_build_object('order_id', v_order_id),
                (SELECT organization FROM public.occasions WHERE id=v_occasion_id),
                v_occasion_id,
                (SELECT unit FROM public.occasions WHERE id=v_occasion_id),
                now(), 'last-ticket-cancelled:' || v_order_id);
            END IF;


        -- -----------------------------------------------------
        -- SCENARIO B: Partial Cancellation (Modify Order)
        -- -----------------------------------------------------
        ELSE
            -- 1. Mark specific tickets as storno in DB
            PERFORM internal_storno_tickets_221(v_tickets_to_cancel_in_order);

            -- 2. Fetch Order Data
            SELECT data, price INTO v_original_data, v_current_price
            FROM eshop.orders WHERE id = v_order_id;

            v_updated_tickets_json := '[]'::JSONB;
            v_removed_price := 0;

            -- 3. Rebuild JSON data, filtering out cancelled tickets and summing price to remove
            FOR v_ticket_elem IN SELECT * FROM jsonb_array_elements(v_original_data->'tickets')
            LOOP
                v_ticket_id_to_remove := (v_ticket_elem->>'id')::BIGINT;

                -- If this ticket is one of the ones being cancelled
                IF v_ticket_id_to_remove = ANY(v_tickets_to_cancel_in_order) THEN
                    -- Sum up price to deduct
                    FOR v_product_elem IN SELECT * FROM jsonb_array_elements(v_ticket_elem->'products')
                    LOOP
                        v_removed_price := v_removed_price + COALESCE((v_product_elem->>'price')::NUMERIC, 0);
                    END LOOP;
                ELSE
                    -- Keep this ticket in the new JSON
                    v_updated_tickets_json := v_updated_tickets_json || v_ticket_elem;
                END IF;
            END LOOP;

            -- Fence unsent snapshots of the previous ticket set, and keep the
            -- payment amount aligned with the new order total.
            PERFORM public.cancel_order_email_intents(v_order_id);
            UPDATE eshop.payment_info SET amount=GREATEST(0, COALESCE(v_current_price,0)-v_removed_price)
            WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=v_order_id);

            -- 4. Update Order (Data & Price)
            UPDATE eshop.orders
            SET
                data = v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                price = GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                email_payment_version = email_payment_version + 1,
                updated_at = NOW()
            WHERE id = v_order_id;

            -- Refresh only this order's existing reminder schedule for its new amount.
            PERFORM public.set_payment_deadline(pi.id,pi.deadline)
            FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
            WHERE o.id=v_order_id AND o.state='ordered' AND pi.deadline IS NOT NULL;

            -- Existing delivery policy prepares the surviving tickets if their
            -- paid order has not finished sending yet; sent orders stay untouched.
            PERFORM public.enqueue_paid_order_tickets(v_order_id);

            -- 5. Insert ONE history record for this modification
            INSERT INTO eshop.orders_history (
                "order",
                data,
                state,
                price,
                created_at
            )
            VALUES (
                v_order_id,
                v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                (SELECT state FROM eshop.orders WHERE id=v_order_id),
                GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                NOW()
            );
        END IF;
    END LOOP;
END;
$$;




-- Source: database/functions/eshop_orders/update_order_and_tickets_to_storno.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_221(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=order_id)]);
    PERFORM public.check_order_is_mutable(order_id);
    PERFORM public.cancel_order_email_intents(order_id);
    -- Retrieve all ticket ids associated with the order
    SELECT ARRAY_AGG(t.id) INTO ticket_ids
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = order_id;

    -- Check if the order exists and has associated tickets
    IF ticket_ids IS NULL THEN
        -- This is not an error, just an order with no tickets yet.
        -- But we can still storno the order itself.
        RAISE NOTICE 'No tickets found for order %, proceeding to storno order shell.', order_id;
    END IF;

    -- Call the helper to storno all tickets and their relations
    -- The helper function gracefully handles an empty/NULL array
    PERFORM internal_storno_tickets_221(ticket_ids);

    -- Set the order state to 'storno', price to 0, and update the data field
    UPDATE eshop.orders
    SET state = 'storno',
        price = 0,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('tickets', '[]'::jsonb),
        updated_at = NOW()
    WHERE id = order_id
    RETURNING data INTO updated_order_data;

    -- Save the change to orders_history by inserting the updated order row
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        order_id,
        'storno',
        0,
        updated_order_data,
        NOW()
    );

END;
$$;


-- Source: database/functions/eshop_orders/update_order_and_tickets_to_storno_ws.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_ws_internal_v1(order_id bigint)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=order_id)]);
    -- Retrieve the occasion associated with the order
    SELECT occasion INTO occasion_id FROM eshop.orders WHERE id = order_id;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    -- Verify if the user is an editor on the occasion
    IF (SELECT get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User is not editor.';
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    -- Use the same parent lock order as ticket cancellation.
    PERFORM 1 FROM eshop.orders WHERE id=order_id FOR UPDATE;

    -- Call the original function to update the order and tickets
    PERFORM update_order_and_tickets_to_storno_221(order_id);
END;
$$;



-- Source: database/functions/eshop_orders/storno_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.storno_order_client_sync_v1(p_order bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[];
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=p_order)]);
  SELECT o.occasion INTO v_occasion FROM eshop.orders o WHERE o.id=p_order;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.admit_order_mutation_v1(v_occasion,(SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=p_order));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  PERFORM public.update_order_and_tickets_to_storno_ws_internal_v1(p_order);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.cancel',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,
      'operation','update','safeLabel','Order cancellation',
      'changedFields',jsonb_build_array('state','tickets','membership','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order));
END; $function$;





-- Source: database/functions/eshop_orders/storno_tickets_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.storno_tickets_client_sync_v1(
  p_tickets bigint[],p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[]; v_changed_orders bigint[]; v_cancelled jsonb; v_updated jsonb;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(p_tickets)));
  IF cardinality(p_tickets)>(SELECT hard_cap FROM public.abuse_policy_rules WHERE rule_key='order.mutation.items') THEN RAISE SQLSTATE 'PT429' USING MESSAGE='abuse_limit_exceeded'; END IF;
  SELECT min(t.occasion) INTO v_occasion FROM eshop.tickets t
    WHERE t.id=ANY(p_tickets);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_tickets)=0
    OR (SELECT count(*) FROM eshop.tickets t
      WHERE t.id=ANY(p_tickets) AND t.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'tickets',p_tickets)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.tickets.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.admit_order_mutation_v1(v_occasion,cardinality(p_tickets));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_tickets)));
  -- Lock in the same order as the bulk mutation, then capture only actual changes.
  PERFORM o.id FROM eshop.orders o WHERE o.id IN (
    SELECT opt."order" FROM eshop.order_product_ticket opt
    JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets)) ORDER BY o.id FOR UPDATE;
  SELECT array_agg(DISTINCT opt."order") INTO v_changed_orders
    FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets) AND t.state IS DISTINCT FROM 'storno';
  PERFORM public.storno_tickets_bulk_internal_v1(p_tickets);
  SELECT coalesce(jsonb_agg(o.id ORDER BY o.id) FILTER(WHERE o.state='storno'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('id',o.id,'email',o.data->>'email') ORDER BY o.id)
      FILTER(WHERE o.state IS DISTINCT FROM 'storno'),'[]'::jsonb)
    INTO v_cancelled,v_updated FROM eshop.orders o WHERE o.id=ANY(v_changed_orders);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.tickets.cancel',
    jsonb_build_array(jsonb_build_object('entityType','ticket','entityId',NULL,
      'operation','update','safeLabel','Ticket cancellation',
      'changedFields',jsonb_build_array('state','membership','allocations'))),
    v_before_users,jsonb_build_object('ticketIds',to_jsonb(p_tickets),
      'cancelledOrderIds',v_cancelled,'updatedOrders',v_updated));
END; $$;




-- Source: database/functions/eshop_orders/replace_blueprint_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_before_users uuid[];
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id=ANY(p_spot_ids);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_spot_ids)=0
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id=ANY(p_spot_ids) AND s.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF public.payment_reference_scope_enabled_internal((SELECT id FROM public.forms WHERE occasion=v_occasion ORDER BY id LIMIT 1)) THEN
    RETURN jsonb_build_object('status','rejected','code',409,'data',jsonb_build_object('errorCode','ATOMIC_REPLACEMENT_REQUIRED')); END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spots',p_spot_ids,'input',p_input_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.prepare_replace',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN public.project_local_payment_reference_order_internal(v_begin->'response'); END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.confirm_blueprint_order_change_internal_v1(
    p_spot_ids,p_input_data);
  IF COALESCE((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',400,v_result); END IF;
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.prepare_replace',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',NULL,
      'operation','update','safeLabel','Blueprint order replacement',
      'changedFields',jsonb_build_array('cancellations','allocations'))),
    v_before_users,v_result);
END; $$;



CREATE OR REPLACE FUNCTION public.replace_blueprint_order_client_sync_v1(
  p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_prepare jsonb; v_result jsonb; v_before_users uuid[];
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id=ANY(p_spot_ids);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_spot_ids)=0
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id=ANY(p_spot_ids) AND s.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spots',p_spot_ids,'input',p_input_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.replace',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN public.project_local_payment_reference_order_internal(v_begin->'response'); END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  BEGIN
    v_prepare:=public.confirm_blueprint_order_change_internal_v1(
      p_spot_ids,p_input_data);
    IF COALESCE((v_prepare->>'success')::boolean,false) IS NOT TRUE THEN
      RAISE check_violation USING MESSAGE='replacement preparation rejected',
        DETAIL=v_prepare::text; END IF;
    v_result:=public.create_ticket_order_internal_v1(v_prepare->'orderDetails');
    IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
      RAISE check_violation USING MESSAGE='replacement order rejected',
        DETAIL=v_result::text; END IF;
  EXCEPTION WHEN check_violation THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',400,COALESCE(v_result,v_prepare,
        jsonb_build_object('message','order replacement rejected')));
  END;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,
    COALESCE(p_input_data->>'lang',v_prepare#>>'{orderDetails,lang}'));
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.replace',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Blueprint order replacement','changedFields',jsonb_build_array(
        'cancellations','tickets','products','allocations','membership'))),
    v_before_users,v_result);
END; $$;




-- Source: database/functions/eshop/get_blueprint.sql
CREATE OR REPLACE FUNCTION get_blueprint(
    my_secret UUID,
    form_key UUID,
    blueprint_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    valid_spots JSONB;
BEGIN
    -- Validate the form and blueprint association
    IF NOT EXISTS (
        SELECT 1
        FROM public.forms f
        WHERE f.key = form_key
          AND (NOT public.is_demo_occasion(f.occasion) OR public.can_read_demo_occasion(f.occasion))
          AND (f.is_open = true OR public.get_is_editor_order_view_on_occasion(f.occasion))
          AND EXISTS (
              SELECT 1
              FROM eshop.blueprints b
              WHERE b.id = blueprint_id
                AND f.blueprint = blueprint_id
          )
    ) THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Invalid form key or blueprint association.'
        );
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Fetch valid spot IDs
    SELECT jsonb_agg((obj->>'id')::BIGINT)
    INTO valid_spots
    FROM jsonb_array_elements(
        (SELECT b.objects FROM eshop.blueprints b WHERE b.id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    SELECT coalesce(valid_spots,'[]'::jsonb)||coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN
                CASE
                    WHEN s.secret = my_secret THEN 'selected_by_me'
                    ELSE 'selected'
                END
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

    -- Fetch product data for all spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price, 'currency_code', p.currency_code
    ))
    INTO productsData
    FROM eshop.products p
    WHERE p.occasion=(SELECT occasion FROM public.forms WHERE key=form_key)
      AND p.id IN (SELECT s.product FROM eshop.spots s WHERE s.id=ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
        UNION SELECT ab.product FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=blueprint_id);

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_public_binding_projection_internal(blueprint_id,my_secret);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,(SELECT id FROM public.forms WHERE key=form_key)));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;


-- Source: database/functions/eshop/get_blueprint_for_edit.sql
CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprint_id BIGINT;
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    valid_spots JSONB;
    occasion_id BIGINT;
BEGIN
    -- Resolve occasion_id using occasion_link
    SELECT id
    INTO occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Check if occasion_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion link does not exist');
    END IF;

    -- Authorization check
    IF (SELECT get_is_editor_order_view_on_occasion(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    -- Fetch the first blueprint_id for the occasion
    SELECT id
    INTO blueprint_id
    FROM eshop.blueprints
    WHERE occasion = occasion_id
    ORDER BY id
    LIMIT 1;

    -- Check if a blueprint exists for the occasion
    IF blueprint_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No blueprint found for this occasion');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Fetch valid spot IDs
    SELECT jsonb_agg((obj->>'id')::BIGINT)
    INTO valid_spots
    FROM jsonb_array_elements(
        (SELECT objects FROM eshop.blueprints WHERE id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    SELECT coalesce(valid_spots,'[]'::jsonb)||coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
          WHEN t.state = 'used' THEN 'used'
          WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
          WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
          ELSE 'available'
        END
      )
    )
    INTO spotsData
    FROM eshop.spots s
    LEFT JOIN eshop.order_product_ticket opt ON s.order_product_ticket = opt.id
    LEFT JOIN eshop.tickets t ON opt.ticket = t.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = occasion_id;

    -- Fetch all products of type "spot", "taxi", "food"
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'type', pt.type,
        'description', pt.description,
        'product_type', p.product_type,
        'currency_code', p.currency_code
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    -- Fetch relevant tickets associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND t.occasion = occasion_id;

    -- Fetch relevant orders associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'order_symbol', o.order_symbol,
        'order_sequence', o.order_sequence,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note')
    ))
    INTO ordersData
    FROM eshop.orders o
    JOIN eshop.order_product_ticket opt ON opt."order" = o.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
            'id', opt.id,
            'order', opt."order",
            'product', opt.product,
            'ticket', opt.ticket,
            'created_at', opt.created_at
        ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    -- Add relevant tickets data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{tickets}',
        COALESCE(ticketsData, '[]'::jsonb)
    );

    -- Add relevant orders data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{orders}',
        COALESCE(ordersData, '[]'::jsonb)
    );

    -- Add relevant order-product-ticket data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{order_product_ticket}',
        COALESCE(orderProductTicketsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_binding_projection_internal(blueprint_id);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,NULL));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

-- Source: database/functions/others/update_occasion.sql
CREATE OR REPLACE FUNCTION public.update_occasion_internal_v1(input_data JSONB)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 AS $$
 DECLARE
     updated_occ public.occasions;
     occ_id BIGINT;
     now TIMESTAMPTZ := NOW();
     final_unit BIGINT;

     -- Variable for the determined support flag
     is_app_supported BOOLEAN;

     -- Variable to help find the organization to check settings
     v_org_id BIGINT;

     -- Variables for feature handling
     new_blueprint_id BIGINT;
     v_form_id BIGINT;
     v_form_blueprint BIGINT;
     v_form_settings JSONB;
     v_form_link TEXT;
     v_reminder_interval_seconds BIGINT;
     v_email_order record;

     input_features JSONB;
     old_features JSONB;
     processed_features JSONB;
     feature JSONB;
     form_feature_found BOOLEAN;
 BEGIN
     -- Validate input data. Raise an exception if it's missing or empty.
     IF input_data IS NULL OR input_data = '{}'::jsonb THEN
         RAISE EXCEPTION 'Input data is missing or empty';
     END IF;

     -- 1. Identify the Organization ID
     IF (input_data->>'id') IS NOT NULL THEN
         -- Case A: UPDATE - Get organization from the existing occasion
         SELECT organization INTO v_org_id
         FROM public.occasions
         WHERE id = (input_data->>'id')::BIGINT;
     ELSE
         -- Case B: INSERT - Try to get organization from input
         v_org_id := (input_data->>'organization')::BIGINT;

         -- Case C: INSERT fallback - If org is missing, try to get it via the Unit
         IF v_org_id IS NULL AND (input_data->>'unit') IS NOT NULL THEN
            SELECT organization INTO v_org_id
            FROM public.units
            WHERE id = (input_data->>'unit')::BIGINT;
         END IF;
     END IF;

     -- 2. Fetch the setting from public.organizations.data
     -- Defaults to TRUE if the organization or the key is not found to ensure backward compatibility
     IF v_org_id IS NOT NULL THEN
         SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
         INTO is_app_supported
         FROM public.organizations
         WHERE id = v_org_id;
     ELSE
         is_app_supported := false;
     END IF;

     -- Ensure is_app_supported is not null (redundant safety check)
     is_app_supported := COALESCE(is_app_supported, false);

     --
     -- Prepare features based on is_app_supported flag
     --
     input_features := COALESCE(input_data->'features', '[]'::jsonb);
     processed_features := '[]'::jsonb;

     IF NOT is_app_supported THEN
         -- If the app is not supported, we must enable the 'form' feature.
         form_feature_found := false;
         -- Loop through existing features to find and enable the form feature
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             IF feature->>'code' = 'form' THEN
                 -- If form feature exists, ensure it is enabled
                 feature := feature || '{"is_enabled": true}';
                 form_feature_found := true;
             END IF;
             processed_features := processed_features || feature;
         END LOOP;

         -- If the form feature was not found in the original array, add it.
         IF NOT form_feature_found THEN
             processed_features := processed_features || '{"code": "form", "is_enabled": true}';
         END IF;
     ELSE
         -- If app is supported, use features as they were provided.
         processed_features := input_features;
     END IF;

     -- Determine if this is an UPDATE or INSERT based on the presence of an 'id'
     occ_id := (input_data->>'id')::BIGINT;

     IF occ_id IS NOT NULL THEN
         PERFORM public.check_occasion_writable(occ_id);
         -- This is an UPDATE operation

         -- Check for the existence of the occasion and get its current unit
         SELECT unit, features INTO final_unit, old_features FROM public.occasions WHERE id = occ_id FOR UPDATE;
         IF NOT FOUND THEN
             RAISE EXCEPTION 'Occasion with ID % not found', occ_id;
         END IF;

         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;
         processed_features := public.merge_ticket_layout_features(old_features, processed_features, input_data->'ticket_layout_change');
         PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';

         -- Determine the final unit, allowing it to be updated.
         final_unit := COALESCE((input_data->>'unit')::BIGINT, final_unit);

         -- Security check: ensure the current user has editor rights on the target unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         IF (input_data ? 'organization' AND (input_data->>'organization')::bigint IS DISTINCT FROM v_org_id)
           OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=final_unit AND organization=v_org_id) THEN
           RAISE insufficient_privilege USING MESSAGE='Occasion tenant cannot change'; END IF;

         UPDATE public.occasions
            SET updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',false),
                data        = COALESCE(input_data->'data', data),
                is_hidden   = COALESCE((input_data->>'is_hidden')::BOOLEAN, is_hidden),
                is_open     = COALESCE((input_data->>'is_open')::BOOLEAN, is_open),
                is_promoted = COALESCE((input_data->>'is_promoted')::BOOLEAN, is_promoted),
                start_time  = COALESCE((input_data->>'start_time')::TIMESTAMPTZ, start_time),
                end_time    = COALESCE((input_data->>'end_time')::TIMESTAMPTZ, end_time),
                organization = COALESCE((input_data->>'organization')::BIGINT, organization),
                services    = COALESCE(input_data->'services', services),
                unit        = final_unit,
                is_order_synchronization_enabled=COALESCE((input_data->>'is_order_synchronization_enabled')::boolean,is_order_synchronization_enabled),
                features    = processed_features -- Use the processed features
          WHERE id = occ_id
          RETURNING * INTO updated_occ;

     ELSE
         -- This is an INSERT operation

         -- For new occasions, the 'unit' field is mandatory.
         final_unit := (input_data->>'unit')::BIGINT;
         IF final_unit IS NULL THEN
             RAISE EXCEPTION 'The "unit" field is required for new occasions';
         END IF;

         -- Security check for the new occasion's unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         -- We still need to default 'reminder_is_enabled' for the 'form' feature if not specified.
         -- We do this on the already processed_features array.
         input_features := processed_features; -- Use the result from the is_app_supported logic
         processed_features := '[]'::jsonb;
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             -- If the current feature is the 'form' feature
             IF feature->>'code' = 'form' THEN
                 -- And if 'reminder_is_enabled' is NOT specified, default it to true.
                 IF NOT (feature ? 'reminder_is_enabled') THEN
                     feature := feature || '{"reminder_is_enabled": true}';
                 END IF;
             END IF;
             processed_features := processed_features || feature::jsonb;
         END LOOP;

         processed_features := public.merge_ticket_layout_features('[]', processed_features, input_data->'ticket_layout_change', true);

         INSERT INTO public.occasions(
             created_at, updated_at, title, description, link, data,
             is_hidden, is_open, is_promoted, start_time, end_time, organization,
             services, unit, features
         )
         VALUES(
             now, now,
             COALESCE(input_data->>'title', ''),
             COALESCE(input_data->>'description', ''),
             '',
             COALESCE(input_data->'data', '{}'::jsonb),
             COALESCE((input_data->>'is_hidden')::BOOLEAN, false),
             COALESCE((input_data->>'is_open')::BOOLEAN, true),
             COALESCE((input_data->>'is_promoted')::BOOLEAN, false),
             (input_data->>'start_time')::TIMESTAMPTZ,
             (input_data->>'end_time')::TIMESTAMPTZ,
             (input_data->>'organization')::BIGINT,
             COALESCE(input_data->'services', '{}'::jsonb),
             final_unit,
             processed_features
         )
         RETURNING * INTO updated_occ;

         -- Set the occ_id from the newly created record for subsequent logic
         occ_id := updated_occ.id;
         UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',true) WHERE id=occ_id RETURNING * INTO updated_occ;
     END IF;

     -- Enabling the blueprint feature must not bypass form capacity/waitlist guards,
     -- including when the stored blueprint already exists.
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
       FOR v_form_id IN SELECT id FROM public.forms WHERE occasion=occ_id ORDER BY id LOOP
         PERFORM public.check_form_capacity_settings_internal(v_form_id, '{"blueprint":1}'::jsonb);
       END LOOP;
     END IF;

     PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
     --
     -- Post-update/insert feature handling
     --

     -- Check if form feature is enabled and handle related logic.
     -- This will now be triggered if is_app_supported was false (based on organization settings).
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "form" && @.is_enabled == true)') THEN
         -- Extract the settings for the 'form' feature from the newly saved data
         SELECT elem INTO v_form_settings
         FROM jsonb_array_elements(updated_occ.features) AS elem
         WHERE elem->>'code' = 'form';

         -- Create a default form if one doesn't exist for the occasion
         IF NOT EXISTS (SELECT 1 FROM public.forms WHERE occasion = occ_id) THEN
             v_form_link := NULLIF(btrim(input_data->>'form_link'), '');
             PERFORM create_form(occ_id, v_form_link, 'Registration');
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders

         END IF;
     END IF;

     -- Revalidate in-flight reminders after every relevant occasion update.
     PERFORM public.queue_payment_reminders(occ_id,coalesce(v_reminder_interval_seconds,86400));
     IF updated_occ.is_order_synchronization_enabled THEN
       FOR v_email_order IN SELECT id FROM eshop.orders WHERE occasion=occ_id AND state='paid' LOOP
         PERFORM public.enqueue_paid_order_tickets(v_email_order.id);
       END LOOP;
     END IF;
     -- Check if the blueprint feature is enabled in the final, saved state
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         -- Find the associated form to attach the blueprint to
         SELECT id, blueprint INTO v_form_id, v_form_blueprint
           FROM public.forms
          WHERE occasion = occ_id
          LIMIT 1;

         -- If a form exists and it doesn't already have a blueprint, create one.
         IF FOUND AND v_form_blueprint IS NULL THEN
             INSERT INTO eshop.blueprints(configuration, occasion, organization, created_at, updated_at,layout)
             VALUES ('{"dimensions": {"width": 28, "height": 52}}'::jsonb, occ_id, COALESCE(updated_occ.organization, 1), now, now,
              '{"schemaVersion":1,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1120,"height":2080,"fill":"#ffffffff"},"defaultTextStyle":{"fontId":"builtin:roboto-unpacked:24438383f80387edbbd3a199d7b257258db7003f5b291a7d3fb6fa89483ae57f","size":24,"color":"#222222FF"},"nodes":[]}'::jsonb)
             RETURNING id INTO new_blueprint_id;

             UPDATE public.forms
                SET blueprint = new_blueprint_id,
                    updated_at = now
              WHERE id = v_form_id;
         END IF;
     END IF;
 END;
 $$;






-- Source: database/functions/blueprint/copy_layout_ids.sql
-- Called only by the existing occasion-copy owner. Rewrite declared identity
-- fields and actual geometry references, never arbitrary string content.
CREATE OR REPLACE FUNCTION public.remap_blueprint_layout_ids_internal(p_value jsonb,p_ids jsonb,p_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(item.key,public.remap_blueprint_layout_ids_internal(item.value,p_ids,item.key)),'{}') INTO result FROM jsonb_each(p_value) item;
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.remap_blueprint_layout_ids_internal(item.value,p_ids,p_key) ORDER BY item.position),'[]') INTO result FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,position);
  RETURN result;
 ELSIF jsonb_typeof(p_value)='string' AND p_key IN ('id','parentId','rootId','assemblyId','seatId','targetId','nodeIds') THEN
  RETURN coalesce(p_ids->(p_value#>>'{}'),p_value);
 END IF;
 RETURN p_value;
END $$;
REVOKE ALL ON FUNCTION public.remap_blueprint_layout_ids_internal(jsonb,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/others/duplicate_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint, p_target_unit bigint, p_locale text)
RETURNS bigint
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  new_occ         bigint;
  rec             record;
  new_info_id     bigint;
  v_new_id        bigint;
  new_place_id    bigint;
  new_event_id    bigint;
  new_bp_id       bigint;
  new_pt_id       bigint;
  new_product_id  bigint;
  new_form_id     bigint;
  v_source_unit bigint;
  v_target_unit bigint;
  v_organization bigint;
  v_demo boolean;
  v_layout_ids jsonb; v_copied_layout jsonb;
BEGIN
  SELECT unit, organization INTO v_source_unit, v_organization
  FROM public.occasions WHERE id = oc;
  v_target_unit := COALESCE(p_target_unit, v_source_unit);
  v_demo := public.is_demo_occasion(oc);
  IF auth.uid() IS NULL OR v_source_unit IS NULL OR v_target_unit IS NULL
     OR NOT public.can_copy_occasion_source(oc)
     OR public.is_demo_unit(v_target_unit)
     OR NOT public.get_is_manager_on_unit(v_target_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units
       WHERE id = v_target_unit AND organization = v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE = 'source and target unit manager required within one organization';
  END IF;

  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, CASE WHEN v_demo THEN true ELSE is_hidden END,
         CASE WHEN v_demo THEN false ELSE is_open END, CASE WHEN v_demo THEN false ELSE is_promoted END, start_time, end_time,
         '' AS link,
         public.copy_occasion_title_internal(title,p_locale), v_organization, services, v_target_unit, features, NULL, description
  FROM public.occasions
  WHERE id = oc
  RETURNING id INTO new_occ;

  UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',new_occ,NULL,true) WHERE id=new_occ;

  ------------------------------------------------------------------
  -- 2. Create temporary mapping tables (old id → new id)
  ------------------------------------------------------------------
  CREATE TEMP TABLE tmp_places (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_events (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_exclusive_groups (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprints (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprint_layout_ids (blueprint bigint,old_id uuid,new_id uuid,PRIMARY KEY(blueprint,old_id)) ON COMMIT DROP;
  PERFORM 1 FROM public.occasions WHERE id=oc FOR UPDATE;
  CREATE TEMP TABLE tmp_product_types (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_products (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_spots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_pools (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_contexts (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resources (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resource_slots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_scanner_fields (old_id bigint,new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_forms (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_information_hidden (old_id bigint, new_id bigint) ON COMMIT DROP;

  ------------------------------------------------------------------
  -- 3. Duplicate tables that reference the occasion directly
  ------------------------------------------------------------------

  -- 3a. Email Templates
  INSERT INTO public.email_templates (html, occasion, unit, subject, organization, code, title)
  SELECT DISTINCT ON (code) html, new_occ, v_target_unit, subject, v_organization, code, title
  FROM public.email_templates
  WHERE occasion = oc
  ORDER BY code, (unit IS NOT DISTINCT FROM v_source_unit) DESC,
    (organization IS NOT DISTINCT FROM v_organization) DESC, id DESC;

  -- 3b. Duplicate information_hidden rows using a loop and record mapping.
  FOR rec IN
    SELECT id, data
    FROM public.information_hidden
    WHERE occasion = oc AND NOT v_demo
  LOOP
    INSERT INTO public.information_hidden (created_at, data, occasion)
    VALUES (now(), rec.data, new_occ)
    RETURNING id INTO new_info_id;

    INSERT INTO tmp_information_hidden (old_id, new_id)
    VALUES (rec.id, new_info_id);
  END LOOP;

  -- 3c. Information – update its foreign key to information_hidden using the mapping.
  INSERT INTO public.information
    (created_at, title, description, is_hidden, "order", updated_at, type, occasion, data, information_hidden, unit)
  SELECT now(), title, description, is_hidden, "order", now(), type, new_occ, data,
         CASE WHEN information_hidden IS NOT NULL
              THEN (SELECT tih.new_id FROM tmp_information_hidden AS tih WHERE tih.old_id = information_hidden)
              ELSE NULL END,
         v_target_unit
  FROM public.information
  WHERE occasion = oc;

  -- 3d. Role Info
  INSERT INTO public.role_info (title, occasion)
  SELECT title, new_occ
  FROM public.role_info
  WHERE occasion = oc;

  ------------------------------------------------------------------
  -- 4. Duplicate tables with additional foreign keys (using loops)
  ------------------------------------------------------------------

  -- 4a. Places
  FOR rec IN
    SELECT id, title, description, type, created_at, coordinates, is_hidden, "order", icon, unit
    FROM public.places
    WHERE occasion = oc
  LOOP
    INSERT INTO public.places
      (title, description, type, created_at, coordinates, is_hidden, updated_at, occasion, "order", icon, unit)
    VALUES (rec.title, rec.description, rec.type, rec.created_at, rec.coordinates, rec.is_hidden, now(), new_occ, rec."order", rec.icon, v_target_unit)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_places (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4b. Exclusive Groups
  FOR rec IN
    SELECT id, title
    FROM public.exclusive_groups
    WHERE occasion = oc
  LOOP
    INSERT INTO public.exclusive_groups (title, occasion)
    VALUES (rec.title, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_exclusive_groups (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4c. Events – adjust the "place" foreign key using tmp_places.
  FOR rec IN
    SELECT id, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, is_hidden, type
    FROM public.events
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_place_id
      FROM tmp_places AS t
      WHERE t.old_id = rec.place;

    INSERT INTO public.events
      (created_at, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, updated_at, is_hidden, occasion, type)
    VALUES (now(), rec.title, rec.start_time, rec.end_time, rec.max_participants, rec.description,
            COALESCE(new_place_id, rec.place), rec.split_for_men_women, rec.is_group_event, now(), rec.is_hidden, new_occ, rec.type)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_events (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4d. Event Groups – update both parent and child using the event mapping.
  INSERT INTO public.event_groups (event_parent, event_child)
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_parent),
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_child)
  FROM public.event_groups eg
  WHERE eg.event_parent IN (SELECT old_id FROM tmp_events)
    AND eg.event_child IN (SELECT old_id FROM tmp_events);

  -- 4e. Event Roles – update event using mapping.
  INSERT INTO public.event_roles (event, role)
  SELECT (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = er.event), er.role
  FROM public.event_roles er
  WHERE er.event IN (SELECT old_id FROM tmp_events);

  -- 4f. Exclusive Events – update both event and group using mappings.
  INSERT INTO public.exclusive_events (event, "group")
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = ee.event),
    (SELECT teg.new_id FROM tmp_exclusive_groups AS teg WHERE teg.old_id = ee."group")
  FROM public.exclusive_events ee
  WHERE ee.event IN (SELECT old_id FROM tmp_events)
    AND ee."group" IN (SELECT old_id FROM tmp_exclusive_groups);

  ------------------------------------------------------------------
  -- 5. Duplicate ESHOP tables (using loops)
  ------------------------------------------------------------------

  -- 5a. Blueprints
  FOR rec IN
    SELECT id, data, title, organization, configuration, objects, groups, background_svg, layout
    FROM eshop.blueprints
    WHERE occasion = oc
  LOOP
    v_layout_ids:='{}';v_copied_layout:=rec.layout;
    IF rec.layout IS NOT NULL THEN
      -- Collect every declared record UUID, including nested preset documents.
      WITH RECURSIVE records(value) AS (
        SELECT rec.layout UNION ALL SELECT child.value FROM records CROSS JOIN LATERAL (
          SELECT item.value FROM jsonb_each(CASE WHEN jsonb_typeof(records.value)='object' THEN records.value ELSE '{}'::jsonb END) item
          UNION ALL SELECT item.value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(records.value)='array' THEN records.value ELSE '[]'::jsonb END) item
        ) child
      )
      INSERT INTO tmp_blueprint_layout_ids(blueprint,old_id,new_id)
      SELECT rec.id,(value->>'id')::uuid,extensions.gen_random_uuid() FROM records WHERE jsonb_typeof(value)='object' AND value ? 'id'
      ON CONFLICT(blueprint,old_id) DO NOTHING;
      SELECT coalesce(jsonb_object_agg(old_id::text,new_id),'{}') INTO v_layout_ids FROM tmp_blueprint_layout_ids WHERE blueprint=rec.id;
      v_copied_layout:=public.remap_blueprint_layout_ids_internal(rec.layout,v_layout_ids);
      PERFORM public.validate_blueprint_layout_internal(v_copied_layout);
    END IF;
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, configuration, objects, groups, occasion, updated_at, background_svg,layout,layout_revision)
    VALUES (now(), rec.data, rec.title, v_organization, rec.configuration, rec.objects, rec.groups, new_occ, now(), rec.background_svg,v_copied_layout,0)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_blueprints (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5b. Product Types
  FOR rec IN
    SELECT id, title, description, type, data
    FROM eshop.product_types
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.product_types
      (created_at, updated_at, title, description, type, data, occasion)
    VALUES (now(), now(), rec.title, rec.description, rec.type, rec.data, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_product_types (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5c. Products – adjust product_type via mapping.
  FOR rec IN
    SELECT id, title, description, price, data, product_type, is_hidden, currency_code, "order", maximum
    FROM eshop.products
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_pt_id
      FROM tmp_product_types AS t
      WHERE t.old_id = rec.product_type;

    INSERT INTO eshop.products
      (created_at, updated_at, title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
    VALUES (now(), now(), rec.title, rec.description, rec.price, rec.data,
            COALESCE(new_pt_id, rec.product_type), new_occ, rec.is_hidden, rec.currency_code, rec."order", rec.maximum)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_products (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- Inventory configuration is copied, never its allocations or reservations.
  FOR rec IN SELECT * FROM public.inventory_pools WHERE occasion=oc LOOP
    INSERT INTO public.inventory_pools(title,description,type,data,sellable_capacity,occasion)
    VALUES(rec.title,rec.description,rec.type,rec.data,rec.sellable_capacity,new_occ)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_pools VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT c.* FROM public.inventory_contexts c
    JOIN tmp_inventory_pools m ON m.old_id=c.inventory_pool LOOP
    INSERT INTO public.inventory_contexts(inventory_pool,block_date,title,"order",data)
    VALUES((SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      rec.block_date,rec.title,rec."order",rec.data) RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_contexts VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resources r
    JOIN tmp_inventory_pools m ON m.old_id=r.inventory_pool LOOP
    INSERT INTO public.resources(title,description,capacity,booking_rules,inventory_pool,place,occasion,unit,data)
    VALUES(rec.title,rec.description,rec.capacity,rec.booking_rules,
      (SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      (SELECT new_id FROM tmp_places WHERE old_id=rec.place),new_occ,v_target_unit,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resources VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resource_slots r JOIN tmp_resources m ON m.old_id=r.resource LOOP
    INSERT INTO public.resource_slots(resource,title,data)
    VALUES((SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),rec.title,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resource_slots VALUES(rec.id,v_new_id);
  END LOOP;
  INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity)
    SELECT p.new_id,c.new_id,x.quantity FROM eshop.product_inventory_contexts x
    JOIN tmp_products p ON p.old_id=x.product
    JOIN tmp_inventory_contexts c ON c.old_id=x.inventory_context;

  -- 5d. Spots – adjust foreign keys for product and blueprint.
  FOR rec IN
    SELECT id, product, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot
    FROM eshop.spots
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_product_id
      FROM tmp_products AS t
      WHERE t.old_id = rec.product;

    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO eshop.spots
      (created_at, occasion, product, updated_at, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot)
    VALUES (now(), new_occ, COALESCE(new_product_id, rec.product), now(), null, null, rec.title, null, COALESCE(new_bp_id, rec.blueprint),
      (SELECT new_id FROM tmp_inventory_contexts WHERE old_id=rec.inventory_context),
      (SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),
      (SELECT new_id FROM tmp_resource_slots WHERE old_id=rec.resource_slot))
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- Copied geometry and commercial state share the same new UUID mapping.
  -- Holds/orders are deliberately absent and numeric spots/products remap too.
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
  SELECT bp.new_id,node_map.new_id,sp.new_id,unit_map.new_id,group_map.new_id,sb.blocked
  FROM eshop.blueprint_seat_bindings sb JOIN tmp_blueprints bp ON bp.old_id=sb.blueprint JOIN tmp_spots sp ON sp.old_id=sb.spot
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=sb.blueprint AND node_map.old_id=sb.node_id
  LEFT JOIN tmp_blueprint_layout_ids unit_map ON unit_map.blueprint=sb.blueprint AND unit_map.old_id=sb.selection_unit
  LEFT JOIN tmp_blueprint_layout_ids group_map ON group_map.blueprint=sb.blueprint AND group_map.old_id=sb.group_node;
  INSERT INTO eshop.blueprint_group_products(blueprint,group_node,product)
  SELECT bp.new_id,node_map.new_id,p.new_id FROM eshop.blueprint_group_products gp
  JOIN tmp_blueprints bp ON bp.old_id=gp.blueprint JOIN tmp_products p ON p.old_id=gp.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=gp.blueprint AND node_map.old_id=gp.group_node;
  INSERT INTO eshop.blueprint_area_bindings(blueprint,node_id,inventory_context,product)
  SELECT bp.new_id,node_map.new_id,c.new_id,p.new_id FROM eshop.blueprint_area_bindings ab JOIN tmp_blueprints bp ON bp.old_id=ab.blueprint
  JOIN tmp_inventory_contexts c ON c.old_id=ab.inventory_context JOIN tmp_products p ON p.old_id=ab.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=ab.blueprint AND node_map.old_id=ab.node_id;

  -- 6. Update blueprints “objects” JSON column if it contains spot objects.
  --    For each blueprint, if its "objects" JSON array contains an object with "type" = 'spot',
  --    replace its "id" with the corresponding new spot id.
  ------------------------------------------------------------------
  FOR rec IN
    SELECT tb.old_id AS old_bp, tb.new_id AS new_bp, b.objects
    FROM tmp_blueprints tb
    JOIN eshop.blueprints b ON b.id = tb.new_id
  LOOP
    IF rec.objects IS NOT NULL THEN
      UPDATE eshop.blueprints
      SET objects = (
        SELECT jsonb_agg(
          CASE
            WHEN obj->>'type' = 'spot' THEN
              obj || jsonb_build_object(
                'id',
                COALESCE(
                  (SELECT ts.new_id FROM tmp_spots ts WHERE ts.old_id = (obj->>'id')::bigint),
                  (obj->>'id')::int
                )
              )
            ELSE obj
          END
        )
        FROM jsonb_array_elements(rec.objects) AS obj
      )
      WHERE id = rec.new_bp;
    END IF;
  END LOOP;


  ------------------------------------------------------------------
  -- 7. Duplicate Forms and Form Fields
  ------------------------------------------------------------------

  -- 7a. Forms – adjust the blueprint foreign key via mapping and update the link to be unique.
  FOR rec IN
    SELECT id, data, key, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds
    FROM public.forms
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO public.forms
      (created_at, data, key, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, updated_at, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds)
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type,
            CASE WHEN v_demo THEN NULL WHEN v_source_unit = v_target_unit OR EXISTS (
              SELECT 1 FROM eshop.unit_bank_accounts uba
              WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN rec.bank_account ELSE NULL END,
            rec.deadline_duration_seconds,
            CASE WHEN v_demo THEN false WHEN v_source_unit <> v_target_unit AND rec.bank_account IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts uba
                WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN false ELSE rec.is_open END,
            NULL,
            COALESCE(new_bp_id, rec.blueprint), rec.header, rec.header_off, now(), rec.title, rec.participant_capacity, rec.waitlist_enabled, rec.show_remaining_capacity, rec.waitlist_offer_duration_seconds)
    RETURNING id INTO v_new_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',v_new_id,NULL,true) WHERE id=v_new_id;

    INSERT INTO tmp_forms (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 7b. Form Fields – update the "form" foreign key and product_type via mapping tables.
  FOR rec IN SELECT * FROM public.form_fields WHERE form IN (SELECT old_id FROM tmp_forms) LOOP
    INSERT INTO public.form_fields(created_at,title,description,data,type,is_required,form,is_hidden,"order",product_type,is_ticket_field)
    VALUES(now(),rec.title,rec.description,rec.data,rec.type,rec.is_required,
      (SELECT new_id FROM tmp_forms WHERE old_id=rec.form),rec.is_hidden,rec."order",
      (SELECT new_id FROM tmp_product_types WHERE old_id=rec.product_type),rec.is_ticket_field) RETURNING id INTO v_new_id;
    INSERT INTO tmp_scanner_fields VALUES(rec.id,v_new_id);
  END LOOP;
  INSERT INTO public.scanner_settings(occasion_id,config)
  SELECT new_occ,jsonb_set(jsonb_set(config,'{products}',jsonb_build_object('mode',config#>>'{products,mode}',
    'ids',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,ids}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb),
    'order',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,order}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb))),
    '{fields}',coalesce((SELECT jsonb_agg(CASE WHEN f->>'source'='builtin' THEN f ELSE
      f||jsonb_build_object('form_id',fm.new_id,'field_id',ff.new_id,'key',(CASE WHEN f->>'source'='ticket_field' THEN 'ticket' ELSE 'order' END)||':'||fm.new_id||':'||ff.new_id) END ORDER BY n)
      FROM jsonb_array_elements(config->'fields') WITH ORDINALITY x(f,n)
      LEFT JOIN tmp_forms fm ON fm.old_id=(f->>'form_id')::bigint LEFT JOIN tmp_scanner_fields ff ON ff.old_id=(f->>'field_id')::bigint
      WHERE f->>'source'='builtin' OR (fm.new_id IS NOT NULL AND ff.new_id IS NOT NULL)),'[]'::jsonb))
  FROM public.scanner_settings WHERE occasion_id=oc;


  ------------------------------------------------------------------
  -- 8. Return the new occasion id
  ------------------------------------------------------------------
  -- References are remapped only after the complete type map exists.
  UPDATE public.occasions o SET features=(SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' AND f ? 'layout'
    THEN jsonb_set(f,'{layout,templates}',(SELECT jsonb_object_agg(t.key,jsonb_set(t.value,'{elements}',
      (SELECT jsonb_agg(CASE WHEN e->>'binding'='productType' THEN jsonb_set(e,'{productTypeId}',
        to_jsonb((SELECT m.new_id FROM tmp_product_types m WHERE m.old_id=(e->>'productTypeId')::bigint))) ELSE e END ORDER BY n)
       FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)))) FROM jsonb_each(f->'layout'->'templates') t)) ELSE f END ORDER BY n)
    FROM jsonb_array_elements(o.features) WITH ORDINALITY x(f,n)) WHERE o.id=new_occ;
  PERFORM public.validate_ticket_layout_references(new_occ,f->'layout') FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=new_occ AND f->>'code'='ticket' AND f ? 'layout';
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,tmp_blueprint_layout_ids,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden,
    tmp_inventory_pools,tmp_inventory_contexts,tmp_resources,tmp_resource_slots,tmp_scanner_fields;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;


-- Existing internal callers retain same-unit semantics.
