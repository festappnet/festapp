-- Syntax only. Conformance cases are shared with Dart and JavaScript.
CREATE OR REPLACE FUNCTION public.email_address_is_valid(p_email text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE SECURITY INVOKER
SET search_path=pg_catalog AS $email$
DECLARE parts text[]; labels text[]; label text;
BEGIN
 IF p_email IS NULL OR length(p_email)>254 OR p_email ~ '[[:space:]]' THEN RETURN false; END IF;
 parts:=string_to_array(p_email,'@');
 IF cardinality(parts)<>2 OR length(parts[1]) NOT BETWEEN 1 AND 64
 OR parts[1] !~ '^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+$'
 OR left(parts[1],1)='.' OR right(parts[1],1)='.' OR strpos(parts[1],'..')>0 THEN RETURN false; END IF;
 labels:=string_to_array(parts[2],'.');
 IF cardinality(labels)<2 OR labels[cardinality(labels)] ~ '^[0-9]+$' THEN RETURN false; END IF;
 FOREACH label IN ARRAY labels LOOP
  IF label !~ '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$' THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END $email$;
REVOKE ALL ON FUNCTION public.email_address_is_valid(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_address_is_valid(text) TO anon,authenticated,service_role;
