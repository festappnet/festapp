-- One business-data seeder, with explicit locale presentation inputs.
-- These maintenance helpers exist only for this psql session.
CREATE OR REPLACE FUNCTION pg_temp.demo_locale_text(value text, translations jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE item record; result text := value;
BEGIN
 IF value IS NULL THEN RETURN NULL; END IF;
 FOR item IN SELECT key, val FROM jsonb_each_text(translations) t(key,val)
  ORDER BY length(key) DESC, key LOOP
  result := replace(result,item.key,item.val);
 END LOOP;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.demo_locale_json(value jsonb, translations jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 CASE jsonb_typeof(value)
 WHEN 'string' THEN RETURN to_jsonb(pg_temp.demo_locale_text(value#>>'{}',translations));
 WHEN 'array' THEN RETURN coalesce((SELECT jsonb_agg(pg_temp.demo_locale_json(v,translations) ORDER BY n)
  FROM jsonb_array_elements(value) WITH ORDINALITY a(v,n)),'[]'::jsonb);
 WHEN 'object' THEN RETURN coalesce((SELECT jsonb_object_agg(pg_temp.demo_locale_text(k,translations),
  pg_temp.demo_locale_json(v,translations)) FROM jsonb_each(value) a(k,v)),'{}'::jsonb);
 ELSE RETURN value;
 END CASE;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.seed_demo_occasions_localized(p_org bigint,p_locale text)
RETURNS void LANGUAGE plpgsql AS $localized$
DECLARE inputs jsonb; translations jsonb; demo_row record; existing integer;
BEGIN
 IF current_user<>'postgres' THEN RAISE insufficient_privilege; END IF;
 SELECT payload INTO STRICT inputs FROM pg_temp.demo_locale_inputs WHERE locale=p_locale;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_org) THEN
  RAISE EXCEPTION 'Missing explicit target organization';
 END IF;
 PERFORM pg_advisory_xact_lock(7141014,p_org::integer);
 IF p_locale='cs' THEN
  IF EXISTS(SELECT 1 FROM public.demo_occasions d JOIN public.occasions o ON o.id=d.occasion
    WHERE d.organization=p_org AND o.data->>'demo_locale' IS NOT NULL AND o.data->>'demo_locale'<>'cs') THEN
   RAISE EXCEPTION 'Existing demos belong to another locale';
  END IF;
  PERFORM pg_temp.seed_demo_occasions(p_org);
  RETURN;
 END IF;
 SELECT count(*) INTO existing FROM public.demo_occasions WHERE organization=p_org;
 IF existing<>0 THEN
  IF existing=3 AND (SELECT count(*) FROM public.demo_occasions d JOIN public.occasions o ON o.id=d.occasion
    WHERE d.organization=p_org AND d.fixture_version='2026-10-14.3' AND o.data->>'demo_locale'=p_locale)=3 THEN
   PERFORM pg_temp.ensure_demo_public_links(p_org);
   RETURN; -- Replay repairs URL claims without creating or rewriting examples.
  END IF;
  RAISE EXCEPTION 'Existing or incomplete demo fixtures require investigation';
 END IF;
 translations:=inputs->'translations';
 IF translations IS NULL THEN RAISE EXCEPTION 'Missing presentation inputs'; END IF;
 UPDATE pg_temp.demo_ticket_layouts SET content=pg_temp.demo_locale_json(content,translations);
 -- The identical seat, inventory, order, ticket and payment rules build both locales.
 PERFORM pg_temp.seed_demo_occasions(p_org);
 FOR demo_row IN SELECT registry.*,o.unit FROM public.demo_occasions registry
  JOIN public.occasions o ON o.id=registry.occasion
  WHERE registry.organization=p_org AND registry.fixture_version='2026-10-14.3' ORDER BY registry.sort_order LOOP
  UPDATE public.units SET title=inputs->>'organizer'
   WHERE id=demo_row.unit AND organization=p_org;
  UPDATE public.occasions SET title=inputs#>>ARRAY['titles',demo_row.demo_key],
   description='<p>'||(inputs#>>ARRAY['descriptions',demo_row.demo_key])||'. Explore the example using fictional data.</p>',
   data=pg_temp.demo_locale_json(data,translations)||jsonb_build_object('demo_locale',p_locale),
   features=pg_temp.demo_locale_json(features,translations),updated_at=now()
   WHERE id=demo_row.occasion AND organization=p_org;
  UPDATE public.demo_occasions SET description=inputs#>>ARRAY['descriptions',demo_row.demo_key]
   WHERE occasion=demo_row.occasion AND organization=p_org;
  UPDATE public.forms SET title=inputs#>>ARRAY['titles',demo_row.demo_key],
   header=inputs#>>ARRAY['headers',demo_row.demo_key],header_off=inputs->>'notice',
   data=pg_temp.demo_locale_json(data,translations) WHERE occasion=demo_row.occasion;
  UPDATE public.form_fields SET title=pg_temp.demo_locale_text(title,translations),
   description=CASE WHEN title='Informace o osobních údajích' THEN inputs->>'privacy'
    ELSE pg_temp.demo_locale_text(description,translations) END,
   data=pg_temp.demo_locale_json(data,translations)
   WHERE form IN(SELECT id FROM public.forms WHERE occasion=demo_row.occasion);
  UPDATE public.information SET title=pg_temp.demo_locale_text(title,translations),
   description=CASE WHEN "order"=1 THEN '<h2>'||(inputs#>>ARRAY['titles',demo_row.demo_key])||'</h2><p>'||
    (inputs#>>ARRAY['descriptions',demo_row.demo_key])||'. We look forward to sharing the experience.</p>'
    ELSE '<p>'||(inputs#>>ARRAY['practical',demo_row.demo_key])||'</p>' END
   WHERE occasion=demo_row.occasion;
  UPDATE public.places SET title=pg_temp.demo_locale_text(title,translations),
   description=pg_temp.demo_locale_text(description,translations) WHERE occasion=demo_row.occasion;
  UPDATE public.events SET title=pg_temp.demo_locale_text(title,translations) WHERE occasion=demo_row.occasion;
  UPDATE eshop.product_types SET title=pg_temp.demo_locale_text(title,translations) WHERE occasion=demo_row.occasion;
  UPDATE eshop.products SET title=pg_temp.demo_locale_text(title,translations) WHERE occasion=demo_row.occasion;
  UPDATE eshop.blueprints SET title=pg_temp.demo_locale_text(title,translations) WHERE occasion=demo_row.occasion;
  UPDATE eshop.spots SET title=pg_temp.demo_locale_text(title,translations) WHERE occasion=demo_row.occasion;
  UPDATE public.inventory_pools SET title=pg_temp.demo_locale_text(title,translations) WHERE occasion=demo_row.occasion;
  UPDATE public.inventory_contexts SET title=pg_temp.demo_locale_text(title,translations)
   WHERE inventory_pool IN(SELECT id FROM public.inventory_pools WHERE occasion=demo_row.occasion);
  UPDATE public.resources SET title=pg_temp.demo_locale_text(title,translations) WHERE occasion=demo_row.occasion;
  UPDATE public.resource_slots SET title=pg_temp.demo_locale_text(title,translations)
   WHERE resource IN(SELECT id FROM public.resources WHERE occasion=demo_row.occasion);
  UPDATE eshop.bank_accounts SET title='Demo account - no payments',
   account_number_human_readable='DEMO - NOT A PAYMENT ACCOUNT',creditor_name=inputs->>'organizer'
   WHERE id=demo_row.bank_account AND account_number IS NULL AND secret IS NULL AND NOT is_fetch_enabled;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unexpected demo payment configuration'; END IF;
  UPDATE eshop.orders SET data=pg_temp.demo_locale_json(data,translations) WHERE occasion=demo_row.occasion;
  UPDATE eshop.tickets SET data=pg_temp.demo_locale_json(data,translations),
   note=pg_temp.demo_locale_text(note,translations) WHERE occasion=demo_row.occasion;
  UPDATE eshop.orders_history SET data=pg_temp.demo_locale_json(data,translations)
   WHERE "order" IN(SELECT id FROM eshop.orders WHERE occasion=demo_row.occasion);
  UPDATE eshop.transactions SET counter_account_name=pg_temp.demo_locale_text(counter_account_name,translations),
   comment=pg_temp.demo_locale_text(comment,translations) WHERE bank_account_id=demo_row.bank_account;
  PERFORM public.record_client_sync_commit_v1(demo_row.occasion,'demo.locale','configuration',
   jsonb_build_array(jsonb_build_object('entityType','occasion','entityId',demo_row.occasion::text,
    'operation','update','safeLabel',demo_row.demo_key,'changedFields',jsonb_build_array('title','description','data','features'))),
   ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'system','Apply shared demo presentation locale');
 END LOOP;
END $localized$;
