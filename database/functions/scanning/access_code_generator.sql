-- One cryptographic five-character sampler for runtime allocation and cutovers.
-- Reservation/collision handling remains at the write boundary and unique index.
CREATE OR REPLACE FUNCTION public.generate_scanner_access_code_internal()
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE candidate text:=''; bytes bytea; ch integer; i integer;
BEGIN
 WHILE length(candidate)<5 LOOP
   bytes:=gen_random_bytes(16);
   FOR i IN 0..15 LOOP
     ch:=get_byte(bytes,i);
     IF ch<252 THEN candidate:=candidate||substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',1+(ch%36),1); END IF;
     EXIT WHEN length(candidate)=5;
   END LOOP;
 END LOOP;
 RETURN candidate;
END $$;
REVOKE ALL ON FUNCTION public.generate_scanner_access_code_internal() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.generate_scanner_access_code_internal() TO postgres;
