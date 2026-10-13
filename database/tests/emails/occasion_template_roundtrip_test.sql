-- Reproduce an occasion moved to another unit, with an older template and
-- an override saved under its current ancestry. No messages are sent.
BEGIN;
-- Local rollback-only legacy fixture: production migration removes these duplicates.
DROP INDEX IF EXISTS public.email_templates_occasion_code_unique;
DO $$
DECLARE
  org_id bigint;
  old_unit bigint;
  new_unit bigint;
  oc bigint;
  sibling bigint;
  resolved jsonb;
  payload jsonb;
  selected_id bigint;
BEGIN
  INSERT INTO public.organizations(title) VALUES ('Template roundtrip') RETURNING id INTO org_id;
  INSERT INTO public.units(title,organization) VALUES ('Old unit',org_id) RETURNING id INTO old_unit;
  INSERT INTO public.units(title,organization) VALUES ('Current unit',org_id) RETURNING id INTO new_unit;
  INSERT INTO public.occasions(title,link,unit,organization,start_time,end_time)
    VALUES ('Moved occasion',gen_random_uuid()::text,new_unit,org_id,now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO public.occasions(title,link,unit,organization,start_time,end_time)
    VALUES ('Sibling occasion',gen_random_uuid()::text,new_unit,org_id,now(),now()+interval '1 day') RETURNING id INTO sibling;
  INSERT INTO public.email_wrappers(occasion,unit,organization,html)
    VALUES (oc,old_unit,org_id,'<event>{{content}}</event>'),
           (NULL,new_unit,org_id,'<unit>{{content}}</unit>'),
           (NULL,NULL,org_id,'<org>{{content}}</org>');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.get_resolved_email_template(text,jsonb)','EXECUTE'),
    'Internal selector is not exposed as an authenticated RPC');
  INSERT INTO public.email_templates(code,subject,html,occasion,unit,organization)
    VALUES ('TICKET_ORDER_CONFIRMATION','Old subject','Old body',oc,old_unit,org_id),
           ('TICKET_ORDER_CONFIRMATION','Saved subject','Saved body',oc,new_unit,org_id),
           ('TICKET_ORDER_CONFIRMATION','Unit subject','Unit body',NULL,new_unit,org_id),
           ('TICKET_ORDER_CONFIRMATION','Org subject','Org body',NULL,NULL,org_id);
  resolved := public.get_entity_email_templates('occasion',oc);
  SELECT value INTO resolved FROM jsonb_array_elements(resolved->'templates')
    WHERE value->>'code'='TICKET_ORDER_CONFIRMATION';
  PERFORM assert_eq(resolved->>'html','Saved body','Reload shows the saved override instead of its stale ancestor duplicate');
  PERFORM assert_eq(
    public.get_email_template_and_wrapper('TICKET_ORDER_CONFIRMATION',
      jsonb_build_object('occasion',oc))#>>'{template,html}',
    resolved->>'html','Legacy editor and sender use the same selector');
  selected_id := (resolved->>'id')::bigint;
  DELETE FROM public.email_templates WHERE occasion=oc AND unit=old_unit;
  CREATE UNIQUE INDEX email_templates_occasion_code_unique ON public.email_templates(occasion,code) WHERE occasion IS NOT NULL;
  BEGIN
    INSERT INTO public.email_templates(code,subject,html,occasion,unit,organization)
      VALUES ('TICKET_ORDER_CONFIRMATION','Duplicate','Duplicate',oc,old_unit,org_id);
    RAISE EXCEPTION 'Duplicate occasion template was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  payload := jsonb_build_object('occasion',oc,'unit',new_unit,'organization',org_id,
    'code','TICKET_ORDER_CONFIRMATION','subject','Edited subject','html','Edited body');
  PERFORM public.update_email_template(payload);
  PERFORM public.update_email_template(payload);
  PERFORM assert_eq((SELECT count(*)::int FROM public.email_templates WHERE occasion=oc AND code='TICKET_ORDER_CONFIRMATION'),1,
    'Repeated save does not create another occasion override');
  resolved := public.get_email_template_and_wrapper('TICKET_ORDER_CONFIRMATION',jsonb_build_object('occasion',oc,'unit',new_unit,'organization',org_id));
  PERFORM assert_eq(resolved#>>'{template,html}','Edited body','Email preparation uses edited occasion content');
  PERFORM assert_eq(resolved#>>'{template,subject}','Edited subject','Email preparation uses edited subject');
  PERFORM assert_eq((resolved#>>'{template,id}')::bigint,selected_id,'Editor and sender select the same override');
  -- An occasion-only context must resolve parents, not allow sibling templates.
  resolved := public.get_email_template_and_wrapper('TICKET_ORDER_CONFIRMATION',jsonb_build_object('occasion',sibling));
  PERFORM assert_eq(resolved#>>'{template,html}','Unit body','Sibling inherits only its own unit override');
  PERFORM assert_eq(resolved#>>'{wrapper,html}','<unit>{{content}}</unit>','Sibling does not inherit another occasion wrapper');
  UPDATE public.email_templates SET unit=old_unit WHERE occasion=oc;
  -- Saving the remaining old-ancestry row must update it, not insert again.
  PERFORM public.update_email_template(payload);
  PERFORM assert_eq((SELECT count(*)::int FROM public.email_templates WHERE occasion=oc AND code='TICKET_ORDER_CONFIRMATION'),1,
    'Save repairs old ancestry without creating a duplicate');
  resolved := public.get_entity_email_templates('occasion',oc);
  SELECT value INTO resolved FROM jsonb_array_elements(resolved->'templates') WHERE value->>'code'='TICKET_ORDER_CONFIRMATION';
  PERFORM assert_eq(resolved->>'html','Edited body','Repaired template survives reload');
  PERFORM assert_eq((resolved->>'unit')::bigint,new_unit,'Save normalizes ancestor metadata');
  DELETE FROM public.email_templates WHERE occasion=oc;
  resolved := public.get_email_template_and_wrapper('TICKET_ORDER_CONFIRMATION',jsonb_build_object('occasion',oc));
  PERFORM assert_eq(resolved#>>'{template,html}','Unit body','Deleting occasion override restores unit inheritance');
  DELETE FROM public.email_templates WHERE unit=new_unit;
  resolved := public.get_email_template_and_wrapper('TICKET_ORDER_CONFIRMATION',jsonb_build_object('occasion',oc));
  PERFORM assert_eq(resolved#>>'{template,html}','Org body','Missing unit override restores organization inheritance');
END $$;
ROLLBACK;
