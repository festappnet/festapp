BEGIN;
-- Operator configuration is empty until one explicitly selected tenant is enabled.
CREATE TABLE IF NOT EXISTS public.first_login_notification_settings (
  organization bigint PRIMARY KEY REFERENCES public.organizations(id),
  recipient text NOT NULL CHECK (length(recipient)<=320 AND position('@' in recipient)>1),
  enabled boolean NOT NULL DEFAULT false,
  activated_at timestamptz NOT NULL DEFAULT now(),
  last_poll_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.first_login_notifications (
  user_id uuid PRIMARY KEY,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  observed_at timestamptz NOT NULL DEFAULT now(),
  message_id uuid REFERENCES public.email_messages(message_id),
  baseline boolean NOT NULL DEFAULT false
);
ALTER TABLE public.first_login_notification_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.first_login_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.first_login_notification_settings,public.first_login_notifications FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.configure_first_login_notifications_v1(p_organization bigint,p_recipient text,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('festapp-first-login-notifications',0));
  -- Never send a historical flood when enabling a tenant. Existing users with no
  -- successful login remain eligible for their first real login after activation.
  IF NOT EXISTS(SELECT 1 FROM public.first_login_notification_settings WHERE organization=p_organization) THEN
    INSERT INTO public.first_login_notifications(user_id,organization,baseline)
    SELECT ui.id,ui.organization,true FROM public.user_info ui JOIN auth.users au ON au.id=ui.id
    WHERE ui.organization=p_organization AND au.last_sign_in_at IS NOT NULL ON CONFLICT(user_id) DO NOTHING;
  END IF;
  INSERT INTO public.first_login_notification_settings(organization,recipient,enabled)
  VALUES(p_organization,lower(btrim(p_recipient)),p_enabled)
  ON CONFLICT(organization) DO UPDATE SET recipient=excluded.recipient,enabled=excluded.enabled;
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_first_login_notifications_v1()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r record;v_message jsonb;v_count integer:=0;
BEGIN
  PERFORM public.require_service_role();
  IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('festapp-first-login-notifications',0)) THEN RETURN 0; END IF;
  FOR r IN
    SELECT ui.id,ui.organization,ui.email_readonly,concat_ws(' ',ui.name,ui.surname) name,
      au.last_sign_in_at,settings.recipient,org.data->>'APP_NAME' app_name
    FROM public.user_info ui JOIN auth.users au ON au.id=ui.id
    JOIN public.first_login_notification_settings settings ON settings.organization=ui.organization AND settings.enabled
    JOIN public.organizations org ON org.id=ui.organization
    WHERE au.last_sign_in_at IS NOT NULL AND au.last_sign_in_at>=settings.activated_at
      AND NOT EXISTS(SELECT 1 FROM public.first_login_notifications n WHERE n.user_id=ui.id)
      -- GoTrue sets last_sign_in_at for both password and Google-issued sessions.
      -- Require a live session and, for MFA accounts, successful second factor.
      AND EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=ui.id AND (s.not_after IS NULL OR s.not_after>now())
        AND (s.aal::text='aal2' OR NOT EXISTS(SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=ui.id AND f.status::text='verified')))
    ORDER BY au.last_sign_in_at,ui.id LIMIT 100
  LOOP
    v_message:=public.enqueue_email('custom',jsonb_build_object('organization',r.organization),r.recipient,
      jsonb_build_object('app_name',r.app_name,'name',r.name,'email',r.email_readonly,'signed_in_at',r.last_sign_in_at),
      'first-login:'||r.id::text,'NEW_USER_FIRST_LOGIN',now(),now()+interval '30 days');
    UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(v_message->>'message_id')::uuid;
    INSERT INTO public.first_login_notifications(user_id,organization,message_id)
    VALUES(r.id,r.organization,(v_message->>'message_id')::uuid);
    v_count:=v_count+1;
  END LOOP;
  UPDATE public.first_login_notification_settings SET last_poll_at=now() WHERE enabled;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public.configure_first_login_notifications_v1(bigint,text,boolean),public.enqueue_first_login_notifications_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_first_login_notifications_v1(bigint,text,boolean),public.enqueue_first_login_notifications_v1() TO service_role;

-- A separate hashed capability exposes bounded operational facts only. It cannot
-- mint sessions, enqueue mail or access customer rows through another RPC.
CREATE TABLE IF NOT EXISTS public.festapp_monitoring_credentials (
  token_hash text PRIMARY KEY CHECK(length(token_hash)=64),
  expires_at timestamptz NOT NULL,
  registered_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.festapp_monitoring_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.festapp_monitoring_credentials FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_festapp_monitoring_health_v1(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;v_since timestamptz;v_oldest timestamptz;v_alerts text[]:='{}';
BEGIN
  IF p_token IS NULL OR length(p_token)<32 OR length(p_token)>256 THEN RAISE insufficient_privilege USING MESSAGE='monitoring capability required'; END IF;
  SELECT registered_at INTO v_since FROM public.festapp_monitoring_credentials
    WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND expires_at>now();
  IF v_since IS NULL THEN RAISE insufficient_privilege USING MESSAGE='monitoring capability required'; END IF;
  SELECT * INTO c FROM public.email_capacity;
  SELECT min(created_at) INTO v_oldest FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait','preparing','sending') AND target_time<=now();
  IF c.paused THEN v_alerts:=array_append(v_alerts,'email_paused'); END IF;
  IF c.quota_at IS NULL OR c.quota_at<now()-interval '15 minutes' THEN v_alerts:=array_append(v_alerts,'quota_stale'); END IF;
  IF v_oldest<now()-interval '5 minutes' THEN v_alerts:=array_append(v_alerts,'email_backlog'); END IF;
  IF c.provider_outage_streak>0 OR c.wake_error IS NOT NULL OR c.circuit_until>now() THEN v_alerts:=array_append(v_alerts,'email_provider_failed'); END IF;
  IF EXISTS(SELECT 1 FROM public.email_messages WHERE created_at>=v_since AND (workflow_state IN ('dead','unknown') OR provider_failure IS NOT NULL OR last_error='post_action_failed')) THEN v_alerts:=array_append(v_alerts,'email_delivery_failed'); END IF;
  IF EXISTS(SELECT 1 FROM public.email_messages m WHERE accepted_at>=v_since AND accepted_at<now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id)) THEN v_alerts:=array_append(v_alerts,'email_feedback_overdue'); END IF;
  IF EXISTS(SELECT 1 FROM public.first_login_notification_settings WHERE enabled AND activated_at<now()-interval '3 minutes' AND (last_poll_at IS NULL OR last_poll_at<now()-interval '3 minutes')) THEN v_alerts:=array_append(v_alerts,'first_login_poll_stale'); END IF;
  RETURN jsonb_build_object('ok',cardinality(v_alerts)=0,'alerts',to_jsonb(v_alerts));
END $$;
REVOKE ALL ON FUNCTION public.get_festapp_monitoring_health_v1(text) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION public.get_festapp_monitoring_health_v1(text) TO anon;

NOTIFY pgrst, 'reload schema';
COMMIT;
