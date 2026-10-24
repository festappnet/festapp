-- Synthetic local fixture completion; no production data or payments.
DO $$ BEGIN IF (SELECT title FROM public.organizations WHERE id=1)<>'Test Organization' THEN RAISE EXCEPTION 'Synthetic backend required'; END IF; END $$;
UPDATE eshop.bank_accounts SET account_number_human_readable='123456/0100',creditor_name='Synthetic Organizer' WHERE title='Synthetic bank';
INSERT INTO public.occasion_users(occasion,"user",is_editor)
SELECT o.id,u.id,true FROM public.occasions o CROSS JOIN auth.users u
WHERE o.link='embedded-event' AND u.email='1+t@t.com'
AND NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=o.id AND ou."user"=u.id);
UPDATE public.occasion_users SET is_editor_view=true,is_manager=true,is_editor_order=true,is_editor_order_view=true,is_approved=true
WHERE occasion=(SELECT id FROM public.occasions WHERE link='embedded-event') AND "user"=(SELECT id FROM auth.users WHERE email='1+t@t.com');
UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,link,true)
WHERE link='embedded-event';
UPDATE public.forms SET participant_capacity=20 WHERE link='embedded-synthetic' AND participant_capacity IS NULL;
UPDATE eshop.products p SET occasion=pt.occasion FROM eshop.product_types pt
WHERE p.product_type=pt.id AND pt.occasion=(SELECT id FROM public.occasions WHERE link='embedded-event') AND p.occasion IS NULL;

-- Buyer identity belongs to the order once, not to every admission ticket.
UPDATE public.form_fields ff SET is_ticket_field=false
FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
WHERE ff.form=f.id AND o.link='embedded-event' AND ff.type IN ('name','surname');
