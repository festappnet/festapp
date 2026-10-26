-- Occasion-shaped released-client adapter; unit ownership is canonical.
CREATE OR REPLACE FUNCTION public.delete_icon_client_sync_v1(p_occasion bigint,p_icon_id bigint,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u bigint; old_receipt jsonb; old_hash text;
BEGIN
 SELECT unit INTO u FROM public.occasions WHERE id=p_occasion;
 IF u IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='occasion unit required'; END IF;
 -- Preserve receipts produced by the former occasion-scoped command.
 IF EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id
   AND command_name='map.icon.delete') THEN
  IF auth.uid() IS NULL OR NOT public.can_write_unit_icons(u) THEN
   RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
  old_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,'iconId',p_icon_id)::text,'UTF8'),'sha256'),'hex');
  old_receipt:=public.begin_client_mutation_v1(p_command_id,'map.icon.delete',p_occasion,auth.uid(),old_hash);
  IF old_receipt->>'disposition'='replay' THEN RETURN old_receipt->'response'; END IF;
  RAISE serialization_failure USING MESSAGE='incomplete legacy icon intent';
 END IF;
 RETURN public.delete_unit_icon_client_sync_v1(u,p_icon_id,p_command_id);
END $$;

REVOKE ALL ON FUNCTION public.delete_icon_client_sync_v1(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_icon_client_sync_v1(bigint,bigint,uuid) TO authenticated;
