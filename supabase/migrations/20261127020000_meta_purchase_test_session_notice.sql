-- Record Meta receipts whose test event code has no active Test Events session.

-- SOURCE: eshop_forms/meta_purchase_worker.sql
CREATE OR REPLACE FUNCTION public.finish_meta_purchase_delivery(p_order_id bigint,p_lease uuid,p_result text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE delivery analytics.meta_purchase_deliveries; final_status text; connector_unit bigint;
 accepted boolean:=p_result IN ('sent','sent_test_inactive');
BEGIN
 PERFORM public.require_service_role();
 -- sent_test_inactive: Meta accepted the event, but its test_event_code has no
 -- active Test Events session, so it will not appear there.
 IF p_result IS NULL OR p_result NOT IN ('sent','sent_test_inactive','retry','credentials','rejected') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid delivery result'; END IF;
 -- A disconnected connector may be absent; its terminal receipt still exists.
 -- Lock any surviving connector before the delivery, like prepare and delete.
 SELECT unit INTO connector_unit FROM analytics.meta_purchase_deliveries WHERE order_id=p_order_id;
 IF NOT FOUND THEN RETURN false; END IF;
 PERFORM 1 FROM analytics.meta_purchase_connectors WHERE unit=connector_unit FOR NO KEY UPDATE;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND lease=p_lease AND status IN ('pending','revoked') AND prepared FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_result='credentials' THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=delivery.unit AND revision=delivery.connector_revision
   AND (token_changed_at IS NULL OR token_changed_at<delivery.prepared_at);
 END IF;
 -- Withdrawal scrubs the payload but must still record the authorized in-flight result.
 IF delivery.status='revoked' THEN
  UPDATE analytics.meta_purchase_deliveries
  SET error_code=CASE WHEN accepted THEN 'sent_in_flight' ELSE p_result END,
   lease=NULL,lease_until=NULL
  WHERE order_id=p_order_id;
  RETURN true;
 END IF;
 final_status:=CASE WHEN accepted THEN 'sent'
  WHEN p_result='rejected' OR delivery.attempts>=6 THEN 'failed' ELSE 'pending' END;
 UPDATE analytics.meta_purchase_deliveries SET status=final_status,
  error_code=CASE WHEN p_result='sent_test_inactive' THEN 'test_events_inactive' ELSE nullif(p_result,'sent') END,
  next_attempt_at=clock_timestamp()+interval '2 minutes'*power(2,greatest(delivery.attempts-1,0)),
  lease=NULL,lease_until=NULL,done_at=CASE WHEN final_status<>'pending' THEN clock_timestamp() END,
  consent_snapshot=CASE WHEN final_status='pending' THEN consent_snapshot END,
  email_hash=CASE WHEN final_status='pending' THEN email_hash END,
  phone_hash=CASE WHEN final_status='pending' THEN phone_hash END,
  fbp=CASE WHEN final_status='pending' THEN fbp END,
  fbc=CASE WHEN final_status='pending' THEN fbc END,
  client_ip=CASE WHEN final_status='pending' AND consent_at>clock_timestamp()-interval '7 days' THEN client_ip END,
  client_agent=CASE WHEN final_status='pending' THEN client_agent END,
  source_url=CASE WHEN final_status='pending' THEN source_url END
 WHERE order_id=p_order_id;
 RETURN true;
END $$;

-- SOURCE: eshop_forms/meta_purchase_settings.sql
CREATE OR REPLACE FUNCTION public.get_unit_meta_purchase(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Meta CAPI access denied'; END IF;
 SELECT jsonb_build_object('dataset',c.dataset,'website_origin',c.website_origin,'test_event_code',c.test_event_code,
  'enabled',c.enabled,'paused_at',c.paused_at,'token_saved',c.vault_secret IS NOT NULL,'revision',c.revision,
  -- Only the stored masked suffix is projected; reads never decrypt the Vault secret.
  'token_hint',c.token_hint,'token_changed_at',c.token_changed_at,
  'website_ready',coalesce(c.website_origin=ANY(public.unit_meta_purchase_origins_internal(p_unit)) AND (
   c.website_origin=(SELECT rtrim(org.data->>'DEFAULT_URL','/') FROM public.units u
    JOIN public.organizations org ON org.id=u.organization WHERE u.id=p_unit)
   OR EXISTS(SELECT FROM analytics.website_consent_bindings b WHERE b.unit=p_unit
    AND b.website_origin=c.website_origin AND b.provider_config->>'provider' IN ('cookiebot','cookieconsent','wix','complianz')
    AND public.website_consent_binding_effective_internal(b))
  ),false))
 INTO result FROM analytics.meta_purchase_connectors c WHERE c.unit=p_unit;
 RETURN coalesce(result,'{}'::jsonb)||jsonb_build_object('allowed',true,
  'websites',to_jsonb(public.unit_meta_purchase_origins_internal(p_unit)),
  'queue',(SELECT jsonb_build_object('pending',count(*) FILTER(WHERE status='pending'),
    'sent',count(*) FILTER(WHERE status='sent'),'failed',count(*) FILTER(WHERE status='failed'),
    'revoked',count(*) FILTER(WHERE status='revoked'),
    'invalid',count(*) FILTER(WHERE status='invalid'),'expired',count(*) FILTER(WHERE status='expired')) FROM analytics.meta_purchase_deliveries
    WHERE unit=p_unit AND coalesce(done_at,consent_at)>=statement_timestamp()-interval '30 days'),
  'last_error',coalesce(
    (SELECT jsonb_build_object('code',error_code,'status',status,'at',outcome_at) FROM (
      SELECT error_code,status,coalesce(done_at,next_attempt_at-interval '2 minutes'*power(2,greatest(attempts-1,0))) AS outcome_at
      FROM analytics.meta_purchase_deliveries d WHERE d.unit=p_unit AND d.error_code IS NOT NULL
       -- A Test Events notice is resolved once the organizer saves a new code (new revision).
       AND NOT (d.error_code='test_events_inactive' AND d.connector_revision IS DISTINCT FROM
        (SELECT c.revision FROM analytics.meta_purchase_connectors c WHERE c.unit=p_unit))
     ) outcomes ORDER BY outcome_at DESC LIMIT 1),
    (SELECT jsonb_build_object('code','credentials','status','pending','at',paused_at)
      FROM analytics.meta_purchase_connectors WHERE unit=p_unit AND paused_at IS NOT NULL)),
  'forms',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'enabled',m.form IS NOT NULL,
     'measurement_ready',EXISTS(SELECT FROM public.form_measurement_decision_internal(f.id) d WHERE d.conversion_eligible)) ORDER BY f.id),'[]'::jsonb)
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    LEFT JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=p_unit WHERE o.unit=p_unit));
END $$;
