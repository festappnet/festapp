BEGIN;
-- Rollback-only synthetic scenarios use the canonical reviewed test ceiling.
UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE f public.forms; un bigint; actor uuid; source jsonb; plan jsonb; form_data jsonb; payload jsonb; d jsonb; response jsonb; target bigint; identifier uuid; n integer; before_count bigint;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned fixture required'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=current_setting('festapp.fixture_form')::bigint;
 SELECT unit INTO un FROM public.occasions WHERE id=f.occasion;
 SELECT "user" INTO actor FROM public.occasion_users WHERE occasion=f.occasion AND is_editor ORDER BY "user" LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT item INTO source FROM jsonb_array_elements(public.get_occasion_setup_sources(un)) item WHERE (item#>>'{occasion,id}')::bigint=f.occasion;
 SELECT item->'blueprintLayoutDraft' INTO plan FROM jsonb_array_elements(source->'blueprints') item WHERE (item->>'id')::bigint=f.blueprint;
 FOR n IN 1..6 LOOP
  form_data:=source->'forms'->0;
  IF n=2 THEN form_data:=jsonb_set(form_data,'{fields}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(form_data->'fields') WHERE value->>'type'<>'ticket'));
  ELSIF n=3 THEN form_data:=jsonb_set(form_data,'{fields}',(SELECT jsonb_agg(CASE WHEN value->>'type'='ticket' THEN value||'{"is_hidden":true}' ELSE value END) FROM jsonb_array_elements(form_data->'fields'))); END IF;
  payload:=jsonb_build_object('title','V2 active choice '||n,'link','v2-choice-'||gen_random_uuid(),'sourceId',f.occasion,
   'start',now()+interval '1 day','end',now()+interval '2 days','reviewConfirmed',true,'formEnabled',n<>4,'formDraft',form_data,
   'blueprintMode',CASE WHEN n IN(5,6) THEN 'Nový' ELSE 'Bez plánku' END,
   'ticketDraft',CASE WHEN n IN(2,3,4) THEN '{"code":"ticket","layout":{"schemaVersion":999,"templates":null}}'::jsonb ELSE '{"code":"schedule","is_enabled":false}'::jsonb END,
   'blueprintLayoutDraft',CASE WHEN n=5 THEN plan ELSE '{"layout":{"bad":true},"seatBindings":[],"areaBindings":[]}'::jsonb END,
   'blueprintObjects','[{"type":"spot","product":-999}]'::jsonb);
  identifier:=gen_random_uuid();d:=public.create_occasion_setup_draft(identifier,un);
  d:=public.save_occasion_setup_draft(identifier,(d->>'revision')::bigint,payload,5);
  SELECT count(*) INTO before_count FROM public.occasions;
  IF n=6 THEN
   BEGIN PERFORM public.finalize_occasion_setup_draft(identifier,(d->>'revision')::bigint,gen_random_uuid());RAISE EXCEPTION 'active empty V2 accepted';
   EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
   IF (SELECT count(*) FROM public.occasions)<>before_count THEN RAISE EXCEPTION 'empty V2 rejection not atomic'; END IF;
   CONTINUE;
  END IF;
  response:=public.finalize_occasion_setup_draft(identifier,(d->>'revision')::bigint,gen_random_uuid());target:=(response#>>'{data,occasionId}')::bigint;
  IF (SELECT count(*) FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) feature WHERE o.id=target AND feature->>'code'='ticket' AND (feature->>'is_enabled')::boolean)<>(CASE WHEN n IN(1,5) THEN 1 ELSE 0 END) THEN RAISE EXCEPTION 'ticket activation mismatch case %',n; END IF;
  IF EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) feature WHERE o.id=target AND feature->>'code'='schedule') THEN RAISE EXCEPTION 'ticket config injected alternate feature'; END IF;
  IF n=5 THEN
   IF NOT EXISTS(SELECT 1 FROM public.forms target_form JOIN eshop.blueprints b ON b.id=target_form.blueprint WHERE target_form.occasion=target AND b.layout_revision=1) THEN RAISE EXCEPTION 'active V2 aggregate absent'; END IF;
  ELSIF EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=target) THEN RAISE EXCEPTION 'dormant V2/legacy created blueprint'; END IF;
 END LOOP;
 RAISE NOTICE 'V2 active feature choices six scenarios: visible/hidden/absent/disabled tickets, dormant no-plan, active aggregate, atomic empty reject PASS';
END $$;
ROLLBACK;
