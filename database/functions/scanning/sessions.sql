CREATE OR REPLACE FUNCTION public.scanner_session_internal(p_session uuid,p_token text,p_allow_expired boolean DEFAULT false)
RETURNS public.scanner_sessions LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; secret text;
BEGIN
 -- Shared policy then session locks also serialize revocation and settings changes.
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=(SELECT occasion_id FROM public.scanner_sessions WHERE id=p_session) FOR SHARE;
 SELECT * INTO s FROM public.scanner_sessions WHERE id=p_session FOR SHARE;
 IF s.id IS NULL OR p_token IS NULL OR s.token_hash<>encode(digest(p_token,'sha256'),'hex') THEN
  RAISE SQLSTATE 'PT401' USING MESSAGE='invalid_scanner_session'; END IF;
 IF s.actor_user_id IS NOT NULL AND (auth.uid() IS DISTINCT FROM s.actor_user_id OR NOT public.get_is_editor_order_on_occasion(s.occasion_id)) THEN
  RAISE SQLSTATE 'PT403' USING MESSAGE='scanner_actor_changed'; END IF;
 SELECT oh.secret INTO secret FROM public.occasions o JOIN public.occasions_hidden oh ON oh.id=o.occasion_hidden WHERE o.id=s.occasion_id;
 IF NOT p_allow_expired AND (s.revoked_at IS NOT NULL OR s.expires_at<=now() OR s.epoch<>cfg.epoch
 OR (s.access_origin='scan_link' AND s.scan_secret_hash IS DISTINCT FROM encode(digest(secret,'sha256'),'hex'))) THEN
  RAISE SQLSTATE 'PT401' USING MESSAGE='scanner_session_expired'; END IF;
 RETURN s;
END $$;
CREATE OR REPLACE FUNCTION public.open_scanner_session(p_scan_code text DEFAULT NULL,p_occasion bigint DEFAULT NULL,p_device_name text DEFAULT 'Hlavní vstup')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; s public.scanner_sessions; cfg public.scanner_settings; token text; origin text; sec text;
BEGIN
 IF NOT public.check_scan_attempt_budget_v1(p_occasion) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now()); END IF;
 IF p_scan_code IS NOT NULL THEN
  SELECT o.* INTO oc FROM public.occasions o JOIN public.occasions_hidden oh ON oh.id=o.occasion_hidden WHERE oh.secret=p_scan_code LIMIT 1;
  -- record assignment above must match the occasion row exactly
  origin:='scan_link'; sec:=p_scan_code;
 ELSE
  PERFORM public.check_is_editor_order_on_occasion(p_occasion);
  SELECT * INTO oc FROM public.occasions WHERE id=p_occasion; origin:='authenticated';
 END IF;
 IF oc.id IS NULL THEN PERFORM public.admit_scan_access_v1(NULL,false); RETURN jsonb_build_object('code',401,'reason','invalid_scan_code','server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(oc.id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 INSERT INTO public.scanner_settings(occasion_id,config) VALUES(oc.id,public.scanner_default_settings_internal(oc.id)) ON CONFLICT DO NOTHING;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=oc.id FOR SHARE;
 token:=encode(gen_random_bytes(32),'hex');
 INSERT INTO public.scanner_sessions(occasion_id,actor_user_id,access_origin,token_hash,scan_secret_hash,epoch,device_name,expires_at,offline_until)
 VALUES(oc.id,CASE WHEN origin='authenticated' THEN auth.uid() END,origin,encode(digest(token,'sha256'),'hex'),encode(digest(sec,'sha256'),'hex'),cfg.epoch,left(p_device_name,80),now()+interval '12 hours',
 now()+make_interval(hours=>CASE WHEN (cfg.config#>>'{offline,enabled}')::boolean THEN (cfg.config#>>'{offline,max_hours}')::integer ELSE 0 END)) RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'server_time',now(),'data',jsonb_build_object('session_id',s.id,'token',token,'occasion_id',oc.id,'organization_id',oc.organization,
 'title',oc.title,'epoch',s.epoch,'expires_at',s.expires_at,'offline_until',s.offline_until,'settings_revision',cfg.revision,'settings',cfg.config,'device_name',s.device_name,
 'capabilities',jsonb_build_object('search_tickets',(cfg.config#>>'{manual_search,tickets}')::boolean,'search_users',(cfg.config#>>'{manual_search,users}')::boolean,
 'settings',auth.uid() IS NOT NULL AND public.get_is_editor_order_on_occasion(oc.id),'offline',(cfg.config#>>'{offline,enabled}')::boolean)));
END $$;
CREATE OR REPLACE FUNCTION public.revoke_scanner_session(p_session uuid,p_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions;
BEGIN
 SELECT * INTO s FROM public.scanner_sessions WHERE id=p_session;
 IF p_token IS NOT NULL THEN s:=public.scanner_session_internal(p_session,p_token,true);
 ELSE PERFORM public.check_is_editor_order_on_occasion(s.occasion_id); END IF;
 UPDATE public.scanner_sessions SET revoked_at=now() WHERE id=p_session;
 RETURN jsonb_build_object('code',200,'server_time',now());
END $$;
