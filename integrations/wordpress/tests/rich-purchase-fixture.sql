-- Additional public demo in the owned disposable WordPress backend only.
DO $$
DECLARE f bigint;
BEGIN
 IF (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization'
    OR NOT EXISTS(SELECT 1 FROM public.forms WHERE link='wordpress-nakup') THEN
  RAISE EXCEPTION 'Disposable WordPress checkout fixture required';
 END IF;
 IF EXISTS(SELECT 1 FROM public.forms WHERE link='wordpress-podrobny') THEN RETURN; END IF;
 PERFORM set_config('request.jwt.claim.sub',(SELECT id::text FROM auth.users WHERE email='1+t@t.com'),true);
 f:=public.duplicate_form_to_occasion_internal_v1(
  (SELECT id FROM public.forms WHERE link='wordpress-nakup'),'embedded-event','cs');
 UPDATE public.forms SET
  link=public.reserve_public_link_internal('form',f,'wordpress-podrobny',true),
  title='Podrobný formulář s údaji návštěvníků',
  header='<h1>Podrobný formulář s údaji návštěvníků</h1><p>Vyplňte kontaktní údaje objednávky a samostatné údaje pro každou vstupenku. Před odesláním si vše zkontrolujete v rekapitulaci.</p>',
  participant_capacity=100
 WHERE id=f;
 UPDATE public.form_fields SET title=CASE type
  WHEN 'email' THEN 'E-mail' WHEN 'name' THEN 'Jméno objednávajícího'
  WHEN 'surname' THEN 'Příjmení objednávajícího' WHEN 'ticket' THEN 'Vstupenky'
  ELSE title END WHERE form=f;
 UPDATE public.form_fields SET title='Poznámka k návštěvníkovi' WHERE form=f AND type='text';
 INSERT INTO public.form_fields(form,type,title,is_required,is_hidden,is_ticket_field,"order",data) VALUES
 (f,'text','Organizace nebo firma',false,false,false,6,NULL),
 (f,'address','Ulice a číslo domu',false,false,false,7,NULL),
 (f,'city','Město',false,false,false,8,NULL),
 (f,'select_many','Co vás zajímá',false,false,false,9,
  '{"options":[{"value":"Hudební program"},{"value":"Doprovodný program"},{"value":"Setkání s přáteli"}]}'::jsonb),
 (f,'text','Jméno návštěvníka',false,false,true,10,NULL),
 (f,'select_one','Stravování',false,false,true,20,
  '{"options":[{"value":"Běžné menu"},{"value":"Vegetariánské menu"},{"value":"Bez jídla"}]}'::jsonb);
END $$;
