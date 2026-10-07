-- Operational measurement only: no persistence, authorization or write routing.
-- Activation of this PostgREST hook is a separately applied operation.
CREATE OR REPLACE FUNCTION public.log_canonical_mutation_request_v1()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
 h jsonb; method text; path text; request_id text; fields jsonb; client_info text[];
BEGIN
 method:=current_setting('request.method',true);
 IF method IS NULL OR method NOT IN ('POST','PATCH','PUT','DELETE') THEN RETURN; END IF;
 path:=current_setting('request.path',true);
 -- Never log query strings, bodies, cookies, arbitrary header values or JWTs.
 IF path IS NULL OR length(path)>180 OR path !~ '^/[a-zA-Z0-9_/.-]+$' THEN path:='unidentified'; END IF;
 BEGIN h:=nullif(current_setting('request.headers',true),'')::jsonb;
 EXCEPTION WHEN invalid_text_representation THEN h:='{}'::jsonb; END;
 client_info:=regexp_match(h->>'x-client-info','^festapp/([0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4})[+]([0-9]{1,10})/(web|pwa|android|ios|js|service|edge|import|cron)$');
 request_id:=gen_random_uuid()::text;
 PERFORM set_config('festapp.mutation_audit_request_id',request_id,true);
 fields:=jsonb_build_object('schemaVersion',1,'event','request','requestId',request_id,
   'pid',pg_backend_pid(),'actor',auth.uid(),'role',current_user,'method',method,'path',path,
   'declaredVersion',client_info[1],'declaredBuild',client_info[2],'declaredPlatform',client_info[3]);
 RAISE LOG 'FESTAPP_MUTATION_OBSERVATION %',fields;
END $$;
REVOKE ALL ON FUNCTION public.log_canonical_mutation_request_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_canonical_mutation_request_v1() TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.log_canonical_mutation_scope_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE request_id text:=nullif(current_setting('festapp.mutation_audit_request_id',true),'');
BEGIN
 -- Called only by the existing owner, with its resolved occasion. A client
 -- cannot supply a scope through this hook or invoke this internal function.
 IF request_id IS NOT NULL THEN
  RAISE LOG 'FESTAPP_MUTATION_OBSERVATION %',jsonb_build_object('schemaVersion',1,
    'event','scope','requestId',request_id,'pid',pg_backend_pid(),'occasion',p_occasion);
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.log_canonical_mutation_scope_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
