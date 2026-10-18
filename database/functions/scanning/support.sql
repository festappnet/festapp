-- Reuse the existing organization app-support feature and target restrictions.
CREATE OR REPLACE FUNCTION public.scanner_can_reset_password_internal(p_occasion bigint,p_ticket bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE target uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
   WHERE o.id=p_occasion AND org.data->>'IS_APP_SUPPORTED'='true') THEN RETURN false; END IF;
 SELECT ou."user" INTO target FROM public.occasion_users ou JOIN eshop.tickets t ON t.id=ou.ticket
 WHERE ou.occasion=p_occasion AND t.occasion=p_occasion AND t.id=p_ticket LIMIT 1;
 IF target IS NULL THEN RETURN false; END IF;
 PERFORM public.check_is_scan_password_reset_target_allowed(target);
 RETURN true;
EXCEPTION WHEN insufficient_privilege THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.scanner_can_reset_password_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Existing scan reset authority, target restrictions and abuse limits are reused.
CREATE OR REPLACE FUNCTION public.reset_scanner_password(p_session uuid,p_token text,p_ticket bigint,p_password text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; secret text;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=p_ticket AND occasion=s.occasion_id) THEN RAISE insufficient_privilege; END IF;
 IF NOT public.scanner_can_reset_password_internal(s.occasion_id,p_ticket) THEN RAISE insufficient_privilege USING MESSAGE='password_reset_not_available'; END IF;
 SELECT oh.secret INTO secret FROM public.occasions o JOIN public.occasions_hidden oh ON oh.id=o.occasion_hidden WHERE o.id=s.occasion_id;
 RETURN public.reset_password_via_scan(p_ticket,p_password,secret);
END $$;
REVOKE ALL ON FUNCTION public.reset_scanner_password(uuid,text,bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_scanner_password(uuid,text,bigint,text) TO anon,authenticated;
CREATE OR REPLACE FUNCTION public.get_scanner_event_history(p_occasion bigint,p_before timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_is_editor_order_on_occasion(p_occasion);
 SELECT coalesce(jsonb_agg(item),'[]'::jsonb) INTO result FROM (
 SELECT jsonb_build_object('receipt',op.receipt,'captured_at',op.payload->'captured_at','offline',op.payload->>'snapshot_id' IS NOT NULL,'resolved',r.operation_id IS NOT NULL) item
 FROM public.scanner_operations op LEFT JOIN public.scanner_conflict_resolutions r ON r.operation_id=op.operation_id
 WHERE op.occasion_id=p_occasion AND op.committed_at<p_before ORDER BY op.committed_at DESC LIMIT 50) rows;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.get_scanner_event_history(bigint,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_scanner_event_history(bigint,timestamptz) TO authenticated;
CREATE OR REPLACE FUNCTION public.search_scanner_users(p_session uuid,p_token text,p_query text,p_after uuid DEFAULT '00000000-0000-0000-0000-000000000000')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg jsonb; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 SELECT config INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT coalesce((cfg#>>'{manual_search,users}')::boolean,false) THEN RAISE insufficient_privilege USING MESSAGE='manual_search_disabled'; END IF;
 IF length(p_query) NOT BETWEEN 2 AND 100 THEN RETURN jsonb_build_object('code',400,'reason','invalid_query'); END IF;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded'); END IF;
 SELECT coalesce(jsonb_agg(item ORDER BY id),'[]'::jsonb) INTO result FROM (
 SELECT u.id,jsonb_build_object('user_id',u.id,'holder_name',concat_ws(' ',u.name,u.surname),'symbol',u.id) item
 FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user"
 JOIN public.occasions o ON o.id=ou.occasion
 LEFT JOIN public.organization_users orgu ON orgu."user"=u.id AND orgu.organization=o.organization
 WHERE ou.occasion=s.occasion_id AND u.id>p_after AND orgu.is_hidden IS NOT TRUE
 AND strpos(lower(concat_ws(' ',u.name,u.surname)),lower(p_query))>0 ORDER BY u.id LIMIT 30) rows;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.search_scanner_users(uuid,text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_scanner_users(uuid,text,text,uuid) TO anon,authenticated;
CREATE OR REPLACE FUNCTION public.preview_scanner_ticket(p_occasion bigint,p_config jsonb,p_symbol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.scanner_require_settings_editor_internal(p_occasion);
 PERFORM public.scanner_validate_settings_internal(p_occasion,p_config);
 SELECT dto INTO result FROM public.scanner_ticket_projection_internal(p_occasion,p_config,(SELECT id FROM eshop.tickets WHERE occasion=p_occasion AND ticket_symbol=p_symbol LIMIT 1)) WHERE dto->>'symbol'=p_symbol;
 RETURN jsonb_build_object('code',CASE WHEN result IS NULL THEN 404 ELSE 200 END,'reason',CASE WHEN result IS NULL THEN 'not_found' END,'data',result,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.preview_scanner_ticket(bigint,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_scanner_ticket(bigint,jsonb,text) TO authenticated;
