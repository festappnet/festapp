-- Projection only: BankSync owns readiness, warning clocks and incident UUIDs.
CREATE OR REPLACE FUNCTION public.notification_center_bank_incident_internal(p_connection bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE c eshop.bank_sync_connections; h eshop.bank_sync_health; scope record; affected bigint[]; ev uuid; ready boolean; reason text;
BEGIN
 SELECT * INTO c FROM eshop.bank_sync_connections WHERE id=p_connection;
 SELECT * INTO h FROM eshop.bank_sync_health WHERE connection_id=p_connection;
 ready:=coalesce(public.bank_sync_alert_ready(p_connection),false);
 reason:=CASE h.warning_code WHEN 'token_invalid' THEN 'fio_token_invalid_or_inactive'
 WHEN 'account_mismatch' THEN 'fio_receiving_account_mismatch' WHEN 'unavailable' THEN 'transport_unavailable'
 ELSE 'bank_sync_retry_required' END;
 FOR scope IN SELECT a.organization,a.initialized_at FROM public.notification_center_organizations a
 WHERE EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
  WHERE u.organization=a.organization AND (uba.bank_account=c.bank_account_id OR uba.bank_account IN(
   SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection))) LOOP
  FOR ev IN SELECT id FROM public.notification_center_events WHERE organization=scope.organization AND kind='bank_problem'
   AND data->>'bankConnectionId'=p_connection::text AND status NOT IN ('recovered','resolved')
   AND (h.incident_id IS NULL OR c.state NOT IN ('connected','degraded') OR data->>'incidentId' IS DISTINCT FROM h.incident_id::text) LOOP
   PERFORM public.notification_center_prepared_invalidate(ev);
   UPDATE public.notification_center_events SET status='recovered' WHERE id=ev;
  END LOOP;
  IF NOT ready OR h.incident_id IS NULL OR h.warning_since<scope.initialized_at THEN CONTINUE; END IF;
  SELECT array_agg(DISTINCT oc.id) INTO affected FROM public.occasions oc
  WHERE oc.organization=scope.organization AND (
   EXISTS(SELECT 1 FROM public.forms f WHERE f.occasion=oc.id AND (f.bank_account=c.bank_account_id OR f.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection)))
   OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.occasion=oc.id AND (pi.bank_account=c.bank_account_id OR pi.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection))));
  ev:=public.notification_center_publish_internal(scope.organization,NULL,'bank_problem',
   'bank:'||p_connection||':incident:'||h.incident_id,
   jsonb_build_object('bankConnectionId',p_connection,'incidentId',h.incident_id,'reason',reason),NULL,h.warning_since,coalesce(affected,'{}'));
  IF ev IS NOT NULL AND EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=ev
   AND (data->>'reason' IS DISTINCT FROM reason OR affected_occasions IS DISTINCT FROM coalesce(affected,'{}'))) THEN
   PERFORM public.notification_center_prepared_invalidate(ev);
   UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',reason),affected_occasions=coalesce(affected,'{}') WHERE id=ev;
   PERFORM public.notification_center_capture_recipients_internal(ev,NULL);
  END IF;
 END LOOP;
 -- Disconnection/deletion of the final alias still closes already projected sources.
 FOR ev IN SELECT e.id FROM public.notification_center_events e WHERE e.kind='bank_problem'
  AND e.data->>'bankConnectionId'=p_connection::text AND e.status NOT IN ('recovered','resolved')
  AND NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit
   WHERE u.organization=e.organization AND (uba.bank_account=c.bank_account_id OR uba.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=p_connection))) LOOP
  PERFORM public.notification_center_prepared_invalidate(ev);
  UPDATE public.notification_center_events SET status='recovered' WHERE id=ev;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_bank_incident_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
