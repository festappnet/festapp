CREATE OR REPLACE FUNCTION public.get_blueprint_for_authoring_v1(p_blueprint bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; result jsonb;
BEGIN
 SELECT occasion INTO oc FROM eshop.blueprints WHERE id=p_blueprint;
 IF auth.uid() IS NULL OR oc IS NULL OR public.can_read_orders(oc) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order editor view required'; END IF;
 SELECT jsonb_build_object('id',b.id,'occasion',b.occasion,'organization',b.organization,'title',b.title,
  'aggregate_version',coalesce(v.version,0),'configuration',b.configuration,'groups',b.groups,'background_svg',b.background_svg,
  'objects',coalesce((SELECT jsonb_agg(o-ARRAY['secret','secret_expiration_time','order_product_ticket','state']) FROM jsonb_array_elements(b.objects) o),'[]'),
  'spots',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'product',s.product,'title',s.title,
   'occupied',s.order_product_ticket IS NOT NULL,'held',s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()) ORDER BY s.id)
   FROM eshop.spots s WHERE s.blueprint=b.id AND s.occasion=oc),'[]')) INTO result
 FROM eshop.blueprints b LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='blueprint'
 AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=b.id::text WHERE b.id=p_blueprint;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_blueprint_for_authoring_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_blueprint_for_authoring_v1(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_form_for_authoring_v1(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; link text;
BEGIN
 SELECT f.link INTO link FROM public.forms f WHERE f.id=p_form;
 IF link IS NULL THEN RAISE insufficient_privilege USING MESSAGE='form unavailable'; END IF;
 -- Reuse field/product eligibility and permission rules; omit form capabilities.
 result:=public.get_form_for_edit(link);
 IF result->>'code'<>'200' THEN RETURN result; END IF;
 RETURN jsonb_set(result,'{data,form}',(result#>'{data,form}')-ARRAY['key','secret']);
END $$;
REVOKE ALL ON FUNCTION public.get_form_for_authoring_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_form_for_authoring_v1(bigint) TO authenticated;
