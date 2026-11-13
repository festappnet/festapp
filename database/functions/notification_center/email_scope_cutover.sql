-- Production inventory found zero per-occasion overrides. Never silently lose
-- an override if a released client creates one before this guarded cutover.
LOCK TABLE public.notification_center_email_subscriptions IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.notification_center_email_subscriptions WHERE occasion IS NOT NULL) THEN
  RAISE EXCEPTION 'notification_email_occasion_overrides_require_resolution';
 END IF;
END $$;
ALTER TABLE public.notification_center_email_subscriptions DROP COLUMN occasion;
ALTER TABLE public.notification_center_email_subscriptions ADD PRIMARY KEY(recipient,organization);
