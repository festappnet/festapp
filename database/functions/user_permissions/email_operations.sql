-- One custom-mail policy for the user-facing check and the trusted producer's
-- transactional enqueue. The producer supplies a verified actor, never role facts.
CREATE OR REPLACE FUNCTION public.custom_email_send_rule(p_editor boolean,p_order_writer boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_editor OR p_order_writer; $$;
REVOKE ALL ON FUNCTION public.custom_email_send_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.custom_email_send_rule(boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.can_send_custom_email_as_actor_internal_v1(p_actor uuid,p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.custom_email_send_rule(
   public.active_membership(m.is_editor,public.is_demo_occasion(p_occasion)),
   public.order_write_rule(m.is_editor_order,public.is_demo_occasion(p_occasion)))
 FROM public.occasion_users m WHERE m.occasion=p_occasion AND m."user"=p_actor),false);
$$;
REVOKE ALL ON FUNCTION public.can_send_custom_email_as_actor_internal_v1(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_send_custom_email_as_actor_internal_v1(uuid,bigint) TO postgres;

CREATE OR REPLACE FUNCTION public.can_send_custom_email(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_send_custom_email_as_actor_internal_v1(auth.uid(),p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_send_custom_email(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_send_custom_email(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.enqueue_custom_email_for_actor_v1(
 p_actor uuid,p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,
 p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE resource public.occasions; context jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO resource FROM public.occasions WHERE id=(p_context->>'occasion')::bigint FOR SHARE;
 IF NOT FOUND OR p_actor IS NULL OR p_kind IS DISTINCT FROM 'custom'
   OR (p_context->>'organization')::bigint IS DISTINCT FROM resource.organization
   OR (p_context->>'unit')::bigint IS DISTINCT FROM resource.unit
   OR NOT public.can_send_custom_email_as_actor_internal_v1(p_actor,resource.id) THEN
  RAISE insufficient_privilege USING MESSAGE='custom email permission required';
 END IF;
 context:=p_context||jsonb_build_object('actor_id',p_actor,'organization',resource.organization,
   'unit',resource.unit,'occasion',resource.id);
 -- Live authorization precedes both insert and dedupe replay. A committed email
 -- intent may subsequently be processed by its existing service worker.
 RETURN public.enqueue_prepared_email('custom',context,p_recipient,p_sealed,p_dedupe,p_content_hash,p_code,p_expires);
END $$;
REVOKE ALL ON FUNCTION public.enqueue_custom_email_for_actor_v1(uuid,text,jsonb,text,jsonb,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_custom_email_for_actor_v1(uuid,text,jsonb,text,jsonb,text,text,text,timestamptz) TO service_role;

-- Recipient identity facts protect the existing team-account invitation path.
-- This selects a delivery mode; it never grants the requesting actor permission.
CREATE OR REPLACE FUNCTION public.team_access_notice_rule(p_editor boolean,p_viewer boolean,p_manager boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_editor,false) OR coalesce(p_viewer,false) OR coalesce(p_manager,false);
$$;
REVOKE ALL ON FUNCTION public.team_access_notice_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.team_access_notice_rule(boolean,boolean,boolean) TO postgres;

-- App-link delivery is a participant-management mutation. Recheck the verified
-- actor and stored recipient scope at durable enqueue, including dedupe replay.
CREATE OR REPLACE FUNCTION public.enqueue_participant_notice_for_actor_v1(
 p_actor uuid,p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,
 p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE resource public.occasions; recipient uuid:=(p_context->>'recipient_user')::uuid;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO resource FROM public.occasions WHERE id=(p_context->>'occasion')::bigint FOR SHARE;
 IF NOT FOUND OR coalesce((p_kind='app_links' AND p_code='APP_LINKS')
   OR (p_kind='custom' AND p_code='TEAM_ACCESS_NOTICE'),false) IS NOT TRUE
   OR p_actor IS NULL OR public.is_demo_occasion(resource.id)
   OR (p_context->>'organization')::bigint IS DISTINCT FROM resource.organization
   OR (p_context->>'unit')::bigint IS DISTINCT FROM resource.unit
   OR NOT public.can_manage_occasion_users_as_actor_internal_v1(p_actor,resource.id)
   OR NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=resource.id AND "user"=recipient
     AND (p_code='APP_LINKS' OR public.team_access_notice_rule(is_editor,is_editor_view,is_manager))) THEN
  RAISE insufficient_privilege USING MESSAGE='app links participant management required';
 END IF;
 RETURN public.enqueue_prepared_email(p_kind,p_context||jsonb_build_object('actor_id',p_actor,
   'organization',resource.organization,'unit',resource.unit,'occasion',resource.id),
   p_recipient,p_sealed,p_dedupe,p_content_hash,p_code,p_expires);
END $$;
REVOKE ALL ON FUNCTION public.enqueue_participant_notice_for_actor_v1(uuid,text,jsonb,text,jsonb,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_participant_notice_for_actor_v1(uuid,text,jsonb,text,jsonb,text,text,text,timestamptz) TO service_role;
