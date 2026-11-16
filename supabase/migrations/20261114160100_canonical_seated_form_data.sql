-- Canonicalize the eight reviewed vstupenky.online seated forms. No product,
-- price, blueprint, order or ticket is rewritten. The common guard stays strict.
DO $$
DECLARE form_ids bigint[]; occasions bigint[]; item record;
BEGIN
 SELECT array_agg(f.id ORDER BY f.id),array_agg(DISTINCT f.occasion ORDER BY f.occasion)
 INTO form_ids,occasions FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN (VALUES (58,'PlesAKH2025'),(60,'new-form2026-test'),(64,'farni-ples-2026-cernobily'),
   (73,'myfestival2025'),(75,'ples2026'),(568,'4aa0bcbb7d114ceb9f07762cc8660c1b'),
   (583,'farni-ples-2027'),(638,'5tc4bfvv')) reviewed(id,link) ON reviewed.id=f.id AND reviewed.link=f.link
 WHERE o.organization=3 AND EXISTS(SELECT 1 FROM public.form_fields ff
   JOIN eshop.product_types pt ON pt.id=ff.product_type WHERE ff.form=f.id AND pt.type='spot' AND ff.is_hidden);
 IF form_ids IS NULL THEN RETURN; END IF;
 PERFORM public.lock_blueprint_scope_internal(occasions);
 PERFORM 1 FROM public.forms WHERE id=ANY(form_ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.product_types WHERE id IN(SELECT product_type FROM public.form_fields WHERE form=ANY(form_ids)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.form_fields WHERE form=ANY(form_ids) ORDER BY id FOR UPDATE;
 -- Fail closed if these reviewed forms are no longer using a real saved plan.
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=ANY(form_ids)
   AND (NOT EXISTS(SELECT 1 FROM eshop.blueprints b WHERE b.id=f.blueprint AND b.occasion=f.occasion)
     OR NOT jsonb_path_exists(o.features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
     OR NOT EXISTS(SELECT 1 FROM public.form_fields s WHERE s.form=f.id AND s.type='spot' AND s.is_ticket_field AND NOT s.is_hidden))) THEN
   RAISE EXCEPTION 'Reviewed seated form configuration changed'; END IF;
 FOR item IN SELECT ff.* FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
   WHERE ff.form=ANY(form_ids) AND ff.type='product_type' AND ff.is_ticket_field AND ff.is_hidden AND pt.type='spot'
     AND NOT EXISTS(SELECT 1 FROM eshop.products p WHERE p.product_type=pt.id)
 LOOP
   -- There are two reviewed obsolete fields. Never infer permission to remove
   -- another field or any saved answer/scanner configuration.
   IF item.id NOT IN(604,3404)
     OR EXISTS(SELECT 1 FROM eshop.orders q WHERE q.form=item.form AND q.data::text LIKE '%"'||item.id||'"%')
     OR EXISTS(SELECT 1 FROM eshop.tickets t JOIN eshop.order_product_ticket opt ON opt.ticket=t.id
       JOIN eshop.orders q ON q.id=opt."order" WHERE q.form=item.form AND t.data::text LIKE '%"'||item.id||'"%')
     OR EXISTS(SELECT 1 FROM public.scanner_settings s WHERE s.config::text ~ ('(^|[^0-9])'||item.id||'([^0-9]|$)')) THEN
     RAISE EXCEPTION 'Obsolete primary field has unreviewed usage'; END IF;
   DELETE FROM public.form_fields WHERE id=item.id;
 END LOOP;
 UPDATE public.form_fields ff SET is_hidden=false FROM eshop.product_types pt
 WHERE ff.form=ANY(form_ids) AND ff.product_type=pt.id AND pt.type='spot'
   AND ff.type='product_type' AND ff.is_ticket_field AND ff.is_hidden;
 FOR item IN SELECT f.id,f.occasion FROM public.forms f WHERE f.id=ANY(form_ids) LOOP
   PERFORM public.assert_form_primary_products_internal(item.id);
   INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
   VALUES('form','occasion',item.occasion,item.id::text,1)
   ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
   SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 END LOOP;
 RAISE NOTICE 'Canonicalized % reviewed seated forms',cardinality(form_ids);
END $$;
