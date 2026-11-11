-- Rebuild retained projections so participant history and badges follow app support.
-- Source events and personal read receipts remain audit history.
DO $$ DECLARE item record; BEGIN
 FOR item IN SELECT e.id FROM public.notification_center_events e
 JOIN public.organizations org ON org.id=e.organization
 WHERE e.kind='occasion_joined' AND org.data->>'IS_APP_SUPPORTED' IS DISTINCT FROM 'true'
 LOOP PERFORM public.notification_center_prepared_invalidate(item.id); END LOOP;
END $$;
