-- Task-owned synthetic E2E fixture only. Run psql -v fixture_form=2.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment) THEN RAISE EXCEPTION 'disposable fixture database required'; END IF;
END $$;
UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,link,true)
 WHERE id=(SELECT occasion FROM public.forms WHERE id=:'fixture_form'::bigint);
UPDATE public.forms SET type='ticket',link=public.reserve_public_link_internal('form',id,link,true) WHERE id=:'fixture_form'::bigint;
INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,"order",data)
 SELECT :'fixture_form'::bigint,'Email','email',true,false,false,0,'{}' WHERE NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=:'fixture_form'::bigint AND type='email' AND NOT is_ticket_field);
INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,"order",data)
 SELECT :'fixture_form'::bigint,'Tickets','ticket',true,false,false,10,'{"max_tickets":20}' WHERE NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=:'fixture_form'::bigint AND type='ticket');
INSERT INTO public.form_fields(form,title,type,is_required,is_hidden,is_ticket_field,"order",data)
 SELECT :'fixture_form'::bigint,'Seat','spot',false,false,true,20,'{}' WHERE NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=:'fixture_form'::bigint AND type='spot' AND is_ticket_field);
UPDATE public.form_fields SET is_hidden=false,is_ticket_field=false,is_required=true,data=coalesce(data,'{}')||'{"max_tickets":20}' WHERE form=:'fixture_form'::bigint AND type='ticket';
UPDATE public.form_fields SET is_hidden=false,is_ticket_field=true,is_required=false WHERE form=:'fixture_form'::bigint AND type='spot';
UPDATE public.form_fields SET title='Admission',"order"=30,data=coalesce(data,'{}')||'{"selection_type":"select_one"}' WHERE form=:'fixture_form'::bigint AND type='product_type';
COMMIT;
