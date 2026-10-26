-- The unit context and refresh read share this single authorized projection.
CREATE OR REPLACE FUNCTION public.get_unit_occasion_dashboard_internal(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_org bigint; v_drafts jsonb := '[]'; v_landing jsonb := NULL;
 v_demos jsonb := '{"hasOwnWork":false,"items":[]}';
BEGIN
 IF NOT public.can_read_unit_occasion_catalog(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Unit dashboard access denied';
 END IF;
 SELECT organization INTO v_org FROM public.units WHERE id=p_unit;
 IF public.can_create_occasion(p_unit) THEN
  v_drafts := public.get_occasion_setup_drafts(p_unit);
 END IF;
 IF public.can_read_unit_app_landing(p_unit) THEN
  v_landing := public.get_unit_app_landing(p_unit);
 END IF;
 IF EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=v_org) THEN
  v_demos := public.get_demo_occasions(v_org);
 END IF;
 RETURN jsonb_build_object('unit_id',p_unit,
  'occasions',public.get_all_occasions_for_edit_v212(p_unit),
  'drafts',v_drafts,'app_landing',v_landing,'demo_catalog',v_demos);
END $$;
REVOKE ALL ON FUNCTION public.get_unit_occasion_dashboard_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
