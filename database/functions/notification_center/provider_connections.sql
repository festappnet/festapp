-- Connector adapters own operational health. This table owns only the episode
-- identity, like payment_notification_incidents; it is not another poller.
CREATE TABLE IF NOT EXISTS eshop.provider_connection_notification_incidents (
 provider text NOT NULL REFERENCES eshop.payment_providers(provider_key), connection_id uuid NOT NULL,
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
 incident_id uuid NOT NULL DEFAULT gen_random_uuid(), active boolean NOT NULL,
 reason text NOT NULL, opened_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(provider,connection_id)
);
ALTER TABLE eshop.provider_connection_notification_incidents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.provider_connection_notification_incidents FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_provider_connection_internal(p_provider text,p_connection uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE health jsonb; incident eshop.provider_connection_notification_incidents; ev uuid; problem boolean;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('provider-notification:'||p_provider||':'||p_connection,0));
 health:=public.payment_provider_call_internal(p_provider,'notification_connection_health',jsonb_build_object('connectionId',p_connection));
 IF health IS NULL THEN RETURN; END IF;
 problem:=health->>'reason' IS NOT NULL;
 -- All callers already hold their connector mutation lock. The episode lock
 -- also serializes different Barion attempts belonging to the same connection.
 SELECT * INTO incident FROM eshop.provider_connection_notification_incidents WHERE provider=p_provider AND connection_id=p_connection FOR UPDATE;
 IF NOT problem THEN
  IF incident.active THEN
   UPDATE eshop.provider_connection_notification_incidents SET active=false WHERE provider=p_provider AND connection_id=p_connection;
   FOR ev IN SELECT id FROM public.notification_center_events WHERE kind='provider_problem' AND data->>'incidentId'=incident.incident_id::text LOOP
    PERFORM public.notification_center_prepared_invalidate(ev);
    UPDATE public.notification_center_events SET status='recovered' WHERE id=ev;
   END LOOP;
  END IF;
  RETURN;
 END IF;
 IF incident.connection_id IS NULL THEN
  INSERT INTO eshop.provider_connection_notification_incidents(provider,connection_id,organization,unit,active,reason)
  VALUES(p_provider,p_connection,(health->>'organizationId')::bigint,(health->>'unitId')::bigint,true,health->>'reason') RETURNING * INTO incident;
 ELSIF NOT incident.active THEN
  UPDATE eshop.provider_connection_notification_incidents SET active=true,incident_id=gen_random_uuid(),reason=health->>'reason',opened_at=clock_timestamp()
  WHERE provider=p_provider AND connection_id=p_connection RETURNING * INTO incident;
 ELSE
  UPDATE eshop.provider_connection_notification_incidents SET reason=health->>'reason'
  WHERE provider=p_provider AND connection_id=p_connection AND reason IS DISTINCT FROM health->>'reason';
 END IF;
 -- Tenant initialization/activation still determine the publication boundary.
 ev:=public.notification_center_publish_internal(incident.organization,NULL,'provider_problem',
  'provider:'||p_provider||':'||p_connection||':incident:'||incident.incident_id,
  jsonb_build_object('provider',p_provider,'connectionId',p_connection,'incidentId',incident.incident_id,'unitId',incident.unit,
   'title',health->>'title','reason',health->>'reason'),NULL,incident.opened_at);
 IF ev IS NOT NULL AND EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=ev AND data->>'reason' IS DISTINCT FROM health->>'reason') THEN
  PERFORM public.notification_center_prepared_invalidate(ev);
  UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',health->>'reason') WHERE id=ev;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_provider_connection_internal(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
