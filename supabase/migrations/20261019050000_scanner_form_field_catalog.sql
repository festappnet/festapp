-- Source: database/functions/scanning/settings.sql (get_scanner_settings)
CREATE OR REPLACE FUNCTION public.get_scanner_settings(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_settings;
BEGIN
 PERFORM public.scanner_require_settings_editor_internal(p_occasion);
 INSERT INTO public.scanner_settings(occasion_id,config) VALUES(p_occasion,public.scanner_default_settings_internal(p_occasion)) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM public.scanner_settings WHERE occasion_id=p_occasion;
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object('revision',s.revision,'config',s.config,
 'occasion_link',(SELECT link FROM public.occasions WHERE id=p_occasion),'occasion_title',(SELECT title FROM public.occasions WHERE id=p_occasion),
 'products',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'type_id',p.product_type,'type_title',pt.title) ORDER BY p."order",p.id),'[]'::jsonb) FROM eshop.products p LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.occasion=p_occasion),
 'fields',(SELECT coalesce(jsonb_agg(jsonb_build_object('field_id',ff.id,'form_id',ff.form,'label',ff.title,'type',ff.type,'form_title',coalesce(nullif(btrim(fm.title),''),fm.link),'source',CASE WHEN ff.is_ticket_field THEN 'ticket_field' ELSE 'order_field' END) ORDER BY fm.id,ff."order",ff.id),'[]'::jsonb)
 FROM public.form_fields ff JOIN public.forms fm ON fm.id=ff.form
 WHERE fm.occasion=p_occasion AND NOT ff.is_hidden
 -- Identity, notes, seats and purchased products already have dedicated presentation.
 AND ff.type IN ('text','email','phone','city','birth_year','birth_date','address','nationality','sex','id_document','select_one','select_many')
 AND (NOT ff.is_ticket_field OR EXISTS(SELECT 1 FROM public.form_fields parent WHERE parent.form=fm.id AND parent.type='ticket' AND NOT parent.is_hidden)))),'server_time',now());
END $$;
