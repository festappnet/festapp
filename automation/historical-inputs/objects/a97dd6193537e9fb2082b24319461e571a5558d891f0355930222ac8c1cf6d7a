-- Capture the delivery address in the service-only claim response before the
-- same transaction removes public.user_info. The Edge Function keeps it only
-- in request memory and the terminal audit row remains de-identified.
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
  PERFORM public.cleanup_account_deletion_domain(v_request.id);
  RETURN jsonb_build_object('status','processing','requestId',v_request.id,
    'userId',v_request.user_id,'organization',v_request.organization,
    'completionEmail',v_completion_email,
    'publicDeleted',true,'authDeleted',false,'onesignalDeleted',false);
END;
$$;
