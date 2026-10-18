-- Synthetic, transaction-local tenant; runner rolls back every fixture and RPC write.
CREATE FUNCTION pg_temp.legal_fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; other_org bigint; un bigint; spare bigint; manager uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); editor uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Legal fixture','{"DEFAULT_URL":"https://example.invalid"}') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other legal fixture') RETURNING id INTO other_org;
 INSERT INTO public.units(title,organization) VALUES('Legal fixture',org) RETURNING id INTO un;
 INSERT INTO public.units(title,organization) VALUES('Spare legal fixture',org) RETURNING id INTO spare;
 INSERT INTO auth.users(id,email) VALUES(manager,manager||'@example.invalid'),(admin,admin||'@example.invalid'),(outsider,outsider||'@example.invalid'),(editor,editor||'@example.invalid');
 INSERT INTO public.user_info(id,organization) VALUES(manager,org),(admin,org),(outsider,other_org),(editor,org);
 UPDATE public.user_info SET email_readonly=id||'@example.invalid' WHERE id IN (manager,admin,outsider,editor);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,manager,true,true),(spare,manager,true,true),(un,editor,false,true);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,admin,true),(other_org,outsider,true);
 PERFORM set_config('request.jwt.claim.sub',manager::text,true);
 RETURN jsonb_build_object('organization',org,'otherOrganization',other_org,'unit',un,'spare',spare,'manager',manager,'admin',admin,'outsider',outsider,'editor',editor);
END $$;
CREATE FUNCTION pg_temp.legal_data() RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"legalName":"  Kulturní spolek  ","countryCode":"cz","registrationNumber":"27074358","address":{"street":"Dlouhá 1","city":"Praha","postalCode":"11000"},"contactEmail":"PUBLIC@example.invalid","website":"https://example.invalid"}'::jsonb;
$$;
DO $$
DECLARE x jsonb:=pg_temp.legal_fixture(); un bigint:=(x->>'unit')::bigint; oc bigint; f bigint; oid bigint; offer uuid; r jsonb; identity jsonb; token text:=repeat('e',64); link text:=gen_random_uuid()::text; keys text[];
BEGIN
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,features) VALUES('Legal public',un,(x->>'organization')::bigint,gen_random_uuid()::text,now(),now()+interval '1 day','[]') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,link,is_open) VALUES(oc,link,true) RETURNING id INTO f;
 PERFORM public.reserve_public_link_internal('form',f,link,true);
 PERFORM assert_true(public.get_verified_unit_identity_internal(un) IS NULL,'missing profile is private');
 PERFORM public.save_unit_legal_profile(un,0,pg_temp.legal_data());
 PERFORM assert_true(public.get_verified_unit_identity_internal(un) IS NULL,'draft is private');
 PERFORM public.submit_unit_verification(un,1);
 PERFORM assert_true(public.get_verified_unit_identity_internal(un) IS NULL,'pending is private');
 PERFORM set_config('request.jwt.claim.sub',x->>'admin',true);
 PERFORM public.review_unit_verification(un,2,'approve',NULL,'SECRET-NOTE','SECRET-SOURCE');
 identity:=public.get_verified_unit_identity_internal(un);
 SELECT array_agg(key ORDER BY key) INTO keys FROM jsonb_object_keys(identity) key;
 PERFORM assert_eq(keys,ARRAY['address','contactEmail','countryCode','legalName','registrationNumber','revision','unitId','verifiedAt','website']::text[],'exact public whitelist with omitted empty optionals');
 PERFORM set_config('request.jwt.claim.sub','',true);
 r:=public.get_form_by_link(link)::jsonb;
 PERFORM assert_eq(r->>'code','200'::text,'open form succeeds');
 PERFORM assert_eq(r#>'{data,organizationIdentity}',identity,'open form identity');
 PERFORM assert_false(r::text LIKE '%SECRET-%','no private review leakage');
 UPDATE public.forms SET is_open=false WHERE id=f;
 r:=public.get_form_by_link(link)::jsonb;
 PERFORM assert_eq(r->>'code','400'::text,'closed form reduced');
 PERFORM assert_eq(r#>'{data,organizationIdentity}',identity,'closed form identity');
 INSERT INTO eshop.orders(id,occasion,form,order_symbol,order_sequence,state,price,data) VALUES(nextval('eshop.orders_id_seq'),oc,f,'1A2C3E4F5G',1,'waitlisted',NULL,'{}') RETURNING id INTO oid;
 INSERT INTO eshop.waitlist_capabilities(token_hash,organization_id,form_id,order_id,kind,expires_at) VALUES(encode(extensions.digest(token,'sha256'),'hex'),(x->>'organization')::bigint,f,oid,'order_view',now()+interval '1 day');
 r:=public.get_customer_order_overview(token,oid);
 PERFORM assert_eq(r->>'code','200'::text,'valid overview capability');
 PERFORM assert_eq(r->'organizationIdentity',identity,'overview shares projection');
 r:=public.get_customer_order_overview(repeat('f',64),oid);
 PERFORM assert_eq(r->>'code','403'::text,'bad capability rejected');
 PERFORM assert_false(r?'organizationIdentity','bad capability leaks no identity');
 UPDATE eshop.waitlist_capabilities SET kind='manage' WHERE order_id=oid;
 r:=public.get_waitlist_offer_form(token,NULL,oid);
 PERFORM assert_eq(r->>'code','200'::text,'valid closed waitlist capability');
 PERFORM assert_eq(r#>'{form,organizationIdentity}',identity,'waitlist shares closed-enabled builder');
 INSERT INTO eshop.waitlist_offers(order_id,form_id,expires_at,revision) VALUES(oid,f,now()+interval '1 hour',1) RETURNING id INTO offer;
 UPDATE eshop.waitlist_capabilities SET kind='offer',offer_id=offer WHERE order_id=oid;
 r:=public.get_waitlist_offer_form(token,offer,NULL);
 PERFORM assert_eq(r->>'code','200'::text,'terminal offer authorized');
 PERFORM assert_eq(r->'organizationIdentity',identity,'terminal offer identity without form');
 PERFORM assert_eq(public.get_form_by_link('missing-'||link)::jsonb->>'code','404'::text,'missing form no identity');
 UPDATE public.occasions SET unit=(x->>'spare')::bigint WHERE id=oc;
 PERFORM assert_eq(public.get_form_by_link(link)::jsonb#>'{data,organizationIdentity}','null'::jsonb,'moving event uses new Unit identity');
 UPDATE public.occasions SET unit=un,organization=(x->>'otherOrganization')::bigint WHERE id=oc;
 PERFORM assert_eq(public.get_form_by_link(link)::jsonb#>'{data,organizationIdentity}','null'::jsonb,'mismatched occasion tenant hides identity');
END $$;
