-- Field definitions and shaping policy come from the core-generated metadata.
CREATE OR REPLACE FUNCTION public.blueprint_resolved_label_internal(p_doc jsonb,p_node jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT (public.blueprint_contract_metadata_internal()->'labelDefaults')
  ||jsonb_build_object('align',CASE WHEN p_node->>'kind'='text' THEN 'left' ELSE 'center' END)
  ||(p_doc->'textPolicy')||coalesce(p_doc#>'{styles,label}','{}')
  ||coalesce(p_doc->'styles'->'kinds'->(p_node->>'kind')->'label','{}')
  ||coalesce((SELECT parent#>'{childStyles,seat,label}' FROM jsonb_array_elements(p_doc->'nodes') parent
    WHERE p_node->>'kind'='seat' AND parent->>'kind'='table' AND parent->>'id'=p_node->>'parentId'),'{}')
  ||coalesce(p_node#>'{style,label}','{}')
$$;
REVOKE ALL ON FUNCTION public.blueprint_resolved_label_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
REVOKE ALL ON FUNCTION public.blueprint_layout_text_requests_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE INDEX IF NOT EXISTS blueprint_text_resources_descriptor_idx ON public.blueprint_text_resources USING gin((payload->'descriptor') jsonb_path_ops);
CREATE OR REPLACE FUNCTION public.blueprint_canonical_text_resources_internal(p_layout jsonb,p_occasion bigint,p_setup_draft uuid DEFAULT NULL,p_presets boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH requests AS (SELECT * FROM public.blueprint_layout_text_requests_internal(p_layout,p_presets)),
 prepared AS (SELECT DISTINCT r.resource_id,r.resource_kind,r.payload FROM public.blueprint_text_resources r JOIN requests q
  ON r.scope_key=CASE WHEN p_occasion IS NOT NULL THEN 'occasion:'||p_occasion::text ELSE 'setup:'||p_setup_draft::text END
   AND r.payload->'descriptor' @> q.descriptor AND r.payload->'descriptor'=q.descriptor)
 SELECT jsonb_build_object('protocol',2,
  'fontFamilies',coalesce((SELECT jsonb_object_agg(f.id,f.manifest) FROM public.ticket_font_families f WHERE f.id IN (SELECT font_family_id FROM requests)),'{}'),
  'textLayouts',coalesce((SELECT jsonb_object_agg(resource_id,payload) FROM prepared WHERE resource_kind='text'),'{}'),
  'numberSymbols',coalesce((SELECT jsonb_object_agg(payload->>'fontFaceId',payload) FROM prepared WHERE resource_kind='number'),'{}'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_canonical_text_resources_internal(jsonb,bigint,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_blueprint_text_resources_internal(p_layout jsonb,p_occasion bigint,p_setup_draft uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.blueprint_layout_text_requests_internal(p_layout,true) q
  WHERE q.font_face_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.blueprint_text_resources r
   WHERE r.scope_key=CASE WHEN p_occasion IS NOT NULL THEN 'occasion:'||p_occasion::text ELSE 'setup:'||p_setup_draft::text END
    AND r.payload->'descriptor' @> q.descriptor AND r.payload->'descriptor'=q.descriptor)) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_NOT_READY';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_text_resources_internal(jsonb,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_text_resource_ids_internal(p_layout jsonb,p_occasion bigint,p_setup_draft uuid DEFAULT NULL)
RETURNS text[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(array_agg(DISTINCT r.resource_id ORDER BY r.resource_id),'{}'::text[])
 FROM public.blueprint_text_resources r JOIN public.blueprint_layout_text_requests_internal(p_layout,true) q
  ON r.payload->'descriptor' @> q.descriptor AND r.payload->'descriptor'=q.descriptor
 WHERE r.scope_key=CASE WHEN p_occasion IS NOT NULL THEN 'occasion:'||p_occasion::text ELSE 'setup:'||p_setup_draft::text END
$$;
REVOKE ALL ON FUNCTION public.blueprint_text_resource_ids_internal(jsonb,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
