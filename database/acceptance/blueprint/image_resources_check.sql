-- Requires owned local image pipeline to register at least one real asset first.
-- Run in one rollback transaction; no synthetic claim of processed readiness.
BEGIN;
\ir ../../tests/blueprint/fixtures.sql
DO $$
DECLARE a public.blueprint_image_assets; f jsonb; req jsonb; r jsonb; bg jsonb; asset jsonb; initial_count bigint; copied bigint; copied_bp bigint; target_unit bigint; actual_revision bigint; variant jsonb; expected_reason text; public_read jsonb; ua public.blueprint_image_assets;
BEGIN
 SELECT * INTO a FROM public.blueprint_image_assets WHERE occasion=1 ORDER BY created_at DESC LIMIT 1;
 IF a.asset_ref IS NULL THEN RAISE EXCEPTION 'real owned pipeline asset required';END IF;
 asset:=jsonb_build_object('assetRef',a.asset_ref,'hash',a.hash,'url',a.url,'width',a.width,'height',a.height,'mimeType',a.mime_type,'byteLength',a.byte_length,'state','ready');
 f:=public.blueprint_test_fixture_internal(a.organization);req:=f->'request';
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 bg:=jsonb_build_object('assetRef',a.asset_ref,'hash',a.hash,'width',a.width,'height',a.height,'x',10,'y',10,'rotation',0,'scale',1,'opacity',1,'crop',jsonb_build_object('x',0,'y',0,'width',1,'height',1));
 req:=jsonb_set(req,'{layout,background}',bg);
 -- Same real bytes are unavailable to an unrelated occasion without trusted copy.
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());
 IF r#>>'{data,reason}'<>'BLUEPRINT_ASSET_RESOURCE_NOT_READY' THEN RAISE EXCEPTION 'foreign asset accepted: %',r;END IF;
 IF (SELECT layout_revision FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint)<>0 OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint) THEN RAISE EXCEPTION 'rejected save partially mutated';END IF;
 -- JWT alone cannot manufacture or replay a stale processing receipt.
 SELECT count(*) INTO initial_count FROM public.blueprint_image_assets;
 BEGIN PERFORM public.register_blueprint_image_asset(1,'default',asset,extract(epoch FROM now())::bigint,repeat('0',64));RAISE EXCEPTION 'forged HMAC accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.register_blueprint_image_asset(1,'default',asset,extract(epoch FROM now())::bigint-601,repeat('0',64));RAISE EXCEPTION 'stale HMAC accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF (SELECT count(*) FROM public.blueprint_image_assets)<>initial_count THEN RAISE EXCEPTION 'forged receipt wrote readiness';END IF;
 PERFORM public.copy_blueprint_image_resources_internal(1,(f->>'occasion')::bigint,req->'layout');
 r:=public.update_blueprint_client_sync_v1(req,gen_random_uuid());IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'scoped background save: %',r;END IF;
 actual_revision:=(r#>>'{data,layout_revision}')::bigint;
 req:=jsonb_set(req,'{expected_layout_revision}',to_jsonb(actual_revision));req:=jsonb_set(req,'{seatChanges}','[]');
 FOR variant,expected_reason IN SELECT jsonb_set(bg,'{hash}',to_jsonb(repeat('0',64))),'BLUEPRINT_ASSET_MANIFEST_MISMATCH' UNION ALL SELECT jsonb_set(bg,'{width}',to_jsonb(a.width+1)),'BLUEPRINT_ASSET_MANIFEST_MISMATCH' UNION ALL SELECT jsonb_set(bg,'{crop,width}','1.1'),'BLUEPRINT_INVALID_BACKGROUND_CROP' LOOP
  r:=public.update_blueprint_client_sync_v1(jsonb_set(req,'{layout,background}',variant),gen_random_uuid());
  IF r#>>'{data,reason}'<>expected_reason THEN RAISE EXCEPTION 'invalid background reason %: %',expected_reason,r;END IF;
 END LOOP;
 IF (SELECT layout_revision FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint)<>actual_revision THEN RAISE EXCEPTION 'invalid metadata advanced revision';END IF;
 -- Public form path supplies the same safe manifest without privileged fields.
 public_read:=public.get_blueprint(NULL,(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 IF public_read#>>ARRAY['data','layoutResources','assets',a.asset_ref,'hash'] IS DISTINCT FROM a.hash OR (public_read#>ARRAY['data','layoutResources','assets',a.asset_ref]) ?| ARRAY['organization','occasion','image','proof','state'] THEN RAISE EXCEPTION 'unsafe or incomplete public resource projection';END IF;
 SELECT unit INTO target_unit FROM public.occasions WHERE id=(f->>'occasion')::bigint;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(target_unit,(f->>'actor')::uuid,true) ON CONFLICT(unit,"user") DO UPDATE SET is_manager=true;
 copied:=public.duplicate_occasion_internal_v1((f->>'occasion')::bigint,target_unit,'en');
 SELECT id INTO copied_bp FROM eshop.blueprints WHERE occasion=copied;
 IF (SELECT public.blueprint_layout_resources_internal(layout,copied)#>>ARRAY['assets',a.asset_ref,'hash'] FROM eshop.blueprints WHERE id=copied_bp) IS DISTINCT FROM a.hash THEN RAISE EXCEPTION 'copy missing trusted image resource';END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE blueprint=copied_bp AND (secret IS NOT NULL OR order_product_ticket IS NOT NULL)) THEN RAISE EXCEPTION 'copy retained holds/tickets';END IF;
 BEGIN PERFORM public.authorize_image_deletion(ARRAY[a.url]);RAISE EXCEPTION 'immutable asset deletion allowed';EXCEPTION WHEN insufficient_privilege THEN IF SQLERRM<>'BLUEPRINT_IMAGE_IMMUTABLE' THEN RAISE;END IF;END;
 UPDATE public.occasion_users SET is_editor=false,is_manager=false,is_editor_order=true WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 IF public.get_blueprint_image_upload_access((f->>'occasion')::bigint,'default') THEN RAISE EXCEPTION 'order-only upload geometry access';END IF;
 UPDATE public.occasion_users SET is_editor=false,is_manager=true WHERE occasion=(f->>'occasion')::bigint AND "user"=(f->>'actor')::uuid;
 IF NOT public.get_blueprint_image_upload_access((f->>'occasion')::bigint,'default') THEN RAISE EXCEPTION 'manager image access rejected';END IF;
 -- Wizard uses a genuine unit-owned processed asset before occasion creation.
 SELECT * INTO ua FROM public.blueprint_image_assets WHERE unit IS NOT NULL ORDER BY created_at DESC LIMIT 1;
 IF ua.asset_ref IS NULL THEN RAISE EXCEPTION 'real unit upload required';END IF;
 UPDATE public.occasions SET unit=ua.unit WHERE id=(f->>'occasion')::bigint;
 variant:=jsonb_set(jsonb_set(req->'layout','{background,assetRef}',to_jsonb(ua.asset_ref)),'{background,hash}',to_jsonb(ua.hash));
 variant:=jsonb_set(jsonb_set(variant,'{background,width}',to_jsonb(ua.width)),'{background,height}',to_jsonb(ua.height));
 IF public.blueprint_layout_resources_internal(variant,NULL,ua.unit)#>>ARRAY['assets',ua.asset_ref,'hash'] IS DISTINCT FROM ua.hash THEN RAISE EXCEPTION 'unit private resource absent';END IF;
 PERFORM public.copy_blueprint_unit_image_resources_internal(ua.unit,(f->>'occasion')::bigint,variant);
 PERFORM public.check_blueprint_image_resource_internal(variant,(f->>'occasion')::bigint);
 BEGIN PERFORM public.copy_blueprint_unit_image_resources_internal(ua.unit+100000,(f->>'occasion')::bigint,variant);RAISE EXCEPTION 'foreign unit copy accepted';EXCEPTION WHEN check_violation THEN NULL;END;
 IF has_function_privilege('authenticated','public.copy_blueprint_image_resources_internal(bigint,bigint,jsonb)','EXECUTE') OR has_table_privilege('authenticated','public.blueprint_image_assets','INSERT') THEN RAISE EXCEPTION 'internal resource minting exposed';END IF;
 RAISE NOTICE 'PASS real processed resource: HMAC/stale/foreign/metadata/crop atomic rejection, safe read, immutable delete, trusted copy, role guards';
END $$;
ROLLBACK;
