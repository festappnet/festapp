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
REVOKE ALL ON FUNCTION public.validate_blueprint_polygon_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated;

-- Storage boundary validation. Numeric limits and authoring keys mirror the
-- public layout protocol; commercial identities never belong in the document.
CREATE OR REPLACE FUNCTION public.validate_blueprint_geometry_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE n jsonb; value jsonb; field text; index_nodes jsonb; current_node jsonb; seen text[]; depth int; a jsonb; ids text[]; referenced text; shape text;
 geometry_keys text[];
BEGIN
 SELECT array_agg(keys.key) INTO geometry_keys FROM jsonb_array_elements_text(public.blueprint_contract_metadata_internal()->'nodeGeometryKeys') keys(key);
 IF jsonb_typeof(p_doc) IS DISTINCT FROM 'object' OR p_doc->>'schemaVersion' IS DISTINCT FROM '2' OR p_doc->>'symbolSetVersion' IS DISTINCT FROM '1'
  OR jsonb_typeof(p_doc->'nodes') IS DISTINCT FROM 'array' OR jsonb_typeof(p_doc->'canvas') IS DISTINCT FROM 'object' THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LAYOUT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc) key WHERE key<>ALL(ARRAY['schemaVersion','symbolSetVersion','canvas','styles','textPolicy','seatingDefaults','nodes','sections','selectionUnits','attachments','background','presets'])) THEN
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
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}') INTO index_nodes FROM jsonb_array_elements(p_doc->'nodes') x;
 IF (SELECT count(*) FROM jsonb_array_elements(p_doc->'nodes'))<>(SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(p_doc->'nodes') x) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_NODE'; END IF;
 FOR n IN SELECT * FROM jsonb_array_elements(p_doc->'nodes') LOOP
  IF jsonb_typeof(n) IS DISTINCT FROM 'object' OR coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   OR coalesce(n->>'kind','') NOT IN ('group','table','seat','furniture','capacityArea','shape','text','vector','image')
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(n) key WHERE key<>ALL(geometry_keys||ARRAY['id','kind','parentId','transform','width','height','z','locked','label','style','childStyles','seating','surface','assembly','graphic','originalSource'])) THEN
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
  IF n ? 'locked' AND jsonb_typeof(n->'locked')<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_BOOLEAN';END IF;
  IF n ? 'obstacle' AND jsonb_typeof(n->'obstacle')<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_BOOLEAN';END IF;
  IF n ? 'capacity' AND (jsonb_typeof(n->'capacity')<>'number' OR (n->>'capacity')::numeric<0 OR (n->>'capacity')::numeric<>trunc((n->>'capacity')::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
  shape:=n->>'shape';
  IF shape IS NOT NULL AND shape NOT IN ('rect','rectangle','roundedRect','ellipse','oval','circle','round','polygon','polyline','line','arrow') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SHAPE'; END IF;
  IF n->>'symbol' IS NOT NULL AND n->>'symbol' NOT IN ('chair','bench','sofa','wheelchair','driver') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SYMBOL'; END IF;
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
 UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) item LOOP
  IF coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' OR n->>'id'=ANY(ids) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_OR_INVALID_ID'; END IF;
  ids:=array_append(ids,n->>'id');
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) LOOP
  IF coalesce(index_nodes->(a->>'rootId')->>'kind','')<>'group' OR coalesce(a->>'title','')='' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SECTION'; END IF;
  IF a->'outline' IS NOT NULL AND a->'outline'<>'null'::jsonb THEN PERFORM public.validate_blueprint_polygon_internal(a->'outline',true); END IF;
 END LOOP;
 IF EXISTS(SELECT attachment->>'seatId' FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) attachment GROUP BY attachment->>'seatId' HAVING count(*)>1)
  OR EXISTS(SELECT section->>'rootId' FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) section GROUP BY section->>'rootId' HAVING count(*)>1) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_AUTHORING_REFERENCE'; END IF;
 IF jsonb_array_length(coalesce(p_doc->'presets','[]'))>100 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_PRESET_LIMIT'; END IF;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) LOOP
  IF coalesce(a->>'title','')='' OR jsonb_typeof(a->'document') IS DISTINCT FROM 'object' OR jsonb_array_length(coalesce(a#>'{document,nodes}','[]'))>2000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRESET'; END IF;
  PERFORM public.validate_blueprint_geometry_internal(a->'document');
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_blueprint_geometry_internal(jsonb) FROM PUBLIC,anon,authenticated;
