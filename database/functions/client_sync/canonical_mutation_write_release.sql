-- Operational release policy, writable only by its SQL owner. No client DML.
CREATE TABLE public.canonical_mutation_write_release_gate(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 paused boolean NOT NULL,
 minimum_build bigint NOT NULL CHECK(minimum_build BETWEEN 1 AND 999999999)
);
REVOKE ALL ON TABLE public.canonical_mutation_write_release_gate FROM PUBLIC,anon,authenticated,service_role;

-- Header metadata never grants domain permissions. Absent policy preserves
-- additive compatibility until the explicitly authorized shared write fence.
-- Release eligibility is global; each command still derives domain permissions
-- from its actual occasion. New organizations need no release allowlist entry.
CREATE OR REPLACE FUNCTION public.assert_canonical_mutation_write_release_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE gate public.canonical_mutation_write_release_gate%ROWTYPE;
 client_build text; headers jsonb;
BEGIN
 SELECT * INTO gate FROM public.canonical_mutation_write_release_gate WHERE singleton FOR SHARE;
 IF NOT FOUND THEN RETURN; END IF;
 -- Preserve existing SQL operator/cron and signed service lanes. This grants no
 -- actor permission: the typed command still performs its own auth checks.
 IF (nullif(current_setting('request.method',true),'') IS NULL
 AND session_user IN ('postgres','supabase_admin')) OR auth.role()='service_role' THEN RETURN; END IF;
 BEGIN
  headers:=COALESCE(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
  client_build:=substring(headers->>'x-client-info' FROM '^festapp/[0-9]+\.[0-9]+\.[0-9]+\+([0-9]{1,9})/(?:web|android|ios|macos|windows|linux|fuchsia|js|service)$');
 EXCEPTION WHEN OTHERS THEN
  RAISE insufficient_privilege USING MESSAGE='canonical editor requires valid release metadata';
 END;
 IF gate.paused OR client_build IS NULL OR client_build::bigint<gate.minimum_build
 OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='canonical editor requires an enabled current release';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_canonical_mutation_write_release_internal_v1(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
