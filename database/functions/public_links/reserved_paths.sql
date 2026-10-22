-- Shared roots must never become occasion slugs.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.occasion_link_reservations WHERE slug='stripe' AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.legacy_occasion_link_bindings WHERE slug='stripe' AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.occasions WHERE link='stripe') THEN
  RAISE EXCEPTION 'Stripe route conflicts with an existing occasion slug';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.occasion_reserved_public_paths_internal()
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
 SELECT ARRAY['resetPassword','forgotPassword','reset-password','forgot-password','login','signup','settings','install','unit','admin','form','order','scan','transfer','app','privacy','terms','support','delete-account','google-auth','stripe','assets','icons','flutter','index.html','flutter.html','favicon.ico','manifest.json','robots.txt','version.json','backend-activation.json'];
$$;

REVOKE ALL ON FUNCTION public.occasion_reserved_public_paths_internal() FROM PUBLIC,anon,authenticated,service_role;
