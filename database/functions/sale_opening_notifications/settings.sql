-- Invoked only inside the existing form aggregate command, under its form lock.
CREATE OR REPLACE FUNCTION public.sync_sale_opening_settings_internal(p_form bigint,p_previous jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; d jsonb; c public.sale_opening_campaigns; a jsonb; enabled boolean;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 d:=public.normalize_form_metadata_internal(f.data);
 IF coalesce(public.normalize_form_metadata_internal(p_previous)#>>'{schedule,countdown_title}','') LIKE '%form-sale-opening-notification%'
  AND coalesce(d#>>'{schedule,countdown_title}','') NOT LIKE '%form-sale-opening-notification%'
  AND coalesce((d#>>'{sale_opening_notifications,enabled}')::boolean,false) THEN
  d:=jsonb_set(d,'{sale_opening_notifications,collection_paused}','true');
  UPDATE public.forms SET data=d WHERE id=p_form;
 END IF;
 enabled:=coalesce((d#>>'{sale_opening_notifications,enabled}')::boolean,false);
 SELECT * INTO c FROM public.sale_opening_campaigns WHERE form_id=p_form FOR UPDATE;
 a:=public.get_form_availability_snapshot_internal(p_form);
 IF enabled AND c.id IS NULL THEN
  IF NOT f.is_open OR (a->>'startAt')::timestamptz IS NULL OR (a->>'startAt')::timestamptz<=clock_timestamp()
   OR public.is_demo_occasion(f.occasion) THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_requires_future_public_form'; END IF;
  INSERT INTO public.sale_opening_campaigns(form_id) VALUES(p_form);
 ELSIF c.id IS NOT NULL AND c.phase<>'cancelled' THEN
  IF NOT enabled THEN
   UPDATE public.sale_opening_campaigns SET phase='cancelled',revision=revision+1,closed_at=clock_timestamp() WHERE id=c.id;
   UPDATE public.sale_opening_subscriptions SET state='closed',closed_at=clock_timestamp(),version=version+1
    WHERE campaign_id=c.id AND state='active';
   UPDATE public.sale_opening_capabilities SET revoked_at=clock_timestamp() WHERE subscription_id IN
    (SELECT id FROM public.sale_opening_subscriptions WHERE campaign_id=c.id) AND revoked_at IS NULL;
  ELSIF (a->>'startAt')::timestamptz IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='explicitly_end_sale_opening_notifications_before_removing_date';
  END IF;
 ELSIF enabled AND c.phase='cancelled' THEN
  RAISE invalid_parameter_value USING MESSAGE='sale_opening_campaign_already_ended';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.sync_sale_opening_settings_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.sale_opening_has_tickets_internal(p_form bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.form_fields WHERE form=p_form AND type='ticket' AND NOT is_hidden);
$$;
REVOKE ALL ON FUNCTION public.sale_opening_has_tickets_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_sale_opening_projection_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH input AS (SELECT f.*,public.get_effective_form_data(f.id) metadata,
  public.get_form_availability_snapshot_internal(f.id) availability,c.phase
  FROM public.forms f LEFT JOIN public.sale_opening_campaigns c ON c.form_id=f.id WHERE f.id=p_form),
 reason AS (SELECT *,CASE
  WHEN public.is_demo_occasion(occasion) OR phase IS NULL OR phase<>'armed' OR
   NOT coalesce((metadata#>>'{sale_opening_notifications,enabled}')::boolean,false) THEN 'disabled'
  WHEN coalesce((metadata#>>'{sale_opening_notifications,collection_paused}')::boolean,false) THEN 'paused'
  WHEN NOT is_open THEN 'manual_closed'
  WHEN availability->>'gate'<>'before_start' THEN 'not_before_start'
  ELSE NULL END unavailable FROM input)
 SELECT jsonb_build_object('canSubscribe',unavailable IS NULL,'hasTickets',public.sale_opening_has_tickets_internal(id),'reason',unavailable,
  'startAt',availability->'startAt','timeZone',public.get_waitlist_form_timezone_internal(id),'serverTime',statement_timestamp()) FROM reason;
$$;
REVOKE ALL ON FUNCTION public.get_sale_opening_projection_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
