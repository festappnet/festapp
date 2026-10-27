-- Bounded organizer tabs. Existing aggregate commands remain the write owners.
CREATE OR REPLACE FUNCTION public.manage_unit_agenda(p_unit bigint,p_organization bigint,p_action text,p_payload jsonb,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; begun jsonb; hash text; lim int:=coalesce((p_payload->>'limit')::int,50);
BEGIN
 PERFORM public.lock_people_scope_internal_v1(NULL,p_organization,p_unit);
 IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>786432 OR lim NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid organizer agenda'; END IF;
 IF p_action='quotes.list' THEN
  IF NOT public.can_read_unit_information(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit information reader required'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]') INTO result FROM (
   SELECT i.id,i.title,i.description,i.type,i.is_hidden AS "isHidden",i."order",i.data,coalesce(v.version,0) AS "aggregateVersion"
   FROM public.information i LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='information' AND v.scope_type='unit' AND v.scope_id=p_unit AND v.aggregate_id=i.id::text
   WHERE i.unit=p_unit AND i.occasion IS NULL AND i.information_hidden IS NULL AND i.type='quote' AND (p_payload->>'after' IS NULL OR i.id>(p_payload->>'after')::bigint) ORDER BY i.id LIMIT lim) page;
  RETURN jsonb_build_object('items',result);
 ELSIF p_action IN ('quotes.save','quotes.delete') THEN
  IF p_action='quotes.save' THEN
   IF p_payload#>>'{quote,type}' IS DISTINCT FROM 'quote' THEN RAISE invalid_parameter_value USING MESSAGE='quote type required'; END IF;
   IF p_payload#>>'{quote,id}' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.information WHERE id=(p_payload#>>'{quote,id}')::bigint AND unit=p_unit AND occasion IS NULL AND type='quote') THEN RAISE insufficient_privilege USING MESSAGE='quote unavailable'; END IF;
   RETURN public.save_unit_information_client_sync_v1(p_unit,p_command_id,(p_payload->>'expectedVersion')::bigint,p_payload->'quote');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.information WHERE id=(p_payload->>'quoteId')::bigint AND unit=p_unit AND occasion IS NULL AND type='quote') THEN
   -- The original owner must still be able to return a receipt after deletion.
   IF NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND unit=p_unit AND command_name='unit.information.delete') THEN RAISE insufficient_privilege USING MESSAGE='quote unavailable'; END IF;
  END IF;
  RETURN public.delete_unit_information_client_sync_v1(p_unit,(p_payload->>'quoteId')::bigint,p_command_id,(p_payload->>'expectedVersion')::bigint);
 ELSIF p_action='legal.inspect' THEN
  result:=public.get_unit_legal_profile(p_unit);
  RETURN jsonb_set(result,'{profile}',(result->'profile')-ARRAY['reviewNote','reviewSource']);
 ELSIF p_action IN ('legal.save','legal.submit') THEN
  IF NOT public.can_manage_unit_legal_profile(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit legal manager required'; END IF;
  hash:=encode(extensions.digest(jsonb_build_object('unit',p_unit,'action',p_action,'payload',p_payload)::text,'sha256'),'hex');
  begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.'||p_action,p_unit,auth.uid(),hash);
  IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
  result:=CASE WHEN p_action='legal.save' THEN public.save_unit_legal_profile(p_unit,(p_payload->>'expectedRevision')::bigint,p_payload->'profile')
   ELSE public.submit_unit_verification(p_unit,(p_payload->>'expectedRevision')::bigint) END;
  IF result ? 'profile' THEN result:=jsonb_set(result,'{profile}',(result->'profile')-ARRAY['reviewNote','reviewSource']); END IF;
  IF result->>'code'<>'200' THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,CASE WHEN result->>'code'='409' THEN 'conflict' ELSE 'rejected' END,(result->>'code')::int,result); END IF;
  RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.'||p_action,'unit_legal_profile',p_unit,'update',result);
 END IF;
 RAISE invalid_parameter_value USING MESSAGE='unsupported organizer agenda';
END $$;
REVOKE ALL ON FUNCTION public.manage_unit_agenda(bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_unit_agenda(bigint,bigint,text,jsonb,uuid) TO authenticated;

-- A deleted organizer has no live membership row. Its exact actor-owned
-- tombstone may only replay the recorded result; it cannot authorize a new effect.
CREATE OR REPLACE FUNCTION public.delete_unit_client_sync_v1(p_unit bigint,p_command_id uuid,p_organization bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE hash text; receipt public.client_mutation_receipts; organization_id bigint; begun jsonb;
BEGIN
 IF auth.uid() IS NULL OR p_command_id IS NULL THEN RAISE insufficient_privilege USING MESSAGE='authenticated command required'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('unit',p_unit)::text,'sha256'),'hex');
 SELECT * INTO receipt FROM public.client_mutation_receipts WHERE command_id=p_command_id AND command_name='unit.delete' AND unit=p_unit AND actor_id=auth.uid() AND request_sha256=hash;
 IF FOUND AND receipt.status IN ('completed','expired') THEN
  organization_id:=(receipt.response#>>'{data,organizationId}')::bigint;
  IF (p_organization IS NOT NULL AND p_organization IS DISTINCT FROM organization_id)
   OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=organization_id)
   OR (EXISTS(SELECT 1 FROM public.units WHERE id=p_unit) AND NOT public.can_manage_unit_configuration(p_unit)) THEN RAISE insufficient_privilege USING MESSAGE='organizer tombstone unavailable'; END IF;
  IF receipt.status='expired' THEN RETURN public.expired_client_mutation_response_v1(receipt); END IF;
  RETURN receipt.response;
 END IF;
 PERFORM public.lock_people_scope_internal_v1(NULL,p_organization,p_unit);
 SELECT organization INTO organization_id FROM public.units WHERE id=p_unit FOR UPDATE;
 IF organization_id IS NULL OR NOT public.can_manage_unit_configuration(p_unit) OR public.is_demo_unit(p_unit) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.delete',p_unit,auth.uid(),hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 PERFORM public.delete_unit(p_unit);
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.delete','unit',p_unit,'delete',jsonb_build_object('unitId',p_unit,'organizationId',organization_id));
END $$;
REVOKE ALL ON FUNCTION public.delete_unit_client_sync_v1(bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_unit_client_sync_v1(bigint,uuid,bigint) TO authenticated;
