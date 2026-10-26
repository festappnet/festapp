CREATE OR REPLACE FUNCTION public.complete_unit_mutation_internal_v1(
 p_command_id uuid,p_unit bigint,p_source text,p_entity_type text,p_entity_id bigint,p_operation text,p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.client_commits%ROWTYPE;
BEGIN
 INSERT INTO public.client_commits(unit,actor_id,actor_display,actor_kind,source,change_class)
 SELECT p_unit,auth.uid(),nullif(concat_ws(' ',u.name,u.surname),''),'user',p_source,'configuration'
 FROM public.user_info u WHERE u.id=auth.uid() RETURNING * INTO c;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 VALUES(c.commit_id,0,p_entity_type,p_entity_id::text,p_operation,'Unit configuration',ARRAY['aggregate']);
 PERFORM public.fanout_unit_catalog_v1(c.commit_id,p_unit);
 RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object('status','applied','code',200,'data',p_data,
  'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,'commitId',c.commit_id,
  'replayed',false,'occurredAt',c.occurred_at),'sync',jsonb_build_object('replacements','[]'::jsonb)),c.commit_id);
END $$;
REVOKE ALL ON FUNCTION public.complete_unit_mutation_internal_v1(uuid,bigint,text,text,bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
