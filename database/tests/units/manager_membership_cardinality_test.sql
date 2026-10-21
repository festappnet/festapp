-- Explicit historical-schema-drift simulation, not evidence of live duplicate
-- memberships: canonical tables.sql and baseline both require (unit,"user") PK.
-- The runner wraps this entire test in a rollback, restoring rows, PK and bodies.
ALTER TABLE public.unit_users DROP CONSTRAINT unit_users_pkey;
DO $$
DECLARE
 actor uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); org bigint; foreign_org bigint;
 own_unit bigint; foreign_unit bigint; account bigint; occ bigint;
 fixed_definition text; diagnostic text; error_code text; n bigint; organization_data jsonb;
BEGIN
 SELECT pg_get_functiondef('public.get_is_manager_on_unit(bigint)'::regprocedure) INTO fixed_definition;
 INSERT INTO auth.users(id,email,aud,role) VALUES
  (actor,'manager-drift-'||actor||'@example.invalid','authenticated','authenticated'),
  (outsider,'outsider-drift-'||outsider||'@example.invalid','authenticated','authenticated');
 INSERT INTO public.organizations(title) VALUES('Membership drift fixture') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Foreign membership fixture') RETURNING id INTO foreign_org;
 INSERT INTO public.user_info(id,organization) VALUES(actor,org),(outsider,org);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,actor,true);
 INSERT INTO public.units(title,organization) VALUES('Membership drift unit',org) RETURNING id INTO own_unit;
 INSERT INTO public.units(title,organization) VALUES('Foreign membership unit',foreign_org) RETURNING id INTO foreign_unit;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES
  (own_unit,actor,true,true),(own_unit,actor,false,true),
  (own_unit,outsider,false,true),(own_unit,outsider,false,false),
  (foreign_unit,actor,false,true);
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies)
 VALUES('Membership drift bank','FIO',ARRAY['CZK']) RETURNING id INTO account;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(own_unit,account,0);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);

 -- Exact former scalar semantics, retaining the installed demo write fence.
 EXECUTE $legacy$
 CREATE OR REPLACE FUNCTION public.get_is_manager_on_unit(unit_id bigint) RETURNS bool
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $body$
  SELECT NOT public.is_demo_unit(unit_id) AND coalesce((
   SELECT is_manager FROM public.unit_users
   WHERE "user"=auth.uid() AND unit=unit_id),false)
 $body$
 $legacy$;
 EXECUTE 'SET LOCAL ROLE authenticated';
 organization_data:=public.get_current_organization_data();
 IF organization_data->>'code' IS DISTINCT FROM '200' THEN
  RAISE EXCEPTION 'Independent organization lookup unexpectedly failed'; END IF;
 BEGIN
  PERFORM public.get_bank_accounts_for_unit_management(own_unit);
  RAISE EXCEPTION 'Historical duplicate memberships did not reproduce scalar failure';
 EXCEPTION WHEN cardinality_violation THEN
  GET STACKED DIAGNOSTICS diagnostic=PG_EXCEPTION_CONTEXT,error_code=RETURNED_SQLSTATE;
  RAISE NOTICE 'Simulated historical drift reproduced SQLSTATE %: %',error_code,diagnostic;
 END;
 EXECUTE 'RESET ROLE';
 EXECUTE fixed_definition;

 EXECUTE 'SET LOCAL ROLE authenticated';
 IF public.get_is_manager_on_unit(own_unit) IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Any true membership must confer manager access'; END IF;
 SELECT count(*) INTO n FROM public.get_bank_accounts_for_unit_management(own_unit);
 IF n<>1 THEN RAISE EXCEPTION 'Fixed bank list must retain the linked account'; END IF;
 IF public.get_is_manager_on_unit(foreign_unit) IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Other unit editor role conferred manager access'; END IF;
 BEGIN
  PERFORM public.get_bank_accounts_for_unit_management(foreign_unit);
  RAISE EXCEPTION 'Foreign unit bank management accepted editor';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'User is not manager.' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 IF public.get_is_manager_on_unit(own_unit) IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Multiple false memberships must not confer access'; END IF;
 BEGIN
  PERFORM public.get_bank_accounts_for_unit_management(own_unit);
  RAISE EXCEPTION 'Non-manager bank list accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'User is not manager.' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','',true);
 IF public.get_is_manager_on_unit(own_unit) IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Unauthenticated manager lookup must deny'; END IF;
 EXECUTE 'RESET ROLE';

 -- Existing membership must not restore mutation rights on a demo unit.
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,own_unit,'Demo drift fixture','demo-drift-'||actor,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,is_listed,sort_order,description,reference_at)
 VALUES(occ,org,'ball','membership-drift',account,false,0,'Synthetic fixture',now());
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF public.get_is_manager_on_unit(own_unit) IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Demo guard was lost by existential membership fix'; END IF;
 EXECUTE 'RESET ROLE';
 RAISE NOTICE 'Existential manager lookup passed duplicate roles, bank list, denied and demo guards';
END $$;
