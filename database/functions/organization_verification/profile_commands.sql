CREATE OR REPLACE FUNCTION public.get_unit_legal_profile(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE p public.unit_legal_profiles; org bigint; admin boolean; result jsonb;
BEGIN
 SELECT organization INTO org FROM public.units WHERE id=p_unit;
 admin:=coalesce(public.check_is_admin_of_organization(org),false);
 IF auth.uid() IS NULL OR org IS NULL OR NOT (public.get_is_manager_on_unit(p_unit) OR admin) THEN
  RAISE EXCEPTION 'Legal profile access denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO p FROM public.unit_legal_profiles WHERE unit_id=p_unit;
 result:=jsonb_build_object('unitId',p_unit,'revision',coalesce(p.revision,0),'status',coalesce(p.status,'unverified'),
 'legalName',coalesce(p.legal_name,''),'countryCode',coalesce(p.country_code,''),
 'registrationNumber',coalesce(p.registration_number,''),'vatId',coalesce(p.vat_id,''),
 'address',jsonb_build_object('street',coalesce(p.street,''),'city',coalesce(p.city,''),'postalCode',coalesce(p.postal_code,'')),
 'contactEmail',coalesce(p.contact_email,''),'phone',coalesce(p.phone,''),'website',coalesce(p.website,''),
 'submittedAt',p.submitted_at,'verifiedAt',CASE WHEN p.status='verified' AND p.reviewed_organization_id=org THEN p.reviewed_at END,
 'feedbackToApplicant',CASE WHEN p.reviewed_organization_id=org THEN p.feedback_to_applicant END);
 IF admin AND p.reviewed_organization_id=org THEN
  result:=result||jsonb_build_object('reviewNote',p.review_note,'reviewSource',p.review_source);
 END IF;
 RETURN jsonb_build_object('code',200,'profile',result);
END $$;

CREATE OR REPLACE FUNCTION public.save_unit_legal_profile(p_unit bigint,p_expected_revision bigint,p_profile jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE p public.unit_legal_profiles; n public.unit_legal_profiles; org bigint; k text; v text;
 errors jsonb:='{}'; normalized jsonb; old_values jsonb; checksum integer:=0; i integer;
BEGIN
 SELECT organization INTO org FROM public.units WHERE id=p_unit FOR UPDATE;
 IF auth.uid() IS NULL OR org IS NULL OR NOT public.get_is_manager_on_unit(p_unit) OR public.is_demo_unit(p_unit) THEN
  RAISE EXCEPTION 'Legal profile write denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO p FROM public.unit_legal_profiles WHERE unit_id=p_unit FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM coalesce(p.revision,0) THEN
  RETURN jsonb_build_object('code',409,'errorCode','REVISION_CONFLICT','profile',public.get_unit_legal_profile(p_unit)->'profile');
 END IF;
 IF jsonb_typeof(p_profile) IS DISTINCT FROM 'object' THEN
  RETURN jsonb_build_object('code',422,'errorCode','INVALID_PROFILE','fieldErrors',jsonb_build_object('profile','OBJECT_REQUIRED'));
 END IF;
 FOR k IN SELECT jsonb_object_keys(p_profile) LOOP
  IF k<>ALL(ARRAY['legalName','countryCode','registrationNumber','vatId','address','contactEmail','phone','website']) THEN errors:=errors||jsonb_build_object(k,'UNKNOWN_FIELD'); END IF;
  IF k<>'address' AND jsonb_typeof(p_profile->k) NOT IN ('string','null') THEN errors:=errors||jsonb_build_object(k,'TEXT_REQUIRED'); END IF;
 END LOOP;
 IF p_profile ? 'address' AND jsonb_typeof(p_profile->'address') IS DISTINCT FROM 'object' THEN
  errors:=errors||jsonb_build_object('address','OBJECT_REQUIRED');
 ELSE
  FOR k IN SELECT jsonb_object_keys(coalesce(p_profile->'address','{}')) LOOP
   IF k<>ALL(ARRAY['street','city','postalCode']) THEN errors:=errors||jsonb_build_object('address.'||k,'UNKNOWN_FIELD'); END IF;
   IF jsonb_typeof(p_profile->'address'->k) NOT IN ('string','null') THEN errors:=errors||jsonb_build_object('address.'||k,'TEXT_REQUIRED'); END IF;
  END LOOP;
 END IF;
 IF errors<>'{}' THEN RETURN jsonb_build_object('code',422,'errorCode','INVALID_PROFILE','fieldErrors',errors); END IF;
 n.legal_name:=btrim(coalesce(p_profile->>'legalName',''));
 n.country_code:=upper(btrim(coalesce(p_profile->>'countryCode','')));
 n.registration_number:=btrim(coalesce(p_profile->>'registrationNumber',''));
 n.vat_id:=btrim(coalesce(p_profile->>'vatId',''));
 n.street:=btrim(coalesce(p_profile#>>'{address,street}',''));
 n.city:=btrim(coalesce(p_profile#>>'{address,city}',''));
 n.postal_code:=btrim(coalesce(p_profile#>>'{address,postalCode}',''));
 n.contact_email:=lower(btrim(coalesce(p_profile->>'contactEmail','')));
 n.phone:=btrim(coalesce(p_profile->>'phone',''));
 n.website:=btrim(coalesce(p_profile->>'website',''));
 normalized:=jsonb_build_object('legalName',n.legal_name,'countryCode',n.country_code,'registrationNumber',n.registration_number,
 'vatId',n.vat_id,'address',jsonb_build_object('street',n.street,'city',n.city,'postalCode',n.postal_code),
 'contactEmail',n.contact_email,'phone',n.phone,'website',n.website);
 FOR k,v IN SELECT key,value#>>'{}' FROM jsonb_each(normalized-'address') LOOP
  IF length(v)>(CASE k WHEN 'legalName' THEN 200 WHEN 'contactEmail' THEN 254 WHEN 'website' THEN 500 WHEN 'phone' THEN 40 WHEN 'countryCode' THEN 2 ELSE 50 END)
   OR v ~ '[[:cntrl:]]' THEN errors:=errors||jsonb_build_object(k,'INVALID_LENGTH_OR_CHARACTERS'); END IF;
 END LOOP;
 IF length(n.street)>200 OR length(n.city)>100 OR length(n.postal_code)>20 OR (n.street||n.city||n.postal_code) ~ '[[:cntrl:]]' THEN errors:=errors||jsonb_build_object('address','INVALID_ADDRESS'); END IF;
 IF n.country_code<>'' AND n.country_code !~ '^[A-Z]{2}$' THEN errors:=errors||jsonb_build_object('countryCode','INVALID_COUNTRY'); END IF;
 IF n.registration_number<>'' AND n.country_code='CZ' THEN
  IF n.registration_number !~ '^[0-9]{8}$' THEN errors:=errors||jsonb_build_object('registrationNumber','INVALID_CZ_ICO');
  ELSE
   FOR i IN 1..7 LOOP checksum:=checksum+substring(n.registration_number,i,1)::integer*(9-i); END LOOP;
   IF ((11-checksum%11)%10)<>substring(n.registration_number,8,1)::integer THEN errors:=errors||jsonb_build_object('registrationNumber','INVALID_CZ_ICO'); END IF;
  END IF;
 END IF;
 IF n.contact_email<>'' AND n.contact_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN errors:=errors||jsonb_build_object('contactEmail','INVALID_EMAIL'); END IF;
 IF n.phone<>'' AND n.phone !~ '^[+0-9][0-9 ()-]{2,39}$' THEN errors:=errors||jsonb_build_object('phone','INVALID_PHONE'); END IF;
 IF n.website<>'' AND n.website !~ '^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?([/?#][^[:space:]<>]*)?$' THEN errors:=errors||jsonb_build_object('website','HTTPS_REQUIRED'); END IF;
 IF errors<>'{}' THEN RETURN jsonb_build_object('code',422,'errorCode','INVALID_PROFILE','fieldErrors',errors); END IF;
 old_values:=(public.get_unit_legal_profile(p_unit)->'profile')-ARRAY['unitId','revision','status','submittedAt','verifiedAt','feedbackToApplicant','reviewNote','reviewSource'];
 IF normalized=old_values AND (p.reviewed_organization_id IS NULL OR p.reviewed_organization_id=org) THEN
  RETURN jsonb_build_object('code',200,'outcome','unchanged','profile',public.get_unit_legal_profile(p_unit)->'profile');
 END IF;
 INSERT INTO public.unit_legal_profiles(unit_id,revision,legal_name,country_code,registration_number,vat_id,street,city,postal_code,contact_email,phone,website)
 VALUES(p_unit,coalesce(p.revision,0)+1,n.legal_name,n.country_code,n.registration_number,n.vat_id,n.street,n.city,n.postal_code,n.contact_email,n.phone,n.website)
 ON CONFLICT(unit_id) DO UPDATE SET revision=excluded.revision,status='unverified',legal_name=excluded.legal_name,
 country_code=excluded.country_code,registration_number=excluded.registration_number,vat_id=excluded.vat_id,
 street=excluded.street,city=excluded.city,postal_code=excluded.postal_code,contact_email=excluded.contact_email,
 phone=excluded.phone,website=excluded.website,submitted_at=NULL,submitted_by=NULL,reviewed_at=NULL,reviewed_by=NULL,
 reviewed_organization_id=NULL,feedback_to_applicant=NULL,review_note=NULL,review_source=NULL;
 INSERT INTO public.unit_legal_profile_audit(unit_id,organization_id,revision,actor_id,action,snapshot)
 SELECT p_unit,org,revision,auth.uid(),'save',to_jsonb(t) FROM public.unit_legal_profiles t WHERE unit_id=p_unit;
 RETURN jsonb_build_object('code',200,'outcome','applied','profile',public.get_unit_legal_profile(p_unit)->'profile');
END $$;

CREATE OR REPLACE FUNCTION public.submit_unit_verification(p_unit bigint,p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE p public.unit_legal_profiles; org bigint; errors jsonb:='{}'; k text; v text;
BEGIN
 SELECT organization INTO org FROM public.units WHERE id=p_unit FOR UPDATE;
 IF auth.uid() IS NULL OR org IS NULL OR NOT public.get_is_manager_on_unit(p_unit) OR public.is_demo_unit(p_unit) THEN
  RAISE EXCEPTION 'Legal profile submission denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO p FROM public.unit_legal_profiles WHERE unit_id=p_unit FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM coalesce(p.revision,0) THEN RETURN jsonb_build_object('code',409,'errorCode','REVISION_CONFLICT','profile',public.get_unit_legal_profile(p_unit)->'profile'); END IF;
 FOR k,v IN SELECT key,value#>>'{}' FROM jsonb_each(public.get_unit_legal_profile(p_unit)->'profile') WHERE key=ANY(ARRAY['legalName','countryCode','registrationNumber','contactEmail']) LOOP
  IF coalesce(v,'')='' THEN errors:=errors||jsonb_build_object(k,'REQUIRED'); END IF;
 END LOOP;
 IF coalesce(p.street,'')='' OR coalesce(p.city,'')='' OR coalesce(p.postal_code,'')='' THEN errors:=errors||jsonb_build_object('address','REQUIRED'); END IF;
 IF errors<>'{}' THEN RETURN jsonb_build_object('code',422,'errorCode','INCOMPLETE_PROFILE','fieldErrors',errors); END IF;
 IF p.status NOT IN ('unverified','rejected','revoked') THEN RETURN jsonb_build_object('code',422,'errorCode','INVALID_TRANSITION','fieldErrors','{}'::jsonb); END IF;
 UPDATE public.unit_legal_profiles SET revision=revision+1,status='pending',submitted_at=statement_timestamp(),submitted_by=auth.uid(),
 reviewed_at=NULL,reviewed_by=NULL,reviewed_organization_id=NULL,feedback_to_applicant=NULL,review_note=NULL,review_source=NULL WHERE unit_id=p_unit;
 INSERT INTO public.unit_legal_profile_audit(unit_id,organization_id,revision,actor_id,action,snapshot)
 SELECT p_unit,org,revision,auth.uid(),'submit',to_jsonb(t) FROM public.unit_legal_profiles t WHERE unit_id=p_unit;
 RETURN jsonb_build_object('code',200,'outcome','applied','profile',public.get_unit_legal_profile(p_unit)->'profile');
END $$;
REVOKE ALL ON FUNCTION public.get_unit_legal_profile(bigint),public.save_unit_legal_profile(bigint,bigint,jsonb),public.submit_unit_verification(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_legal_profile(bigint),public.save_unit_legal_profile(bigint,bigint,jsonb),public.submit_unit_verification(bigint,bigint) TO authenticated;
