-- Occasion setup UX contracts. Generated from canonical sources listed below.
BEGIN;

-- Source: database/functions/user_permissions/get_is_manager_on_unit.sql
CREATE OR REPLACE FUNCTION public.get_is_manager_on_unit(unit_id bigint) RETURNS bool
    LANGUAGE sql STABLE
    SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT NOT public.is_demo_unit(unit_id) AND EXISTS (
    SELECT 1
    FROM public.unit_users membership
    WHERE membership."user" = auth.uid()
      AND membership.unit = unit_id
      AND membership.is_manager
  );
$$;


-- Source: database/functions/occasion_setup/sources.sql
-- One internal configuration projection, shared by new detail and legacy manifest.
CREATE OR REPLACE FUNCTION public.occasion_setup_source_internal(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT jsonb_build_object(
    'occasion', jsonb_build_object('id',o.id,'title',o.title,'link',o.link,
      'start_time',o.start_time,'end_time',o.end_time,'description',o.description,
      'data',o.data,'features',o.features,'is_open',false,'is_hidden',true),
    'forms', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',f.id,'title',f.title,'link',f.link,'type',f.type,'data',f.data,'header',f.header,
      'header_off',f.header_off,'deadline_duration_seconds',f.deadline_duration_seconds,'bank_account',f.bank_account,
      'is_open',false,'blueprint',f.blueprint,
      'fields',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'title',ff.title,'description',ff.description,'data',ff.data,'type',ff.type,
        'is_required',ff.is_required,'is_hidden',ff.is_hidden,'order',ff."order",
        'is_ticket_field',ff.is_ticket_field,
        'product_type_data',(SELECT jsonb_build_object('id',pt.id,'title',pt.title,
          'description',pt.description,'type',pt.type,'data',pt.data,
          'products',COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'id',p.id,'title',p.title,'description',p.description,'price',p.price,
            'currency_code',p.currency_code,'maximum',p.maximum,'data',p.data,
            'is_hidden',p.is_hidden,'order',p."order") ORDER BY p."order",p.id)
            FROM eshop.products p WHERE p.product_type=pt.id),'[]'::jsonb))
          FROM eshop.product_types pt WHERE pt.id=ff.product_type)) ORDER BY ff."order",ff.id)
        FROM public.form_fields ff WHERE ff.form=f.id),'[]'::jsonb)) ORDER BY f.id)
      FROM public.forms f WHERE f.occasion=o.id),'[]'::jsonb),
    'blueprints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',b.id,'title',b.title,'configuration',b.configuration,'groups',b.groups,
      'background_svg',b.background_svg,
      'objects',COALESCE((SELECT jsonb_agg((obj - 'state' - 'order_product_ticket' - 'secret' - 'secret_expiration_time') ||
        jsonb_build_object('state','available','product',coalesce(to_jsonb(s.product),obj->'product'),'title',COALESCE(s.title,obj->>'title')))
        FROM jsonb_array_elements(COALESCE(b.objects,'[]'::jsonb)) obj
        LEFT JOIN eshop.spots s ON s.id=NULLIF(obj->>'id','')::bigint AND s.blueprint=b.id),'[]'::jsonb)) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description))
      FROM public.events e WHERE e.occasion=o.id),'[]'::jsonb),
    'information',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',i.title,
      'description',i.description,'type',i.type,'data',i.data) ORDER BY i."order",i.id)
      FROM public.information i WHERE i.occasion=o.id),'[]'::jsonb)
    ) FROM public.occasions o WHERE o.id=p_occasion;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_source_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_source_list(p_unit bigint,p_source_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.units target JOIN public.units source ON source.organization=target.organization
   WHERE target.id=p_unit AND source.id=coalesce(p_source_unit,p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Source tenant denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('occasion',jsonb_build_object(
  'id',o.id,'title',o.title,'start_time',o.start_time,'end_time',o.end_time),
  'forms',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'title',f.title)) FROM public.forms f WHERE f.occasion=o.id),'[]'::jsonb),
  'blueprints',coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'title',b.title)) FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb)) ORDER BY o.start_time DESC,o.id DESC)
  FROM public.occasions o WHERE o.unit=coalesce(p_source_unit,p_unit) AND public.can_copy_occasion_source(o.id)),'[]');
END $$;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_source(p_unit bigint,p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit))
  OR NOT public.can_copy_occasion_source(p_occasion)
  OR NOT EXISTS(SELECT 1 FROM public.occasions o JOIN public.units u ON u.organization=o.organization
    WHERE o.id=p_occasion AND u.id=p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 RETURN public.occasion_setup_source_internal(p_occasion);
END $$;

-- Compatibility for already deployed opt-in development clients. Remove once
-- all such clients use source_list/source; no separate projection is maintained.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_sources(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(public.occasion_setup_source_internal(o.id) ORDER BY o.start_time DESC,o.id DESC)
  FROM public.occasions o WHERE o.unit=p_unit),'[]');
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_payment_context(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Payment settings access denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,
  'account_number',b.account_number,'supported_currencies',b.supported_currencies,'type',b.type)
  ORDER BY u.priority,b.id) FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
  WHERE u.unit=p_unit AND b.type IS DISTINCT FROM 'CASH'),'[]');
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_payment_context(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_payment_context(bigint) TO authenticated;


-- Source: database/functions/occasion_setup/drafts.sql
-- Round in the event tenant's civil time; a single captured instant owns defaults.
CREATE OR REPLACE FUNCTION public.occasion_setup_default_start_internal(p_now timestamptz,p_timezone text DEFAULT 'Europe/Prague')
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT (date_trunc('hour',local_now) + ceil(extract(epoch FROM (local_now-date_trunc('hour',local_now)))/1800)*interval '30 minutes') AT TIME ZONE p_timezone
 FROM (SELECT (p_now AT TIME ZONE p_timezone)+interval '30 days' local_now) x;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_default_start_internal(timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;

-- Drafts are private workspace objects, never public occasions.
CREATE TABLE IF NOT EXISTS public.occasion_setup_drafts (
  id uuid PRIMARY KEY,
  unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  author uuid NOT NULL REFERENCES auth.users(id),
  data jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(data) = 'object' AND octet_length(data::text) <= 262144),
  revision bigint NOT NULL DEFAULT 1,
  current_step integer NOT NULL DEFAULT 0 CHECK (current_step BETWEEN 0 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.occasion_setup_drafts DROP CONSTRAINT IF EXISTS occasion_setup_drafts_current_step_check;
ALTER TABLE public.occasion_setup_drafts ADD CONSTRAINT occasion_setup_drafts_current_step_check CHECK (current_step BETWEEN 0 AND 6);
CREATE INDEX IF NOT EXISTS occasion_setup_drafts_unit_idx ON public.occasion_setup_drafts(unit);
ALTER TABLE public.occasion_setup_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_setup_drafts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_drafts(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY updated_at DESC)
    FROM public.occasion_setup_drafts d WHERE unit = p_unit AND NOT (d.data ? 'finalizedOccasion')), '[]'::jsonb);
END $$;

-- Terminal receipts remain readable to an already-open wizard, independently
-- of the resumable list. Never infer completion from a missing list item.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_draft(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='Draft access denied';
  END IF;
  RETURN to_jsonb(d);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_draft(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_draft(uuid) TO authenticated;

-- Run the canonical creator inside a rollback-only subtransaction. Its
-- complete configuration survives in a PL/pgSQL variable, but no occasion,
-- form, product, reminders or other rows escape into the normal application.
-- PostgreSQL sequences may advance; those IDs are draft-local references.
CREATE OR REPLACE FUNCTION public.build_occasion_setup_configuration(p_unit bigint, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE configuration jsonb; organization_id bigint;
  default_start timestamptz := public.occasion_setup_default_start_internal(now(),coalesce((SELECT data->>'timezone' FROM public.units WHERE id=p_unit),'Europe/Prague'));
  provisional_link text := 'draft-' || p_id::text;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT organization INTO organization_id FROM public.units WHERE id = p_unit;
  BEGIN
    PERFORM public.update_occasion_internal_v1(jsonb_build_object(
      'unit',p_unit,'organization',organization_id,'title','',
      'link',provisional_link,'is_hidden',true,'is_open',false,
      'start_time',default_start,'end_time',default_start+interval '3 days'));
    SELECT public.occasion_setup_source_internal(id) INTO configuration
      FROM public.occasions WHERE link=provisional_link AND unit=p_unit;
    IF configuration IS NULL THEN RAISE EXCEPTION 'Creation configuration missing'; END IF;
    RAISE EXCEPTION 'Rollback provisional creation' USING ERRCODE = 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN
    -- Variables retain their values while all writes in the block roll back.
    NULL;
  END;
  configuration := jsonb_set(configuration,'{occasion,link}','""'::jsonb);
  configuration := jsonb_set(configuration,'{forms}',coalesce((SELECT jsonb_agg(jsonb_set(jsonb_set(jsonb_set(f,'{link}','""'::jsonb),'{deadline_duration_seconds}','null'::jsonb),'{data}',coalesce(nullif(f->'data','null'::jsonb),'{}'::jsonb)-'is_reminder_enabled'))
    FROM jsonb_array_elements(configuration->'forms') f),'[]'::jsonb));
  configuration := configuration || jsonb_build_object('communicationDefaults',coalesce((SELECT jsonb_strip_nulls(jsonb_build_object('reply_to',data->'reply_to','communication_tone',data->'communication_tone','is_reminder_enabled',data->'is_reminder_enabled','reminder_interval_seconds',data->'reminder_interval_seconds')) FROM public.units WHERE id=p_unit),'{}'::jsonb));
  RETURN configuration;
END $$;
REVOKE ALL ON FUNCTION public.build_occasion_setup_configuration(bigint,uuid) FROM PUBLIC,anon,authenticated;

-- Client-generated UUID makes canonical draft initialization safe to retry.
CREATE OR REPLACE FUNCTION public.create_occasion_setup_draft(p_id uuid, p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb; is_new boolean; policy jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  -- Serialize identical UUIDs before inspecting existence, without charging retries.
  PERFORM pg_advisory_xact_lock(hashtextextended('draft:'||p_id::text,0));
  is_new:=NOT EXISTS(SELECT 1 FROM public.occasion_setup_drafts WHERE id=p_id);
  IF is_new THEN
    policy:=public.abuse_effective_rules_v1('occasion.draft',p_unit,(SELECT organization FROM public.units WHERE id=p_unit));
    PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,
      (SELECT organization FROM public.units WHERE id=p_unit),0,true,true,policy);
  END IF;
  INSERT INTO public.occasion_setup_drafts(id,unit,organization,author)
    SELECT p_id,id,organization,auth.uid() FROM public.units WHERE id = p_unit
    ON CONFLICT (id) DO NOTHING;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF d.unit IS DISTINCT FROM p_unit OR d.author IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (d.data ? 'defaultConfiguration') THEN
    IF NOT is_new THEN
      policy:=public.abuse_effective_rules_v1('occasion.draft',p_unit,d.organization);
      PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,d.organization,0,false,true,policy);
    END IF;
    configuration := public.build_occasion_setup_configuration(p_unit,p_id);
    UPDATE public.occasion_setup_drafts SET data =
      jsonb_build_object('defaultConfiguration',configuration,
        'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true)
      || d.data WHERE id = p_id RETURNING * INTO d;
    PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,d.organization,octet_length(d.data::text),false,false,policy);
  END IF;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.initialize_occasion_setup_draft_defaults(p_id uuid, p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb; policy jsonb;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'defaultConfiguration' THEN
    IF NOT (d.data->'defaultConfiguration' ? 'communicationDefaults') AND NOT (d.data ? 'finalizedOccasion') THEN
      IF d.revision IS DISTINCT FROM p_expected_revision THEN
        RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
      UPDATE public.occasion_setup_drafts SET data=jsonb_set(data,'{defaultConfiguration,communicationDefaults}',
        coalesce((SELECT jsonb_strip_nulls(jsonb_build_object('reply_to',u.data->'reply_to','communication_tone',u.data->'communication_tone','is_reminder_enabled',u.data->'is_reminder_enabled','reminder_interval_seconds',u.data->'reminder_interval_seconds')) FROM public.units u WHERE u.id=d.unit),'{}'::jsonb)),revision=revision+1,updated_at=now()
        WHERE id=p_id RETURNING * INTO d;
    END IF;
    RETURN to_jsonb(d);
  END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  policy:=public.abuse_effective_rules_v1('occasion.draft',d.unit,d.organization);
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,0,false,true,policy);
  configuration := public.build_occasion_setup_configuration(d.unit,p_id);
  UPDATE public.occasion_setup_drafts SET data =
    jsonb_build_object('defaultConfiguration',configuration,
      'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true)
    || d.data, revision = revision+1, updated_at=now()
    WHERE id=p_id RETURNING * INTO d;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(d.data::text),false,false,policy);
  RETURN to_jsonb(d);
END $$;
REVOKE ALL ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_occasion_setup_draft(p_id uuid, p_expected_revision bigint, p_data jsonb, p_step integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
  p_data := p_data - 'finalizedOccasion' - 'finalizeResponse';
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' OR octet_length(p_data::text) > 262144 OR p_step IS NULL OR p_step NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Invalid draft' USING ERRCODE = '22023'; END IF;
  IF d.data ? 'copy_locale' THEN p_data := jsonb_set(p_data,'{copy_locale}',d.data->'copy_locale'); END IF;
  IF p_data ? 'copy_locale' AND p_data->>'sourceId' IS NOT NULL
     AND coalesce((p_data->>'copy_title_edited')::boolean,false)=false AND coalesce(p_data->>'title','')='' THEN
    IF NOT public.can_copy_occasion_source((p_data->>'sourceId')::bigint) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint AND organization=d.organization) THEN
      RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
    IF d.revision=p_expected_revision+1 AND d.data->>'sourceId'=p_data->>'sourceId' THEN
      p_data := jsonb_set(p_data,'{title}',d.data->'title');
    ELSE
      p_data := jsonb_set(p_data,'{title}',to_jsonb(public.copy_occasion_title_internal(
        (SELECT title FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint),p_data->>'copy_locale')));
    END IF;
  END IF;
  IF d.revision = p_expected_revision + 1 AND d.data = p_data AND d.current_step = p_step THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001'; END IF;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(p_data::text),false,false);
  UPDATE public.occasion_setup_drafts SET data = p_data, current_step = p_step,
    revision = revision + 1, updated_at = now() WHERE id = p_id RETURNING * INTO d;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.delete_occasion_setup_draft(p_id uuid, p_unit bigint, p_expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF d.unit <> p_unit THEN RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501'; END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  DELETE FROM public.occasion_setup_drafts WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) TO authenticated;


-- Source: database/functions/occasion_setup/form_link.sql
-- Suggestions consult the same global reservations (including tombstones) as
-- final writes. This is a preview, not a claim or an alternate allocator.
CREATE OR REPLACE FUNCTION public.suggest_occasion_setup_form_link(p_id uuid,p_title text,p_requested_link text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; base text; candidate text; suffix integer:=1; year text;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF length(coalesce(p_title,''))>500 OR length(coalesce(p_requested_link,''))>80 THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid public link input'; END IF;
 base:=trim(both '_' from regexp_replace(public.f_unaccent(left(coalesce(p_title,''),500)),'[^a-z0-9_-]+','_','g'));
 base:=trim(trailing '_' from left(base,64));
 IF base='' THEN base:='akce'; END IF;
 year:=substring(coalesce(d.data->>'start',d.data->>'start_time','') from '^([0-9]{4})-');
 IF year IS NOT NULL AND base !~ '[0-9]{4}' THEN base:=base||'_'||year; END IF;
 candidate:=base;
 WHILE EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=candidate) LOOP
  suffix:=suffix+1; candidate:=base||'_'||suffix;
  IF suffix>1000 THEN candidate:=base||'_'||left(replace(d.id::text,'-',''),8); EXIT; END IF;
 END LOOP;
 -- Deterministic bounded fallback, still checked rather than presumed free.
 IF EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=candidate) THEN
  RAISE unique_violation USING MESSAGE='Public link suggestions exhausted'; END IF;
 RETURN jsonb_build_object('suggestion',candidate,'available',
  CASE WHEN p_requested_link IS NULL OR p_requested_link='' THEN NULL
  ELSE p_requested_link ~ '^[a-z0-9]+([-_][a-z0-9]+)*$'
    AND NOT EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=p_requested_link) END);
END $$;
REVOKE ALL ON FUNCTION public.suggest_occasion_setup_form_link(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.suggest_occasion_setup_form_link(uuid,text,text) TO authenticated;


-- Source: database/functions/occasion_setup/finalize.sql
-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 blueprint_mode text; blueprint_id bigint; objects jsonb := '[]'; obj jsonb; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := d.data;
 blueprint_mode := CASE payload->>'blueprintMode'
  WHEN 'none' THEN 'none' WHEN 'Bez plánku' THEN 'none'
  WHEN 'new' THEN 'new' WHEN 'Nový' THEN 'new'
  WHEN 'copy' THEN 'copy' WHEN 'Převzít' THEN 'copy'
  WHEN NULL THEN 'none' ELSE payload->>'blueprintMode' END;
 -- Old drafts without a mode were valid inline plans; keep that explicit legacy adapter.
 IF blueprint_mode IS NULL THEN blueprint_mode := CASE WHEN jsonb_array_length(coalesce(payload->'blueprintObjects','[]'))>0 THEN 'copy' ELSE 'none' END; END IF;
 IF blueprint_mode NOT IN ('none','new','copy') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid blueprint mode'; END IF;
 IF blueprint_mode<>'none' AND (
  coalesce((payload->>'formEnabled')::boolean,true) IS NOT TRUE OR
  payload->'formDraft' IS NULL OR payload->'formDraft'='null'::jsonb OR
  NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload->'blueprintObjects','[]')) o WHERE o->>'type'='spot')
 ) THEN RAISE invalid_parameter_value USING MESSAGE='Blueprint requires a form and sellable seats'; END IF;
 source_id := (payload->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 FOREACH source_id IN ARRAY ARRAY[nullif(payload->>'formSourceOccasionId','')::bigint,nullif(payload->>'blueprintSourceOccasionId','')::bigint] LOOP
  IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END LOOP;
 source_id := (payload->>'sourceId')::bigint;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 IF payload->'ticketDraft' IS NOT NULL AND payload->'ticketDraft'<>'null'::jsonb THEN features := features || jsonb_build_array((payload->'ticketDraft')-'layout'); END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN features := features || '[{"code":"form","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'features',features,'data',jsonb_build_object('client_sync_v1',false) || CASE WHEN nullif(btrim(payload->>'replyTo'),'') IS NOT NULL THEN jsonb_build_object('reply_to',btrim(payload->>'replyTo')) ELSE '{}'::jsonb END);
 policies:=public.abuse_policy_bundle_v1(ARRAY['occasion.creation','occasion.copy'],d.unit,d.organization);
 IF source_id IS NOT NULL AND (coalesce((payload->>'copyProgram')::boolean,false) OR coalesce((payload->>'copyInformation')::boolean,false) OR coalesce((payload->>'copyEmails')::boolean,false)) THEN
  PERFORM public.admit_occasion_copy_v1(source_id,d.unit,d.organization,policies->'occasion.copy'); END IF;
 PERFORM public.admit_occasion_creation_v1(auth.uid(),d.unit,d.organization,NULL,policies->'occasion.creation');
 PERFORM public.update_occasion_internal_v1(config);
 new_id := currval(pg_get_serial_sequence('public.occasions','id'));
 SELECT o.features INTO features FROM public.occasions o WHERE o.id=new_id;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view)
 VALUES(new_id,auth.uid(),true,true,true,true,true);
 form_data := payload->'formDraft';
 IF nullif(btrim(payload->>'replyTo'),'') IS NOT NULL AND (length(payload->>'replyTo')>254 OR payload->>'replyTo' !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 IF coalesce(payload->>'communicationTone','inherit') NOT IN ('inherit','formal','informal') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid communication tone'; END IF;
 IF payload ? 'communicationTone' THEN
  form_data:=jsonb_set(form_data,'{data}',coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)-'communication_tone' ||
   CASE WHEN payload->>'communicationTone' IN ('formal','informal') THEN jsonb_build_object('communication_tone',payload->>'communicationTone') ELSE '{}'::jsonb END);
 END IF;
 -- A copied source's schedule is never the creation intent of the destination.
 IF payload ? 'saleMode' THEN
  form_data:=jsonb_set(form_data,'{data}',(coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)-'start_time'-'end_time'-'enable_countdown') ||
   jsonb_build_object('schedule',(coalesce(nullif(form_data#>'{data,schedule}','null'::jsonb),'{}'::jsonb)-'start_time'-'end_time') || jsonb_build_object('sale_preparation',payload->>'saleMode'='preparation')));
 END IF;
 IF payload->>'saleMode' NOT IN ('preparation','scheduled','immediate') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid sale mode'; END IF;
 IF payload->>'saleMode' IN ('scheduled','immediate') THEN
  IF coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz) > (payload->>'end')::timestamptz OR
     coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz) <= now() OR
     (payload->>'saleMode'='scheduled' AND ((payload->>'saleStart') IS NULL OR (payload->>'saleStart')::timestamptz <= now() OR
       (payload->>'saleStart')::timestamptz >= coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz))) THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid sale interval'; END IF;
  form_data:=jsonb_set(form_data,'{data}',coalesce(form_data->'data','{}'::jsonb) || jsonb_build_object('schedule',jsonb_build_object(
    'start_time',CASE WHEN payload->>'saleMode'='scheduled' THEN payload->>'saleStart' ELSE now()::text END,
    'end_time',coalesce(payload->>'saleEnd',payload->>'end'))));
 END IF;
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Seat selection belongs to the active plan, never a stale form toggle.
  form_data := jsonb_set(form_data,'{fields}',coalesce((
   SELECT jsonb_agg(f) FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f
   WHERE f->>'type' IS DISTINCT FROM 'spot'),'[]'::jsonb) ||
   CASE WHEN blueprint_mode<>'none' THEN '[{"type":"spot","is_ticket_field":true,"is_hidden":false,"order":-1}]'::jsonb ELSE '[]'::jsonb END);
  -- Every field/product is newly owned by this occasion. Retain a local mapping
  -- for seats that referred to draft/source product IDs.
  FOR field IN SELECT value FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) LOOP
   pt := coalesce(nullif(field->'product_type_data','null'::jsonb),field->'product_type');
   IF jsonb_typeof(pt)<>'object' THEN pt := NULL; END IF;
   field := field - 'id' - 'form' - 'product_type';
   IF pt IS NOT NULL AND pt<>'null'::jsonb THEN
    old_products := old_products || coalesce(pt->'products','[]');
    products := '[]';
    FOR product IN SELECT value FROM jsonb_array_elements(coalesce(pt->'products','[]')) LOOP
     products := products || jsonb_build_array(product-'id'-'occasion'-'product_type');
    END LOOP;
    field := (field-'product_type_data') || jsonb_build_object('product_type',(pt-'id'-'occasion') || jsonb_build_object('products',products));
   END IF;
   old_types := old_types || jsonb_build_array(pt->'id');
   fields := fields || jsonb_build_array(field);
  END LOOP;
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(nullif(form_data->>'link',''),(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',coalesce(payload->>'saleMode','preparation') IN ('scheduled','immediate'),'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  -- Validate configured bank routes using the checkout's exact linked-account,
  -- non-cash and supported-currency predicates. Account priority stays checkout-owned.
  IF coalesce(form_data#>'{data,payments,bankEnabled}','true'::jsonb)='true'::jsonb AND EXISTS(
    SELECT 1 FROM eshop.products p WHERE p.occasion=new_id AND p.price>0
      AND NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
        WHERE u.unit=d.unit AND b.type IS DISTINCT FROM 'CASH' AND b.supported_currencies @> ARRAY[p.currency_code::text]
          AND (nullif(form_data->>'bank_account','') IS NULL OR b.id=(form_data->>'bank_account')::bigint))) THEN
    RAISE invalid_parameter_value USING MESSAGE='No valid bank route for the selected currencies';
  END IF;
  IF jsonb_array_length(old_types)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_types)-1 LOOP
    IF old_types->>idx IS NOT NULL THEN type_map := type_map || jsonb_build_object(old_types->>idx,result->'form_fields'->idx->'product_type'->'id'); END IF;
   END LOOP;
  END IF;
  SELECT coalesce(jsonb_agg(p ORDER BY field_order,product_order),'[]') INTO new_products
  FROM (SELECT p,ff.ordinality field_order,pp.ordinality product_order
   FROM jsonb_array_elements(result->'form_fields') WITH ORDINALITY ff(f,ordinality)
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(ff.f->'product_type'->'products','[]')) WITH ORDINALITY pp(p,ordinality)) x;
  IF jsonb_array_length(old_products)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_products)-1 LOOP
    IF old_products->idx->>'id' IS NOT NULL THEN product_map := product_map || jsonb_build_object(old_products->idx->>'id',new_products->idx->'id'); END IF;
   END LOOP;
  END IF;
  IF blueprint_mode<>'none' THEN
   FOR obj IN SELECT value FROM jsonb_array_elements(payload->'blueprintObjects') LOOP
    -- Editor/source models contain read-only occupancy. Only configuration
    -- crosses the create boundary; the general blueprint command stays strict.
    obj := obj-ARRAY['id','state','order_product_ticket','secret','secret_expiration_time'];
    IF obj->>'type'='spot' AND (obj->>'product' IS NULL OR product_map->>(obj->>'product') IS NULL) THEN
     RAISE invalid_parameter_value USING MESSAGE='Every blueprint seat requires a form product'; END IF;
    IF obj->>'product' IS NOT NULL THEN obj := jsonb_set(obj,'{product}',coalesce(product_map->(obj->>'product'),'null'::jsonb)); END IF;
    objects := objects || jsonb_build_array(obj);
   END LOOP;
   result := public.update_blueprint_internal_v1(jsonb_build_object('occasion',new_id,'organization',d.organization,
    'title',payload->>'blueprintTitle','configuration',jsonb_build_object('dimensions',jsonb_build_object(
     'width',coalesce((payload->>'blueprintWidth')::numeric,12),'height',coalesce((payload->>'blueprintHeight')::numeric,8))),
    'groups',coalesce(payload->'blueprintGroups','[]'),'objects',objects,'background_svg',payload->>'blueprintBackground'));
   IF (result->>'code')::int NOT IN (200,201) THEN RAISE EXCEPTION '%',result; END IF;
   blueprint_id := (result->>'blueprint_id')::bigint;
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features := features || '[{"code":"blueprint","is_enabled":true}]';
  END IF;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft';
  SELECT jsonb_set(pt,'{layout,templates}',jsonb_object_agg(t.key,
    jsonb_set(t.value,'{elements}',coalesce((SELECT jsonb_agg(CASE WHEN e->>'binding'='productType'
      THEN jsonb_set(e,'{productTypeId}',coalesce(type_map->(e->>'productTypeId'),'null'::jsonb)) ELSE e END ORDER BY n)
      FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)),'[]'::jsonb))))
   INTO pt FROM jsonb_each(pt->'layout'->'templates') t;
  features := (SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN pt ELSE f END) FROM jsonb_array_elements(features) f);
 END IF;
 PERFORM public.validate_ticket_layout_references(new_id,f->'layout') FROM jsonb_array_elements(features) f WHERE f ? 'layout';
 final_features := features;
 UPDATE public.occasions SET features=final_features WHERE id=new_id;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN
  INSERT INTO public.events(occasion,title,start_time,end_time,description)
  SELECT new_id,e->>'title',(e->>'start_time')::timestamptz,(e->>'end_time')::timestamptz,e->>'description'
  FROM jsonb_array_elements(coalesce(payload->'sourceProgram','[]')) e;
 END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN
  INSERT INTO public.information(occasion,unit,title,description,type,data)
  SELECT new_id,d.unit,i->>'title',i->>'description',i->>'type',i->'data'
  FROM jsonb_array_elements(coalesce(payload->'sourceInformation','[]')) i;
 END IF;
 IF coalesce((payload->>'copyEmails')::boolean,false) AND source_id IS NOT NULL THEN
  INSERT INTO public.email_templates(occasion,unit,organization,code,title,subject,html)
  SELECT new_id,d.unit,d.organization,code,title,subject,html FROM public.email_templates WHERE occasion=source_id;
 END IF;
 PERFORM public.admit_occasion_copy_v1(new_id,d.unit,d.organization,policies->'occasion.copy');
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id)));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;


-- Source: database/functions/occasion_setup/email_preview.sql
-- Draft-scoped read projection. No caller-provided hierarchy or template ID is accepted.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_email_preview(
 p_id uuid,p_expected_revision bigint,p_tone text DEFAULT NULL,p_reply_to text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; unit_data jsonb; resolved jsonb; copied jsonb;
 source_id bigint; tone text; reply_to text;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT
   (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN
  RAISE serialization_failure USING MESSAGE='Draft revision conflict'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft is finalized'; END IF;
 SELECT data INTO unit_data FROM public.units WHERE id=d.unit AND organization=d.organization;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Draft hierarchy denied'; END IF;
 tone:=coalesce(p_tone,nullif(nullif(d.data->>'communicationTone',''),'inherit'),unit_data->>'communication_tone','formal');
 IF tone NOT IN ('formal','informal') THEN RAISE invalid_parameter_value USING MESSAGE='Invalid tone'; END IF;
 reply_to:=coalesce(nullif(btrim(coalesce(p_reply_to,d.data->>'replyTo')),''),nullif(btrim(unit_data->>'reply_to'),''));
 IF reply_to IS NOT NULL AND (length(reply_to)>254 OR reply_to !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 resolved:=public.get_email_template_and_wrapper('TICKET_ORDER_CONFIRMATION',
  jsonb_build_object('unit',d.unit,'organization',d.organization));
 -- Finalization copies occasion templates only. An inherited source template or
 -- source wrapper must not replace the destination hierarchy in this preview.
 IF coalesce((d.data->>'copyEmails')::boolean,false) AND nullif(d.data->>'sourceId','') IS NOT NULL THEN
  source_id:=(d.data->>'sourceId')::bigint;
  IF NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(
   SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization) THEN
   RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
  SELECT to_jsonb(t) INTO copied FROM public.email_templates t
   WHERE t.occasion=source_id AND t.code='TICKET_ORDER_CONFIRMATION' ORDER BY t.id DESC LIMIT 1;
  IF copied IS NOT NULL THEN resolved:=jsonb_set(resolved,'{template}',copied); END IF;
 END IF;
 RETURN jsonb_build_object('revision',d.revision,'title',coalesce(nullif(d.data->>'title',''),'Ukázková událost'),
  'tone',tone,'replyTo',reply_to,'resolved',resolved,
  'has_custom_template',coalesce((resolved->'template'->>'occasion') IS NOT NULL
    OR (resolved->'template'->>'unit') IS NOT NULL OR (resolved->'template'->>'organization') IS NOT NULL,false));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_email_preview(uuid,bigint,text,text) TO authenticated;

COMMIT;
