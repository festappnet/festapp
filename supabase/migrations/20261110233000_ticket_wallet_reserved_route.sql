-- Reserve the Wallet landing page in the canonical public-link namespace.
-- SOURCE: public_links/reserved_paths.sql
-- Shared roots must never become occasion slugs.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.occasion_link_reservations WHERE slug IN ('stripe','payments','wallet') AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.legacy_occasion_link_bindings WHERE slug IN ('stripe','payments','wallet') AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.occasions WHERE link IN ('stripe','payments','wallet')) THEN
  RAISE EXCEPTION 'Private route conflicts with an existing occasion slug';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.occasion_reserved_public_paths_internal()
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
 SELECT ARRAY['resetPassword','forgotPassword','reset-password','forgot-password','login','signup','settings','install','unit','admin','form','order','scan','transfer','app','privacy','terms','support','delete-account','google-auth','stripe','payments','wallet','assets','icons','flutter','index.html','flutter.html','favicon.ico','manifest.json','robots.txt','version.json','backend-activation.json'];
$$;

REVOKE ALL ON FUNCTION public.occasion_reserved_public_paths_internal() FROM PUBLIC,anon,authenticated,service_role;

NOTIFY pgrst, 'reload schema';
