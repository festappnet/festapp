BEGIN;

CREATE OR REPLACE FUNCTION public.revoke_reception_login_qr_v1(
  p_occasion bigint,p_user uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid();
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN
    RETURN jsonb_build_object('code',403,'message','reception_unavailable');
  END IF;
  IF NOT public.reception_rate_limit_v1('revoke',30) THEN
    RETURN jsonb_build_object('code',429,'message','rate_limited');
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.reception_registrations r
    WHERE r.occasion=p_occasion AND r."user"=p_user AND r.status='active'
      AND ((r.created_by=v_actor AND r.created_at>now()-interval '30 minutes')
        OR public.get_is_manager_on_occasion(p_occasion)
        OR public.get_is_admin_on_occasion(p_occasion))
  ) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable');
  END IF;
  UPDATE public.user_login_qr_credentials
  SET revoked_at=now()
  WHERE occasion=p_occasion AND "user"=p_user AND revoked_at IS NULL;
  RETURN jsonb_build_object('code',200,'status','revoked');
END $$;

REVOKE ALL ON FUNCTION public.revoke_reception_login_qr_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.revoke_reception_login_qr_v1(bigint,uuid)
  TO authenticated,service_role;

COMMIT;
