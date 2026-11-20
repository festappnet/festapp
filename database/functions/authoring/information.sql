-- Scoped transport adapter; the ordinary editor command owns mutations/receipts.
CREATE OR REPLACE FUNCTION public.manage_information_authoring(
 p_occasion bigint,p_organization bigint,p_unit bigint,p_action text,
 p_payload jsonb,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 entity bigint:=(p_payload->>'informationId')::bigint;
 lim integer:=coalesce((p_payload->>'limit')::integer,50);
 item jsonb; result jsonb; rows jsonb; v_version bigint;
 content_type text;
 action text:=p_action;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 CASE p_action
  WHEN 'song_list' THEN content_type:='song'; action:='list';
  WHEN 'song_inspect' THEN content_type:='song'; action:='inspect';
  WHEN 'song_save' THEN content_type:='song'; action:='save';
  ELSE NULL;
 END CASE;
 IF action='save' THEN
  IF NOT public.can_write_information(p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='occasion information editor required';
  END IF;
 ELSIF action IN ('list','inspect') THEN
  IF NOT public.can_read_information_editor_bundle(p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='occasion information reader required';
  END IF;
 ELSE RAISE invalid_parameter_value USING MESSAGE='unsupported information action';
 END IF;
 IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>786432
  OR lim NOT BETWEEN 1 AND 100 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid information request';
 END IF;
 IF action='list' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]') INTO rows FROM (
   SELECT i.id,i.title,i.is_hidden AS "isHidden",i."order",coalesce(v.version,0) AS "aggregateVersion"
   FROM public.information i LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='information' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=i.id::text
   WHERE i.occasion=p_occasion AND nullif(i.type,'') IS NOT DISTINCT FROM content_type
    AND (p_payload->>'after' IS NULL OR i.id>(p_payload->>'after')::bigint)
   ORDER BY i.id LIMIT lim
  ) page;
  RETURN jsonb_build_object('items',rows);
 END IF;
 IF action='save' THEN
  item:=p_payload->'information';entity:=(item->>'id')::bigint;
  IF p_command_id IS NULL OR jsonb_typeof(item) IS DISTINCT FROM 'object'
   OR nullif(item->>'type','') IS DISTINCT FROM content_type
   OR coalesce(item->'hiddenData','null')<>'null' THEN
   RAISE invalid_parameter_value USING MESSAGE='information type does not match action';
  END IF;
 END IF;
 IF entity IS NOT NULL THEN
  -- Serialize against both edits and type changes before any secret-bearing
  -- native editor/receipt projection can be returned to this transport.
  PERFORM 1 FROM public.information WHERE id=entity AND occasion=p_occasion
   AND nullif(type,'') IS NOT DISTINCT FROM content_type FOR UPDATE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='information outside scope'; END IF;
 ELSIF action='inspect' THEN
  RAISE invalid_parameter_value USING MESSAGE='information ID required';
 END IF;
 IF action='save' THEN
  result:=public.save_information_client_sync_v1(p_occasion,p_command_id,
   (p_payload->>'expectedVersion')::bigint,item||jsonb_build_object('hiddenData',NULL));
  item:=result->'data'->'information';
 ELSE
  SELECT to_jsonb(i)||jsonb_build_object('aggregate_version',coalesce(v.version,0)) INTO item
   FROM public.information i LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='information' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=i.id::text WHERE i.id=entity;
 END IF;
 -- Never expose information_hidden, its ID, or arbitrary native envelope data.
 IF item IS NOT NULL AND item<>'null' THEN
  IF (item->>'occasion')::bigint IS DISTINCT FROM p_occasion OR nullif(item->>'type','') IS DISTINCT FROM content_type THEN
   RAISE insufficient_privilege USING MESSAGE='information result outside scope';
  END IF;
  item:=jsonb_build_object('id',item->'id','title',item->'title','description',item->'description',
   'type',item->'type','isHidden',item->'is_hidden','order',item->'order','data',item->'data');
 END IF;
 IF action='save' THEN
  RETURN jsonb_build_object('code',result->'code','status',result->'status','mutation',result->'mutation',
   'data',jsonb_build_object('aggregateVersion',result->'data'->'version','information',item));
 END IF;
 SELECT coalesce(version,0) INTO v_version FROM public.client_aggregate_versions
  WHERE aggregate_type='information' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=entity::text;
 RETURN jsonb_build_object('aggregateVersion',coalesce(v_version,0),'information',item);
END $$;
REVOKE ALL ON FUNCTION public.manage_information_authoring(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_information_authoring(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated;
