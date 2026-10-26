-- Quiet upgrade baseline without enabling, disabling or changing activation generation.
DO $$ DECLARE a record; f record; baseline_at timestamptz:=clock_timestamp(); BEGIN
 FOR a IN SELECT organization FROM public.notification_center_organizations ORDER BY organization LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('notification-center-organization:'||a.organization,0));
  FOR f IN SELECT forms.id FROM public.forms JOIN public.occasions oc ON oc.id=forms.occasion WHERE oc.organization=a.organization ORDER BY forms.id LOOP
   PERFORM public.notification_center_form_availability_internal(f.id,baseline_at,NULL,true);
  END LOOP;
 END LOOP;
END $$;
