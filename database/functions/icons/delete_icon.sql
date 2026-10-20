-- Legacy unit-editor facade, previously missing from the reproducible baseline.
-- Organization-owned historic icons remain read-only; never bind them to an arbitrary occasion.
CREATE OR REPLACE FUNCTION public.delete_icon(p_icon_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u bigint; r jsonb;
BEGIN
 SELECT unit INTO u FROM public.icons WHERE id=p_icon_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',200); END IF;
 IF u IS NULL OR auth.uid() IS NULL OR NOT public.get_is_editor_on_unit(u) THEN RETURN jsonb_build_object('code',403); END IF;
 r:=public.delete_unit_icon_client_sync_v1(u,p_icon_id,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',r->'code','refs',r#>'{data,refs}');
END $$;

REVOKE ALL ON FUNCTION public.delete_icon(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_icon(bigint) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.icons FROM anon,authenticated;
