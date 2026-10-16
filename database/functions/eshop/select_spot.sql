CREATE OR REPLACE FUNCTION public.select_spot(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; occ bigint; org bigint; un bigint; s eshop.spots; policy jsonb; scopes jsonb; costs jsonb; r jsonb; held bigint; duration_seconds integer; form_data jsonb; form_open boolean; fid bigint;
BEGIN
 IF secret_id IS NULL OR selecting IS NULL THEN RETURN jsonb_build_object('code',400,'message','Invalid reservation'); END IF;
 SELECT f.blueprint,f.occasion,o.organization,o.unit,f.id,f.is_open INTO bp,occ,org,un,fid,form_open FROM public.forms f
 JOIN public.occasions o ON o.id=f.occasion WHERE f.key=form_key;
 IF bp IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form blueprint not found'); END IF;
 PERFORM public.check_occasion_writable(occ);
 IF selecting AND public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN
  form_data:=public.get_effective_form_data(fid);
  IF form_open IS NOT TRUE OR
   (coalesce(form_data#>>'{schedule,start_time}',form_data->>'start_time'))::timestamptz>statement_timestamp() OR
   (coalesce(form_data#>>'{schedule,end_time}',form_data->>'end_time'))::timestamptz<statement_timestamp() THEN
   RETURN jsonb_build_object('code',403,'message','Form is not open'); END IF;
 END IF;
 -- A buyer's active inventory is serialized before the individual spot lock.
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=bp FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Spot not found'); END IF;
 IF s.order_product_ticket IS NOT NULL THEN RETURN jsonb_build_object('code',409,'message','Spot is already ordered'); END IF;
 IF s.secret_expiration_time<=statement_timestamp() THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=spot_id;
  s.secret:=NULL; s.secret_expiration_time:=NULL;
 END IF;
 IF s.secret IS NOT NULL AND s.secret IS DISTINCT FROM secret_id THEN
  RETURN jsonb_build_object('code',403,'message','Spot is held by another buyer'); END IF;
 IF NOT selecting THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now() WHERE id=spot_id;
  RETURN jsonb_build_object('code',200,'message','Spot deselected');
 END IF;
 -- A retry cannot move the original expiration, including after another tab reload.
 IF s.secret=secret_id THEN RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time); END IF;
 policy:=public.abuse_effective_rules_v1('spot.hold',un,org);
 scopes:=jsonb_build_object('recipient',secret_id,'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT count(*) INTO held FROM eshop.spots WHERE secret=secret_id AND secret_expiration_time>statement_timestamp() AND order_product_ticket IS NULL;
 costs:=jsonb_build_object('hold.active.buyer',held+1);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 SELECT (x->>'base_limit')::integer INTO duration_seconds FROM jsonb_array_elements(public.abuse_effective_rules_v1('hold.duration',un,org)->'rules') x;
 IF duration_seconds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 UPDATE eshop.spots SET secret=secret_id,secret_expiration_time=statement_timestamp()+make_interval(secs=>duration_seconds),updated_at=now() WHERE id=spot_id RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time);
END $$;
REVOKE ALL ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) TO anon,authenticated;
