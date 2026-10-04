CREATE OR REPLACE FUNCTION public.create_account_deletion_request(
  p_user uuid,
  p_organization bigint,
  p_token_hash text,
  p_expires_at timestamptz,
  p_masked_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_previous public.account_deletion_requests%ROWTYPE;
  v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_invalid_request' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id = p_user AND ui.organization = p_organization
  ) THEN
    RAISE EXCEPTION 'account_deletion_account_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_previous
  FROM public.account_deletion_requests
  WHERE user_id = p_user
    AND status IN ('email_pending','email_sent','deletion_pending')
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF v_previous.status = 'deletion_pending' THEN
    RAISE EXCEPTION 'account_deletion_already_pending' USING ERRCODE = '55000';
  END IF;
  IF v_previous.id IS NOT NULL AND v_previous.cooldown_until > clock_timestamp() THEN
    RAISE EXCEPTION 'account_deletion_cooldown' USING ERRCODE = 'P0001';
  END IF;
  IF v_previous.id IS NOT NULL THEN
    UPDATE public.account_deletion_requests
    SET status = 'revoked', token_hash = NULL, masked_email = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_previous.id;
  END IF;

  INSERT INTO public.account_deletion_requests(
    user_id, organization, token_hash, masked_email, expires_at, cooldown_until
  ) VALUES (
    p_user, p_organization, p_token_hash, p_masked_email, p_expires_at,
    clock_timestamp() + interval '5 minutes'
  ) RETURNING * INTO v_request;

  RETURN jsonb_build_object('requestId', v_request.id, 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_account_deletion_email_state(
  p_request_id uuid,
  p_delivered boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_deletion_requests
  SET status = CASE WHEN p_delivered THEN 'email_sent' ELSE 'revoked' END,
      email_sent_at = CASE WHEN p_delivered THEN clock_timestamp() ELSE NULL END,
      token_hash = CASE WHEN p_delivered THEN token_hash ELSE NULL END,
      masked_email = CASE WHEN p_delivered THEN masked_email ELSE NULL END,
      error_class = CASE WHEN p_delivered THEN NULL ELSE 'email_delivery' END,
      updated_at = clock_timestamp()
  WHERE id = p_request_id AND status = 'email_pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.inspect_account_deletion_token(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  IF p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;
  RETURN jsonb_build_object('status', 'valid', 'expiresAt', v_request.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_account_deletion(p_token_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_request public.account_deletion_requests%ROWTYPE;
  v_completion_email text;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE token_hash = p_token_hash OR used_token_hash = p_token_hash
  LIMIT 1 FOR UPDATE;
  IF v_request.id IS NULL THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.status = 'completed' THEN RETURN jsonb_build_object('status', 'already_completed'); END IF;
  IF v_request.status IN ('deletion_pending','failed') AND v_request.used_token_hash = p_token_hash THEN
    RETURN jsonb_build_object('status','processing','requestId',v_request.id,
      'userId',v_request.user_id,'organization',v_request.organization,
      'publicDeleted',v_request.public_deleted,'authDeleted',v_request.auth_deleted,
      'onesignalDeleted',v_request.onesignal_deleted);
  END IF;
  IF v_request.status <> 'email_sent' THEN RETURN jsonb_build_object('status', 'invalid'); END IF;
  IF v_request.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('status', 'expired'); END IF;

  v_completion_email := public.get_user_delivery_email(v_request.user_id);

  UPDATE public.account_deletion_requests SET
    status='deletion_pending', used_token_hash=token_hash, token_hash=NULL,
    masked_email=NULL, claimed_at=clock_timestamp(), attempt_count=attempt_count+1,
    updated_at=clock_timestamp()
  WHERE id=v_request.id RETURNING * INTO v_request;
  -- The claim and first-party cleanup share one transaction. Consequently an
  -- already-issued JWT cannot regain domain access between confirmation and a
  -- later Edge call; its public.user_info row is gone before claim commits.
  PERFORM public.cleanup_account_deletion_domain(v_request.id);
  RETURN jsonb_build_object('status','processing','requestId',v_request.id,
    'userId',v_request.user_id,'organization',v_request.organization,
    'completionEmail',v_completion_email,
    'publicDeleted',true,'authDeleted',false,'onesignalDeleted',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_account_deletion_domain(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user uuid; v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests
  WHERE id=p_request_id FOR UPDATE;
  IF v_request.id IS NULL OR v_request.status NOT IN ('deletion_pending','failed') THEN
    RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000';
  END IF;
  IF v_request.public_deleted THEN RETURN jsonb_build_object('status','already_deleted'); END IF;
  v_user := v_request.user_id;

  PERFORM public.record_account_deletion_sync_v1(
    v_user,v_request.organization);

  UPDATE public.cleaning_reports SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.cleaning_reports SET resolved_by=NULL WHERE resolved_by=v_user;
  UPDATE public.news SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.orders_history SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.bank_account_requests SET created_by=NULL WHERE created_by=v_user;
  UPDATE eshop.transactions SET created_by=NULL WHERE created_by=v_user;
  UPDATE public.client_commits SET actor_id=NULL, actor_display=NULL WHERE actor_id=v_user;
  DELETE FROM public.event_feedback WHERE "user"=v_user;

  DELETE FROM public.client_mutation_receipts WHERE actor_id=v_user;
  DELETE FROM public.client_sync_private_scopes WHERE user_id=v_user;
  DELETE FROM public.activity_assignments WHERE "user"=v_user;
  DELETE FROM public.activity_history WHERE user_id=v_user;
  DELETE FROM public.event_users_saved WHERE "user"=v_user;
  DELETE FROM public.event_users WHERE "user"=v_user;
  DELETE FROM public.user_groups WHERE "user"=v_user;
  DELETE FROM public.user_companions WHERE "user"=v_user OR companion=v_user;
  DELETE FROM public.user_reset_token WHERE "user"=v_user;
  DELETE FROM eshop.bank_account_users WHERE "user"=v_user;
  DELETE FROM public.occasion_users WHERE "user"=v_user;
  DELETE FROM public.unit_users WHERE "user"=v_user;
  DELETE FROM public.organization_users WHERE "user"=v_user;
  PERFORM public.invalidate_external_login_for_user_v1(v_user);
  DELETE FROM public.user_info WHERE id=v_user;

  UPDATE public.account_deletion_requests SET public_deleted=true,
    status='deletion_pending', error_class=NULL, updated_at=clock_timestamp()
  WHERE id=p_request_id;
  RETURN jsonb_build_object('status','deleted');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_account_deletion_storage_batch(
  p_request_id uuid,
  p_limit integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user uuid; v_result jsonb;
BEGIN
  PERFORM public.require_service_role();
  IF p_limit < 1 OR p_limit > 1000 THEN
    RAISE EXCEPTION 'account_deletion_invalid_storage_batch_limit' USING ERRCODE = '22023';
  END IF;
  SELECT user_id INTO v_user
  FROM public.account_deletion_requests
  WHERE id=p_request_id AND status IN ('deletion_pending','failed');
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'bucketId', item.bucket_id, 'name', item.name
  ) ORDER BY item.bucket_id,item.name),'[]'::jsonb)
  INTO v_result
  FROM (
    SELECT bucket_id,name FROM storage.objects
    WHERE owner_id=v_user::text
    ORDER BY bucket_id,name LIMIT p_limit
  ) item;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_account_deletion_job(
  p_request_id uuid,
  p_auth_deleted boolean DEFAULT NULL,
  p_onesignal_deleted boolean DEFAULT NULL,
  p_error_class text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE;
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_deletion_requests SET
    auth_deleted=coalesce(p_auth_deleted,auth_deleted),
    onesignal_deleted=coalesce(p_onesignal_deleted,onesignal_deleted),
    error_class=p_error_class,
    status=CASE
      WHEN public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN 'completed'
      WHEN p_error_class IS NOT NULL THEN 'failed' ELSE 'deletion_pending' END,
    completed_at=CASE
      WHEN public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN clock_timestamp()
      ELSE completed_at END,
    user_id=CASE
      WHEN public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN NULL ELSE user_id END,
    updated_at=clock_timestamp()
  WHERE id=p_request_id AND status IN ('deletion_pending','failed')
  RETURNING * INTO v_request;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
  RETURN jsonb_build_object('status',v_request.status);
END;
$$;

REVOKE ALL ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_account_deletion(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_account_deletion_domain(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_account_deletion_storage_batch(uuid,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_account_deletion_request(uuid,bigint,text,timestamptz,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_account_deletion_email_state(uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_account_deletion_domain(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_storage_batch(uuid,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_account_deletion_job(uuid,boolean,boolean,text) TO service_role;
REVOKE ALL ON FUNCTION public.inspect_account_deletion_token(text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.inspect_account_deletion_token(text) TO anon, service_role;
