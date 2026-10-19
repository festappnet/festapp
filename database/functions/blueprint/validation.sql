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
REVOKE ALL ON FUNCTION public.validate_blueprint_layout_internal(jsonb) FROM PUBLIC,anon,authenticated;
