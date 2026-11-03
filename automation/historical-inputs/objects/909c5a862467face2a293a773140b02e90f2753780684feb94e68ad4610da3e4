CREATE OR REPLACE FUNCTION public.get_occasion_user_command_data_v1(p_occasion bigint, p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
  SELECT to_jsonb(ou)||jsonb_build_object('profile',jsonb_build_object(
    'id',ui.id,'email',ui.email_readonly,'name',ui.name,'surname',ui.surname,
    'sex',ui.sex,'phone',ui.phone,'birthDate',ui.birth_date,'data',ui.data))
  FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user"
  WHERE ou.occasion=p_occasion AND ou."user"=p_user;
$function$
;
REVOKE ALL ON FUNCTION public.get_occasion_user_command_data_v1(p_occasion bigint, p_user uuid) FROM PUBLIC,anon,authenticated;
