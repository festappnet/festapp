-- Forward migration only: rebuild disposable presentation groups in bounded
-- worker passes. Canonical delivery facts and read receipts remain untouched.
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM public.notification_center_projection_scopes WHERE organization<>3) THEN
  RAISE EXCEPTION 'notification_history_cutover_unapproved_organization';
 END IF;
 DELETE FROM public.notification_center_views WHERE organization=3;
 UPDATE public.notification_center_projection_scopes
 SET revision=revision+1, build_revision=revision+1, phase='clear_members',
     work_requested=true, next_check_at='-infinity', retry_count=0,
     quarantined=false, last_error_code=NULL, failed_event=NULL
 WHERE organization=3;
END $$;
