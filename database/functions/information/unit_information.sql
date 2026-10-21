CREATE OR REPLACE FUNCTION public.get_unit_information_for_edit_v1(p_unit bigint,p_type text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_read_unit_information(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor view required'; END IF;
 IF p_type='game' THEN RAISE invalid_parameter_value USING MESSAGE='unit games unsupported'; END IF;
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(i)||jsonb_build_object('aggregate_version',coalesce(v.version,0)) ORDER BY i.id)
 FROM public.information i LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='information'
 AND v.scope_type='unit' AND v.scope_id=p_unit AND v.aggregate_id=i.id::text
 WHERE i.unit=p_unit AND i.occasion IS NULL AND i.information_hidden IS NULL
 AND coalesce(i.type,'')=coalesce(p_type,'')),'[]');
END $$;
CREATE OR REPLACE FUNCTION public.save_unit_information_client_sync_v1(p_unit bigint,p_command_id uuid,p_expected_version bigint,p_information jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); ident bigint; ver bigint; before_row jsonb; after_row jsonb; begun jsonb; hash text;
BEGIN
 IF actor IS NULL OR NOT public.can_write_unit_information(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 PERFORM public.validate_information_content_internal_v1(p_information,true);
 ident:=(p_information->>'id')::bigint;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('unit',p_unit,'expectedVersion',p_expected_version,'information',p_information)::text,'UTF8'),'sha256'),'hex');
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.information.save',p_unit,actor,hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 IF ident IS NOT NULL THEN
  SELECT to_jsonb(i) INTO before_row FROM public.information i WHERE i.id=ident AND i.unit=p_unit AND i.occasion IS NULL FOR UPDATE;
  IF before_row IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',404,'{}'); END IF;
  IF before_row->>'type'='game' OR before_row->>'information_hidden' IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='unit games unsupported'; END IF;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('information','unit',p_unit,ident::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO ver FROM public.client_aggregate_versions WHERE aggregate_type='information' AND scope_type='unit' AND scope_id=p_unit AND aggregate_id=ident::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM ver THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('version',ver,'information',before_row)); END IF;
  IF jsonb_build_object('title',before_row->'title','description',before_row->'description','type',before_row->'type','isHidden',before_row->'is_hidden','order',before_row->'order','data',before_row->'data')
   =p_information-'id'-'hiddenData' THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,jsonb_build_object('version',ver,'information',before_row)); END IF;
  UPDATE public.information SET title=p_information->>'title',description=p_information->>'description',type=p_information->>'type',
   is_hidden=(p_information->>'isHidden')::boolean,"order"=(p_information->>'order')::bigint,data=p_information->'data',updated_at=clock_timestamp() WHERE id=ident;
  UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='information' AND scope_type='unit' AND scope_id=p_unit AND aggregate_id=ident::text RETURNING version INTO ver;
 ELSE
  IF p_expected_version IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='new information cannot have version'; END IF;
  INSERT INTO public.information(unit,title,description,type,is_hidden,"order",data)
  VALUES(p_unit,p_information->>'title',p_information->>'description',p_information->>'type',(p_information->>'isHidden')::boolean,(p_information->>'order')::bigint,p_information->'data') RETURNING id INTO ident;
  ver:=1;INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version) VALUES('information','unit',p_unit,ident::text,ver);
 END IF;
 SELECT to_jsonb(i)||jsonb_build_object('aggregate_version',ver) INTO after_row FROM public.information i WHERE id=ident;
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.information.save','information',ident,CASE WHEN before_row IS NULL THEN 'insert' ELSE 'update' END,jsonb_build_object('version',ver,'information',after_row));
END $$;
CREATE OR REPLACE FUNCTION public.delete_unit_information_client_sync_v1(p_unit bigint,p_information_id bigint,p_command_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); ver bigint; old_row jsonb; begun jsonb; hash text;
BEGIN
 IF actor IS NULL OR NOT public.can_write_unit_information(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('unit',p_unit,'id',p_information_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.information.delete',p_unit,actor,hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 SELECT to_jsonb(i) INTO old_row FROM public.information i WHERE id=p_information_id AND unit=p_unit AND occasion IS NULL FOR UPDATE;
 IF old_row IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,'{}'); END IF;
 IF old_row->>'type'='game' OR old_row->>'information_hidden' IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='unit games unsupported'; END IF;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version) VALUES('information','unit',p_unit,p_information_id::text,0) ON CONFLICT DO NOTHING;
 SELECT version INTO ver FROM public.client_aggregate_versions WHERE aggregate_type='information' AND scope_type='unit' AND scope_id=p_unit AND aggregate_id=p_information_id::text FOR UPDATE;
 IF p_expected_version IS DISTINCT FROM ver THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('version',ver,'information',old_row)); END IF;
 DELETE FROM public.information WHERE id=p_information_id;
 DELETE FROM public.client_aggregate_versions WHERE aggregate_type='information' AND scope_type='unit' AND scope_id=p_unit AND aggregate_id=p_information_id::text;
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.information.delete','information',p_information_id,'delete',jsonb_build_object('version',ver,'information',NULL));
END $$;
REVOKE ALL ON FUNCTION public.get_unit_information_for_edit_v1(bigint,text),public.save_unit_information_client_sync_v1(bigint,uuid,bigint,jsonb),public.delete_unit_information_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_information_for_edit_v1(bigint,text),public.save_unit_information_client_sync_v1(bigint,uuid,bigint,jsonb),public.delete_unit_information_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.information,public.information_hidden FROM anon,authenticated;
