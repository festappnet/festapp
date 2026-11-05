-- The button records a direct request for one opening notification. Only the
-- unsubscribe capability is generated/encrypted at the trusted Edge boundary.
CREATE OR REPLACE FUNCTION public.sale_opening_notification_command(p_operation text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; c public.sale_opening_campaigns; s public.sale_opening_subscriptions; cap public.sale_opening_capabilities;
 email text; language text; projection jsonb; h text; o public.occasions;
BEGIN
 PERFORM public.require_service_role();
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16384 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid sale opening request'; END IF;
 IF p_operation='subscribe' THEN fid:=public.resolve_form_link_internal(p_payload->>'formLink');
 ELSIF p_operation='unsubscribe' AND coalesce(p_payload->>'tokenHash','') ~ '^[0-9a-f]{64}$' THEN
  SELECT x.form_id INTO fid FROM public.sale_opening_capabilities a
   JOIN public.sale_opening_subscriptions b ON b.id=a.subscription_id
   JOIN public.sale_opening_campaigns x ON x.id=b.campaign_id WHERE a.token_hash=p_payload->>'tokenHash';
 ELSE RAISE invalid_parameter_value USING MESSAGE='invalid sale opening action'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE id=fid)]);
 PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_link_invalid'; END IF;
 SELECT * INTO c FROM public.sale_opening_campaigns WHERE form_id=fid FOR UPDATE;
 IF p_operation='subscribe' THEN
  projection:=public.get_sale_opening_projection_internal(fid);
  IF NOT coalesce((projection->>'canSubscribe')::boolean,false) THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_collection_unavailable'; END IF;
  email:=lower(btrim(p_payload->>'email')); language:=p_payload->>'lang';
  IF email IS NULL OR length(email)>320 OR email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   OR language IS NULL OR language NOT IN ('cs','en','sk','de','pl','uk') THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid sale opening contact'; END IF;
  IF EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=email) THEN RETURN '{"ok":true}'::jsonb; END IF;
  SELECT * INTO s FROM public.sale_opening_subscriptions WHERE campaign_id=c.id AND email_normalized=email;
  IF s.state='active' THEN RETURN '{"ok":true}'::jsonb; END IF;
  SELECT occ.* INTO STRICT o FROM public.occasions occ JOIN public.forms f ON f.occasion=occ.id WHERE f.id=fid;
  -- Collection creates no email, but still consumes the existing bounded
  -- ordinary recipient/tenant admission before inserting/locking a contact.
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.ordinary',o.unit,o.organization),
   jsonb_build_object('unit',o.unit,'organization',o.organization,'recipient',public.abuse_recipient_key_v1(email)),jsonb_build_object('growth',0));
  h:=p_payload#>>'{unsubscribe,hash}';
  IF coalesce(h,'') !~ '^[0-9a-f]{64}$' OR jsonb_typeof(p_payload#>'{unsubscribe,envelope}') IS DISTINCT FROM 'object'
   OR p_payload#>>'{unsubscribe,envelope,v}' IS DISTINCT FROM '1'
   OR length(coalesce(p_payload#>>'{unsubscribe,envelope,ciphertext}',''))<32 THEN
   RAISE invalid_parameter_value USING MESSAGE='sale_opening_encrypted_source_required'; END IF;
  IF s.id IS NULL THEN
   INSERT INTO public.sale_opening_subscriptions(campaign_id,email_normalized,lang,state) VALUES(c.id,email,language,'active') RETURNING * INTO s;
  ELSE
   UPDATE public.sale_opening_capabilities SET revoked_at=clock_timestamp() WHERE subscription_id=s.id AND revoked_at IS NULL;
   UPDATE public.sale_opening_subscriptions SET state='active',version=s.version+1,lang=language,closed_at=NULL,
    created_at=clock_timestamp() WHERE id=s.id RETURNING * INTO s;
  END IF;
  INSERT INTO public.sale_opening_capabilities(token_hash,subscription_id,purpose,source_version,envelope,expires_at)
   VALUES(h,s.id,'unsubscribe',s.version,p_payload#>'{unsubscribe,envelope}','infinity');
 ELSE
  SELECT * INTO cap FROM public.sale_opening_capabilities WHERE token_hash=p_payload->>'tokenHash' AND purpose='unsubscribe' FOR UPDATE;
  IF cap.token_hash IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_link_invalid'; END IF;
  SELECT * INTO s FROM public.sale_opening_subscriptions WHERE id=cap.subscription_id FOR UPDATE;
  IF cap.expires_at<=clock_timestamp() OR cap.source_version<>s.version THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_link_expired'; END IF;
  IF s.state='unsubscribed' THEN RETURN '{"ok":true}'::jsonb; END IF;
  IF cap.revoked_at IS NOT NULL OR c.phase='cancelled' OR s.state='closed' THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_link_invalid'; END IF;
  UPDATE public.sale_opening_subscriptions SET state='unsubscribed',closed_at=clock_timestamp() WHERE id=s.id;
  UPDATE public.email_messages SET workflow_state='cancelled',lease_token=NULL,lease_until=NULL
   WHERE data->>'subscription_id'=s.id::text AND message_kind='sale_opening_opened'
   AND workflow_state IN ('pending','blocked','retry_wait','preparing');
 END IF;
 RETURN jsonb_build_object('ok',true);
END $$;
REVOKE ALL ON FUNCTION public.sale_opening_notification_command(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sale_opening_notification_command(text,jsonb) TO service_role;
