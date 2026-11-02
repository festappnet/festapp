-- Correct only the task-owned disposable demo; never reseed user edits.
BEGIN;
DO $$
DECLARE oc bigint; form_id bigint; field_ids text[]; category bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE project='festapp-order-detail-20261101') THEN
  RAISE EXCEPTION 'Wrong review sandbox';
 END IF;
 SELECT id INTO STRICT oc FROM public.occasions WHERE link='order-detail-ples';
 SELECT id INTO STRICT form_id FROM public.forms WHERE occasion=oc AND title='Vstupenky na zimní ples';
 SELECT coalesce(array_agg(id::text),'{}') INTO field_ids FROM public.form_fields
 WHERE form=form_id AND is_ticket_field AND
  ((type='name' AND title='Jméno účastníka') OR (type='select_one' AND title='Strava'));
 IF cardinality(field_ids) NOT IN (0,2) THEN RAISE EXCEPTION 'Unexpected demo field definitions'; END IF;
 UPDATE eshop.tickets t SET data=jsonb_set(t.data,'{fields}',(
  SELECT coalesce(jsonb_agg(clean ORDER BY n) FILTER(WHERE clean<>'{}'::jsonb),'[]')
  FROM (SELECT value-field_ids AS clean,n FROM jsonb_array_elements(t.data->'fields') WITH ORDINALITY a(value,n)) v
 )) WHERE t.occasion=oc AND jsonb_typeof(t.data->'fields')='array' AND cardinality(field_ids)>0;
 UPDATE eshop.orders o SET data=jsonb_set(o.data,'{tickets}',(
  SELECT coalesce(jsonb_agg(CASE WHEN jsonb_typeof(value->'fields')='array' THEN
   jsonb_set(value,'{fields}',(SELECT coalesce(jsonb_agg(clean ORDER BY m) FILTER(WHERE clean<>'{}'::jsonb),'[]')
    FROM (SELECT x-field_ids AS clean,m FROM jsonb_array_elements(value->'fields') WITH ORDINALITY b(x,m)) v))
   ELSE value END ORDER BY n),'[]')
  FROM jsonb_array_elements(o.data->'tickets') WITH ORDINALITY a(value,n)
 )) WHERE o.occasion=oc AND jsonb_typeof(o.data->'tickets')='array' AND cardinality(field_ids)>0;
 DELETE FROM public.form_fields WHERE form=form_id AND id::text=ANY(field_ids);
 SELECT id INTO STRICT category FROM eshop.product_types WHERE occasion=oc AND title='Doplňky';
 INSERT INTO public.form_fields(form,title,type,is_ticket_field,"order",product_type)
 SELECT form_id,'Doplňky','product_type',true,3,category
 WHERE NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=form_id AND product_type=category AND is_ticket_field);
END $$;
COMMIT;
