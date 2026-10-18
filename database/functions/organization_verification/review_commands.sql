CREATE OR REPLACE FUNCTION public.get_unit_verification_queue(p_organization bigint,p_status text DEFAULT 'pending',p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE items jsonb; next_cursor jsonb; lim integer:=greatest(1,least(coalesce(p_limit,50),50));
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.check_is_admin_of_organization(p_organization),false) THEN
  RAISE EXCEPTION 'Verification queue access denied' USING ERRCODE='42501';
 END IF;
 IF p_status IS NULL OR p_status NOT IN ('pending','verified') THEN RETURN jsonb_build_object('code',422,'errorCode','INVALID_STATUS','fieldErrors','{}'::jsonb); END IF;
 SELECT coalesce(jsonb_agg(profile ORDER BY submitted_at,unit_id),'[]') INTO items FROM (
  SELECT p.unit_id,p.submitted_at,(public.get_unit_legal_profile(p.unit_id)->'profile')||jsonb_build_object('unitTitle',u.title) AS profile
  FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
  WHERE u.organization=p_organization AND p.status=p_status
   AND (p_status<>'verified' OR p.reviewed_organization_id=p_organization)
   AND (p_cursor IS NULL OR (p.submitted_at,p.unit_id)>((p_cursor->>'submittedAt')::timestamptz,(p_cursor->>'unitId')::bigint))
  ORDER BY p.submitted_at,p.unit_id LIMIT lim+1
 ) page;
 IF jsonb_array_length(items)>lim THEN
  items:=items-(jsonb_array_length(items)-1);
  next_cursor:=jsonb_build_object('submittedAt',items->(lim-1)->'submittedAt','unitId',items->(lim-1)->'unitId');
 END IF;
 RETURN jsonb_build_object('code',200,'items',items,'nextCursor',next_cursor);
END $$;

CREATE OR REPLACE FUNCTION public.review_unit_verification(p_unit bigint,p_expected_revision bigint,p_decision text,p_feedback text DEFAULT NULL,p_note text DEFAULT NULL,p_source text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE p public.unit_legal_profiles; org bigint; errors jsonb:='{}';
BEGIN
 SELECT organization INTO org FROM public.units WHERE id=p_unit FOR UPDATE;
 IF auth.uid() IS NULL OR org IS NULL OR NOT coalesce(public.check_is_admin_of_organization(org),false) OR public.is_demo_unit(p_unit) THEN
  RAISE EXCEPTION 'Verification review denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO p FROM public.unit_legal_profiles WHERE unit_id=p_unit FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM coalesce(p.revision,0) THEN RETURN jsonb_build_object('code',409,'errorCode','REVISION_CONFLICT','profile',public.get_unit_legal_profile(p_unit)->'profile'); END IF;
 IF p_decision IS NULL OR p_decision NOT IN ('approve','reject','revoke')
  OR (p_decision IN ('approve','reject') AND p.status IS DISTINCT FROM 'pending')
  OR (p_decision='revoke' AND (p.status IS DISTINCT FROM 'verified' OR p.reviewed_organization_id IS DISTINCT FROM org))
 THEN RETURN jsonb_build_object('code',422,'errorCode','INVALID_TRANSITION','fieldErrors','{}'::jsonb); END IF;
 IF p_decision='approve' THEN
  IF p.legal_name='' OR p.country_code='' OR p.registration_number='' OR p.street='' OR p.city='' OR p.postal_code='' OR p.contact_email='' THEN errors:=errors||jsonb_build_object('profile','INCOMPLETE_PROFILE'); END IF;
  IF coalesce(btrim(p_source),'')='' THEN errors:=errors||jsonb_build_object('reviewSource','REQUIRED'); END IF;
 ELSE
  IF coalesce(btrim(p_feedback),'')='' THEN errors:=errors||jsonb_build_object('feedbackToApplicant','REQUIRED'); END IF;
 END IF;
 IF length(p_feedback)>4000 OR length(p_note)>4000 OR length(p_source)>2000 THEN errors:=errors||jsonb_build_object('review','TOO_LONG'); END IF;
 IF errors<>'{}' THEN RETURN jsonb_build_object('code',422,'errorCode','INVALID_REVIEW','fieldErrors',errors); END IF;
 UPDATE public.unit_legal_profiles SET revision=revision+1,
 status=CASE p_decision WHEN 'approve' THEN 'verified' WHEN 'reject' THEN 'rejected' ELSE 'revoked' END,
 reviewed_at=statement_timestamp(),reviewed_by=auth.uid(),reviewed_organization_id=org,
 feedback_to_applicant=nullif(btrim(p_feedback),''),review_note=nullif(btrim(p_note),''),review_source=nullif(btrim(p_source),'')
 WHERE unit_id=p_unit;
 INSERT INTO public.unit_legal_profile_audit(unit_id,organization_id,revision,actor_id,action,snapshot)
 SELECT p_unit,org,revision,auth.uid(),p_decision,to_jsonb(t) FROM public.unit_legal_profiles t WHERE unit_id=p_unit;
 RETURN jsonb_build_object('code',200,'outcome','applied','profile',public.get_unit_legal_profile(p_unit)->'profile');
END $$;
REVOKE ALL ON FUNCTION public.get_unit_verification_queue(bigint,text,jsonb,integer),public.review_unit_verification(bigint,bigint,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_verification_queue(bigint,text,jsonb,integer),public.review_unit_verification(bigint,bigint,text,text,text,text) TO authenticated;
