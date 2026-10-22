-- Generated from canonical asset table/cleanup and account job sources.
-- Staged only: activate after verified inventory import, copy and delta gates.
SET lock_timeout='5s';
SET statement_timeout='120s';
-- Exact migrated identity and original ownership; no FK to auth.users: account
-- cleanup runs after Auth deletion and must not lose the durable owner binding.
ALTER TABLE public.account_deletion_requests ADD COLUMN assets_prepared boolean NOT NULL DEFAULT false;
CREATE TABLE public.canonical_assets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 bucket text NOT NULL CHECK(bucket IN ('festapp-images','festapp-images-private')),
 object_key text NOT NULL,
 sha256 text NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
 bytes bigint NOT NULL CHECK(bytes>=0),
 content_type text NOT NULL CHECK(length(content_type)>0),
 visibility text NOT NULL CHECK(visibility IN ('public','private')),
 owner_id text,
 source_bucket text NOT NULL,
 source_key text,
 source_storage_record jsonb NOT NULL CHECK(jsonb_typeof(source_storage_record)='object'),
 verified_at timestamptz NOT NULL,
 deleted_at timestamptz,
 UNIQUE(bucket,object_key), UNIQUE(source_bucket,source_key),
 CHECK(deleted_at IS NOT NULL OR (source_key IS NOT NULL AND
   owner_id IS NOT DISTINCT FROM source_storage_record->>'owner_id')),
 CHECK((bucket='festapp-images')=(visibility='public')),
 CHECK(object_key ~ '^(assets|images)/storage/[A-Za-z0-9_-]+/[a-f0-9]{20}/[a-f0-9]{64}/[a-f0-9]{64}$'
   OR object_key ~ '^ticket-fonts/sha256/[a-f0-9]{64}\.(ttf|woff)$'),
 CHECK(CASE WHEN object_key LIKE 'ticket-fonts/%' THEN owner_id IS NULL
   AND bucket='festapp-images-private' ELSE right(object_key,64)=sha256 END)
);
ALTER TABLE public.canonical_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.canonical_assets FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.canonical_asset_cutover (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 active boolean NOT NULL DEFAULT false,
 inventory_sha256 text CHECK(inventory_sha256 ~ '^[0-9a-f]{64}$'),
 CHECK(NOT active OR inventory_sha256 IS NOT NULL)
);
INSERT INTO public.canonical_asset_cutover(singleton) VALUES(true);
REVOKE ALL ON public.canonical_asset_cutover FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.account_deletion_assets (
 request_id uuid NOT NULL REFERENCES public.account_deletion_requests(id),
 asset_id uuid NOT NULL REFERENCES public.canonical_assets(id),
 deleted_at timestamptz,
 PRIMARY KEY(request_id,asset_id)
);
ALTER TABLE public.account_deletion_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_deletion_assets FROM PUBLIC,anon,authenticated,service_role;

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

CREATE OR REPLACE FUNCTION public.update_account_deletion_job(
  p_request_id uuid,
  p_auth_deleted boolean DEFAULT NULL,
  p_onesignal_deleted boolean DEFAULT NULL,
  p_error_class text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_request public.account_deletion_requests%ROWTYPE; v_assets_done boolean;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_request FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  v_assets_done := COALESCE(v_request.assets_prepared AND
    (SELECT active FROM public.canonical_asset_cutover WHERE singleton) AND
    NOT EXISTS(SELECT 1 FROM public.account_deletion_assets WHERE request_id=p_request_id AND deleted_at IS NULL) AND
    NOT EXISTS(SELECT 1 FROM public.canonical_assets WHERE owner_id=v_request.user_id::text AND deleted_at IS NULL),false);
  UPDATE public.account_deletion_requests SET
    auth_deleted=coalesce(p_auth_deleted,auth_deleted),
    onesignal_deleted=coalesce(p_onesignal_deleted,onesignal_deleted),
    error_class=p_error_class,
    status=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN 'completed'
      WHEN p_error_class IS NOT NULL THEN 'failed' ELSE 'deletion_pending' END,
    completed_at=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN clock_timestamp()
      ELSE completed_at END,
    user_id=CASE
      WHEN v_assets_done AND public_deleted AND coalesce(p_auth_deleted,auth_deleted)
        AND coalesce(p_onesignal_deleted,onesignal_deleted) THEN NULL ELSE user_id END,
    updated_at=clock_timestamp()
  WHERE id=p_request_id AND status IN ('deletion_pending','failed')
  RETURNING * INTO v_request;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'account_deletion_request_state_conflict' USING ERRCODE = '55000'; END IF;
  RETURN jsonb_build_object('status',v_request.status);
END;
$$;
DROP FUNCTION public.get_account_deletion_storage_batch(uuid,integer);
NOTIFY pgrst, 'reload schema';
