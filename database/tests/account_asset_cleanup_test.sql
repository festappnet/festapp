-- Disposable SQL fixture only. No remote object is deleted by this test.
BEGIN;
DO $$
DECLARE
 organization_id bigint; job_a uuid:=gen_random_uuid(); job_b uuid:=gen_random_uuid();
 owner_a uuid:=gen_random_uuid(); owner_b uuid:=gen_random_uuid();
 asset_a uuid:=gen_random_uuid(); asset_b uuid:=gen_random_uuid(); unowned uuid:=gen_random_uuid();
 sha text:=repeat('a',64); result jsonb;
BEGIN
 SELECT min(id) INTO organization_id FROM public.organizations;
 IF organization_id IS NULL THEN RAISE EXCEPTION 'isolated fixture needs one organization'; END IF;
 INSERT INTO public.account_deletion_requests(id,user_id,organization,status,expires_at,cooldown_until,
  public_deleted,auth_deleted,onesignal_deleted)
 VALUES(job_a,owner_a,organization_id,'deletion_pending',now()+interval '1 hour',now(),true,true,true),
 (job_b,owner_b,organization_id,'deletion_pending',now()+interval '1 hour',now(),true,true,true);

 PERFORM set_config('request.jwt.claim.role','service_role',true);
 UPDATE public.canonical_asset_cutover SET active=false;
 BEGIN
  PERFORM public.get_account_deletion_asset_batch(job_a);
  RAISE EXCEPTION 'inactive cutover unexpectedly accepted';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 UPDATE public.canonical_asset_cutover SET active=true,inventory_sha256=repeat('b',64);

 INSERT INTO public.canonical_assets(id,bucket,object_key,sha256,bytes,content_type,visibility,
  owner_id,source_bucket,source_key,source_storage_record,verified_at)
 VALUES(asset_a,'festapp-images-private','assets/storage/editor-files/'||repeat('b',20)||'/'||repeat('c',64)||'/'||sha,
  sha,10,'application/pdf','private',owner_a::text,'editor-files','private-a',jsonb_build_object('owner_id',owner_a),now()),
 (asset_b,'festapp-images-private','assets/storage/editor-files/'||repeat('c',20)||'/'||repeat('c',64)||'/'||sha,
  sha,10,'application/pdf','private',owner_b::text,'editor-files','private-b',jsonb_build_object('owner_id',owner_b),now()),
 (unowned,'festapp-images-private','assets/storage/editor-files/'||repeat('d',20)||'/'||repeat('c',64)||'/'||sha,
  sha,10,'application/pdf','private',NULL,'editor-files','unassigned','{}',now());

 result:=public.update_account_deletion_job(job_a,true,true,NULL);
 IF result->>'status'='completed' THEN RAISE EXCEPTION 'account completed before asset queue preparation'; END IF;
 result:=public.get_account_deletion_asset_batch(job_a,100);
 IF jsonb_array_length(result)<>1 OR result->0->>'assetId'<>asset_a::text THEN
  RAISE EXCEPTION 'asset inventory crossed owner boundary'; END IF;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN
  PERFORM public.get_account_deletion_asset_batch(job_a);
  RAISE EXCEPTION 'user accessed service inventory';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 BEGIN
  PERFORM public.ack_account_deletion_asset(job_a,asset_b,sha);
  RAISE EXCEPTION 'cross-owner acknowledgement accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.ack_account_deletion_asset(job_a,asset_a,repeat('0',64));
  RAISE EXCEPTION 'hash conflict acknowledgement accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 result:=public.update_account_deletion_job(job_a,true,true,NULL);
 IF result->>'status'='completed' THEN RAISE EXCEPTION 'account completed before remote cleanup'; END IF;

 -- This acknowledges a simulated successful Worker response; SQL alone is not
 -- proof that R2 was contacted. Provider calls are covered separately.
 PERFORM public.ack_account_deletion_asset(job_a,asset_a,sha);
 PERFORM public.ack_account_deletion_asset(job_a,asset_a,sha);
 IF public.get_account_deletion_asset_batch(job_a)<>'[]'::jsonb THEN RAISE EXCEPTION 'acknowledged item requeued'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.canonical_assets WHERE id=asset_a AND owner_id IS NULL
  AND source_key IS NULL AND source_storage_record='{}' AND deleted_at IS NOT NULL) THEN
  RAISE EXCEPTION 'deleted asset retained original owner/key record'; END IF;
 IF EXISTS(SELECT 1 FROM public.canonical_assets WHERE id IN (asset_b,unowned) AND deleted_at IS NOT NULL) THEN
  RAISE EXCEPTION 'unrelated assets were removed'; END IF;
 result:=public.update_account_deletion_job(job_a,true,true,NULL);
 IF result->>'status'<>'completed' OR (SELECT user_id FROM public.account_deletion_requests WHERE id=job_a) IS NOT NULL THEN
  RAISE EXCEPTION 'clean account failed to complete'; END IF;
 IF has_function_privilege('anon','public.get_account_deletion_asset_batch(uuid,integer)','EXECUTE') OR
  has_function_privilege('authenticated','public.ack_account_deletion_asset(uuid,uuid,text)','EXECUTE') OR
  has_table_privilege('service_role','public.canonical_assets','UPDATE') THEN
  RAISE EXCEPTION 'asset owner ACL leaked'; END IF;
END $$;
ROLLBACK;
