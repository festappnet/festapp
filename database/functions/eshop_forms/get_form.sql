CREATE OR REPLACE FUNCTION public.get_form(form_key uuid)
RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE link text;
BEGIN
 SELECT f.link INTO link FROM public.forms f WHERE key=form_key;
 IF link IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form not found'); END IF;
 RETURN public.get_form_by_link(link);
END $$;
