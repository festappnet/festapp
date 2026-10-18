-- Internal producer shared by submission and an explicitly scoped repair.
CREATE OR REPLACE FUNCTION public.enqueue_unit_verification_request(p_unit bigint)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE p public.unit_legal_profiles; u public.units; o public.organizations; a record; msg jsonb; n integer:=0; origin text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO u FROM public.units WHERE id=p_unit FOR UPDATE;
 SELECT * INTO p FROM public.unit_legal_profiles WHERE unit_id=p_unit FOR UPDATE;
 IF p.status IS DISTINCT FROM 'pending' OR public.is_demo_unit(p_unit) THEN RETURN 0; END IF;
 SELECT * INTO o FROM public.organizations WHERE id=u.organization;
 origin:=rtrim(o.data->>'DEFAULT_URL','/');
 IF origin IS NULL OR origin !~ '^https://[^/?#[:space:]]+$' THEN RAISE EXCEPTION 'verification_notification_origin_missing'; END IF;
 FOR a IN SELECT ou."user" id,public.get_user_delivery_email(ou."user") email
  FROM public.organization_users ou WHERE ou.organization=u.organization AND ou.is_admin ORDER BY ou."user"
 LOOP
  IF a.email IS NULL THEN CONTINUE; END IF;
  msg:=public.enqueue_email('custom',jsonb_build_object('organization',u.organization,'unit',p_unit,'recipient_user',a.id),a.email,
   jsonb_build_object('unit_id',p_unit,'revision',p.revision,'legal_name',p.legal_name,'registration_number',p.registration_number,
    'review_url',origin||'/organizationEdit/'||u.organization,'app_name',o.title),
   'unit-verification:'||p_unit||':'||p.revision||':'||a.id,'UNIT_VERIFICATION_REQUEST',now(),now()+interval '30 days',NULL,p.revision);
  UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(msg->>'message_id')::uuid;
  n:=n+1;
 END LOOP;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_unit_verification_request(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_unit_verification_request(bigint) TO service_role;
