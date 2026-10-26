-- Shared content invariant for ordinary saves and setup-draft overrides.
CREATE OR REPLACE FUNCTION public.validate_email_template_content_internal(p_code text,p_html text)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF p_code='TICKET_ORDER_PAYMENT_DONE' AND
  (length(coalesce(p_html,''))-length(replace(coalesce(p_html,''),'{{tickets}}','')))/length('{{tickets}}')>1 THEN
  RAISE invalid_parameter_value USING MESSAGE='Only one tickets block is allowed'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_email_template_content_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.lock_email_template_hierarchy_internal(p_context jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM 1 FROM public.organizations WHERE id=(p_context->>'organization')::bigint FOR SHARE;
 IF p_context->>'occasion' IS NOT NULL THEN
  PERFORM 1 FROM public.units WHERE id=(p_context->>'unit')::bigint FOR SHARE;
  PERFORM 1 FROM public.occasions WHERE id=(p_context->>'occasion')::bigint FOR UPDATE;
 ELSIF p_context->>'unit' IS NOT NULL THEN
  PERFORM 1 FROM public.units WHERE id=(p_context->>'unit')::bigint FOR UPDATE;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_email_template_hierarchy_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Typed authoring boundary. Scope narrows live rights; template text is data.
CREATE OR REPLACE FUNCTION public.check_email_template_scope_internal(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,p_write boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o bigint; u bigint; c bigint;
BEGIN
 IF auth.uid() IS NULL OR p_organization IS NULL OR p_entity_id IS NULL THEN
  RAISE insufficient_privilege USING MESSAGE='email template scope required'; END IF;
 IF p_entity_type='occasion' THEN
  SELECT organization,unit,id INTO o,u,c FROM public.occasions WHERE id=p_entity_id;
  IF NOT FOUND OR (CASE WHEN p_write THEN public.can_write_occasion_email_templates(c)
     ELSE public.can_read_occasion_email_templates(c) END) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='email template access denied'; END IF;
 ELSIF p_entity_type='unit' THEN
  SELECT organization,id INTO o,u FROM public.units WHERE id=p_entity_id;
  IF NOT FOUND OR (CASE WHEN p_write THEN public.can_write_unit_email_templates(u)
     ELSE public.can_read_unit_email_templates(u) END) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='email template access denied'; END IF;
 ELSE RAISE invalid_parameter_value USING MESSAGE='invalid email template entity'; END IF;
 IF o IS DISTINCT FROM p_organization OR (p_unit IS NOT NULL AND u IS DISTINCT FROM p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='email template hierarchy changed'; END IF;
 RETURN jsonb_build_object('occasion',c,'unit',u,'organization',o);
END $$;
REVOKE ALL ON FUNCTION public.check_email_template_scope_internal(text,bigint,bigint,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- The effective row and target override together form the compare-and-set token.
-- A newly created/deleted override changes identity even if its text is identical.
CREATE OR REPLACE FUNCTION public.get_email_template_state_internal(p_context jsonb,p_code text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT effective || jsonb_build_object('source',jsonb_build_object(
  'type',CASE WHEN effective->>'occasion' IS NOT NULL THEN 'occasion'
    WHEN effective->>'unit' IS NOT NULL THEN 'unit'
    WHEN effective->>'organization' IS NOT NULL THEN 'organization' ELSE 'global' END,
  'id',to_jsonb(coalesce((effective->>'occasion')::bigint,(effective->>'unit')::bigint,(effective->>'organization')::bigint))),
  'revision',encode(extensions.digest(convert_to(jsonb_build_object('effective',effective,
    'override',(SELECT to_jsonb(t) FROM public.email_templates t WHERE t.code=p_code AND
      CASE WHEN p_context->>'occasion' IS NOT NULL THEN t.occasion=(p_context->>'occasion')::bigint
      ELSE t.occasion IS NULL AND t.unit=(p_context->>'unit')::bigint END
      ORDER BY t.id DESC LIMIT 1))::text,'UTF8'),'sha256'),'hex'))
 FROM (SELECT public.get_resolved_email_template(p_code,p_context) effective) s;
$$;
REVOKE ALL ON FUNCTION public.get_email_template_state_internal(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_template_catalog(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,p_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; templates jsonb; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 SELECT coalesce(jsonb_agg(CASE WHEN p_code IS NULL THEN t-'html' ELSE t END ORDER BY t->>'code'),'[]')
 INTO templates FROM jsonb_array_elements(public.get_all_email_templates(context)) t
 WHERE p_code IS NULL OR t->>'code'=p_code;
 IF p_code IS NOT NULL AND jsonb_array_length(templates)=0 THEN
  RAISE invalid_parameter_value USING MESSAGE='template unavailable in this scope'; END IF;
 result:=jsonb_build_object('entityType',p_entity_type,'entityId',p_entity_id,'templates',templates);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='email template result too large'; END IF;
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_template_catalog(text,bigint,bigint,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_email_template_catalog(text,bigint,bigint,bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_email_template(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,
 p_action text,p_code text,p_expected_revision text,p_payload jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; state jsonb; started jsonb; hash text; name text; result jsonb; audience uuid[];
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 IF p_action IS NULL OR p_action NOT IN ('save','reset') OR p_code IS NULL
  OR p_expected_revision IS NULL OR p_expected_revision !~ '^[0-9a-f]{64}$'
  OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>524288
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('title','subject','html'))
  OR (p_action='save' AND (NOT p_payload ?& ARRAY['title','subject','html'] OR EXISTS(
    SELECT 1 FROM jsonb_each(p_payload) e WHERE jsonb_typeof(e.value) NOT IN ('string','null'))))
  OR (p_action='reset' AND p_payload<>'{}'::jsonb) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid email template command'; END IF;
 name:=p_entity_type||'.email_template.'||p_action;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('context',context,'action',p_action,
  'code',p_code,'expectedRevision',p_expected_revision,'payload',p_payload)::text,'UTF8'),'sha256'),'hex');
 IF p_entity_type='occasion' THEN
  started:=public.begin_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash);
 ELSE started:=public.begin_unit_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash); END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 -- Receipt -> hierarchy -> target. Legacy writes use these same hierarchy locks.
 PERFORM public.lock_email_template_hierarchy_internal(context);
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 SELECT t INTO state FROM jsonb_array_elements(public.get_all_email_templates(context)) t WHERE t->>'code'=p_code;
 IF state IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='template unavailable in this scope'; END IF;
 IF state->>'revision' IS DISTINCT FROM p_expected_revision THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','EMAIL_TEMPLATE_CHANGED'));
 END IF;
 IF p_action='save' THEN
  PERFORM public.update_email_template(p_payload||context||jsonb_build_object('code',p_code));
 ELSE PERFORM public.delete_entity_email_template(p_entity_type,p_entity_id,p_code); END IF;
 result:=public.get_email_template_catalog(p_entity_type,p_entity_id,p_organization,p_unit,p_code);
 IF p_entity_type='unit' THEN
  RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_entity_id,name,'email_template',p_entity_id,'update',result);
 END IF;
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_entity_id,name,'configuration',
  jsonb_build_array(jsonb_build_object('entityType','email_template','entityId',p_entity_id,'operation','update',
   'safeLabel','Email template','changedFields',jsonb_build_array('template'))),'{}'::text[],'[]','[]',result);
END $$;
REVOKE ALL ON FUNCTION public.manage_email_template(text,bigint,bigint,bigint,text,text,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_email_template(text,bigint,bigint,bigint,text,text,text,jsonb,uuid) TO authenticated;

-- Wrapper selection remains owned by the sending resolver, never a MCP copy.
CREATE OR REPLACE FUNCTION public.get_email_banner_state_internal(p_context jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('overrideUrl',own_url,'inheritedUrl',inherited_url,
  'effectiveUrl',coalesce(own_url,inherited_url),'wrapperHtml',resolved->'wrapper'->'html',
  'revision',encode(extensions.digest(convert_to(jsonb_build_object('ownUrl',own_url,
    'inheritedUrl',inherited_url,'wrapper',resolved->'wrapper')::text,'UTF8'),'sha256'),'hex'))
 FROM (SELECT public.get_email_template_and_wrapper('',p_context) resolved,
  CASE WHEN p_context->>'occasion' IS NOT NULL THEN o.data->>'email_banner'
    ELSE u.data->>'email_banner' END own_url,
  CASE WHEN p_context->>'occasion' IS NOT NULL THEN coalesce(u.data->>'email_banner',org.data->>'email_banner')
    ELSE org.data->>'email_banner' END inherited_url
  FROM public.organizations org
  JOIN public.units u ON u.id=(p_context->>'unit')::bigint AND u.organization=org.id
  LEFT JOIN public.occasions o ON o.id=(p_context->>'occasion')::bigint AND o.unit=u.id
  WHERE org.id=(p_context->>'organization')::bigint) s;
$$;
REVOKE ALL ON FUNCTION public.get_email_banner_state_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_banner(p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 result:=public.get_email_banner_state_internal(context)||jsonb_build_object('entityType',p_entity_type,'entityId',p_entity_id);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='email banner too large'; END IF;
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_banner(text,bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_email_banner(text,bigint,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_email_banner(p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,
 p_expected_revision text,p_banner_url text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; state jsonb; started jsonb; hash text; name text; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 IF p_expected_revision IS NULL OR p_expected_revision !~ '^[0-9a-f]{64}$'
  OR (p_banner_url IS NOT NULL AND (length(p_banner_url)>8192
    OR p_banner_url !~ '^https://(a\.)?img\.festapp\.net/(images|assets)/[A-Za-z0-9_./-]+$'
    OR p_banner_url LIKE '%/../%')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid email banner command'; END IF;
 name:=p_entity_type||'.email_banner.save';
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('context',context,
   'expectedRevision',p_expected_revision,'url',p_banner_url)::text,'UTF8'),'sha256'),'hex');
 IF p_entity_type='occasion' THEN
  started:=public.begin_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash);
 ELSE started:=public.begin_unit_client_mutation_v1(p_command_id,name,p_entity_id,auth.uid(),hash); END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 PERFORM public.lock_email_template_hierarchy_internal(context);
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit,true);
 state:=public.get_email_banner_state_internal(context);
 IF state->>'revision' IS DISTINCT FROM p_expected_revision THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','EMAIL_BANNER_CHANGED'));
 END IF;
 PERFORM public.update_entity_email_banner(p_entity_type,p_entity_id,p_banner_url);
 result:=public.get_email_banner(p_entity_type,p_entity_id,p_organization,p_unit);
 IF p_entity_type='unit' THEN
  RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_entity_id,name,'unit',p_entity_id,'update',result);
 END IF;
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_entity_id,name,'configuration',
  jsonb_build_array(jsonb_build_object('entityType','occasion','entityId',p_entity_id,'operation','update',
   'safeLabel','Email banner','changedFields',jsonb_build_array('email_banner'))),ARRAY['occasion_config'],'[]','[]',result,
  '{}'::text[],'[]','user',NULL,'[]',ARRAY[(context->>'unit')::bigint]);
END $$;
REVOKE ALL ON FUNCTION public.manage_email_banner(text,bigint,bigint,bigint,text,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_email_banner(text,bigint,bigint,bigint,text,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_email_template_preview_context(
 p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE context jsonb; catalog jsonb; result jsonb;
BEGIN
 context:=public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 catalog:=public.get_email_template_catalog(p_entity_type,p_entity_id,p_organization,p_unit,p_code);
 result:=public.get_email_template_and_wrapper(p_code,context)||jsonb_build_object('context',context);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='email preview too large'; END IF;
 PERFORM public.check_email_template_scope_internal(p_entity_type,p_entity_id,p_organization,p_unit);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_template_preview_context(text,bigint,bigint,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_email_template_preview_context(text,bigint,bigint,bigint,text) TO authenticated;
