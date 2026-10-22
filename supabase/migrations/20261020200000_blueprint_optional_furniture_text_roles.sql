-- Field definitions and shaping policy come from the core-generated metadata.



CREATE OR REPLACE FUNCTION public.blueprint_layout_text_requests_internal(p_layout jsonb,p_presets boolean DEFAULT false)
RETURNS TABLE(node_key text,font_family_id text,font_face_id text,role text,descriptor jsonb)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH RECURSIVE documents(doc,prefix) AS (
  SELECT p_layout,''::text UNION ALL
  SELECT preset->'document',prefix||(preset->>'id')||'/' FROM documents
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'presets','[]')) preset WHERE p_presets
 ), roles AS (
  SELECT doc,prefix||(node->>'id') AS node_key,node,
   public.blueprint_resolved_label_internal(doc,node) AS label,
   CASE WHEN node->>'kind'='text' THEN 'text' ELSE 'label' END AS role,
   CASE WHEN node->>'kind'='text' THEN coalesce(node->>'text','') ELSE coalesce(node->>'label','') END AS source
  FROM documents CROSS JOIN LATERAL jsonb_array_elements(doc->'nodes') node
  WHERE node->>'kind' NOT IN ('group','seat','vector','image')
   AND (node->>'kind'<>'furniture' OR node->>'furniture' IS DISTINCT FROM 'couch')
   AND (node->>'kind'<>'table' OR node->>'furniture' IS DISTINCT FROM 'bar')
  UNION ALL
  SELECT doc,prefix||(node->>'id')||':number',node,
   (public.blueprint_contract_metadata_internal()->'labelDefaults')||(doc->'textPolicy')||coalesce(doc#>'{styles,label}','{}'),
   'number','' FROM documents CROSS JOIN LATERAL jsonb_array_elements(doc->'nodes') node
  WHERE node->>'kind'='capacityArea' OR (node->>'kind'='furniture' AND node->>'furniture' IS DISTINCT FROM 'couch' AND EXISTS(
   SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) unit WHERE jsonb_array_length(unit->'nodeIds')>1
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(unit->'nodeIds') member
     WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(doc->'nodes') child WHERE child->>'id'=member AND child->>'parentId'=node->>'id'))))
 ), requests AS (
  SELECT roles.*,f.manifest->'faces'->>((label->>'weight')||':'||CASE WHEN label->>'italic'='true' THEN 'italic' ELSE 'normal' END) AS face_id
   FROM roles LEFT JOIN public.ticket_font_families f ON f.id=label->>'fontFamilyId'
 )
 SELECT node_key,label->>'fontFamilyId',face_id,role,
  CASE WHEN role='number' THEN jsonb_build_object('layoutResourceProtocol',2,'policy',public.blueprint_contract_metadata_internal()->'textPolicy','role','number','fontFaceId',face_id)
  ELSE jsonb_build_object('layoutResourceProtocol',2,'policy',public.blueprint_contract_metadata_internal()->'textPolicy',
   'request',jsonb_build_object('text',source,'role',role,'fontFamilyId',label->>'fontFamilyId','fontFaceId',face_id,
    'size',label->'size','language',label->'language','direction',label->'direction','lineHeight',label->'lineHeight','align',label->'align',
    'box',jsonb_build_object('x',-(node->>'width')::numeric/2,'y',-(node->>'height')::numeric/2,'width',node->'width','height',node->'height'),
    'fit',CASE WHEN role='text' THEN 'wrap' ELSE 'shrink' END)) END
 FROM requests WHERE role='number' OR source<>''
$$;


CREATE INDEX IF NOT EXISTS blueprint_text_resources_descriptor_idx ON public.blueprint_text_resources USING gin((payload->'descriptor') jsonb_path_ops);
