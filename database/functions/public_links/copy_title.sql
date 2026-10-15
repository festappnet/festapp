CREATE OR REPLACE FUNCTION public.copy_occasion_title_internal(p_title text,p_locale text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE suffix text; base text := coalesce(p_title,'');
BEGIN
 suffix := CASE split_part(replace(lower(coalesce(p_locale,'en')),'_','-'),'-',1)
  WHEN 'cs' THEN 'kopie' WHEN 'sk' THEN 'kópia' WHEN 'de' THEN 'kopie'
  WHEN 'pl' THEN 'kopia' WHEN 'uk' THEN 'копія' ELSE 'copy' END;
 base := regexp_replace(base, '(\s*\((copy|kopie|kópia|kopia|копія)\))+$', '', 'i');
 RETURN left(rtrim(base),500-length(suffix)-3) || ' (' || suffix || ')';
END $$;
REVOKE ALL ON FUNCTION public.copy_occasion_title_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;
