CREATE OR REPLACE FUNCTION public.get_notification_center_projection_health(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization) THEN RAISE invalid_parameter_value USING MESSAGE='notification_organization_required'; END IF;
 SELECT jsonb_build_object('organization',p_organization,'scopes',count(*),'backfilling',count(*) FILTER(WHERE phase<>'ready'),
  'failed',count(*) FILTER(WHERE quarantined),'pendingDelivery',coalesce(sum(pending_delivery),0),'pendingSourceRepairs',coalesce(sum(pending_events),0),
  'pendingReadRepairs',coalesce(sum(pending_groups),0),'privacyRepairs',count(*) FILTER(WHERE privacy_pending),
  'expiryDebt',count(*) FILTER(WHERE next_expiry<clock_timestamp()),'oldestReadyAt',min(last_ready_at),
  'liveViews',(SELECT count(*) FROM public.notification_center_views WHERE organization=p_organization AND expires_at>clock_timestamp()),
  'expiredViews',(SELECT count(*) FROM public.notification_center_views WHERE organization=p_organization AND expires_at<=clock_timestamp()),
  'failedViewRows',(SELECT count(*) FROM public.notification_center_view_rows r JOIN public.notification_center_views v ON v.token=r.token WHERE v.organization=p_organization AND r.quarantined))
 INTO result FROM public.notification_center_projection_scopes WHERE organization=p_organization;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_projection_health(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_center_projection_health(bigint) TO service_role;
CREATE OR REPLACE FUNCTION public.retry_notification_center_projection(p_organization bigint,p_recipient uuid DEFAULT NULL,p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=p_organization) THEN RAISE invalid_parameter_value USING MESSAGE='notification_organization_required'; END IF;
 UPDATE public.notification_center_projection_scopes SET retry_count=0,last_error_code=NULL,quarantined=false,next_check_at='-infinity'
 WHERE (organization,recipient) IN(SELECT organization,recipient FROM public.notification_center_projection_scopes
  WHERE organization=p_organization AND (p_recipient IS NULL OR recipient=p_recipient)
  ORDER BY recipient LIMIT greatest(1,least(coalesce(p_limit,100),100)) FOR UPDATE SKIP LOCKED);
 GET DIAGNOSTICS n=ROW_COUNT;
 UPDATE public.notification_center_view_rows SET retry_count=0,last_error_code=NULL,quarantined=false,next_attempt_at='-infinity'
 WHERE (token,position) IN(SELECT r.token,r.position FROM public.notification_center_view_rows r JOIN public.notification_center_views v ON v.token=r.token
  WHERE v.organization=p_organization AND (p_recipient IS NULL OR v.recipient=p_recipient) AND r.quarantined ORDER BY r.token,r.position LIMIT 100 FOR UPDATE OF r SKIP LOCKED);
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.retry_notification_center_projection(bigint,uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.retry_notification_center_projection(bigint,uuid,integer) TO service_role;
CREATE OR REPLACE FUNCTION public.set_notification_center_prepared_paused(p_organization bigint,p_paused boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 UPDATE public.notification_center_organizations SET prepared_paused=coalesce(p_paused,true) WHERE organization=p_organization;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='notification_organization_required'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.set_notification_center_prepared_paused(bigint,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_notification_center_prepared_paused(bigint,boolean) TO service_role;
NOTIFY pgrst,'reload schema';
