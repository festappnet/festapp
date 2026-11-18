-- Identifiers are validated independently of the consent gate at capture.
CREATE OR REPLACE FUNCTION public.meta_purchase_browser_id_internal(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public AS $$
 SELECT CASE WHEN length(p_value)<=1024 AND p_value !~ '[[:cntrl:]]'
  -- PostgreSQL caps regex repetition at 255; the click ID length is checked separately.
  AND p_value ~ '^fb\.[0-9]{1,3}\.[0-9]{13}\.[A-Za-z0-9_-]+$' AND length(split_part(p_value,'.',4))<=500 THEN p_value END;
$$;
REVOKE ALL ON FUNCTION public.meta_purchase_browser_id_internal(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.meta_purchase_ip_internal(p_value text)
RETURNS inet LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE address inet;
BEGIN
 IF p_value IS NULL OR length(p_value)>45 OR p_value !~ '^[0-9a-fA-F:.]+$' THEN RETURN NULL; END IF;
 IF position(':' IN p_value)=0 AND p_value !~ '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' THEN RETURN NULL; END IF;
 BEGIN address:=p_value::inet; EXCEPTION WHEN invalid_text_representation THEN RETURN NULL; END;
 IF masklen(address) NOT IN (32,128) THEN RETURN NULL; END IF;
 RETURN address;
END $$;
REVOKE ALL ON FUNCTION public.meta_purchase_ip_internal(text) FROM PUBLIC,anon,authenticated,service_role;

-- Keep digits only for Meta hashing, without a leading plus. Form prefixes
-- resolve national numbers; CZ is the fallback when no single prefix is saved.
CREATE OR REPLACE FUNCTION public.meta_purchase_phone_internal(p_value text,p_prefix text DEFAULT '+420')
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE phone text;
BEGIN
 IF p_value IS NULL OR length(p_value)>100 OR p_value !~ '^[+0-9 ().-]+$' OR p_value LIKE '%(0)%' THEN RETURN NULL; END IF;
 phone:=regexp_replace(btrim(p_value),'[ ().-]','','g');
 IF phone LIKE '00%' THEN phone:='+'||substr(phone,3); END IF;
 IF phone NOT LIKE '+%' THEN
  IF phone ~ '^(420|421)[0-9]{9}$' THEN phone:='+'||phone;
  ELSIF p_prefix ~ '^\+[1-9][0-9]{0,3}$' THEN
   -- National trunk 0 is dropped (030..., 0903...), except Italy, which keeps it.
   IF p_prefix<>'+39' AND phone ~ '^0[1-9]' THEN phone:=substr(phone,2); END IF;
   phone:=p_prefix||phone;
  ELSE RETURN NULL; END IF;
 END IF;
 IF phone !~ '^\+[1-9][0-9]{7,14}$' THEN RETURN NULL; END IF;
 IF phone ~ '^\+(420|421)' AND phone !~ '^\+(420|421)[1-9][0-9]{8}$' THEN RETURN NULL; END IF;
 RETURN substr(phone,2);
END $$;
REVOKE ALL ON FUNCTION public.meta_purchase_phone_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;
