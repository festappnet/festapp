SET request.jwt.claim.role='service_role';
DO $$ DECLARE org bigint;u bigint;occ bigint;bank bigint;pi bigint;ord bigint; BEGIN
 IF to_regclass('eshop.stripe_connections') IS NOT NULL THEN RAISE EXCEPTION 'Upgrade fixture must precede Stripe'; END IF;
 INSERT INTO public.organizations(title,data) VALUES('Stripe upgrade bank fixture','{"DEFAULT_URL":"https://fixture.example"}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Bank organizer',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Before Stripe',org,u,'stripe-readiness-bank-fixture',now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies) VALUES('Bank fixture','fixture/2010','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(u,bank);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,paid,returned,currency_code) VALUES(bank,912345,123.45,123.45,0,'CZK') RETURNING id INTO pi;
 INSERT INTO eshop.orders(occasion,payment_info,order_sequence,order_symbol,price,currency_code,state) VALUES(occ,pi,public.next_order_sequence(occ),public.generate_order_symbol(),123.45,'CZK','paid') RETURNING id INTO ord;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date) VALUES(bank,pi,123.45,'CZK','2026-10-21');
END $$;
