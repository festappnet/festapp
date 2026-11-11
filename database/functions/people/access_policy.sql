CREATE OR REPLACE FUNCTION public.can_manage_member_access_as_actor_internal_v1(p_actor uuid,p_scope text,p_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(CASE WHEN p_scope='unit' THEN
  NOT public.is_demo_unit(p_id) AND EXISTS(SELECT 1 FROM public.unit_users WHERE unit=p_id AND "user"=p_actor AND is_manager)
 WHEN p_scope='occasion' THEN (SELECT public.participant_manage_rule(
  public.active_membership(m.is_manager,public.is_demo_occasion(o.id)),
  public.active_membership(a.is_admin,public.is_demo_occasion(o.id)))
  FROM public.occasions o LEFT JOIN public.occasion_users m ON m.occasion=o.id AND m."user"=p_actor
  LEFT JOIN public.organization_users a ON a.organization=o.organization AND a."user"=p_actor WHERE o.id=p_id)
 ELSE false END,false) AND p_actor IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.can_manage_member_access_as_actor_internal_v1(uuid,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_manage_member_access(p_scope text,p_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_manage_member_access_as_actor_internal_v1(auth.uid(),p_scope,p_id);
$$;
REVOKE ALL ON FUNCTION public.can_manage_member_access(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_member_access(text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.lock_member_access_internal_v1(p_unit bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE org bigint;
BEGIN
 -- One ordering shared by account creation, member mutation and token acceptance.
 PERFORM pg_advisory_xact_lock(-p_unit);
 SELECT organization INTO STRICT org FROM public.units WHERE id=p_unit FOR SHARE;
 PERFORM pg_advisory_xact_lock(hashtextextended('user-sign-in-email:'||org::text,0));
END $$;
REVOKE ALL ON FUNCTION public.lock_member_access_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.validate_access_roles_internal_v1(p_scope text,p_roles jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF jsonb_typeof(p_roles) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_each(p_roles) r
  WHERE jsonb_typeof(r.value)<>'boolean' OR NOT r.key=ANY(CASE WHEN p_scope='unit'
   THEN ARRAY['is_manager','is_editor','is_editor_view']
   ELSE ARRAY['is_manager','is_editor','is_editor_view','is_editor_order','is_editor_order_view','is_receptionist','is_approver','is_cleaning_crew'] END)) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_role_scope'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_access_roles_internal_v1(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.stage_member_access_email(p_actor uuid,p_command_id uuid,p_intent_hash text,p_preview_hash text,p_prepared jsonb,p_token_hash text DEFAULT NULL,p_password text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE preparation uuid;
BEGIN
 PERFORM public.require_service_role();
 IF p_actor IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_actor)
  OR jsonb_typeof(p_prepared) IS DISTINCT FROM 'object' OR jsonb_typeof(p_prepared->'p_sealed') IS DISTINCT FROM 'object'
  OR coalesce(p_prepared->>'p_content_hash','') !~ '^[0-9a-f]{64}$' OR octet_length(p_prepared::text)>1048576
  OR p_token_hash IS NOT NULL AND p_token_hash !~ '^[0-9a-f]{64}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_preparation'; END IF;
 IF EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=p_actor AND request_sha256=p_intent_hash AND status='completed') THEN RETURN NULL; END IF;
 DELETE FROM public.access_email_preparations WHERE id IN (SELECT id FROM public.access_email_preparations WHERE expires_at<=now() LIMIT 100);
 DELETE FROM public.access_email_preparations WHERE actor=p_actor AND command_id=p_command_id AND expires_at<=now();
 INSERT INTO public.access_email_preparations(actor,command_id,intent_hash,preview_hash,prepared,token_hash,credential)
 VALUES(p_actor,p_command_id,p_intent_hash,p_preview_hash,p_prepared,p_token_hash,CASE WHEN p_password IS NULL THEN NULL ELSE extensions.pgp_sym_encrypt(p_password,(SELECT encode(secret,'hex') FROM public.access_preparation_key WHERE singleton)) END)
 ON CONFLICT(actor,command_id) DO NOTHING RETURNING id INTO preparation;
 IF preparation IS NULL THEN
  SELECT id INTO preparation FROM public.access_email_preparations
  WHERE actor=p_actor AND command_id=p_command_id AND intent_hash=p_intent_hash AND preview_hash=p_preview_hash;
  IF preparation IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='command_payload_conflict'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=p_actor AND request_sha256=p_intent_hash AND status='completed') THEN
  DELETE FROM public.access_email_preparations WHERE id=preparation; RETURN NULL;
 END IF;
 RETURN preparation;
END $$;
REVOKE ALL ON FUNCTION public.stage_member_access_email(uuid,uuid,text,text,jsonb,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.stage_member_access_email(uuid,uuid,text,text,jsonb,text,text) TO service_role;

-- Setup historically lets a unit manager offer editor/read-only event roles.
-- This does not grant participant management or arbitrary occasion roles.
CREATE OR REPLACE FUNCTION public.can_offer_member_access_as_actor_internal_v1(p_actor uuid,p_scope text,p_id bigint,p_roles jsonb)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_manage_member_access_as_actor_internal_v1(p_actor,p_scope,p_id) OR
  (p_scope='occasion' AND NOT public.is_demo_occasion(p_id)
   AND NOT EXISTS(SELECT 1 FROM jsonb_object_keys(p_roles) k WHERE k NOT IN ('is_editor','is_editor_view'))
   AND EXISTS(SELECT 1 FROM public.occasions o JOIN public.unit_users m ON m.unit=o.unit
    WHERE o.id=p_id AND m."user"=p_actor AND m.is_manager AND NOT public.is_demo_unit(o.unit)));
$$;
REVOKE ALL ON FUNCTION public.can_offer_member_access_as_actor_internal_v1(uuid,text,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
