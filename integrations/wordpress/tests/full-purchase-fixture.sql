-- Actual checkout demo, only in the owned disposable backend. Never production.
DO $$
DECLARE f bigint;
BEGIN
 IF (SELECT title FROM public.organizations WHERE id=1)<>'Test Organization' THEN
  RAISE EXCEPTION 'Synthetic backend required';
 END IF;
 SELECT id INTO f FROM public.forms WHERE link='wordpress-nakup';
 IF f IS NOT NULL THEN RETURN; END IF;
 PERFORM set_config('request.jwt.claim.sub',(SELECT id::text FROM auth.users WHERE email='1+t@t.com'),true);
 f:=public.duplicate_form_to_occasion_internal_v1((SELECT id FROM public.forms WHERE link='embedded-synthetic'),'embedded-event','cs');
 UPDATE public.forms SET
  link=public.reserve_public_link_internal('form',f,'wordpress-nakup',true),
  title='Vstupenky na ukázkový ples',
  header='<h1>Vstupenky na ukázkový ples</h1><p>Vyplňte údaje objednávky a přidejte jednu nebo více vstupenek.</p>',
  participant_capacity=100
 WHERE id=f;
 DELETE FROM public.form_fields WHERE form=f AND type='birth_date';
 UPDATE public.form_fields SET data=coalesce(data,'{}')||'{"max_tickets":5}'::jsonb WHERE form=f AND type='ticket';
 UPDATE public.form_fields SET "order"=CASE type WHEN 'email' THEN 1 WHEN 'name' THEN 2 WHEN 'surname' THEN 3 WHEN 'ticket' THEN 10 ELSE "order" END WHERE form=f;
 UPDATE public.form_fields SET title='Vstupné' WHERE form=f AND type='product_type';
 UPDATE eshop.products p SET title='Základní vstupenka'
 FROM public.form_fields ff WHERE ff.form=f AND ff.product_type=p.product_type;
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order") VALUES
 (f,'phone','Telefon',false,false,false,4),
 (f,'note','Poznámka k objednávce',false,false,false,5),
 (f,'text','Požadavek k této vstupence',false,false,true,30);
END $$;
NOTIFY pgrst,'reload schema';
