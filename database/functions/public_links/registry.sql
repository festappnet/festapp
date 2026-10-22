-- Stable identity reservations survive deletion as tombstones. No application triggers.
CREATE TABLE IF NOT EXISTS public.occasion_link_reservations (
 slug text PRIMARY KEY, occasion bigint REFERENCES public.occasions(id) ON DELETE SET NULL
);
CREATE TABLE IF NOT EXISTS public.form_link_reservations (
 slug text PRIMARY KEY, form bigint REFERENCES public.forms(id) ON DELETE SET NULL
);
-- Frozen bindings for pre-existing cross-tenant duplicates. Their slug remains
-- globally blocked in occasion_link_reservations; new writers never add bindings.
CREATE TABLE IF NOT EXISTS public.legacy_occasion_link_bindings (
 slug text NOT NULL REFERENCES public.occasion_link_reservations(slug),
 organization bigint NOT NULL REFERENCES public.organizations(id),
 occasion bigint REFERENCES public.occasions(id) ON DELETE SET NULL,
 PRIMARY KEY(slug,organization)
);
ALTER TABLE public.legacy_occasion_link_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.legacy_occasion_link_bindings FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.occasion_link_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.form_link_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_link_reservations, public.form_link_reservations FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.resolve_occasion_link_internal(p_slug text,p_organization bigint)
RETURNS bigint LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT coalesce(r.occasion,b.occasion)
 FROM public.occasion_link_reservations r
 LEFT JOIN public.legacy_occasion_link_bindings b
   ON b.slug=r.slug AND b.organization=p_organization
 WHERE r.slug=p_slug;
$$;
CREATE OR REPLACE FUNCTION public.resolve_occasion_link_internal(p_slug text)
RETURNS bigint LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT public.resolve_occasion_link_internal(p_slug,
   (SELECT organization FROM public.user_info WHERE id=auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.resolve_occasion_link_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.resolve_form_link_internal(p_slug text)
RETURNS bigint LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT form FROM public.form_link_reservations WHERE slug=p_slug;
$$;

CREATE OR REPLACE FUNCTION public.random_public_link_internal()
RETURNS text LANGUAGE plpgsql VOLATILE SET search_path = public, extensions AS $$
DECLARE alphabet constant text := '23456789abcdefghjkmnpqrstuvwxyz'; result text := ''; b integer;
BEGIN
 -- Rejection sampling avoids modulo bias (31 symbols).
 WHILE length(result)<8 LOOP
  b := get_byte(extensions.gen_random_bytes(1),0);
  IF b < 248 THEN result := result || substr(alphabet,b % 31 + 1,1); END IF;
 END LOOP;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.occasion_reserved_public_paths_internal()
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
 SELECT ARRAY['resetPassword','forgotPassword','reset-password','forgot-password','login','signup','settings','install','unit','admin','form','order','scan','transfer','app','privacy','terms','support','delete-account','google-auth','assets','icons','flutter','index.html','flutter.html','favicon.ico','manifest.json','robots.txt','version.json','backend-activation.json'];
$$;

CREATE OR REPLACE FUNCTION public.reserve_public_link_internal(p_kind text,p_id bigint,p_slug text,p_create boolean DEFAULT false)
RETURNS text LANGUAGE plpgsql VOLATILE SET search_path = public, extensions AS $$
DECLARE current_slug text; candidate text; owner_id bigint; attempt integer; automatic boolean;
BEGIN
 IF p_kind='occasion' THEN
  SELECT link INTO current_slug FROM public.occasions WHERE id=p_id FOR UPDATE;
 ELSIF p_kind='form' THEN
  SELECT link INTO current_slug FROM public.forms WHERE id=p_id FOR UPDATE;
 ELSE RAISE invalid_parameter_value USING MESSAGE='Invalid public link kind'; END IF;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='Public link target missing'; END IF;
 automatic := p_create AND coalesce(p_slug,'')='';
 IF NOT p_create AND p_slug IS NULL THEN RETURN current_slug; END IF;
 -- Exact legacy no-op before new syntax validation.
 IF NOT p_create AND p_slug=current_slug THEN RETURN current_slug; END IF;
 IF NOT automatic AND (p_slug IS NULL OR length(p_slug)>80 OR p_slug !~ '^[a-z0-9]+([-_][a-z0-9]+)*$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid public link';
 END IF;
 FOR attempt IN 1..20 LOOP
  candidate := CASE WHEN automatic THEN public.random_public_link_internal() ELSE p_slug END;
  IF p_kind='occasion' AND candidate=ANY(public.occasion_reserved_public_paths_internal()) THEN
   RAISE invalid_parameter_value USING MESSAGE='Reserved public link'; END IF;
  -- Unique insert serializes contenders, including historical reservations.
  IF p_kind='occasion' THEN
   INSERT INTO public.occasion_link_reservations(slug,occasion) VALUES(candidate,p_id) ON CONFLICT DO NOTHING;
   SELECT occasion INTO owner_id FROM public.occasion_link_reservations WHERE slug=candidate;
   -- Only an original owner may return to its own grandfathered alias.
   IF owner_id IS NULL AND EXISTS(SELECT 1 FROM public.legacy_occasion_link_bindings
     WHERE slug=candidate AND occasion=p_id) THEN owner_id:=p_id; END IF;
  ELSE
   INSERT INTO public.form_link_reservations(slug,form) VALUES(candidate,p_id) ON CONFLICT DO NOTHING;
   SELECT form INTO owner_id FROM public.form_link_reservations WHERE slug=candidate;
  END IF;
  IF owner_id=p_id THEN
   RETURN candidate;
  END IF;
  IF NOT automatic THEN RAISE unique_violation USING MESSAGE='Public link is already in use'; END IF;
 END LOOP;
 RAISE unique_violation USING MESSAGE='Public link allocation exhausted';
END $$;
REVOKE ALL ON FUNCTION public.resolve_occasion_link_internal(text), public.resolve_form_link_internal(text),
 public.random_public_link_internal(), public.occasion_reserved_public_paths_internal(),
 public.reserve_public_link_internal(text,bigint,text,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- All domain writers are definer RPCs. RLS alone cannot reserve a URL.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON public.forms,public.occasions FROM PUBLIC,anon,authenticated,service_role;
