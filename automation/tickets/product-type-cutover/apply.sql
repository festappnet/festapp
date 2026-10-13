-- Included only in the reviewed apply transaction; removed before COMMIT.
CREATE OR REPLACE FUNCTION public.apply_ticket_product_cutover_20261013(p_org bigint,p_rows jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE r jsonb; o public.occasions%ROWTYPE; current_layout jsonb; v bigint; next_features jsonb; commit_data jsonb; catalog_snapshot jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF jsonb_typeof(p_rows)<>'array' OR jsonb_array_length(p_rows)=0 OR (SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(p_rows) x)<>jsonb_array_length(p_rows) THEN RAISE EXCEPTION 'Invalid cutover manifest'; END IF;
  IF (SELECT count(*) FROM public.occasions scope WHERE organization=p_org AND EXISTS(SELECT 1 FROM jsonb_array_elements(scope.features) f WHERE f->>'code'='ticket'))<>jsonb_array_length(p_rows) THEN RAISE EXCEPTION 'Cutover scope changed'; END IF;
  -- Lock the entire manifest and validate every row before the first write.
  FOR r IN SELECT * FROM jsonb_array_elements(p_rows) ORDER BY (value->>'id')::bigint LOOP
    SELECT * INTO STRICT o FROM public.occasions WHERE id=(r->>'id')::bigint AND organization=p_org FOR UPDATE;
    PERFORM public.validate_ticket_layout_references(o.id,r->'layout');
    SELECT f->'layout' INTO current_layout FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket';
    IF current_layout=r->'layout' THEN CONTINUE; END IF;
    SELECT COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='occasion' AND scope_type='occasion' AND scope_id=o.id AND aggregate_id=o.id::text),0) INTO v;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pt.id,'type',pt.type,
      'form_references',(SELECT count(*) FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form WHERE ff.product_type=pt.id AND f.occasion=o.id),
      'ordered_count',(SELECT count(*) FROM eshop.products p JOIN eshop.order_product_ticket opt ON opt.product=p.id WHERE p.product_type=pt.id)) ORDER BY pt.id),'[]')
      INTO catalog_snapshot FROM eshop.product_types pt WHERE pt.occasion=o.id;
    IF catalog_snapshot IS DISTINCT FROM r->'product_types' THEN RAISE EXCEPTION 'Ticket cutover catalog conflict: %',o.id; END IF;
    IF md5(o.features::text)<>r->>'features_hash' OR v<>(r->>'version')::bigint THEN RAISE EXCEPTION 'Ticket cutover conflict: %',o.id; END IF;
  END LOOP;
  FOR r IN SELECT * FROM jsonb_array_elements(p_rows) ORDER BY (value->>'id')::bigint LOOP
    SELECT * INTO STRICT o FROM public.occasions WHERE id=(r->>'id')::bigint;
    SELECT f->'layout' INTO current_layout FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket';
    IF current_layout=r->'layout' THEN CONTINUE; END IF;
    SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN f||jsonb_build_object('layout',r->'layout') ELSE f END ORDER BY n) INTO next_features FROM jsonb_array_elements(o.features) WITH ORDINALITY x(f,n);
    UPDATE public.occasions SET features=next_features,updated_at=clock_timestamp() WHERE id=o.id;
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version) VALUES('occasion','occasion',o.id,o.id::text,1)
    ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
    commit_data:=public.record_client_sync_commit_v1(o.id,'ticket.product-type-cutover','configuration',jsonb_build_array(jsonb_build_object('entityType','occasion','entityId',o.id,'operation','update','changedFields',jsonb_build_array('ticket.layout'))),ARRAY['occasion_config'],'[]','[]','service',jsonb_build_object('before',r->>'features_hash','after',md5((r->'layout')::text))::text);
    IF NOT o.is_hidden THEN PERFORM public.fanout_unit_catalog_v1((commit_data->>'commitId')::uuid,o.unit); END IF;
  END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.apply_ticket_product_cutover_20261013(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.apply_ticket_product_cutover_20261013(bigint,jsonb) TO service_role;
