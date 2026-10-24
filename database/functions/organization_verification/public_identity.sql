CREATE OR REPLACE FUNCTION public.get_verified_unit_identity_internal(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE p public.unit_legal_profiles; org bigint;
BEGIN
 SELECT * INTO p FROM public.unit_legal_profiles WHERE unit_id=p_unit AND status='verified';
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT organization INTO org FROM public.units WHERE id=p_unit;
 IF p.reviewed_organization_id IS DISTINCT FROM org THEN
  RAISE LOG 'Verified identity tenant mismatch for Unit %',p_unit;
  RETURN NULL;
 END IF;
 RETURN jsonb_strip_nulls(jsonb_build_object('unitId',p.unit_id,'revision',p.revision,
 'legalName',p.legal_name,'countryCode',p.country_code,'registrationNumber',p.registration_number,
 'vatId',nullif(p.vat_id,''),'address',jsonb_build_object('street',p.street,'city',p.city,'postalCode',p.postal_code),
 'contactEmail',p.contact_email,'phone',nullif(p.phone,''),'website',nullif(p.website,''),'verifiedAt',p.reviewed_at));
END $$;
REVOKE ALL ON FUNCTION public.get_verified_unit_identity_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
