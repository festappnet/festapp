-- Seed the new due time for already initialized notification projections.
DO $$
DECLARE tenant record; form record; baseline_at timestamptz;
BEGIN
 FOR tenant IN SELECT organization FROM public.notification_center_organizations ORDER BY organization LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('notification-center-organization:'||tenant.organization,0));
  IF NOT public.notification_center_initialized_internal(tenant.organization) THEN CONTINUE; END IF;
  baseline_at:=clock_timestamp();
  FOR form IN
   SELECT f.id FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
   WHERE o.organization=tenant.organization
     AND public.normalize_form_metadata_internal(f.data)#>>'{schedule,end_time}' IS NULL
   ORDER BY f.id
  LOOP
   PERFORM public.notification_center_form_availability_internal(form.id,baseline_at,NULL,true);
  END LOOP;
 END LOOP;
END $$;
