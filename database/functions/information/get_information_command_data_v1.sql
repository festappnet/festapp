CREATE OR REPLACE FUNCTION public.get_information_command_data_v1(p_information_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
  SELECT to_jsonb(i)||jsonb_build_object('information_hidden',CASE
    WHEN ih.id IS NULL THEN NULL ELSE jsonb_build_object('id',ih.id,'data',ih.data) END)
  FROM public.information i LEFT JOIN public.information_hidden ih
    ON ih.id=i.information_hidden WHERE i.id=p_information_id;
$function$
;
REVOKE ALL ON FUNCTION public.get_information_command_data_v1(p_information_id bigint) FROM PUBLIC,anon,authenticated;
