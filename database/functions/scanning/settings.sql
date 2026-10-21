-- Same-occasion editing rights only; a scan code never grants configuration access.
CREATE OR REPLACE FUNCTION public.scanner_can_manage_settings_internal(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND (public.get_is_editor_on_occasion(p_occasion) OR public.get_is_editor_order_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.scanner_can_manage_settings_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.scanner_require_settings_editor_internal(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.scanner_can_manage_settings_internal(p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='scanner_settings_forbidden';
 END IF;
 PERFORM public.check_occasion_writable(p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.scanner_require_settings_editor_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.scanner_default_settings_internal(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('schema_version',1,'products',jsonb_build_object('mode','all','ids','[]'::jsonb,'order','[]'::jsonb),
 'fields','[]'::jsonb,
 'manual_search',jsonb_build_object('tickets',coalesce((feature->>'can_scan_manually')::boolean,false),'users',EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion)),
 'sensitive',jsonb_build_object('price',true,'hidden_note',coalesce((feature->>'show_hidden_note')::boolean,false)),
 'admission',jsonb_build_object('allow_unpaid_online',true,'allow_unpaid_offline',false),
 'offline',jsonb_build_object('enabled',true,'max_hours',12))
 FROM public.occasions o LEFT JOIN LATERAL (SELECT e feature FROM jsonb_array_elements(o.features) e WHERE e->>'code'='ticket' LIMIT 1) x ON true WHERE o.id=p_occasion;
$$;
CREATE OR REPLACE FUNCTION public.scanner_validate_settings_internal(p_occasion bigint,p_config jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE f jsonb; n bigint;
BEGIN
 IF p_config IS NULL OR octet_length(p_config::text)>32768 OR p_config->>'schema_version' IS DISTINCT FROM '1'
 OR coalesce(p_config#>>'{products,mode}','') NOT IN ('all','none','selected')
 OR jsonb_typeof(p_config#>'{products,ids}') IS DISTINCT FROM 'array'
 OR jsonb_typeof(p_config#>'{products,order}') IS DISTINCT FROM 'array'
 OR jsonb_typeof(p_config->'fields') IS DISTINCT FROM 'array'
 OR jsonb_array_length(p_config->'fields')>40
 OR coalesce((p_config#>>'{offline,max_hours}')::numeric,0) NOT BETWEEN 0 AND 12
 OR coalesce((p_config#>>'{admission,allow_unpaid_offline}')::boolean,true)

 THEN RAISE invalid_parameter_value USING MESSAGE='invalid_scanner_settings'; END IF;
 IF (SELECT count(*)<>count(DISTINCT value) FROM jsonb_array_elements(p_config#>'{products,ids}'))
 OR (SELECT count(*)<>count(DISTINCT value) FROM jsonb_array_elements(p_config#>'{products,order}')) THEN RAISE invalid_parameter_value USING MESSAGE='duplicate_product'; END IF;
 FOR n IN SELECT value::text::bigint FROM jsonb_array_elements(p_config#>'{products,ids}') LOOP
  IF NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=n AND occasion=p_occasion) THEN RAISE invalid_parameter_value USING MESSAGE='foreign_product'; END IF;
 END LOOP;
 FOR n IN SELECT value::text::bigint FROM jsonb_array_elements(p_config#>'{products,order}') LOOP
  IF NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=n AND occasion=p_occasion) THEN RAISE invalid_parameter_value USING MESSAGE='foreign_product'; END IF;
 END LOOP;
 IF (SELECT count(*)<>count(DISTINCT e->>'key') FROM jsonb_array_elements(p_config->'fields') e) THEN RAISE invalid_parameter_value USING MESSAGE='duplicate_field'; END IF;
 FOR f IN SELECT * FROM jsonb_array_elements(p_config->'fields') LOOP
  IF f->>'source'='builtin' THEN
   IF f->>'key' NOT IN ('holder_name','spot','groups','note') THEN RAISE invalid_parameter_value USING MESSAGE='invalid_builtin'; END IF;
  ELSIF f->>'source' IN ('order_field','ticket_field') THEN
   IF f->>'key' IS DISTINCT FROM (CASE f->>'source' WHEN 'order_field' THEN 'order' ELSE 'ticket' END)||':'||(f->>'form_id')||':'||(f->>'field_id')
   OR NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN public.forms fm ON fm.id=ff.form
    WHERE ff.id=(f->>'field_id')::bigint AND ff.form=(f->>'form_id')::bigint AND fm.occasion=p_occasion
    AND ff.is_ticket_field=(f->>'source'='ticket_field')) THEN RAISE invalid_parameter_value USING MESSAGE='foreign_field'; END IF;
  ELSE RAISE invalid_parameter_value USING MESSAGE='invalid_field_source'; END IF;
 END LOOP;
END $$;
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
CREATE OR REPLACE FUNCTION public.update_scanner_settings(p_occasion bigint,p_expected_revision bigint,p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_settings;
BEGIN
 PERFORM public.scanner_require_settings_editor_internal(p_occasion); PERFORM public.check_occasion_writable(p_occasion);
 PERFORM public.scanner_validate_settings_internal(p_occasion,p_config);
 SELECT * INTO s FROM public.scanner_settings WHERE occasion_id=p_occasion FOR UPDATE;
 IF NOT FOUND OR s.revision IS DISTINCT FROM p_expected_revision THEN RETURN jsonb_build_object('code',409,'reason','settings_changed','server_time',now()); END IF;
 UPDATE public.scanner_settings SET config=p_config,revision=revision+1,
 epoch=epoch+CASE WHEN (config-'fields'-'products') IS DISTINCT FROM (p_config-'fields'-'products') OR config->'products' IS DISTINCT FROM p_config->'products'
 OR (SELECT coalesce(jsonb_agg(f-'label'-'default_visible'-'hide_empty' ORDER BY f->>'key'),'[]'::jsonb) FROM jsonb_array_elements(config->'fields') f)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(f-'label'-'default_visible'-'hide_empty' ORDER BY f->>'key'),'[]'::jsonb) FROM jsonb_array_elements(p_config->'fields') f) THEN 1 ELSE 0 END,
 updated_at=now(),updated_by=auth.uid() WHERE occasion_id=p_occasion;
 RETURN public.get_scanner_settings(p_occasion);
END $$;
