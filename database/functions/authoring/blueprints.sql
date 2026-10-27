-- Authoring exposes the saved document and commercial identities, never holds,
-- order/customer bundles or authentication material. The aggregate remains canonical.
CREATE OR REPLACE FUNCTION public.manage_blueprint_authoring(p_occasion bigint,p_organization bigint,p_unit bigint,p_action text,p_payload jsonb,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints%ROWTYPE; result jsonb; payload jsonb:=coalesce(p_payload,'{}'); draft jsonb; lim int:=coalesce((p_payload->>'limit')::int,50);
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF public.can_write_blueprints(p_occasion) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 IF jsonb_typeof(payload) IS DISTINCT FROM 'object' OR octet_length(payload::text)>8388608 OR lim NOT BETWEEN 1 AND 100 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid blueprint authoring request'; END IF;
 IF p_action='list' THEN
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page."blueprintId"),'[]'::jsonb)) INTO result FROM (
   SELECT id AS "blueprintId",title,layout_revision AS "layoutRevision" FROM eshop.blueprints
   WHERE occasion=p_occasion AND (payload->>'after' IS NULL OR id>(payload->>'after')::bigint) ORDER BY id LIMIT lim) page;
  RETURN result;
 ELSIF p_action='authorizeText' THEN RETURN jsonb_build_object('actorId',auth.uid());
 END IF;
 IF p_action='save' THEN PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]); END IF;
 IF payload->>'blueprintId' IS NOT NULL THEN
  SELECT * INTO b FROM eshop.blueprints WHERE id=(payload->>'blueprintId')::bigint AND occasion=p_occasion FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='blueprint outside scope'; END IF;
 END IF;
 IF p_action='inspect' THEN
  IF b.id IS NULL OR b.layout IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='saved blueprint required'; END IF;
  RETURN jsonb_build_object('blueprintId',b.id,'occasionId',b.occasion,'title',b.title,'layoutRevision',b.layout_revision,'layout',b.layout,
   'textResourceIds',coalesce(to_jsonb(b.layout_text_resource_ids),'[]'),'resources',public.blueprint_layout_resources_internal(b.layout,b.occasion))||public.blueprint_binding_projection_internal(b.id);
 ELSIF p_action='validate' THEN
  PERFORM public.validate_blueprint_layout_internal(payload->'layout');
  -- Advisory document validation grants no reservation, resource registration or save.
  RETURN jsonb_build_object('valid',true,'schemaVersion',2);
 ELSIF p_action='save' THEN
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(payload) k WHERE k NOT IN ('blueprintId','title','expectedLayoutRevision','layout','textResourceIds','seatChanges','groupProductChanges','areaBindingChanges')) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported blueprint field'; END IF;
  draft:=(payload-'blueprintId'-'expectedLayoutRevision')||jsonb_build_object('occasion',p_occasion,'organization',p_organization,'expected_layout_revision',payload->'expectedLayoutRevision');
  IF b.id IS NOT NULL THEN draft:=draft||jsonb_build_object('id',b.id); END IF;
  result:=public.update_blueprint_client_sync_v1(draft,p_command_id);
  -- Frozen aggregate output is already a narrow binding projection; never reread after replay.
  RETURN result;
 END IF;
 RAISE invalid_parameter_value USING MESSAGE='unknown blueprint operation';
END $$;
REVOKE ALL ON FUNCTION public.manage_blueprint_authoring(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_blueprint_authoring(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.save_delegated_ticket_layout(p_occasion bigint,p_organization bigint,p_unit bigint,p_command_id uuid,p_expected_version bigint,p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF NOT public.can_edit_ticket_layout(p_occasion) OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_config) k WHERE k NOT IN ('id','ticket_layout_change'))
  OR (p_config->>'id')::bigint IS DISTINCT FROM p_occasion OR p_config->'ticket_layout_change' IS NULL THEN
  RAISE insufficient_privilege USING MESSAGE='scoped ticket artwork intent required'; END IF;
 RETURN public.save_occasion_client_sync_v1(p_occasion,p_command_id,p_expected_version,p_config);
END $$;
REVOKE ALL ON FUNCTION public.save_delegated_ticket_layout(bigint,bigint,bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_delegated_ticket_layout(bigint,bigint,bigint,uuid,bigint,jsonb) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_delegated_render_scope(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF (CASE WHEN p_blueprint THEN NOT public.can_prepare_layout_resources(p_occasion) ELSE NOT public.can_read_ticket_layout(p_occasion) END) THEN
  RAISE insufficient_privilege USING MESSAGE='render scope denied'; END IF;
 RETURN jsonb_build_object('actorId',auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.check_delegated_render_scope(bigint,bigint,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.check_delegated_render_scope(bigint,bigint,bigint,boolean) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.register_delegated_blueprint_text_resources(p_occasion bigint,p_organization bigint,p_unit bigint,p_actor uuid,p_resources jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o public.occasions%ROWTYPE;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' OR p_actor IS NULL THEN RAISE insufficient_privilege USING MESSAGE='resource service required'; END IF;
 SELECT * INTO o FROM public.occasions WHERE id=p_occasion FOR SHARE;
 IF o.id IS NULL OR o.organization IS DISTINCT FROM p_organization OR (p_unit IS NOT NULL AND o.unit IS DISTINCT FROM p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='resource scope changed'; END IF;
 PERFORM 1 FROM public.units WHERE id=o.unit AND organization=p_organization FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='resource organizer changed'; END IF;
 PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_actor FOR SHARE;
 PERFORM 1 FROM public.unit_users WHERE unit=o.unit AND "user"=p_actor FOR SHARE;
 IF NOT public.can_prepare_layout_resources_as_actor_internal_v1(p_actor,p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='resource actor revoked'; END IF;
 PERFORM public.register_blueprint_text_resources(p_occasion,NULL,p_resources);
END $$;
REVOKE ALL ON FUNCTION public.register_delegated_blueprint_text_resources(bigint,bigint,bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.register_delegated_blueprint_text_resources(bigint,bigint,bigint,uuid,jsonb) TO service_role;
