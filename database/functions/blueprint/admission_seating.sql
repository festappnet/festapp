-- Applied by every materializer, including stale/editor/direct callers.
CREATE OR REPLACE FUNCTION public.assert_admission_seating_internal(p_form bigint,p_product bigint,p_spot bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE bp bigint; bound_bp bigint;
BEGIN
 SELECT f.blueprint INTO bp FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form
 AND jsonb_path_exists(o.features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)');
 SELECT min(f.blueprint) INTO bound_bp FROM public.forms f JOIN public.occasions owner ON owner.id=f.occasion
 JOIN eshop.spots s ON s.blueprint=f.blueprint AND s.product=p_product JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
 WHERE jsonb_path_exists(owner.features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)');
 IF bound_bp IS NOT NULL AND (bp IS DISTINCT FROM bound_bp OR p_spot IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.spots WHERE id=p_spot AND blueprint=bp AND product=p_product)) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
 IF bp IS NOT NULL AND p_spot IS NULL AND EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id WHERE sb.blueprint=bp AND s.product=p_product)
 AND NOT EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings WHERE blueprint=bp AND product=p_product) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_admission_seating_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_form_seating_source_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.form_fields ff ON ff.form=f.id AND NOT ff.is_hidden
 JOIN eshop.products p ON p.product_type=ff.product_type AND NOT p.is_hidden
 JOIN eshop.spots s ON s.product=p.id JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id
 JOIN public.forms bound ON bound.blueprint=sb.blueprint JOIN public.occasions owner ON owner.id=bound.occasion
 WHERE f.id=p_form AND f.is_open AND jsonb_path_exists(owner.features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)') AND f.blueprint IS DISTINCT FROM bound.blueprint) THEN RAISE EXCEPTION 'ADMISSION_SOURCE_REQUIRES_SEATING'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_form_seating_source_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
