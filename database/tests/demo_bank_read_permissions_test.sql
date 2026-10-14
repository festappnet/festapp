-- Run against the owned synthetic demo fixture, never production.
BEGIN;
DO $$
DECLARE actor uuid; oc bigint; bank bigint; pay bigint; foreign_org bigint; n bigint;
BEGIN
 PERFORM create_user_for_test('demo_bank_reader','demo-bank-reader@example.invalid');
 actor:=get_user_id('demo_bank_reader');
 UPDATE public.user_info SET organization=1 WHERE id=actor;
 SELECT occasion,bank_account INTO STRICT oc,bank FROM public.demo_occasions
  WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='ball';
 SELECT payment_info INTO STRICT pay FROM eshop.orders WHERE occasion=oc AND payment_info IS NOT NULL LIMIT 1;
 UPDATE public.demo_occasions SET is_listed=true WHERE occasion=oc;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 PERFORM assert_eq((SELECT count(*) FROM eshop.bank_accounts WHERE id=bank),1::bigint,'demo account readable without bank admin');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.transactions WHERE bank_account_id=bank AND payment_info IS NULL),'unmatched demo movement readable');
 PERFORM assert_true(jsonb_array_length(public.get_transactions_for_order_all_available(pay))>0,'existing transaction reader works');
 BEGIN
  PERFORM public.update_bank_account(bank,'123/0100','Unauthorized change');
  RAISE EXCEPTION 'bank write accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.form_fields(form,type,title) SELECT id,'text','Unauthorized field' FROM public.forms WHERE occasion=oc LIMIT 1;
  RAISE EXCEPTION 'direct demo field creation accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 -- Even an inherited/admin role cannot change a protected bank through RLS.
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor)
 SELECT unit,actor,true,true FROM public.occasions WHERE id=oc;
 PERFORM assert_false(public.get_is_manager_on_unit((SELECT unit FROM public.occasions WHERE id=oc)),'demo unit manager blocked');
 PERFORM assert_false(public.check_upload_permission(p_unit_id => (SELECT unit FROM public.occasions WHERE id=oc)),'demo unit media upload blocked');
 SET LOCAL ROLE authenticated;
 UPDATE eshop.bank_accounts SET title='Unauthorized change' WHERE id=bank;
 GET DIAGNOSTICS n=ROW_COUNT;
 PERFORM assert_eq(n,0::bigint,'direct bank update denied even to bank admin');
 RESET ROLE;
 INSERT INTO public.organizations(title) VALUES('Foreign bank reader tenant') RETURNING id INTO foreign_org;
 UPDATE public.user_info SET organization=foreign_org WHERE id=actor;
 SET LOCAL ROLE authenticated;
 PERFORM assert_eq((SELECT count(*) FROM eshop.bank_accounts WHERE id=bank),0::bigint,'foreign tenant cannot read protected bank');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.transactions WHERE bank_account_id=bank),'foreign tenant cannot read protected movements');
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub','',true);
 SET LOCAL ROLE anon;
 PERFORM assert_eq((SELECT count(*) FROM public.demo_occasions),0::bigint,'anonymous registry read reveals no demo identities');
 RESET ROLE;
END $$;
ROLLBACK;
