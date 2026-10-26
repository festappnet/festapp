-- Service-only queue owner. Unknown ownership is never inferred from a URL.
CREATE OR REPLACE FUNCTION public.get_account_deletion_asset_batch(
 p_request_id uuid,p_limit integer DEFAULT 100
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE job public.account_deletion_requests%ROWTYPE; result jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN
  RAISE invalid_parameter_value USING MESSAGE='asset_batch_limit';
 END IF;
 IF NOT COALESCE((SELECT active FROM public.canonical_asset_cutover WHERE singleton),false) THEN
  RAISE object_not_in_prerequisite_state USING MESSAGE='asset_cutover_not_active';
 END IF;
 SELECT * INTO job FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
 IF job.id IS NULL OR job.user_id IS NULL OR job.status NOT IN ('deletion_pending','failed') THEN
  RAISE object_not_in_prerequisite_state USING MESSAGE='account_deletion_request_state_conflict';
 END IF;
 INSERT INTO public.account_deletion_assets(request_id,asset_id)
 SELECT job.id,a.id FROM public.canonical_assets a
 WHERE a.owner_id=job.user_id::text AND a.deleted_at IS NULL
 ON CONFLICT DO NOTHING;
 UPDATE public.account_deletion_requests SET assets_prepared=true WHERE id=job.id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('assetId',a.id,'bucket',a.bucket,
  'key',a.object_key,'sha256',a.sha256) ORDER BY a.id),'[]'::jsonb) INTO result
 FROM (SELECT q.asset_id FROM public.account_deletion_assets q
  WHERE q.request_id=job.id AND q.deleted_at IS NULL ORDER BY q.asset_id LIMIT p_limit) q
 JOIN public.canonical_assets a ON a.id=q.asset_id AND a.owner_id=job.user_id::text;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.ack_account_deletion_asset(
 p_request_id uuid,p_asset_id uuid,p_sha256 text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE job public.account_deletion_requests%ROWTYPE;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO job FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
 IF job.id IS NULL OR job.user_id IS NULL OR job.status NOT IN ('deletion_pending','failed') THEN
  RAISE object_not_in_prerequisite_state USING MESSAGE='account_deletion_request_state_conflict';
 END IF;
 UPDATE public.account_deletion_assets q SET deleted_at=COALESCE(q.deleted_at,clock_timestamp())
 FROM public.canonical_assets a WHERE q.request_id=job.id AND q.asset_id=p_asset_id
  AND a.id=q.asset_id AND (a.owner_id=job.user_id::text OR
    (q.deleted_at IS NOT NULL AND a.deleted_at IS NOT NULL)) AND a.sha256=p_sha256;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='asset_cleanup_identity_mismatch'; END IF;
 UPDATE public.canonical_assets SET deleted_at=COALESCE(deleted_at,clock_timestamp()),
  owner_id=NULL,source_key=NULL,source_storage_record='{}'::jsonb
 WHERE id=p_asset_id;
END $$;

REVOKE ALL ON FUNCTION public.get_account_deletion_asset_batch(uuid,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ack_account_deletion_asset(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_asset_batch(uuid,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ack_account_deletion_asset(uuid,uuid,text) TO service_role;
