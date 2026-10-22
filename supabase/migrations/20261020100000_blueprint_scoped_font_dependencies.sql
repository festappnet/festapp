-- Scoped font save/read closure. Sources: database/functions/blueprint/{resources,validation}.sql
ALTER TABLE public.ticket_font_assets ADD COLUMN IF NOT EXISTS layout_outline jsonb;

REVOKE ALL ON FUNCTION public.register_blueprint_layout_font(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_blueprint_layout_font(text,jsonb) TO service_role;
-- Schema-1 dependency boundary. Match effectiveNodeProperties: a kind
-- declaration wins over an unmasked node value; explicit overrides win last.
-- Presets have their own document defaults and namespace.
CREATE OR REPLACE FUNCTION public.blueprint_layout_font_dependencies_internal(p_layout jsonb)
RETURNS TABLE(font_id text,node_id text,rendered_text text)
LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH RECURSIVE documents(doc) AS (
  SELECT p_layout UNION ALL
  SELECT preset->'document' FROM documents
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'presets','[]')) preset
 ), declarations AS (
  SELECT doc#>>'{defaultTextStyle,fontId}' AS font_id FROM documents
  UNION SELECT style->>'fontId' FROM documents
   CROSS JOIN LATERAL jsonb_each(coalesce(doc->'appearance','{}')) styles(kind,style)
  UNION SELECT node->>'fontId' FROM documents
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'nodes','[]')) node
 )
 SELECT font_id,NULL::text,NULL::text FROM declarations WHERE font_id IS NOT NULL
 UNION ALL
 SELECT coalesce(CASE WHEN coalesce(node->'appearanceOverrides','[]') ? 'fontId' THEN node->>'fontId' END,
   doc->'appearance'->(node->>'kind')->>'fontId',node->>'fontId',doc#>>'{defaultTextStyle,fontId}'),
  node->>'id',CASE WHEN node->>'kind'='seat' OR (node->>'kind'='furniture' AND node->>'furniture'='couch')
   OR (node->>'kind'='table' AND node->>'furniture'='bar') THEN ''
   WHEN node->>'kind'='text' THEN coalesce(node->>'text','') ELSE coalesce(node->>'label','') END
 FROM documents CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'nodes','[]')) node
$$;
REVOKE ALL ON FUNCTION public.blueprint_layout_font_dependencies_internal(jsonb) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.blueprint_layout_resources_internal(p_layout jsonb,p_occasion bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('protocol',1,'fonts',coalesce((SELECT jsonb_object_agg(a.id,a.layout_outline)
 FROM public.ticket_font_assets a WHERE a.layout_outline IS NOT NULL AND a.id IN (
  SELECT font_id FROM public.blueprint_layout_font_dependencies_internal(p_layout))),'{}'),
 'assets',coalesce((SELECT jsonb_object_agg(a.asset_ref,jsonb_build_object('hash',a.hash,'url',a.url,'width',a.width,'height',a.height,'mimeType',a.mime_type,'byteLength',a.byte_length))
 FROM public.blueprint_image_assets a WHERE (a.occasion=p_occasion OR a.unit=p_unit) AND a.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion UNION ALL SELECT organization FROM public.units WHERE id=p_unit)
 AND a.state='ready' AND a.asset_ref=p_layout#>>'{background,assetRef}' AND a.hash=p_layout#>>'{background,hash}'),'{}'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_layout_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated;


REVOKE ALL ON FUNCTION public.validate_blueprint_polygon_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated;

-- Storage boundary validation. Numeric limits and authoring keys mirror the
-- public layout protocol; commercial identities never belong in the document.
CREATE OR REPLACE FUNCTION public.validate_blueprint_layout_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE n jsonb; value jsonb; field text; index_nodes jsonb; current_node jsonb; seen text[]; depth int; a jsonb; ids text[]; referenced text; font jsonb; ch text; shape text; scope text; style jsonb; dependency record;
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
 -- Closed kind appearance records use the same keys/ranges as core v1.
 IF p_doc ? 'appearance' THEN
  IF jsonb_typeof(p_doc->'appearance') IS DISTINCT FROM 'object' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
  FOR scope,style IN SELECT * FROM jsonb_each(p_doc->'appearance') LOOP
   IF scope NOT IN ('table','seat','furniture','shape','capacityArea','text') OR jsonb_typeof(style) IS DISTINCT FROM 'object' THEN
    RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
   FOR field,value IN SELECT * FROM jsonb_each(style) LOOP
    IF field NOT IN ('fontId','size','bold','italic','seatWidth','seatHeight','seatGap','seatSpacing','seatEdgePadding','objectStyle','seatStyle','fill','stroke','strokeWidth','cornerRadius','opacity','color')
     OR (field IN ('seatWidth','seatHeight','seatGap','seatSpacing','seatEdgePadding') AND scope<>'table') OR value='null'::jsonb THEN
     RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
    IF field='fontId' THEN
     IF jsonb_typeof(value)<>'string' OR value#>>'{}'='' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
    ELSIF field IN ('bold','italic') THEN
     IF jsonb_typeof(value)<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
    ELSIF field IN ('fill','stroke','color') THEN
     IF jsonb_typeof(value)<>'string' OR value#>>'{}' !~ '^#[0-9a-fA-F]{8}$' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
    ELSIF field='objectStyle' THEN
     IF value#>>'{}' NOT IN ('round','simple','minimal','wood','lounge','transit','hall','banquet') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
    ELSIF field='seatStyle' THEN
     IF value#>>'{}' NOT IN ('roundUpholstered','round','plain','wood','upholstered','transit','banquet') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
    ELSE
     IF jsonb_typeof(value)<>'number' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
     IF value::numeric<(CASE WHEN field IN ('seatWidth','seatHeight','size') THEN 1 ELSE 0 END)
      OR value::numeric>(CASE WHEN field='size' THEN 4096 WHEN field='opacity' THEN 1 WHEN field IN ('seatWidth','seatHeight','seatGap','seatSpacing','seatEdgePadding') THEN 1000000 ELSE 1000000000 END) THEN
      RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_APPEARANCE'; END IF;
    END IF;
   END LOOP;
  END LOOP;
 END IF;
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
 -- Reader and validation share exactly the same dependency closure.
 FOR dependency IN SELECT * FROM public.blueprint_layout_font_dependencies_internal(p_doc) LOOP
  SELECT layout_outline INTO font FROM public.ticket_font_assets WHERE id=dependency.font_id;
  IF font IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_RESOURCE_NOT_READY'; END IF;
  FOR ch IN SELECT regexp_split_to_table(coalesce(dependency.rendered_text,''),'') LOOP
   IF ch NOT IN ('',E'\n',E'\r') AND NOT (font->'glyphs' ? ch) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_GLYPH_NOT_READY',DETAIL=jsonb_build_object('nodeId',dependency.node_id)::text; END IF;
  END LOOP;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_blueprint_layout_internal(jsonb) FROM PUBLIC,anon,authenticated;
