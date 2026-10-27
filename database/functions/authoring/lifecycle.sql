-- The SQL receipt is still the canonical create/delete owner. This ledger owns
-- only completion of the existing copy's two media references in the image Worker.
CREATE TABLE IF NOT EXISTS public.occasion_media_jobs(
 command_id uuid PRIMARY KEY,actor_id uuid NOT NULL,organization bigint NOT NULL,
 source_unit bigint NOT NULL,target_unit bigint NOT NULL,source_occasion bigint NOT NULL,
 target_occasion bigint NOT NULL,action text NOT NULL CHECK(action IN ('copy','delete')),
 request_sha256 text NOT NULL,state text NOT NULL CHECK(state IN ('pending','complete')),
 media jsonb NOT NULL DEFAULT '[]',apply_command uuid NOT NULL DEFAULT gen_random_uuid(),
 created_at timestamptz NOT NULL DEFAULT now(),completed_at timestamptz);
ALTER TABLE public.occasion_media_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_media_jobs FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_media_job(p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE job public.occasion_media_jobs;
BEGIN
 SELECT * INTO job FROM public.occasion_media_jobs WHERE command_id=p_command_id;
 IF job.command_id IS NULL OR job.actor_id IS DISTINCT FROM auth.uid() THEN RAISE insufficient_privilege USING MESSAGE='lifecycle intent unavailable'; END IF;
 PERFORM public.lock_people_scope_internal_v1(NULL,job.organization,job.source_unit);
 IF job.action='delete' THEN
  IF NOT public.can_delete_occasion_in_unit(job.source_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 ELSE
  PERFORM public.lock_people_scope_internal_v1(NULL,job.organization,job.target_unit);
  IF NOT (public.can_copy_occasion_source(job.source_occasion) OR (NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=job.source_occasion) AND public.can_copy_occasion_target(job.source_unit))) OR NOT public.can_copy_occasion_target(job.target_unit)
   OR (EXISTS(SELECT 1 FROM public.occasions WHERE id=job.target_occasion) AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=job.target_occasion AND unit=job.target_unit AND organization=job.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='copy scope changed'; END IF;
 END IF;
 RETURN jsonb_build_object('commandId',job.command_id,'unitId',job.source_unit,'targetUnitId',job.target_unit,
  'occasionId',job.target_occasion,'sourceOccasionId',job.source_occasion,'action',job.action,'state',job.state,'media',job.media,
  'assetDisposition',CASE WHEN job.action='delete' THEN 'detached-retained' WHEN job.state='pending' THEN 'copy-pending' ELSE 'copied' END);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_media_job(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_media_job(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.start_occasion_lifecycle(p_unit bigint,p_organization bigint,p_occasion bigint,p_action text,p_command_id uuid,p_target_unit bigint DEFAULT NULL,p_locale text DEFAULT 'en')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE source_unit bigint; organization_id bigint; target_unit bigint; hash text; job public.occasion_media_jobs; result jsonb; target bigint; manifest jsonb:='[]'; source_url text; field text; target_url text; row_data public.occasions;
BEGIN
 SELECT unit,organization INTO source_unit,organization_id FROM public.occasions WHERE id=p_occasion;
 IF source_unit IS NULL THEN SELECT j.source_unit,j.organization INTO source_unit,organization_id FROM public.occasion_media_jobs j WHERE j.command_id=p_command_id AND j.actor_id=auth.uid(); END IF;
 IF source_unit IS NULL OR (p_unit IS NOT NULL AND p_unit<>source_unit) OR (p_organization IS NOT NULL AND p_organization<>organization_id) THEN RAISE insufficient_privilege USING MESSAGE='occasion scope changed'; END IF;
 target_unit:=coalesce(p_target_unit,source_unit);
 PERFORM public.lock_people_scope_internal_v1(NULL,organization_id,source_unit);
 IF p_action NOT IN ('copy','delete') OR p_action IS NULL OR p_command_id IS NULL OR p_locale NOT IN ('en','cs','sk','de','pl','uk') THEN RAISE invalid_parameter_value USING MESSAGE='invalid lifecycle command'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('unit',source_unit,'organization',organization_id,'occasion',p_occasion,'action',p_action,'targetUnit',target_unit,'locale',p_locale)::text,'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_command_id::text,5319));
 SELECT * INTO job FROM public.occasion_media_jobs WHERE command_id=p_command_id FOR UPDATE;
 IF FOUND THEN
  IF job.request_sha256<>hash OR job.actor_id IS DISTINCT FROM auth.uid() THEN RAISE invalid_parameter_value USING MESSAGE='lifecycle command identity conflict'; END IF;
  PERFORM public.get_occasion_media_job(p_command_id);
  SELECT response INTO result FROM public.client_mutation_receipts WHERE command_id=p_command_id;
  RETURN jsonb_set(result,'{data}',coalesce(result->'data','{}')||jsonb_build_object('mediaJob',public.get_occasion_media_job(p_command_id)));
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND unit=source_unit AND organization=organization_id) THEN RAISE insufficient_privilege USING MESSAGE='occasion scope changed'; END IF;
 IF p_action='copy' THEN
  IF NOT public.can_copy_occasion_source(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='copy source unavailable'; END IF;
  -- Fence organizer moves through the same stored-scope helper as other tools.
  -- Source forms precede its occasion row, matching the canonical save order.
  PERFORM 1 FROM public.forms WHERE occasion=p_occasion ORDER BY id FOR SHARE;
  PERFORM public.lock_people_scope_internal_v1(p_occasion,organization_id,source_unit);
 END IF;
 IF p_action='delete' THEN
  IF target_unit<>source_unit THEN RAISE invalid_parameter_value USING MESSAGE='delete has no target unit'; END IF;
  result:=public.delete_occasion_client_sync_v1(p_occasion,p_command_id);target:=p_occasion;
  -- The canonical deleter owns its forms/products/occasion lock order. Its
  -- accepted receipt carries the actually locked unit even after row removal.
  -- A move during admission rolls back the entire delete rather than widening consent.
  IF NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts r JOIN public.units u ON u.id=r.unit
    WHERE r.command_id=p_command_id AND r.actor_id=auth.uid() AND r.command_name='occasion.delete'
     AND r.unit=source_unit AND u.organization=organization_id) THEN RAISE insufficient_privilege USING MESSAGE='deleted occasion scope changed'; END IF;
 ELSE
  PERFORM public.lock_people_scope_internal_v1(NULL,organization_id,target_unit);
  result:=public.duplicate_occasion_client_sync_v1(p_occasion,p_command_id,target_unit,p_locale);
  target:=(result#>>'{data,occasionId}')::bigint;
  SELECT * INTO row_data FROM public.occasions WHERE id=target;
  FOREACH field IN ARRAY ARRAY['image','background'] LOOP
   source_url:=CASE WHEN field='image' THEN row_data.data->>'image' ELSE (SELECT f->>'background' FROM jsonb_array_elements(row_data.features) f WHERE f->>'code'='ticket') END;
   IF nullif(source_url,'') IS NULL OR source_url LIKE 'https://img.festapp.net/ticket-presets/v1/%'
    OR EXISTS(SELECT 1 FROM public.images WHERE link=source_url AND occasion=target) THEN CONTINUE; END IF;
   -- Only immutable canonical public objects. Never fetch arbitrary URLs from DB text.
   IF source_url !~ '^https://(a[.])?img[.]festapp[.]net/(images|assets)/[A-Za-z0-9._/-]+$' OR source_url LIKE '%..%' THEN RAISE invalid_parameter_value USING MESSAGE='copy source is not a canonical image'; END IF;
   target_url:='https://img.festapp.net/images/lifecycle/'||p_command_id||'/'||encode(extensions.digest(source_url,'sha256'),'hex');
   manifest:=manifest||jsonb_build_array(jsonb_build_object('field',field,'source',source_url,'target',target_url,'ready',false));
  END LOOP;
 END IF;
 IF result->>'code'<>'200' OR target IS NULL THEN RAISE EXCEPTION 'LIFECYCLE_COMMAND_REJECTED'; END IF;
 INSERT INTO public.occasion_media_jobs(command_id,actor_id,organization,source_unit,target_unit,source_occasion,target_occasion,action,request_sha256,state,media,completed_at)
 VALUES(p_command_id,auth.uid(),organization_id,source_unit,target_unit,p_occasion,target,p_action,hash,CASE WHEN manifest='[]' THEN 'complete' ELSE 'pending' END,manifest,CASE WHEN manifest='[]' THEN now() END);
 RETURN jsonb_set(result,'{data}',coalesce(result->'data','{}')||jsonb_build_object('mediaJob',public.get_occasion_media_job(p_command_id)));
END $$;
REVOKE ALL ON FUNCTION public.start_occasion_lifecycle(bigint,bigint,bigint,text,uuid,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.start_occasion_lifecycle(bigint,bigint,bigint,text,uuid,bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_occasion_media_step(p_command_id uuid,p_index integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE job public.occasion_media_jobs; step jsonb;
BEGIN
 PERFORM public.get_occasion_media_job(p_command_id);
 SELECT * INTO job FROM public.occasion_media_jobs WHERE command_id=p_command_id FOR UPDATE;
 IF p_index IS NULL OR p_index<0 OR p_index>=jsonb_array_length(job.media) THEN RAISE invalid_parameter_value USING MESSAGE='invalid media step'; END IF;
 step:=job.media->p_index;
 IF step->>'ready'='true' THEN RETURN public.get_occasion_media_job(p_command_id); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.images WHERE link=step->>'target' AND occasion=job.target_occasion) THEN
  PERFORM public.add_image_record(step->>'target',job.target_occasion,NULL);
 END IF;
 UPDATE public.occasion_media_jobs SET media=jsonb_set(media,ARRAY[p_index::text,'ready'],'true') WHERE command_id=p_command_id;
 RETURN public.get_occasion_media_job(p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.record_occasion_media_step(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_occasion_media_step(uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.finish_occasion_media_job(p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE job public.occasion_media_jobs; occasion_row public.occasions; features jsonb; settings jsonb:='{}'; step jsonb; config jsonb; ver bigint; result jsonb;
BEGIN
 PERFORM public.get_occasion_media_job(p_command_id);
 SELECT * INTO job FROM public.occasion_media_jobs WHERE command_id=p_command_id FOR UPDATE;
 IF job.state='complete' THEN RETURN public.get_occasion_media_job(p_command_id); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(job.media) x WHERE x->>'ready'<>'true') THEN RAISE object_not_in_prerequisite_state USING MESSAGE='media is pending'; END IF;
 -- Same forms -> occasion order as the canonical save owner.
 PERFORM 1 FROM public.forms WHERE occasion=job.target_occasion ORDER BY id FOR UPDATE;
 SELECT * INTO occasion_row FROM public.occasions WHERE id=job.target_occasion AND unit=job.target_unit AND organization=job.organization FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='copy target unavailable'; END IF;
 features:=occasion_row.features;
 FOR step IN SELECT * FROM jsonb_array_elements(job.media) LOOP
  IF step->>'field'='image' AND occasion_row.data->>'image'=step->>'source' THEN settings:=settings||jsonb_build_object('image',step->'target');
  ELSIF step->>'field'='background' THEN
   SELECT coalesce(jsonb_agg(CASE WHEN f->>'code'='ticket' AND f->>'background'=step->>'source' THEN f||jsonb_build_object('background',step->'target') ELSE f END),'[]') INTO features FROM jsonb_array_elements(features) f;
  END IF;
 END LOOP;
 -- Preserve any newer user-selected image and every unrelated setting/feature.
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='occasion' AND scope_type='occasion' AND scope_id=job.target_occasion AND aggregate_id=job.target_occasion::text),0) INTO ver;
 config:=jsonb_build_object('id',job.target_occasion,'settings',settings,'features',features);
 result:=public.save_occasion_client_sync_v1(job.target_occasion,job.apply_command,ver,config);
 IF result->>'code'<>'200' THEN RAISE serialization_failure USING MESSAGE='copy media apply must retry same job'; END IF;
 UPDATE public.occasion_media_jobs SET state='complete',completed_at=now() WHERE command_id=p_command_id;
 RETURN public.get_occasion_media_job(p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.finish_occasion_media_job(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finish_occasion_media_job(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pending_occasion_media_jobs(p_unit bigint,p_organization bigint,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,p_organization,p_unit);
 IF NOT public.can_copy_occasion_target(p_unit) OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE insufficient_privilege USING MESSAGE='organizer manager required'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page."createdAt",page."commandId"),'[]') INTO result FROM (
  SELECT command_id AS "commandId",target_occasion AS "occasionId",target_unit AS "targetUnitId",source_unit AS "unitId",state,created_at AS "createdAt"
  FROM public.occasion_media_jobs WHERE actor_id=auth.uid() AND organization=p_organization AND (source_unit=p_unit OR target_unit=p_unit) AND state='pending' ORDER BY created_at,command_id LIMIT p_limit) page;
 RETURN jsonb_build_object('items',result);
END $$;
REVOKE ALL ON FUNCTION public.get_pending_occasion_media_jobs(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pending_occasion_media_jobs(bigint,bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_occasion_setup_authoring(p_unit bigint,p_organization bigint,p_draft uuid,p_expected_revision bigint DEFAULT NULL,p_command_id uuid DEFAULT NULL,p_source_scopes jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE draft public.occasion_setup_drafts; source bigint; binding jsonb; source_ids bigint[];
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,p_organization,p_unit);
 IF NOT public.can_create_occasion(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='setup author required'; END IF;
 SELECT * INTO draft FROM public.occasion_setup_drafts WHERE id=p_draft AND unit=p_unit AND organization=p_organization FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='setup draft unavailable'; END IF;
 IF p_command_id IS NULL THEN RETURN public.get_occasion_setup_draft(p_draft); END IF;
 IF draft.data ? 'finalizeResponse' THEN RETURN public.finalize_occasion_setup_draft(p_draft,p_expected_revision,p_command_id); END IF;
 IF draft.revision<>p_expected_revision AND NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND unit=p_unit AND command_name='occasion.setup.finalize') THEN RAISE serialization_failure USING MESSAGE='setup draft changed'; END IF;
 source_ids:=ARRAY(SELECT DISTINCT x::bigint FROM unnest(ARRAY[draft.data->>'sourceId',draft.data->>'formSourceOccasionId',draft.data->>'blueprintSourceOccasionId']) x WHERE nullif(x,'') IS NOT NULL);
 IF jsonb_typeof(p_source_scopes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_source_scopes)<>cardinality(source_ids) THEN RAISE insufficient_privilege USING MESSAGE='source consent required'; END IF;
 FOREACH source IN ARRAY source_ids LOOP
  SELECT x INTO binding FROM jsonb_array_elements(p_source_scopes) x WHERE (x->>'occasionId')::bigint=source;
  IF binding IS NULL THEN RAISE insufficient_privilege USING MESSAGE='source consent required'; END IF;
  PERFORM public.lock_people_scope_internal_v1(source,p_organization,(binding->>'unitId')::bigint);
  IF NOT public.can_copy_occasion_source(source) THEN RAISE insufficient_privilege USING MESSAGE='source read denied'; END IF;
 END LOOP;
 RETURN public.finalize_occasion_setup_draft(p_draft,p_expected_revision,p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.manage_occasion_setup_authoring(bigint,bigint,uuid,bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_occasion_setup_authoring(bigint,bigint,uuid,bigint,uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_lifecycle_source_scope(p_occasion bigint,p_organization bigint,p_unit bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF NOT public.can_copy_occasion_source(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='source unavailable'; END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.check_lifecycle_source_scope(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.check_lifecycle_source_scope(bigint,bigint,bigint) TO authenticated;
